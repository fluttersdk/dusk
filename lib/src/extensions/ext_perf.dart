import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:fluttersdk_artisan/artisan.dart';
import 'package:fluttersdk_wind_diagnostics_contracts/fluttersdk_wind_diagnostics_contracts.dart';

import '../dusk_plugin.dart';
import '../utils/dusk_response.dart';
import '../utils/error_envelope.dart';
import '../utils/frame_sync.dart';
import '../utils/perf_insights.dart';
import '../utils/perf_readers.dart';

// ---------------------------------------------------------------------------
// Self-registration entry point
// ---------------------------------------------------------------------------

/// Registers `ext.dusk.perf_begin`, `ext.dusk.perf_end` and
/// `ext.dusk.perf_insight`.
///
/// The first two are one verb split in half: `perf_begin` turns the
/// instrumentation on and records what to compare against, `perf_end` reads,
/// reports and puts every flag back. `perf_insight` drills into one insight of
/// the report `perf_end` last produced. Idempotent via
/// [registerExtensionIdempotent]; call once from `registerAllDuskExtensions()`.
void registerPerfExtensions() {
  registerExtensionIdempotent('ext.dusk.perf_begin', duskPerfBeginHandler);
  registerExtensionIdempotent('ext.dusk.perf_end', duskPerfEndHandler);
  registerExtensionIdempotent('ext.dusk.perf_insight', duskPerfInsightHandler);
}

// ---------------------------------------------------------------------------
// Session state
// ---------------------------------------------------------------------------

/// Everything one `perf_begin` has to remember so the matching `perf_end`
/// can judge the run and undo the instrumentation.
final class _PerfSession {
  _PerfSession({
    required this.token,
    required this.mode,
    required this.phases,
    required this.priorCollectionEnabled,
    required this.priorProfileBuilds,
    required this.priorProfileUserWidgets,
    required this.priorProfileLayouts,
    required this.priorProfilePaints,
  });

  final String token;
  final PerfMode mode;
  final bool phases;

  /// Wall clock since the session opened, for `summary.durationMs`.
  final Stopwatch clock = Stopwatch()..start();

  /// `FlutterTimeline.now` at open, the start of the window
  /// `ext.dusk.perf_trace` exports: the clock interactions are stamped with.
  final int startUs = FlutterTimeline.now;

  /// The liveness counter as it read at `perf_begin`. `perf_end` reports
  /// rather than refuses only when the counter has moved past this.
  ///
  /// Mutable, and set after the session is already installed in [_session].
  /// Reading it means calling `framePerfReader`, which is assigned in another
  /// package and can therefore throw; if the session only came into existence
  /// after that call, a throw would leave the profiling flags switched on with
  /// nothing holding their prior values, and no `perf_end` could ever put them
  /// back. The session has to exist before anything that can fail.
  ///
  /// NULL until that read succeeds, and null is the only safe sentinel. Zero
  /// is not: `perf_end` computes `final - baseline`, the counter is monotonic
  /// since install and is never reset in production, so a baseline of zero
  /// MAXIMISES the apparent advance instead of zeroing it. A session stranded
  /// by a throwing hook would then sail past the stalled-engine refusal and
  /// report frames nobody drove, out of a buffer the hook never got as far as
  /// clearing. Null cannot collide with a real counter value, and `perf_end`
  /// answers it with an error envelope rather than a `refused` report, since
  /// a refusal is a measurement outcome and a session that never opened is
  /// not one.
  int? livenessBaseline;

  // The five flags this session touches, as they read BEFORE it touched
  // them. Restoring these values rather than forcing `false` is deliberate:
  // a host that had build profiling on for its own reasons (a DevTools
  // session, an outer harness) would otherwise have it silently switched off
  // by a dusk verb that never owned it.
  final bool priorCollectionEnabled;
  final bool priorProfileBuilds;
  final bool priorProfileUserWidgets;
  final bool priorProfileLayouts;
  final bool priorProfilePaints;
}

_PerfSession? _session;
int _sessionCounter = 0;

/// The most recent session `perf_end` closed, which `perf_insight` drills
/// into. One session only: the drill-down answers "why did the report I just
/// read say that", and holding older analyses would keep thousands of frame
/// rows alive for questions nobody asks.
final class _ClosedSession {
  const _ClosedSession(
    this.token,
    this.analysis, {
    required this.startUs,
    required this.endUs,
  });

  final String token;

  /// The session's `FlutterTimeline.now` window, open to `perf_end`.
  final int startUs;
  final int endUs;

  /// Null when `perf_end` refused: a refusal has no insights to drill into.
  final PerfAnalysis? analysis;
}

_ClosedSession? _lastClosed;

/// Whether a measurement session is open. Gesture verbs open an interaction
/// only while it is, so outside a session they cost nothing.
bool get perfSessionOpen => _session != null;

/// The token of the most recent session `perf_end` closed, the one
/// `perf_insight` and `perf_trace` answer for; null before any closed.
String? get lastClosedPerfToken => _lastClosed?.token;

/// That session's `FlutterTimeline.now` window, from `perf_begin` to
/// `perf_end`; null before any closed.
({int startUs, int endUs})? get lastClosedPerfWindow {
  final _ClosedSession? closed = _lastClosed;
  if (closed == null) return null;
  return (startUs: closed.startUs, endUs: closed.endUs);
}

/// The most frames a session can produce and still be a stalled engine rather
/// than a measurement.
///
/// Zero is the wrong threshold and was measured being wrong: a backgrounded
/// Chrome page produces exactly ONE frame, not none. Driving a scroll against a
/// hidden page and closing the session read `advanced: 1`, which the first
/// implementation reported on as though the engine were healthy, producing the
/// table of near-zeros this refusal exists to prevent.
///
/// One frame is also not a measurement even when the page is visible: every
/// percentile in the summary would be that single sample.
const int _kStalledEngineFrames = 1;

/// Closes any open session the way `perf_end` does, for tests that assert on
/// `perf_begin` alone and would otherwise leak a session (and its stale
/// prior-flag values) into the next test.
@visibleForTesting
void resetPerfSessionForTesting() {
  final _PerfSession? open = _session;
  if (open != null) _closeSession(open);
}

/// Forgets the session `perf_insight` would drill into, so a test that
/// asserts the no-session error does not read a report an earlier test left.
@visibleForTesting
void resetClosedPerfSessionForTesting() {
  _lastClosed = null;
}

// ---------------------------------------------------------------------------
// ext.dusk.perf_begin
// ---------------------------------------------------------------------------

/// Handler for `ext.dusk.perf_begin`: opens a measurement session.
///
/// Params (all string-valued):
/// - `mode` (optional, default `'attribution'`): `attribution` switches build
///   profiling on for blocks, self time and counters; `timing` touches no
///   flag at all and reports frame timings only, the pass whose milliseconds
///   are worth comparing, since the profiling flags inflate every duration.
/// - `phases` (optional, default `'false'`): also profile layout and paint,
///   not just builds. Phase detail multiplies the span volume, so it is opt
///   in. Rejected with `mode=timing`, which profiles nothing.
///
/// Response JSON:
/// ```json
/// {
///   "sessionToken": "perf-1",
///   "mode": "attribution",
///   "phases": false,
///   "livenessBaseline": 412,
///   "restartedPreviousSession": false
/// }
/// ```
///
/// Calling it while a session is already open RESTARTS rather than errors: a
/// driving agent whose `perf_end` never landed (a crash, a dropped
/// connection) would otherwise be locked out until hot restart. The restart
/// restores the previous session's flags BEFORE saving the current ones,
/// which is what keeps the restore honest; saving first would capture the
/// values `perf_begin` itself set and `perf_end` would then "restore"
/// profiling to on, permanently.
Future<developer.ServiceExtensionResponse> duskPerfBeginHandler(
  String method,
  Map<String, String> params,
) async {
  // 1. Parse, and refuse a contradiction before anything is touched: a
  //    session opened on a mode nobody asked for would be read as the one
  //    they did.
  final String modeName = params['mode'] ?? PerfMode.attribution.name;
  final PerfMode? mode = PerfMode.tryParse(modeName);
  final bool phases = params['phases'] == 'true';
  if (mode == null || (mode == PerfMode.timing && phases)) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.invalidParams,
      wrapErrorDetail(
        mode == null
            ? 'ext.dusk.perf_begin: mode "$modeName" is not one of '
                'attribution, timing.'
            : 'ext.dusk.perf_begin: phases=true profiles layout and paint, '
                'and mode=timing profiles nothing; pick one.',
        DuskErrorEnvelope.unexpected(),
      ),
    );
  }

  try {
    // 2. Close a session left open by a perf_end that never landed.
    final _PerfSession? stale = _session;
    final bool restarted = stale != null;
    if (stale != null) _closeSession(stale);

    // 3. Save the prior flag values, then switch the instrumentation on.
    //    Collection goes first on purpose: `startSync` and `finishSync` both
    //    check the collection flag, so a build span that started while
    //    collection was off and finished while it was on would push a
    //    finish with no matching start.
    final bool priorCollectionEnabled = FlutterTimeline.debugCollectionEnabled;
    final bool priorProfileBuilds = debugProfileBuildsEnabled;
    final bool priorProfileUserWidgets = debugProfileBuildsEnabledUserWidgets;
    final bool priorProfileLayouts = debugProfileLayoutsEnabled;
    final bool priorProfilePaints = debugProfilePaintsEnabled;

    // 4. Install the session BEFORE touching a single flag. Everything below
    //    can throw: two of the calls are function pointers another package
    //    assigns, and a throw between the flag writes and the session's
    //    creation would strand profiling switched on with nowhere to read its
    //    prior values from. `perf_end` would then have no session to restore,
    //    and only a hot restart would clear it. The session is the receipt for
    //    the flags, so it has to exist before they change.
    final _PerfSession session = _PerfSession(
      token: 'perf-${++_sessionCounter}',
      mode: mode,
      phases: phases,
      priorCollectionEnabled: priorCollectionEnabled,
      priorProfileBuilds: priorProfileBuilds,
      priorProfileUserWidgets: priorProfileUserWidgets,
      priorProfileLayouts: priorProfileLayouts,
      priorProfilePaints: priorProfilePaints,
    );
    _session = session;

    // Timing mode leaves every flag where it found it: the milliseconds it
    // exists to report are the ones the profiling flags would inflate.
    if (mode == PerfMode.attribution) {
      FlutterTimeline.debugCollectionEnabled = true;
      // Builds live in package:flutter/widgets.dart, layouts and paints in
      // package:flutter/rendering.dart. Two libraries, one session.
      debugProfileBuildsEnabled = true;
      debugProfileBuildsEnabledUserWidgets = true;
      if (phases) {
        debugProfileLayoutsEnabled = true;
        debugProfilePaintsEnabled = true;
      }
    }

    // 5. Zero the counters dusk cannot reach itself, then read the baseline
    //    the refusal is judged against. Reading after the hook keeps the
    //    baseline on the same side of the reset as everything else. The hook
    //    gets the mode so a timing session can leave wind's counting off.
    perfSessionBeginHook(mode);
    final int livenessBaseline = _asInt(framePerfReader()['livenessCounter']);
    session.livenessBaseline = livenessBaseline;

    return duskResult(<String, dynamic>{
      'sessionToken': session.token,
      'mode': mode.name,
      'phases': phases,
      'livenessBaseline': livenessBaseline,
      'restartedPreviousSession': restarted,
    });
  } catch (e, st) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.perf_begin: unexpected error: $e\n$st',
      name: 'fluttersdk_dusk',
    );
    // Hand the instrumentation back immediately rather than leaving it on
    // until a `perf_end` that may never come. The session was installed before
    // the flags precisely so this is possible; without it a throw from either
    // host closure leaves profiling running with no automatic recovery.
    final _PerfSession? open = _session;
    if (open != null) _closeSession(open);
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.perf_begin: $e',
        DuskErrorEnvelope.unexpected(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ext.dusk.perf_end
// ---------------------------------------------------------------------------

/// Handler for `ext.dusk.perf_end`: closes the session and reports.
///
/// Params (all string-valued):
/// - `full` (optional, default `'false'`): lift every cut, so the counter
///   breakdowns, block rankings, route transitions and insights carry every
///   row and `omitted` reads all zeros. For a host-side runner that writes the
///   report to a file; an agent reading the answer wants the bounded default.
///
/// Reads the frames and the liveness counter through
/// [framePerfReader], wind's aggregate through `WindDebugRegistry.currentPerf`
/// and the magic-side counters through [perfExtrasReader], builds the report
/// with [analysePerf], keeps the analysis for `ext.dusk.perf_insight`, then
/// restores every flag [duskPerfBeginHandler] changed and calls
/// [perfSessionEndHook].
///
/// Response JSON, reporting (bounded to about 6 KB; the rows behind each
/// insight stay behind `perf_insight`):
/// ```json
/// {
///   "sessionToken": "perf-1",
///   "refused": false,
///   "mode": "attribution",
///   "env": {"platform": "macOS", "isWeb": true, "buildMode": "debug",
///           "semanticsEnabled": true, "phases": false},
///   "coverage": {"framesDrawn": 45, "framesSummarized": 45,
///                "complete": true, "missing": []},
///   "summary": {"durationMs": 2310.4, "budgetMs": 16.7,
///               "frames": {"count": 45, "painted": 45, "dropped": 0, "...": 0},
///               "blocksBySelf": [], "blocksByCount": [],
///               "routeTransitions": []},
///   "counters": {"columns": ["name", "count", "perFrame"],
///                "wind": {"...": 0}, "magic": {"...": 0}},
///   "insights": [{"id": "I1", "severity": "warn", "title": "...",
///                 "evidence": {"metric": "...", "value": 1, "perFrame": 0.02,
///                              "threshold": {"budgetMs": 16.7}},
///                 "estimatedSavingsMs": 12.4, "nextStep": "..."}],
///   "omitted": {"blocksBySelf": 0, "insights": 0, "...": 0}
/// }
/// ```
///
/// Refusing (the liveness counter advanced by 1 or less):
/// ```json
/// {
///   "sessionToken": "perf-1",
///   "refused": true,
///   "mode": "attribution",
///   "coverage": {"framesDrawn": 0, "livenessBaseline": 412,
///                "livenessFinal": 412, "complete": false},
///   "reason": "..."
/// }
/// ```
///
/// `refused` is always present and is the ONLY discriminator. It is not the
/// `warnings` block: that one reads `SchedulerBinding.framesEnabled`, which
/// was measured reporting `true` on a Chrome page that had produced one frame
/// in two seconds, so both signals can appear on the same response and only
/// one of them is trustworthy here.
///
/// Called without a prior `perf_begin` it returns an error envelope rather
/// than throwing across the VM Service boundary.
Future<developer.ServiceExtensionResponse> duskPerfEndHandler(
  String method,
  Map<String, String> params,
) async {
  final _PerfSession? session = _session;
  if (session == null) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.perf_end: no measurement session is open. Call '
        'ext.dusk.perf_begin first; the session carries the flag values to '
        'restore and the liveness baseline this report is judged against, '
        'and neither can be reconstructed afterwards.',
        DuskErrorEnvelope.unexpected(),
      ),
    );
  }

  // A failed close must not leave the previous report answering drill-downs
  // as though it were this session's.
  _lastClosed = null;
  final int endUs = FlutterTimeline.now;
  final bool full = params['full'] == 'true';

  try {
    // 1. Read the liveness counter first: everything below is only worth
    //    computing if the engine actually rendered.
    final Map<String, Object?> perf = framePerfReader();
    final int livenessFinal = _asInt(perf['livenessCounter']);
    final int? baseline = session.livenessBaseline;

    // A session with no baseline never finished opening. `perf_begin` reads
    // the counter as its last act and closes the session itself if anything
    // before that throws, so this is not reachable through either verb; the
    // nullable type is what makes the old zero sentinel unrepresentable, and
    // this is the obligation that type creates rather than a state the product
    // can be in. Answered with the same error envelope as a missing session,
    // deliberately NOT as a `refused` report: a refusal is a measurement
    // outcome and this is not one.
    if (baseline == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.perf_end: the open session never completed its baseline '
          'read, so there is nothing to judge a run against. Call '
          'ext.dusk.perf_begin again.',
          DuskErrorEnvelope.unexpected(),
        ),
      );
    }

    final int advanced = livenessFinal - baseline;

    if (advanced <= _kStalledEngineFrames) {
      _lastClosed = _ClosedSession(
        session.token,
        null,
        startUs: session.startUs,
        endUs: endUs,
      );
      return duskResult(<String, dynamic>{
        'sessionToken': session.token,
        'refused': true,
        'mode': session.mode.name,
        'coverage': <String, dynamic>{
          'framesDrawn': advanced,
          'livenessBaseline': baseline,
          'livenessFinal': livenessFinal,
          'complete': false,
        },
        'reason': 'The liveness counter advanced by $advanced between '
            'perf_begin and perf_end (baseline $baseline, '
            'final $livenessFinal), so there is nothing to measure: every '
            'metric would be a zero or a single-sample average that reads as '
            '"fast". '
            'The ordinary cause is an idle app rather than a broken one. '
            'Flutter schedules a frame only when something is dirty, so a '
            'session that opens, sleeps and closes legitimately draws no '
            'frames at all; drive an interaction inside the session, and aim '
            'a scroll at something that actually scrolls. '
            'The other cause is a hidden or backgrounded page, which produces '
            'exactly one frame rather than zero, and is why the threshold is '
            '$_kStalledEngineFrames rather than 0. '
            'That counter is the authority here, not the `warnings` block on '
            'this response and not the SchedulerBinding.framesEnabled reading '
            'behind it: framesEnabled was measured reporting true, with '
            'lifecycle "resumed", on a Chrome page that was hidden and had '
            'produced one frame in two seconds. Only a counter a post-frame '
            'callback increments proves a frame ran. Bring the page to front '
            '(CDP Page.bringToFront) and run the session again.',
      });
    }

    // 2. Hand the parked timings over, AFTER the liveness verdict so the flush
    //    frame can never lift a stalled session past the refusal.
    final Map<String, Object?> flushed = await _flushParkedTimings();

    // 3. Keep the frames of this session's window only. The flush hands over
    //    the tail, but the same read also carries timings of frames drawn
    //    BEFORE perf_begin (parked, delivered after the buffer was cleared)
    //    and the idle frame the flush itself drew; neither is in `advanced`,
    //    which was read before the flush, so counting them made the summary
    //    larger than the session it describes.
    final ({
      List<Map<String, Object?>> inSession,
      int outside,
      bool clockMismatch,
    }) window = perfSessionFrames(flushed['frames'], session.startUs, endUs);

    // 4. The cross-package sections. Timing mode reads neither: it reports
    //    frame timings only, and a counter read it then discards is still a
    //    call into another repository that can throw.
    final bool attribution = session.mode == PerfMode.attribution;
    final PerfAnalysis analysis = analysePerf(
      <String, Object?>{...flushed, 'frames': window.inSession},
      attribution ? perfExtrasReader() : const <String, Object?>{},
      attribution ? WindDebugRegistry.currentPerf?.stats() : null,
      env: _env(session),
      mode: session.mode,
      framesDrawn: advanced,
      framesOutsideSession: window.outside,
      sessionClockMismatch: window.clockMismatch,
      durationMs: session.clock.elapsedMicroseconds / 1000,
      full: full,
    );

    // 5. Keep the analysis for perf_insight, then report.
    _lastClosed = _ClosedSession(
      session.token,
      analysis,
      startUs: session.startUs,
      endUs: endUs,
    );
    return duskResult(<String, dynamic>{
      'sessionToken': session.token,
      'refused': false,
      ...analysis.report,
    });
  } catch (e, st) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.perf_end: unexpected error: $e\n$st',
      name: 'fluttersdk_dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.perf_end: $e',
        DuskErrorEnvelope.unexpected(),
      ),
    );
  } finally {
    // Runs on the report, the refusal and the failure alike. Leaving the
    // profile flags on would tax every later frame in the app and silently
    // degrade the next measurement.
    _closeSession(session);
  }
}

// ---------------------------------------------------------------------------
// ext.dusk.perf_insight
// ---------------------------------------------------------------------------

/// Handler for `ext.dusk.perf_insight`: the rows behind one insight of the
/// most recent report `perf_end` produced.
///
/// Params (all string-valued):
/// - `id` (required): an insight id (`I<n>`) from that report's `insights[]`.
///   Ids are assigned before the report cuts its list, so an insight counted
///   in `omitted.insights` is drillable too.
/// - `token` (optional): the report's `sessionToken`. When given it must name
///   the most recent closed session, the only one kept.
///
/// Response JSON:
/// ```json
/// {
///   "sessionToken": "perf-1",
///   "id": "I1",
///   "severity": "warn",
///   "title": "3 of 45 frames over the 16.7ms budget",
///   "summary": "...",
///   "detail": {"worstFrames": [{"frameNumber": 212, "buildMs": 31.2,
///              "rasterMs": 2.1, "blocks": [{"name": "MonitorRow",
///              "selfMs": 9.8, "count": 12}]}]},
///   "estimatedSavingsMs": 29.4,
///   "nextStep": "..."
/// }
/// ```
///
/// Every miss is an error naming what to read instead: no id, no closed
/// session, a stale token, a refused session, or an id the session never
/// issued (which points at `perf_end`'s list).
Future<developer.ServiceExtensionResponse> duskPerfInsightHandler(
  String method,
  Map<String, String> params,
) async {
  final String id = params['id'] ?? '';
  final String? token = params['token'];

  if (id.isEmpty) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.invalidParams,
      wrapErrorDetail(
        'ext.dusk.perf_insight: id is required, an insight id such as I1 '
        'from the insights[] list ext.dusk.perf_end returned.',
        DuskErrorEnvelope.missingParam('id'),
      ),
    );
  }

  final _ClosedSession? closed = _lastClosed;
  final String? problem = switch (closed) {
    null => 'no closed perf session to drill into. Run ext.dusk.perf_begin, '
        'drive the interaction, then ext.dusk.perf_end; its insights[] list '
        'carries the ids.',
    _ when token != null && token != closed.token =>
      'session $token is not held; only the most recent closed session '
          '(${closed.token}) is kept. Drill into it, or rerun the session.',
    _ when closed.analysis == null =>
      'session ${closed.token} was refused by ext.dusk.perf_end and has no '
          'insights; rerun it with an interaction driven inside.',
    _ => null,
  };
  if (problem != null) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.perf_insight: $problem',
        DuskErrorEnvelope.unexpected(),
      ),
    );
  }

  final Map<String, Object?>? drill = closed!.analysis!.drillDown(id);
  if (drill == null) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.perf_insight: session ${closed.token} issued no insight '
        '$id. Read the ids from the insights[] list ext.dusk.perf_end '
        'returned; one cut from that list is counted in omitted.insights and '
        'is still drillable by its id.',
        DuskErrorEnvelope.notFound(ref: id),
      ),
    );
  }

  return duskResult(<String, dynamic>{
    'sessionToken': closed.token,
    ...drill,
  });
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Where this report was measured, read in-app rather than from artisan
/// state: a profile build launched by hand has no artisan record, and the
/// numbers mean different things in each mode.
///
/// `semanticsEnabled` is on the report because dusk keeps a semantics handle
/// for the whole process, so every dusk-driven measurement builds the
/// semantics tree each frame; a reader comparing against a non-dusk run needs
/// to know that.
Map<String, Object?> _env(_PerfSession session) => <String, Object?>{
      'platform': defaultTargetPlatform.name,
      'isWeb': kIsWeb,
      'buildMode': kProfileMode
          ? 'profile'
          : kDebugMode
              ? 'debug'
              : 'release',
      'renderer': rendererReader(),
      'semanticsEnabled': SemanticsBinding.instance.semanticsEnabled,
      'phases': session.phases,
    };

/// Splits [rawFrames] into the frames that belong to the session window
/// `[startUs, endUs]` and a count of the ones that do not.
///
/// The window is judged by `vsyncStartUs`, the one timestamp a frame record
/// carries that says when the frame began. Frame numbers cannot bound it: the
/// engine numbers frames it never reports, and timings parked before
/// `perf_begin` arrive numbered AFTER the last one the buffer held. A frame
/// with no `vsyncStartUs` cannot be placed and is kept, which is the
/// pre-window behavior for a host that never supplied one.
///
/// `vsyncStartUs` is the engine's clock and `startUs`/`endUs` are
/// `FlutterTimeline.now`; telescope's record documents that their parity is
/// unverified on native. The caller only gets here after the liveness counter
/// proved the session drew, so a read in which frames carry a timestamp and
/// NONE of them lands in the window means the clocks disagree, not that the
/// session was empty. Then every frame is kept and `clockMismatch` is set, so
/// the report describes the frames it has and says it could not cut them.
///
/// `ext.dusk.perf_trace` cuts its frames by the same rule, so the trace and
/// the report it sits beside never disagree on which frames the session had.
({
  List<Map<String, Object?>> inSession,
  int outside,
  bool clockMismatch,
}) perfSessionFrames(
  Object? rawFrames,
  int startUs,
  int endUs,
) {
  final List<Map<String, Object?>> all = rawFrames is List<Object?>
      ? rawFrames.whereType<Map<String, Object?>>().toList()
      : <Map<String, Object?>>[];
  final List<Map<String, Object?>> inSession = <Map<String, Object?>>[];
  int outside = 0;
  int placed = 0;
  for (final Map<String, Object?> frame in all) {
    final Object? vsync = frame['vsyncStartUs'];
    if (vsync is num) {
      if (vsync < startUs || vsync > endUs) {
        outside++;
        continue;
      }
      placed++;
    }
    inSession.add(frame);
  }
  if (outside > 0 && placed == 0) {
    return (inSession: all, outside: 0, clockMismatch: true);
  }
  return (inSession: inSession, outside: outside, clockMismatch: false);
}

/// Longer than the web engine's 100 ms hand-over interval.
const Duration _kTimingsFlushDelay = Duration(milliseconds: 120);

/// Draws one frame so the engine hands over the timings it is still holding,
/// then reads the frames again.
///
/// The web engine passes FrameTimings to `onReportTimings` only from inside
/// a LATER frame, and only once 100 ms have passed since the last hand-over
/// (`flutter_web_sdk/lib/_engine/engine/frame_timing_recorder.dart`,
/// `submitTimings`). The frames a session draws in its last 100 ms therefore
/// stay parked until something draws again, and on uptizm that was all but
/// one of them: 1 of 5 frames reported on every repeat of a list scroll. The
/// flush frame is idle and lands in the report as one more painted frame.
/// `scheduleFrame`, not `scheduleForcedFrame`: a hidden page must stay
/// frameless rather than be woken into looking measured.
Future<Map<String, Object?>> _flushParkedTimings() async {
  await Future<void>.delayed(_kTimingsFlushDelay);
  SchedulerBinding.instance.scheduleFrame();
  await awaitFrameOrTimeout();
  return framePerfReader();
}

/// Restores the five flags to the values [session] saved, hands wind's
/// counters back to their off state, and drops the session.
///
/// A timing session never touched the flags, so it restores none: writing
/// the saved values back would undo a change someone else made during it.
void _closeSession(_PerfSession session) {
  if (session.mode == PerfMode.attribution) {
    FlutterTimeline.debugCollectionEnabled = session.priorCollectionEnabled;
    debugProfileBuildsEnabled = session.priorProfileBuilds;
    debugProfileBuildsEnabledUserWidgets = session.priorProfileUserWidgets;
    debugProfileLayoutsEnabled = session.priorProfileLayouts;
    debugProfilePaintsEnabled = session.priorProfilePaints;
  }
  // A semantics pass whose driver died between `semantics_hold release` and
  // its `acquire` would otherwise leave every later snapshot and ref-based
  // action reading an empty tree. The session is the receipt for that too.
  if (DuskPlugin.semanticsReleased) DuskPlugin.acquireSemantics();
  // Session dropped BEFORE the host hook runs. That hook is assigned in
  // another repository and can throw; from `perf_end`'s `finally` a throw
  // would replace the response and cross the VM Service boundary, which this
  // package never does, and it would leave a session that a later
  // `perf_begin` would report as restarted when it had already been closed.
  // The flags are back either way, which is the part that cannot be deferred.
  _session = null;
  // Deliberately handled, not swallowed: this hook is assigned in another
  // repository, and a throw here would escape `perf_end`'s `finally`, replace
  // the response and cross the VM Service boundary, which no extension in this
  // package does. The flags are already back by this point, so the session is
  // closed either way; the failure is reported the same way perf_begin reports
  // its own.
  try {
    perfSessionEndHook();
  } catch (e, st) {
    developer.log(
      '[fluttersdk_dusk] perfSessionEndHook threw while closing a perf '
      'session; the instrumentation flags were already restored: $e\n$st',
      name: 'fluttersdk_dusk',
    );
  }
}

/// Reads an int out of a map built in another repository.
///
/// A missing or non-numeric value reads as 0, which for the liveness counter
/// is the safe direction: a reader that does not report one produces a
/// refusal rather than a report of numbers nothing vouches for.
int _asInt(Object? value) => value is num ? value.toInt() : 0;
