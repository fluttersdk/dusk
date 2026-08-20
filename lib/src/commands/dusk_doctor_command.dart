import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:meta/meta.dart';

import '../cdp/cdp_client.dart';
import '../utils/chrome_reaper.dart';

/// What a single probe of the recorded CDP port found.
///
/// Three questions, one round-trip, because they fail as one symptom: a
/// screenshot that comes back byte-identical every time tells you nothing
/// about which of them went wrong.
@immutable
final class DuskCdpSessionReport {
  /// Builds a report. [reachable] false means the port refused entirely;
  /// the remaining fields are then meaningless.
  const DuskCdpSessionReport({
    required this.reachable,
    this.pageUrls = const <String>[],
    this.hidden,
  });

  /// Whether `/json` answered at all. False for a stale port left behind by
  /// a killed `flutter run` whose Chrome is gone.
  final bool reachable;

  /// The URL of every `type: "page"` tab the port serves. Used to tell this
  /// run's browser apart from an orphan holding the old build.
  final List<String> pageUrls;

  /// `document.hidden` on the matching page, or null when it could not be
  /// read. True stops frame production, which wedges both snapshots and
  /// gestures.
  final bool? hidden;
}

/// `artisan dusk:doctor` ; environment + runtime preflight for fluttersdk_dusk.
///
/// Runs seven lightweight checks and prints one row per check via the
/// [ArtisanOutput] facade (so colored ✓ / ⚠ / ✗ tokens flow through
/// [ConsoleStyle] in TTY mode and degrade to plain text under
/// [BufferedOutput] / [NullOutput]):
///
///   1. **Hot-restart staleness** ; reads `~/.artisan/state.json`, locates
///      the live Chrome PID via [captureChromePid], and compares Chrome's
///      `ps -o lstart=` start time against `state.json.startedAt`. Drift over
///      30 s means a hot-restart spawned a fresh Chrome after the CLI wrote
///      state.json ; the cached isolate id will be stale, so we WARN. The
///      check downgrades to an INFO "Skipped" row when no state.json exists,
///      no Chrome can be found, or the lstart probe fails (POSIX-only;
///      Windows skips through the chrome_reaper's session-scoped warning).
///   2. **DUSK_DISABLE env-var** ; reads [DuskPlugin.aiTestDisableEnvValue].
///      Non-empty values WARN with the actual value echoed so the operator
///      can confirm where the kill switch came from (a stale `.env` export,
///      a `--dart-define`, etc.).
///   3. **Enricher list non-empty** ; reads `DuskPlugin.enrichers.length`.
///      Zero registered enrichers means the consumer wired DuskPlugin but
///      neither Magic nor Wind glue ; snapshots will still work, just with
///      less context. WARN, never fail.
///   4. **Semantics tree forced on** ; reports whether
///      `RendererBinding.instance.semanticsEnabled` is true. The only
///      ERROR-class check; failure surfaces a non-zero exit code. NOTE:
///      `dusk:doctor` runs in pure-Dart CLI context that cannot import
///      `package:flutter/rendering.dart` (would drag `dart:ui` into a
///      `dart run` invocation), so the default probe returns `true`
///      unconditionally and ERROR is unreachable from CLI alone. The
///      real-runtime check belongs to a future VM-Service-attached doctor
///      invocation; tests override this probe to exercise both branches.
///   5. **Magic-init detection** ; reads `lib/main.dart` and reports whether
///      the consumer wired `Magic.init(` alongside `MagicDuskIntegration.
///      install()`. INFO only ; never fails the doctor regardless of the
///      consumer stack.
///   6. **Session ownership** ; compares `state.json`'s `projectRoot` against
///      the working directory. `~/.artisan/state.json` is one global slot, so
///      a sibling project's `artisan start` silently takes it and every
///      `dusk:*` call from here drives that app instead. WARN.
///   7. **CDP session health** ; probes the recorded `cdpPort` for three
///      failures that all present as a capture which never changes: the port
///      refuses (a killed run left the web port held and its Chrome gone), it
///      serves no page on this run's `webPort` (an orphan browser holding the
///      old build), or the matching page is hidden (frame production off, so
///      snapshots lose their text and gestures cannot land). WARN.
///
/// Test seams: every probe is a static field with a sensible default. Tests
/// override per-check seams via `DuskDoctorCommand.<probe> = ...` in setUp
/// and reset them in tearDown so per-test overrides do not leak.
class DuskDoctorCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:doctor';

  @override
  String get description =>
      'Verify dusk plugin runtime + consumer wiring health';

  @override
  CommandBoot get boot => CommandBoot.none;

  // ---------------------------------------------------------------------------
  // Test seams (static fields; reset between tests in the test file).
  // ---------------------------------------------------------------------------

  /// Reads `~/.artisan/state.json`. Defaults to [StateFile.read].
  static Future<Map<String, dynamic>?> Function() stateFileReader =
      StateFile.read;

  /// Locates the live Chrome PID under a given parent PID. Defaults to the
  /// production [captureChromePid] (POSIX-only; Windows returns null).
  static Future<int?> Function({required int parentPid}) chromePidProbe =
      captureChromePid;

  /// Reads a process's start time (POSIX `ps -o lstart=` / Windows wmic).
  /// Returns null when the probe fails. The default delegates to a private
  /// implementation that mirrors V3's `_parsePsLstart` parser verbatim.
  static DateTime? Function(int pid) processStartTimeProbe =
      _defaultProcessStartTime;

  /// Wall-clock source ; overridable in tests for deterministic drift
  /// arithmetic.
  static DateTime Function() nowProvider = DateTime.now;

  /// Reports whether the running Flutter app has forced Semantics on.
  /// Defaults to `true` because `dusk:doctor` runs in a pure-Dart CLI
  /// context that cannot import `package:flutter/rendering.dart` without
  /// pulling `dart:ui`, which is unavailable outside the Flutter runtime.
  /// In a real debug session the live state is reachable via VM Service +
  /// the dusk:* extensions, not this probe; tests override to exercise
  /// both branches deterministically.
  static bool Function() semanticsEnabledProbe = _defaultSemanticsEnabled;

  /// Reads the DUSK_DISABLE env-var via [DuskPlugin.aiTestDisableEnvValue].
  static String Function() duskDisableEnvReader = _defaultDuskDisableEnvReader;

  /// Reports the count of registered DuskPlugin enrichers. Returns 0 in
  /// CLI context (pure-Dart doctor can't reach into Flutter without pulling
  /// `dart:ui`); the WARN row is the right default outcome since enrichers
  /// living in the running app are only visible via VM Service inspection,
  /// not via static introspection from the CLI process. Tests override to
  /// exercise both branches.
  static int Function() enrichersProbe = _defaultEnrichersProbe;

  /// Resolves the path to the consumer's `lib/main.dart`. Defaults to the
  /// relative path `lib/main.dart`.
  static String Function() mainDartPathResolver = _defaultMainDartPath;

  /// Reads the contents of `lib/main.dart`. Returns null when the file is
  /// absent or unreadable so the check downgrades to an INFO "Skipped" row.
  static String? Function(String path) mainDartReader = _defaultMainDartReader;

  /// Resolves the directory the command is running from, compared against
  /// `state.json`'s `projectRoot` to catch a session that belongs to a
  /// sibling project.
  static String Function() currentDirectoryProbe = defaultCurrentDirectory;

  /// Probes the recorded CDP port. Returns null when the probe itself could
  /// not run, which downgrades the check to a skip rather than inventing a
  /// verdict.
  ///
  /// [webPort] identifies which page belongs to this run; the visibility
  /// read targets that page rather than whichever tab Chrome lists first.
  static Future<DuskCdpSessionReport?> Function(int port, int? webPort)
      cdpSessionProbe = defaultCdpSessionProbe;

  /// Production probe, and the value tests restore [currentDirectoryProbe]
  /// to. A reset that rebuilds the same closure by hand leaves the real one
  /// unexercised, which is how a seam drifts from its default unnoticed.
  static String defaultCurrentDirectory() => Directory.current.path;

  /// Production probe, and the value tests restore [cdpSessionProbe] to.
  /// Public for the same reason [CdpClient.defaultHttpGet] is: a seam a test
  /// swaps needs a named default to swap back.
  ///
  /// One HTTP call for the tab list, one WebSocket for
  /// `document.hidden` on the tab that belongs to this run.
  ///
  /// A refused port is a RESULT here, not an error to propagate: "the port
  /// is dead" is exactly what the check reports, and turning it into a
  /// thrown exception would make the doctor fail instead of diagnose.
  static Future<DuskCdpSessionReport?> defaultCdpSessionProbe(
    int port,
    int? webPort,
  ) async {
    const Duration probeTimeout = Duration(seconds: 5);

    final dynamic raw;
    try {
      // defaultHttpGet, not the cdpHttpGet seam: that one is
      // @visibleForTesting, and this probe is itself the seam tests swap.
      //
      // The decode is inside the try on purpose. A port recorded in
      // state.json that some other service has since taken answers with
      // something that is not CDP JSON, which is one of the three cases
      // this check exists to name; letting the decode throw took the whole
      // doctor run down instead of reporting it.
      final String body = await CdpClient.defaultHttpGet(
        Uri.parse('http://localhost:$port/json'),
      ).timeout(probeTimeout);
      raw = jsonDecode(body);
    } on Object {
      return const DuskCdpSessionReport(reachable: false);
    }

    final List<String> pageUrls = <String>[];
    if (raw is List<dynamic>) {
      for (final dynamic entry in raw) {
        if (entry is Map<String, dynamic> && entry['type'] == 'page') {
          pageUrls.add(entry['url'] as String? ?? '');
        }
      }
    }

    // Visibility is only meaningful for the page under test, and only worth
    // an extra socket once we know one exists.
    bool? hidden;
    final String? match = webPort == null ? null : ':$webPort';
    if (match != null && pageUrls.any((String url) => url.contains(match))) {
      hidden = await _probeHidden(port, match, probeTimeout);
    }

    return DuskCdpSessionReport(
      reachable: true,
      pageUrls: pageUrls,
      hidden: hidden,
    );
  }

  /// Reads `document.hidden` off the page whose URL contains [match].
  /// Returns null when the evaluate could not complete; the caller then
  /// reports the rest of the session rather than guessing.
  static Future<bool?> _probeHidden(
    int port,
    String match,
    Duration timeout,
  ) async {
    CdpClient? client;
    try {
      client = await CdpClient.connect(
        port: port,
        handshakeTimeout: timeout,
        matchUrlSubstring: match,
      );
      final Map<String, dynamic> result = await client.send(
        'Runtime.evaluate',
        <String, dynamic>{
          'expression': 'document.hidden',
          'returnByValue': true,
        },
      );
      final Object? value =
          (result['result'] as Map<String, dynamic>?)?['value'];
      return value is bool ? value : null;
    } on DuskCdpException {
      return null;
    } finally {
      await client?.close();
    }
  }

  static String _defaultMainDartPath() => 'lib/main.dart';

  static String? _defaultMainDartReader(String path) {
    try {
      final File file = File(path);
      if (!file.existsSync()) return null;
      return file.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  /// Reads the same compile-time DUSK_DISABLE value
  /// [DuskPlugin.aiTestDisableEnvValue] resolves to. Replicated here (rather
  /// than imported from DuskPlugin) because the canonical getter on
  /// DuskPlugin is marked `@visibleForTesting` ; reading it from another
  /// production file would trip the analyzer. Both readers consume the same
  /// `--dart-define=DUSK_DISABLE=<value>` compile-time constant so they can
  /// never drift.
  static String _defaultDuskDisableEnvReader() =>
      const String.fromEnvironment('DUSK_DISABLE', defaultValue: '');

  static int _defaultEnrichersProbe() => 0;

  static bool _defaultSemanticsEnabled() {
    // Pure-Dart CLI context cannot import package:flutter/rendering.dart
    // without dragging dart:ui (which is unavailable outside the Flutter
    // runtime), so the default returns true. Tests override this probe
    // to exercise both ERROR and pass branches deterministically; the
    // real-runtime check belongs in a future VM-Service-attached doctor
    // invocation that queries ext.dusk.semantics_enabled or equivalent.
    return true;
  }

  // ---------------------------------------------------------------------------
  // handle()
  // ---------------------------------------------------------------------------

  @override
  Future<int> handle(ArtisanContext ctx) async {
    bool hasError = false;

    // 1. Hot-restart staleness probe.
    await _renderStaleness(ctx);

    // 2. DUSK_DISABLE env-var probe.
    _renderDuskDisable(ctx);

    // 3. Enricher list non-empty probe.
    _renderEnrichers(ctx);

    // 4. Semantics tree forced on probe (only ERROR-class check).
    hasError = !_renderSemantics(ctx) || hasError;

    // 5. Magic-init detection (INFO-only; never fails).
    _renderMagicInit(ctx);

    // 6. Session ownership: is the state file describing THIS project?
    await _renderSessionOwnership(ctx);

    // 7. CDP session: is the recorded port live, serving this run, visible?
    await _renderCdpSession(ctx);

    return hasError ? 1 : 0;
  }

  // ---------------------------------------------------------------------------
  // Check 1 ; hot-restart staleness
  // ---------------------------------------------------------------------------

  Future<void> _renderStaleness(ArtisanContext ctx) async {
    const String label = 'hot-restart staleness';
    final Map<String, dynamic>? state = await stateFileReader();
    if (state == null) {
      ctx.output.info('$label: Skipped (no Chrome attached)');
      return;
    }
    final int? pid = state['pid'] as int?;
    final String? startedAtIso = state['startedAt'] as String?;
    if (pid == null || startedAtIso == null) {
      ctx.output.info('$label: Skipped (no Chrome attached)');
      return;
    }

    final int? chromePid = await chromePidProbe(parentPid: pid);
    if (chromePid == null) {
      ctx.output.info('$label: Skipped (no Chrome attached)');
      return;
    }

    final DateTime? chromeStart = processStartTimeProbe(chromePid);
    if (chromeStart == null) {
      ctx.output.info('$label: Skipped (no Chrome attached)');
      return;
    }

    final DateTime startedAt = DateTime.parse(startedAtIso);
    final Duration drift = chromeStart.difference(startedAt);
    if (drift.inSeconds > 30) {
      ctx.output.warning(
        '$label: hot-restart drift detected (Chrome started '
        '${drift.inSeconds}s after CLI startedAt); restart the CLI to refresh '
        'the cached isolate id.',
      );
      return;
    }
    ctx.output.success('$label: no drift detected (Chrome PID $chromePid)');
  }

  // ---------------------------------------------------------------------------
  // Check 2 ; DUSK_DISABLE env-var
  // ---------------------------------------------------------------------------

  void _renderDuskDisable(ArtisanContext ctx) {
    const String label = 'DUSK_DISABLE env-var';
    final String value = duskDisableEnvReader();
    if (value.isEmpty) {
      ctx.output.success('$label: unset (runtime hooks active)');
      return;
    }
    ctx.output.warning(
      '$label: dusk disabled via DUSK_DISABLE=$value, runtime hooks inactive',
    );
  }

  // ---------------------------------------------------------------------------
  // Check 3 ; enricher list non-empty
  // ---------------------------------------------------------------------------

  void _renderEnrichers(ArtisanContext ctx) {
    const String label = 'snapshot enrichers';
    final int count = enrichersProbe();
    if (count == 0) {
      ctx.output.info('$label: enrichers are opt-in; none registered');
      return;
    }
    ctx.output.success('$label: enrichers registered: $count');
  }

  // ---------------------------------------------------------------------------
  // Check 4 ; Semantics tree forced on (only ERROR-class check)
  // ---------------------------------------------------------------------------

  /// Returns true when the check passes, false when it fails (ERROR).
  bool _renderSemantics(ArtisanContext ctx) {
    const String label = 'Semantics tree forced on';
    if (semanticsEnabledProbe()) {
      ctx.output.success('$label: enabled');
      return true;
    }
    ctx.output.error(
      '$label: Semantics tree not forced on; DuskPlugin.install may not have '
      'run',
    );
    return false;
  }

  // ---------------------------------------------------------------------------
  // Check 5 ; Magic-init detection (INFO-only)
  // ---------------------------------------------------------------------------

  void _renderMagicInit(ArtisanContext ctx) {
    const String label = 'Magic-init detection';
    final String path = mainDartPathResolver();
    final String? source = mainDartReader(path);
    if (source == null) {
      ctx.output.info('$label: Skipped (lib/main.dart unreadable)');
      return;
    }

    final bool hasMagicInit = source.contains('Magic.init(');
    final bool hasMagicIntegration =
        source.contains('MagicDuskIntegration.install');

    if (hasMagicInit && hasMagicIntegration) {
      ctx.output.info('$label: Magic-stack detected, integration wired');
      return;
    }
    if (hasMagicInit) {
      ctx.output.info(
        '$label: Magic detected but MagicDuskIntegration missing — install '
        'via dusk:install',
      );
      return;
    }
    ctx.output.info('$label: vanilla Flutter detected');
  }

  // ---------------------------------------------------------------------------
  // Default process-start-time probe (ported from V3 doctor_command.dart:
  // 190 ; 209, adapted to the new doctor's lstart-only signature).
  // ---------------------------------------------------------------------------

  @visibleForTesting
  static DateTime? defaultProcessStartTime(int pid) =>
      _defaultProcessStartTime(pid);

  @visibleForTesting
  static DateTime? parsePsLstartForTesting(String raw) => _parsePsLstart(raw);

  static DateTime? _defaultProcessStartTime(int pid) {
    try {
      if (Platform.isWindows) {
        final ProcessResult res = Process.runSync(
          'wmic',
          <String>['process', 'where', 'ProcessId=$pid', 'get', 'CreationDate'],
        );
        final String raw = res.stdout.toString().trim();
        final RegExp pattern = RegExp(r'(\d{14})');
        final Match? match = pattern.firstMatch(raw);
        if (match == null) return null;
        final String ts = match.group(1)!;
        return DateTime.utc(
          int.parse(ts.substring(0, 4)),
          int.parse(ts.substring(4, 6)),
          int.parse(ts.substring(6, 8)),
          int.parse(ts.substring(8, 10)),
          int.parse(ts.substring(10, 12)),
          int.parse(ts.substring(12, 14)),
        );
      }
      // POSIX: `ps -o lstart=` emits e.g. "Fri May 16 14:30:25 2026".
      final ProcessResult res = Process.runSync(
        'ps',
        <String>['-o', 'lstart=', '-p', '$pid'],
      );
      final String raw = res.stdout.toString().trim();
      if (raw.isEmpty) return null;
      return _parsePsLstart(raw);
    } catch (_) {
      return null;
    }
  }

  static const Map<String, int> _monthMap = <String, int>{
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
  };

  /// Parses `ps -o lstart=` output ("Fri May 16 14:30:25 2026") to local
  /// DateTime. Returns null on any parse failure.
  static DateTime? _parsePsLstart(String raw) {
    try {
      final RegExp pattern = RegExp(
        r'^\w{3}\s+(\w{3})\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})\s+(\d{4})',
      );
      final Match? m = pattern.firstMatch(raw);
      if (m == null) return null;
      final int? month = _monthMap[m.group(1)!];
      if (month == null) return null;
      return DateTime(
        int.parse(m.group(6)!),
        month,
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Check 6 ; session ownership
  // ---------------------------------------------------------------------------

  /// Compares `state.json`'s `projectRoot` against the directory this
  /// command is running from.
  ///
  /// `~/.artisan/state.json` is ONE global file. Two projects driven at
  /// once share it, and the second `start` silently rewrites the first's
  /// entry: the measured case had a sibling worktree take the file
  /// mid-session, after which two `dusk:*` calls drove the wrong app and
  /// produced a screenshot of an entirely different product. Nothing in the
  /// output said so, because every command succeeded.
  Future<void> _renderSessionOwnership(ArtisanContext ctx) async {
    const String label = 'Session ownership';

    final Map<String, dynamic>? state = await stateFileReader();
    final Object? recorded = state?['projectRoot'];
    if (state == null || recorded is! String || recorded.isEmpty) {
      ctx.output.info('$label: Skipped (no projectRoot in state.json)');
      return;
    }

    final String here = currentDirectoryProbe();
    if (_isWithinProject(here, recorded)) {
      ctx.output.success('$label: state.json describes this project');
      return;
    }

    ctx.output.warning(
      '$label: state.json describes another project ($recorded), not this '
      'one ($here). `~/.artisan/state.json` is a shared pointer to whichever '
      'app started last, so every dusk:* call from here would drive that app '
      'instead. Re-run `artisan start` for this project, or pass '
      '--state=<path> to name the session you mean.',
    );
  }

  /// Probes the CDP port recorded in state and reports the three ways it
  /// goes wrong, all of which present as a capture that never changes.
  Future<void> _renderCdpSession(ArtisanContext ctx) async {
    const String label = 'CDP session';

    final Map<String, dynamic>? state = await stateFileReader();
    final int? cdpPort = _asInt(state?['cdpPort']);
    if (cdpPort == null) {
      ctx.output.info(
        '$label: Skipped (no cdpPort recorded; start with --cdp-port=N to '
        'enable dusk:resize, dusk:device and clipped web screenshots)',
      );
      return;
    }

    final int? webPort = _asInt(state?['webPort']);
    final DuskCdpSessionReport? report =
        await cdpSessionProbe(cdpPort, webPort);
    if (report == null) {
      ctx.output.info('$label: Skipped (probe unavailable)');
      return;
    }

    if (!report.reachable) {
      ctx.output.warning(
        '$label: port $cdpPort is unreachable. A killed `flutter run` can '
        'leave its dart dev server holding the web port while its Chrome '
        'is gone, so the recorded port points at nothing. Re-run '
        '`artisan start --cdp-port=N`.',
      );
      return;
    }

    if (webPort != null &&
        !report.pageUrls.any((String url) => url.contains(':$webPort'))) {
      ctx.output.warning(
        '$label: port $cdpPort serves no page on this run\'s web port '
        '$webPort (found: ${report.pageUrls.join(", ")}). This is usually '
        'an orphan browser left over from a killed run, holding the old '
        'build; captures come back byte-identical from it and nothing else '
        'says why.',
      );
      return;
    }

    if (report.hidden == true) {
      ctx.output.warning(
        '$label: the page on port $cdpPort is hidden '
        '(document.visibilityState). Flutter stops producing frames there, '
        'so snapshots lose their text nodes and gestures cannot take '
        'effect. Send CDP Page.bringToFront and retry.',
      );
      return;
    }

    ctx.output.success(
      '$label: port $cdpPort serving '
      '${webPort == null ? "this run" : ":$webPort"}'
      '${report.hidden == false ? ", page visible" : ""}',
    );
  }

  /// Whether [here] is [recorded] or sits beneath it.
  ///
  /// IS-WITHIN, not equality: running from `backend/` or a package
  /// subdirectory is normal, and artisan's own `sessionOwnershipError` lets
  /// it through. Comparing exactly made the doctor warn about a session
  /// artisan itself considers this project's.
  ///
  /// Duplicated from artisan rather than imported because
  /// `sessionOwnershipError` is not in the published `fluttersdk_artisan`
  /// this package resolves against; fold the two together at the next
  /// coordinated bump.
  ///
  /// Trailing separators and symlinks are normalised first: a git worktree
  /// checkout is routinely a symlink and would otherwise read as a mismatch
  /// on an identical directory.
  static bool _isWithinProject(String here, String recorded) {
    String normalise(String raw) {
      final String trimmed =
          raw.endsWith(Platform.pathSeparator) && raw.length > 1
              ? raw.substring(0, raw.length - 1)
              : raw;
      final Directory dir = Directory(trimmed);
      return dir.existsSync() ? dir.resolveSymbolicLinksSync() : trimmed;
    }

    final String child = normalise(here);
    final String parent = normalise(recorded);
    return child == parent ||
        child.startsWith('$parent${Platform.pathSeparator}');
  }

  /// Reads an int from a state field, tolerating `int`, `num`, or a numeric
  /// `String` so a cross-version state file does not throw on a force-cast.
  static int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }
}
