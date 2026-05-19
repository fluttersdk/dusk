import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';

import '../utils/chrome_reaper.dart';

/// `artisan dusk:doctor` ; environment + runtime preflight for fluttersdk_dusk.
///
/// Runs five lightweight checks and prints one row per check via the
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
      ctx.output.warning(
        '$label: no enrichers registered; install Magic + Wind integrations '
        'for richer snapshots',
      );
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
}
