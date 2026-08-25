import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:fluttersdk_artisan/artisan.dart';
import 'package:fluttersdk_wind_diagnostics_contracts/fluttersdk_wind_diagnostics_contracts.dart';

import '../utils/dusk_response.dart';
import '../utils/error_envelope.dart';
import '../utils/frame_summary.dart';
import '../utils/perf_readers.dart';

// ---------------------------------------------------------------------------
// Self-registration entry point
// ---------------------------------------------------------------------------

/// Registers the `ext.dusk.perf_begin` / `ext.dusk.perf_end` pair.
///
/// The two are one verb split in half: `perf_begin` turns the instrumentation
/// on and records what to compare against, `perf_end` reads, reports and puts
/// every flag back. Idempotent via [registerExtensionIdempotent]; call once
/// from `registerAllDuskExtensions()`.
void registerPerfExtensions() {
  registerExtensionIdempotent('ext.dusk.perf_begin', duskPerfBeginHandler);
  registerExtensionIdempotent('ext.dusk.perf_end', duskPerfEndHandler);
}

// ---------------------------------------------------------------------------
// Session state
// ---------------------------------------------------------------------------

/// Everything one `perf_begin` has to remember so the matching `perf_end`
/// can judge the run and undo the instrumentation.
final class _PerfSession {
  _PerfSession({
    required this.token,
    required this.phases,
    required this.livenessBaseline,
    required this.priorCollectionEnabled,
    required this.priorProfileBuilds,
    required this.priorProfileUserWidgets,
    required this.priorProfileLayouts,
    required this.priorProfilePaints,
  });

  final String token;
  final bool phases;

  /// The liveness counter as it read at `perf_begin`. `perf_end` reports
  /// rather than refuses only when the counter has moved past this.
  final int livenessBaseline;

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

/// How many ranked block entries the report carries. The tail of a real
/// session is thousands of one-off widget types; the ranking is what directs
/// a fix, and everything past the head of it is noise in an agent's context.
const int _kRankedBlockLimit = 20;

/// Stated in the payload itself because a number that travels without it
/// gets quoted as a production fact. Flutter's own docblocks on the three
/// `debugProfile*` flags say the overhead of adding timeline events is
/// significant relative to the time each object takes.
const String _kMeasurementNote =
    'Per-type absolute durations are indicative, not representative: the '
    'timeline instrumentation this session switches on costs time that is '
    'significant relative to the work it measures, and this is a debug '
    'build, which widens the gap again. The counts, the ratios and the '
    'ranking are the parts that direct a fix; do not report a per-type '
    'millisecond as a fact about production.';

/// Closes any open session the way `perf_end` does, for tests that assert on
/// `perf_begin` alone and would otherwise leak a session (and its stale
/// prior-flag values) into the next test.
@visibleForTesting
void resetPerfSessionForTesting() {
  final _PerfSession? open = _session;
  if (open != null) _closeSession(open);
}

// ---------------------------------------------------------------------------
// ext.dusk.perf_begin
// ---------------------------------------------------------------------------

/// Handler for `ext.dusk.perf_begin`: opens a measurement session.
///
/// Params (all string-valued):
/// - `phases` (optional, default `'false'`): also profile layout and paint,
///   not just builds. Phase detail multiplies the span volume, so it is opt
///   in.
///
/// Response JSON:
/// ```json
/// {
///   "sessionToken": "perf-1",
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
  try {
    // 1. Parse.
    final bool phases = params['phases'] == 'true';

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

    FlutterTimeline.debugCollectionEnabled = true;
    // Builds live in package:flutter/widgets.dart, layouts and paints in
    // package:flutter/rendering.dart. Two libraries, one session.
    debugProfileBuildsEnabled = true;
    debugProfileBuildsEnabledUserWidgets = true;
    if (phases) {
      debugProfileLayoutsEnabled = true;
      debugProfilePaintsEnabled = true;
    }

    // 4. Zero the counters dusk cannot reach itself, then read the baseline
    //    the refusal is judged against. Reading after the hook keeps the
    //    baseline on the same side of the reset as everything else.
    perfSessionBeginHook();
    final int livenessBaseline = _asInt(framePerfReader()['livenessCounter']);

    final _PerfSession session = _PerfSession(
      token: 'perf-${++_sessionCounter}',
      phases: phases,
      livenessBaseline: livenessBaseline,
      priorCollectionEnabled: priorCollectionEnabled,
      priorProfileBuilds: priorProfileBuilds,
      priorProfileUserWidgets: priorProfileUserWidgets,
      priorProfileLayouts: priorProfileLayouts,
      priorProfilePaints: priorProfilePaints,
    );
    _session = session;

    return duskResult(<String, dynamic>{
      'sessionToken': session.token,
      'phases': phases,
      'livenessBaseline': livenessBaseline,
      'restartedPreviousSession': restarted,
    });
  } catch (e, st) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.perf_begin: unexpected error: $e\n$st',
      name: 'fluttersdk_dusk',
    );
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
/// Takes no params. Reads the frames and the liveness counter through
/// [framePerfReader], wind's aggregate through `WindDebugRegistry.currentPerf`
/// and the magic-side counters through [perfExtrasReader], then restores every
/// flag [duskPerfBeginHandler] changed and calls [perfSessionEndHook].
///
/// Response JSON, reporting:
/// ```json
/// {
///   "sessionToken": "perf-1",
///   "refused": false,
///   "phases": true,
///   "liveness": {"baseline": 412, "final": 457, "advanced": 45},
///   "frameSummary": { "average_frame_build_time_millis": 3.2, "...": 0 },
///   "blockAttribution": [
///     {"name": "MonitorRow", "micros": 10200, "count": 10, "frames": 2}
///   ],
///   "wind": {"cacheHits": 12, "...": 0},
///   "magic": {"controllerNotifies": {}, "routeTransitions": []},
///   "note": "Per-type absolute durations are indicative ..."
/// }
/// ```
///
/// Refusing (the liveness counter did not move):
/// ```json
/// {
///   "sessionToken": "perf-1",
///   "refused": true,
///   "phases": true,
///   "liveness": {"baseline": 412, "final": 412, "advanced": 0},
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

  try {
    // 1. Read the liveness counter first: everything below is only worth
    //    computing if the engine actually rendered.
    final Map<String, Object?> perf = framePerfReader();
    final int livenessFinal = _asInt(perf['livenessCounter']);
    final int advanced = livenessFinal - session.livenessBaseline;
    final Map<String, dynamic> liveness = <String, dynamic>{
      'baseline': session.livenessBaseline,
      'final': livenessFinal,
      'advanced': advanced,
    };

    if (advanced <= 0) {
      return duskResult(<String, dynamic>{
        'sessionToken': session.token,
        'refused': true,
        'phases': session.phases,
        'liveness': liveness,
        'reason': 'The liveness counter did not advance between perf_begin '
            'and perf_end (baseline ${session.livenessBaseline}, final '
            '$livenessFinal), so the engine rendered nothing during the '
            'session and every metric would be a zero that reads as "fast". '
            'That counter is the authority here, not the `warnings` block on '
            'this response and not the SchedulerBinding.framesEnabled reading '
            'behind it: framesEnabled was measured reporting true, with '
            'lifecycle "resumed", on a Chrome page that was hidden and had '
            'produced one frame in two seconds. Only a counter a post-frame '
            'callback increments proves a frame ran. Bring the page to front '
            '(CDP Page.bringToFront) and run the session again.',
      });
    }

    // 2. Frames, then the two cross-package sections.
    final List<Map<String, Object?>> frames = _readFrames(perf);
    final Map<String, Object?>? windStats =
        WindDebugRegistry.currentPerf?.stats();

    return duskResult(<String, dynamic>{
      'sessionToken': session.token,
      'refused': false,
      'phases': session.phases,
      'liveness': liveness,
      'frameSummary': summarizeFramePerf(frames),
      'blockAttribution': _rankBlocks(frames),
      // Null rather than a map of zeros: "wind never registered a perf
      // resolver" and "wind counted nothing" are different findings and an
      // agent reading a flat report cannot otherwise tell them apart.
      'wind': windStats,
      'magic': perfExtrasReader(),
      'note': _kMeasurementNote,
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
// Private helpers
// ---------------------------------------------------------------------------

/// Restores the five flags to the values [session] saved, hands wind's
/// counters back to their off state, and drops the session.
void _closeSession(_PerfSession session) {
  FlutterTimeline.debugCollectionEnabled = session.priorCollectionEnabled;
  debugProfileBuildsEnabled = session.priorProfileBuilds;
  debugProfileBuildsEnabledUserWidgets = session.priorProfileUserWidgets;
  debugProfileLayoutsEnabled = session.priorProfileLayouts;
  debugProfilePaintsEnabled = session.priorProfilePaints;
  perfSessionEndHook();
  _session = null;
}

/// The frame list out of a [framePerfReader] result.
///
/// The reader is assigned in another repository, so the list arrives as
/// whatever `List` the host built. Entries that are not maps are skipped
/// rather than crashing the report they are one row of.
List<Map<String, Object?>> _readFrames(Map<String, Object?> perf) {
  final Object? raw = perf['frames'];
  if (raw is! List<Object?>) return const <Map<String, Object?>>[];
  return raw.whereType<Map<String, Object?>>().toList();
}

/// Aggregates every frame's block map into one session-wide ranking.
///
/// A per-frame view answers "what was slow in the worst frame" (that is what
/// `worst_frames` in the summary is for); this one answers "what did the
/// interaction spend its time on", which is the question a fix follows from.
/// `frames` separates a block that cost 10ms once from one that cost 0.1ms in
/// each of a hundred frames; those need opposite fixes.
List<Map<String, Object?>> _rankBlocks(List<Map<String, Object?>> frames) {
  final Map<String, _BlockTotal> totals = <String, _BlockTotal>{};

  for (final Map<String, Object?> frame in frames) {
    final Object? blocks = frame['blocks'];
    if (blocks is! Map<String, Object?>) continue;

    for (final MapEntry<String, Object?> entry in blocks.entries) {
      final Object? block = entry.value;
      if (block is! Map<String, Object?>) continue;

      final _BlockTotal total = totals.putIfAbsent(
        entry.key,
        () => _BlockTotal(entry.key),
      );
      total.micros += _asInt(block['micros']);
      total.count += _asInt(block['count']);
      total.frames += 1;
    }
  }

  final List<_BlockTotal> ranked = totals.values.toList()
    ..sort((_BlockTotal a, _BlockTotal b) => b.micros.compareTo(a.micros));

  return ranked
      .take(_kRankedBlockLimit)
      .map((_BlockTotal total) => total.toJson())
      .toList();
}

/// One block's running totals across a session.
final class _BlockTotal {
  _BlockTotal(this.name);

  final String name;
  int micros = 0;
  int count = 0;
  int frames = 0;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'micros': micros,
        'count': count,
        'frames': frames,
      };
}

/// Reads an int out of a map built in another repository.
///
/// A missing or non-numeric value reads as 0, which for the liveness counter
/// is the safe direction: a reader that does not report one produces a
/// refusal rather than a report of numbers nothing vouches for.
int _asInt(Object? value) => value is num ? value.toInt() : 0;
