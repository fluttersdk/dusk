import 'dart:convert';
import 'dart:io';

import 'package:dowel/dowel.dart';
import 'package:meta/meta.dart';

import '../cdp/cdp_client.dart';
import '../utils/chrome_reaper.dart';
import 'tapir_install_command.dart';

/// What a single probe of the recorded CDP port found.
///
/// Three questions, one round-trip, because they fail as one symptom: a
/// screenshot that comes back byte-identical every time tells you nothing
/// about which of them went wrong.
@immutable
final class TapirCdpSessionReport {
  /// Builds a report. [reachable] false means the port refused entirely;
  /// the remaining fields are then meaningless.
  const TapirCdpSessionReport({
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

/// How the running app answered `tapir:doctor`'s `ext.tapir.boot_id` call.
enum TapirAppStatus {
  /// It answered; [TapirAppReport.semanticsEnabled] and
  /// [TapirAppReport.enrichers] hold what it reported.
  answered,

  /// The app runs but registers no `ext.tapir.*`: no `TapirPlugin.install()`
  /// call, or a build with `TAPIR_DISABLE`.
  notRegistered,

  /// The call failed or timed out; [TapirAppReport.reason] says how.
  unreachable,
}

/// What the running app reported to `tapir:doctor`.
@immutable
final class TapirAppReport {
  /// An answer. A null field is a key the app's tapir does not send yet.
  const TapirAppReport.answered({
    required this.semanticsEnabled,
    required this.enrichers,
  }) : status = TapirAppStatus.answered,
       reason = null;

  /// An app without `ext.tapir.*`.
  const TapirAppReport.notRegistered()
    : status = TapirAppStatus.notRegistered,
      semanticsEnabled = null,
      enrichers = null,
      reason = null;

  /// A call that did not come back, for [reason].
  const TapirAppReport.unreachable(String this.reason)
    : status = TapirAppStatus.unreachable,
      semanticsEnabled = null,
      enrichers = null;

  /// How the call went.
  final TapirAppStatus status;

  /// Whether the app's semantics tree is on.
  final bool? semanticsEnabled;

  /// How many snapshot enrichers the app registered.
  final int? enrichers;

  /// The first line of the failure, for [TapirAppStatus.unreachable].
  final String? reason;
}

/// `dowel tapir:doctor` ; environment + runtime preflight for tapir.
///
/// Runs eight lightweight checks and prints one row per check via the
/// [DowelOutput] facade (so colored ✓ / ⚠ / ✗ tokens flow through
/// [ConsoleStyle] in TTY mode and degrade to plain text under
/// [BufferedOutput] / [NullOutput]):
///
///   1. **Hot-restart staleness** ; reads `~/.dowel/state.json`, locates
///      the live Chrome PID via [captureChromePid], and compares Chrome's
///      `ps -o lstart=` start time against `state.json.startedAt`. Drift over
///      30 s means a hot-restart spawned a fresh Chrome after the CLI wrote
///      state.json ; the cached isolate id will be stale, so we WARN. The
///      check downgrades to an INFO "Skipped" row when no state.json exists,
///      no Chrome can be found, or the lstart probe fails (POSIX-only;
///      Windows skips through the chrome_reaper's session-scoped warning).
///   2 to 4 ask the running app over the session's VM Service ([appProbe],
///      an `ext.tapir.boot_id` call), once more after
///      [registrationRetryDelay] when it registers no `ext.tapir.*`; with no
///      session, or an app that does not answer, each prints a skipped row.
///   2. **TAPIR_DISABLE** ; WARN when the app registers no `ext.tapir.*`
///      (built with `TAPIR_DISABLE`, or no `TapirPlugin.install()` call).
///   3. **Snapshot enrichers** ; the count the app registered. Zero means
///      neither Magic nor Wind glue is wired; snapshots still work, with
///      less context. INFO, never fail.
///   4. **Semantics tree forced on** ; the app's semantics state. The only
///      ERROR-class check: a tree that is off, or an app with no tapir,
///      exits non-zero.
///   5. **Magic-init detection** ; reads `lib/main.dart` and reports whether
///      the consumer wired `Magic.init(` alongside `MagicTapirIntegration.
///      install()`. INFO only ; never fails the doctor regardless of the
///      consumer stack. Advice to wire the integration is given only when
///      the resolved `magic_devtools` ships `lib/tapir.dart`; otherwise the
///      row says what to upgrade or add.
///   6. **Session ownership** ; compares `state.json`'s `projectRoot` against
///      the working directory. `~/.dowel/state.json` is one global slot, so
///      a sibling project's `dowel start` silently takes it and every
///      `tapir:*` call from here drives that app instead. WARN.
///   7. **CDP session health** ; probes the recorded `cdpPort` for three
///      failures that all present as a capture which never changes: the port
///      refuses (a killed run left the web port held and its Chrome gone), it
///      serves no page on this run's `webPort` (an orphan browser holding the
///      old build), or the matching page is hidden (frame production off, so
///      snapshots lose their text and gestures cannot land). WARN.
///   8. **fluttersdk_dusk leftovers** ; the files a `fluttersdk_dusk`
///      install left that stop the dowel setup working
///      ([TapirInstallCommand.legacyDuskLeftovers]), with the commands that
///      follow deleting them. WARN.
///
/// Test seams: every probe is a static field with a sensible default. Tests
/// override per-check seams via `TapirDoctorCommand.<probe> = ...` in setUp
/// and reset them in tearDown so per-test overrides do not leak.
class TapirDoctorCommand extends DowelCommand {
  @override
  String get name => 'tapir:doctor';

  @override
  String get description =>
      'Verify tapir plugin runtime + consumer wiring health';

  @override
  CommandBoot get boot => CommandBoot.none;

  // ---------------------------------------------------------------------------
  // Test seams (static fields; reset between tests in the test file).
  // ---------------------------------------------------------------------------

  /// Reads `~/.dowel/state.json`. Defaults to [StateFile.read].
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

  /// Asks the app the session state names for what only it can report:
  /// whether tapir registered, the semantics state and the enricher count.
  /// Returns null when the state names no app (no session), which skips the
  /// three rows that need one.
  ///
  /// The CLI process cannot answer any of them itself: it runs on the plain
  /// Dart VM, and its own `TAPIR_DISABLE` define says nothing about the
  /// app's build.
  static Future<TapirAppReport?> Function(Map<String, dynamic>? state)
  appProbe = defaultAppProbe;

  /// Waits [registrationRetryDelay] before [appProbe] is asked again; tests
  /// substitute a wait that returns at once.
  static Future<void> Function(Duration wait) registrationRetryWait =
      Future<void>.delayed;

  /// How long the doctor waits before asking an app that registered no
  /// `ext.tapir.*` a second time. `ext.tapir.boot_id` registers last, so a
  /// run right after a hot restart can land before tapir has registered.
  static const Duration registrationRetryDelay = Duration(seconds: 1);

  /// Builds the VM Service client [defaultAppProbe] connects with; tests
  /// substitute a fake.
  static VmServiceClient Function(String wsUri) vmClientFactory =
      VmServiceClient.new;

  /// Reports what `fluttersdk_dusk` left in the project
  /// ([TapirInstallCommand.legacyDuskLeftovers] on the working directory).
  static List<String> Function() legacyLeftoversProbe =
      defaultLegacyLeftoversProbe;

  /// Resolves the path to the consumer's `lib/main.dart`. Defaults to the
  /// relative path `lib/main.dart`.
  static String Function() mainDartPathResolver = _defaultMainDartPath;

  /// Reads the contents of `lib/main.dart`. Returns null when the file is
  /// absent or unreadable so the check downgrades to an INFO "Skipped" row.
  static String? Function(String path) mainDartReader = _defaultMainDartReader;

  /// Reports whether the consumer's resolved `magic_devtools` ships the
  /// tapir integration, so the Magic advice never names a class the
  /// consumer cannot import.
  static MagicDevtoolsTapirSupport Function() magicDevtoolsTapirProbe =
      defaultMagicDevtoolsTapirProbe;

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
  static Future<TapirCdpSessionReport?> Function(int port, int? webPort)
  cdpSessionProbe = defaultCdpSessionProbe;

  /// Production probe, and the value tests restore [currentDirectoryProbe]
  /// to. A reset that rebuilds the same closure by hand leaves the real one
  /// unexercised, which is how a seam drifts from its default unnoticed.
  static String defaultCurrentDirectory() => Directory.current.path;

  /// Production probe, and the value tests restore
  /// [magicDevtoolsTapirProbe] to: the installer's own check, run against
  /// the working directory, so the advice and the install never disagree.
  static MagicDevtoolsTapirSupport defaultMagicDevtoolsTapirProbe() =>
      TapirInstallCommand.magicDevtoolsTapirSupport(Directory.current.path);

  /// Production probe, and the value tests restore [legacyLeftoversProbe]
  /// to: the installer's own check, so the two never disagree.
  static List<String> defaultLegacyLeftoversProbe() =>
      TapirInstallCommand.legacyDuskLeftovers(Directory.current.path);

  /// Production probe, and the value tests restore [appProbe] to.
  ///
  /// One `ext.tapir.boot_id` call over the recorded `vmServiceUri`: an
  /// answer proves every `ext.tapir.*` registered, and it carries the
  /// semantics state and the enricher count. A method-not-found answer means
  /// the app never ran `TapirPlugin.install()` or was built with
  /// `TAPIR_DISABLE`. Any other failure (a dead URI, a refused socket, no
  /// answer within the timeout) is a result the rows report, not an error
  /// that ends the doctor run.
  static Future<TapirAppReport?> defaultAppProbe(
    Map<String, dynamic>? state,
  ) async {
    final Object? uri = state?['vmServiceUri'];
    if (uri is! String || uri.isEmpty) return null;

    final VmServiceClient client = vmClientFactory(uri);
    try {
      final Map<String, dynamic> answer = await () async {
        await client.connect();
        final String isolateId = await client.getMainIsolateId();
        return client.callServiceExtension<Map<String, dynamic>>(
          'ext.tapir.boot_id',
          isolateId: isolateId,
        );
      }().timeout(const Duration(seconds: 5));
      final Object? semantics = answer['semanticsEnabled'];
      final Object? enrichers = answer['enrichers'];
      return TapirAppReport.answered(
        semanticsEnabled: semantics is bool ? semantics : null,
        enrichers: enrichers is int ? enrichers : null,
      );
    } on ExtensionNotRegisteredException {
      return const TapirAppReport.notRegistered();
    } on Object catch (e) {
      return TapirAppReport.unreachable('$e'.split('\n').first);
    } finally {
      await client.disconnect();
    }
  }

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
  static Future<TapirCdpSessionReport?> defaultCdpSessionProbe(
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
      return const TapirCdpSessionReport(reachable: false);
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

    return TapirCdpSessionReport(
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
    } on TapirCdpException {
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

  // ---------------------------------------------------------------------------
  // handle()
  // ---------------------------------------------------------------------------

  @override
  Future<int> handle(DowelContext ctx) async {
    // 1. Hot-restart staleness probe.
    await _renderStaleness(ctx);

    // 2 to 4 read the running app. A not-registered answer is asked once
    // more, since a hot restart drops every extension until tapir registers
    // them again; only the second one is the app's state.
    final Map<String, dynamic>? state = await stateFileReader();
    TapirAppReport? app = await appProbe(state);
    if (app?.status == TapirAppStatus.notRegistered) {
      await registrationRetryWait(registrationRetryDelay);
      app = await appProbe(state);
    }

    // 2. Is tapir registered in the app, or did its build disable it?
    _renderTapirDisable(ctx, app);

    // 3. Enricher count, as the app reports it.
    _renderEnrichers(ctx, app);

    // 4. Semantics tree forced on (only ERROR-class check).
    final bool hasError = !_renderSemantics(ctx, app);

    // 5. Magic-init detection (INFO-only; never fails).
    _renderMagicInit(ctx);

    // 6. Session ownership: is the state file describing THIS project?
    await _renderSessionOwnership(ctx);

    // 7. CDP session: is the recorded port live, serving this run, visible?
    await _renderCdpSession(ctx);

    // 8. What a fluttersdk_dusk install left behind.
    _renderLegacyLeftovers(ctx);

    return hasError ? 1 : 0;
  }

  /// The skipped-row reason for [app] when it holds no answer, or null when
  /// it does.
  static String? _skipReason(TapirAppReport? app) => switch (app?.status) {
    null => 'Skipped (no running app; start one with `dowel start`)',
    TapirAppStatus.unreachable =>
      'Skipped (the running app did not answer: ${app!.reason})',
    TapirAppStatus.notRegistered || TapirAppStatus.answered => null,
  };

  // ---------------------------------------------------------------------------
  // Check 1 ; hot-restart staleness
  // ---------------------------------------------------------------------------

  Future<void> _renderStaleness(DowelContext ctx) async {
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
  // Check 2 ; TAPIR_DISABLE in the running app
  // ---------------------------------------------------------------------------

  void _renderTapirDisable(DowelContext ctx, TapirAppReport? app) {
    const String label = 'TAPIR_DISABLE';
    final String? skipped = _skipReason(app);
    if (skipped != null) {
      ctx.output.info('$label: $skipped');
      return;
    }
    if (app!.status == TapirAppStatus.notRegistered) {
      ctx.output.warning(
        '$label: the running app registers no ext.tapir.* extension; it was '
        'built with --dart-define=TAPIR_DISABLE=1, or it never calls '
        'TapirPlugin.install()',
      );
      return;
    }
    ctx.output.success('$label: not set in the running app (ext.tapir.* live)');
  }

  // ---------------------------------------------------------------------------
  // Check 3 ; enricher count in the running app
  // ---------------------------------------------------------------------------

  void _renderEnrichers(DowelContext ctx, TapirAppReport? app) {
    const String label = 'snapshot enrichers';
    final String? skipped = _skipReason(app);
    final int? count = app?.enrichers;
    if (skipped != null || count == null) {
      ctx.output.info('$label: ${skipped ?? _unreported}');
      return;
    }
    if (count == 0) {
      ctx.output.info('$label: enrichers are opt-in; none registered');
      return;
    }
    ctx.output.success('$label: enrichers registered: $count');
  }

  // ---------------------------------------------------------------------------
  // Check 4 ; Semantics tree forced on (only ERROR-class check)
  // ---------------------------------------------------------------------------

  /// Returns true when the check passes or cannot run, false when it fails
  /// (ERROR): the app answers with the tree off, or registers no tapir.
  bool _renderSemantics(DowelContext ctx, TapirAppReport? app) {
    const String label = 'Semantics tree forced on';
    final String? skipped = _skipReason(app);
    if (skipped != null) {
      ctx.output.info('$label: $skipped');
      return true;
    }
    if (app!.status == TapirAppStatus.notRegistered) {
      ctx.output.error(
        '$label: Semantics tree not forced on; TapirPlugin.install has not '
        'run in the running app',
      );
      return false;
    }
    final bool? enabled = app.semanticsEnabled;
    if (enabled == null) {
      ctx.output.info('$label: $_unreported');
      return true;
    }
    if (enabled) {
      ctx.output.success('$label: enabled in the running app');
      return true;
    }
    ctx.output.error(
      '$label: Semantics tree not forced on in the running app; refs cannot '
      'resolve (a perf semantics pass left it released, or the handle was '
      'disposed). Hot restart the app.',
    );
    return false;
  }

  /// The skipped-row reason for an app that answered without a key this
  /// doctor reads: its tapir predates the key.
  static const String _unreported =
      'Skipped (the running app\'s tapir predates this check; upgrade it)';

  // ---------------------------------------------------------------------------
  // Check 8 ; leftovers from fluttersdk_dusk
  // ---------------------------------------------------------------------------

  void _renderLegacyLeftovers(DowelContext ctx) {
    const String label = 'fluttersdk_dusk leftovers';
    final List<String> leftovers;
    try {
      leftovers = legacyLeftoversProbe();
    } on FileSystemException catch (e) {
      // A scan that stopped part way has not shown the project is clean.
      ctx.output.warning(
        '$label: could not inspect ${e.path ?? 'the project'}: ${e.message}',
      );
      return;
    }
    if (leftovers.isEmpty) {
      ctx.output.success('$label: none found');
      return;
    }
    ctx.output.warning(
      '$label: found\n'
      '${leftovers.map((String line) => '  - $line').join('\n')}\n'
      '${TapirInstallCommand.legacyDuskFix}',
    );
  }

  // ---------------------------------------------------------------------------
  // Check 5 ; Magic-init detection (INFO-only)
  // ---------------------------------------------------------------------------

  void _renderMagicInit(DowelContext ctx) {
    const String label = 'Magic-init detection';
    final String path = mainDartPathResolver();
    final String? source = mainDartReader(path);
    if (source == null) {
      ctx.output.info('$label: Skipped (lib/main.dart unreadable)');
      return;
    }

    final bool hasMagicInit = source.contains('Magic.init(');
    final bool hasMagicIntegration = source.contains(
      'MagicTapirIntegration.install',
    );

    if (hasMagicInit && hasMagicIntegration) {
      ctx.output.info('$label: Magic-stack detected, integration wired');
      return;
    }
    if (hasMagicInit) {
      // Only a magic_devtools that ships `lib/tapir.dart` has the class to
      // wire; for any other, the advice is what to upgrade.
      ctx.output.info(switch (magicDevtoolsTapirProbe()) {
        MagicDevtoolsTapirSupport.available =>
          '$label: Magic detected but MagicTapirIntegration missing; wire it '
              'with tapir:install',
        MagicDevtoolsTapirSupport.missing =>
          '$label: Magic detected, but the installed magic_devtools has no '
              'tapir integration yet; upgrade it to a release built on tapir, '
              'then rerun tapir:install',
        MagicDevtoolsTapirSupport.unresolved =>
          '$label: Magic detected, but no magic_devtools resolved; add a '
              'release built on tapir to dev_dependencies, run flutter pub '
              'get, then rerun tapir:install',
      });
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
        final ProcessResult res = Process.runSync('wmic', <String>[
          'process',
          'where',
          'ProcessId=$pid',
          'get',
          'CreationDate',
        ]);
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
      final ProcessResult res = Process.runSync('ps', <String>[
        '-o',
        'lstart=',
        '-p',
        '$pid',
      ]);
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
  /// `~/.dowel/state.json` is ONE global file. Two projects driven at
  /// once share it, and the second `start` silently rewrites the first's
  /// entry: the measured case had a sibling worktree take the file
  /// mid-session, after which two `tapir:*` calls drove the wrong app and
  /// produced a screenshot of an entirely different product. Nothing in the
  /// output said so, because every command succeeded.
  Future<void> _renderSessionOwnership(DowelContext ctx) async {
    const String label = 'Session ownership';

    final Map<String, dynamic>? state = await stateFileReader();
    final Object? recorded = state?['projectRoot'];
    if (state == null || recorded is! String || recorded.isEmpty) {
      ctx.output.info('$label: Skipped (no projectRoot in state.json)');
      return;
    }

    final String here = currentDirectoryProbe();
    // dowel's own rule, not a second copy of it. The doctor used to
    // compare the two paths for equality while `sessionOwnershipError`
    // compares is-within, so a caller standing in a subdirectory was told
    // the session belonged to somebody else while every dowel command
    // happily drove it. Two tools disagreeing about one state file is worse
    // than either answer alone.
    if (sessionOwnershipError(
          state: state,
          workingDirectory: here,
          explicitStatePath: StateFile.explicitPath(),
        ) ==
        null) {
      ctx.output.success('$label: state.json describes this project');
      return;
    }

    ctx.output.warning(
      '$label: state.json describes another project ($recorded), not this '
      'one ($here). `~/.dowel/state.json` is a shared pointer to whichever '
      'app started last, so every tapir:* call from here would drive that app '
      'instead. Re-run `dowel start` for this project, or pass '
      '--state=<path> to name the session you mean.',
    );
  }

  /// Probes the CDP port recorded in state and reports the three ways it
  /// goes wrong, all of which present as a capture that never changes.
  Future<void> _renderCdpSession(DowelContext ctx) async {
    const String label = 'CDP session';

    final Map<String, dynamic>? state = await stateFileReader();
    final int? cdpPort = _asInt(state?['cdpPort']);
    if (cdpPort == null) {
      ctx.output.info(
        '$label: Skipped (no cdpPort recorded; start with --cdp-port=N to '
        'enable tapir:resize_viewport, tapir:device_profile and clipped web screenshots)',
      );
      return;
    }

    final int? webPort = _asInt(state?['webPort']);
    final TapirCdpSessionReport? report = await cdpSessionProbe(
      cdpPort,
      webPort,
    );
    if (report == null) {
      ctx.output.info('$label: Skipped (probe unavailable)');
      return;
    }

    if (!report.reachable) {
      ctx.output.warning(
        '$label: port $cdpPort is unreachable. A killed `flutter run` can '
        'leave its dart dev server holding the web port while its Chrome '
        'is gone, so the recorded port points at nothing. Re-run '
        '`dowel start --cdp-port=N`.',
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

  /// Reads an int from a state field, tolerating `int`, `num`, or a numeric
  /// `String` so a cross-version state file does not throw on a force-cast.
  static int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }
}
