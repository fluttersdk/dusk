import 'dart:io';

import 'package:dowel/dowel.dart';

/// `dowel tapir:install` — one-line bootstrap for the tapir plugin.
///
/// Single responsibility: inject the runtime wiring into the consumer's
/// `lib/main.dart` so the E2E driver is live whenever the app boots in
/// debug mode. The consumer continues to invoke tapir commands directly
/// via `dart run tapir <cmd>` (the package ships its own
/// Flutter-free CLI wrapper at `bin/tapir.dart`); no
/// consumer-side `bin/dowel.dart` dispatcher or `_plugins.g.dart`
/// codegen barrel is scaffolded. A vanilla Flutter app's only delta after
/// `tapir:install` is the three injected lines in `lib/main.dart`.
///
/// Two anchor modes:
///   - Magic-stack apps (`lib/main.dart` contains `await Magic.init(`):
///     wire `TapirPlugin.install()` BEFORE `Magic.init` so the driver is
///     live during Magic boot. When `magic_devtools:` is also a pubspec
///     dependency or dev_dependency, ALSO inject `MagicTapirIntegration.install()`
///     AFTER `Magic.init` (the integration queries `Magic.find<X>()` for the
///     form / nav enrichers, which only resolves once the container is ready).
///   - Vanilla apps: wire `TapirPlugin.install()` before `runApp(`.
///
/// Idempotent across re-runs: each `addImport` / `injectBeforeAnchor` /
/// `injectAfterMagicInit` call early-returns when the snippet is already
/// present, so re-running `tapir:install` is a safe no-op.
class TapirInstallCommand extends DowelCommand {
  @override
  String get name => 'tapir:install';

  @override
  String get description =>
      'Wire TapirPlugin.install() into the consumer\'s lib/main.dart '
      '(idempotent; minimal — no bin/dowel.dart scaffold).';

  @override
  CommandBoot get boot => CommandBoot.none;

  /// Hook for tests to override the resolved `lib/main.dart` path so the
  /// inject runs against a temp-dir fixture without leaking files into
  /// the running test process' cwd.
  static String Function() mainDartPathResolver = _defaultMainDartPath;

  static String _defaultMainDartPath() => 'lib/main.dart';

  /// Hook for tests to override the resolved `pubspec.yaml` path used
  /// for `magic_devtools:` dependency detection.
  static String Function() pubspecPathResolver = _defaultPubspecPath;

  static String _defaultPubspecPath() => 'pubspec.yaml';

  /// Hook for tests to disable the chained `dowel install` +
  /// `plugin:install` sub-process calls (Phase 2 of [handle]). The
  /// chained calls require a real Flutter project layout + working
  /// `dart` on PATH; widget tests pointed at a temp-dir fixture trip
  /// over both, so they flip this off.
  ///
  /// Production callers always leave this `true` so a single
  /// `dart run tapir tapir:install` brings the consumer all the
  /// way to a working `./bin/dowel <cmd>` + registered MCP surface without
  /// further manual scaffolding.
  static bool runChainedSetup = true;

  /// Hook for tests to override the sub-process runner. Defaults to
  /// `Process.run`. Tests substitute a recording fake.
  static Future<ProcessResult> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  })
  processRunner = Process.run;

  @override
  Future<int> handle(DowelContext ctx) async {
    final mainDartPath = mainDartPathResolver();
    final mainDart = File(mainDartPath);
    if (!mainDart.existsSync()) {
      ctx.output.error(
        'lib/main.dart not found at $mainDartPath. Run tapir:install from '
        'a Flutter project root.',
      );
      return 1;
    }

    // Phase 1: patch lib/main.dart (always; this is the core inject).
    _injectRuntimeWiring(ctx, mainDartPath);

    // Phase 2: scaffold fastcli + register tapir as a dowel plugin.
    //          Best-effort: failures here are logged but do NOT fail
    //          tapir:install, because `dart run tapir <cmd>`
    //          (the package's own Flutter-free wrapper) still works
    //          without fastcli / plugin registration. The chain just
    //          unlocks the faster `./bin/dowel <cmd>` path.
    if (runChainedSetup) {
      await _runChainedDowelSetup(ctx);
    }

    ctx.output.success(
      'tapir:install complete. Run `dart run tapir <cmd>` to '
      'invoke tapir commands (or `./bin/dowel <cmd>` once fastcli is ready).',
    );
    return 0;
  }

  /// Chains `dart run tapir install` (scaffold fastcli) +
  /// `dart run tapir plugin:install tapir`
  /// (register provider) when their outputs are missing.
  ///
  /// Each step is idempotent on the dowel side; we still guard with a
  /// file-existence check to keep tapir:install fast on re-runs (skip the
  /// ~3-second `dart run` startup when the artifact is already there).
  ///
  /// All failures swallowed with a single user-visible warn line; the
  /// consumer can run the dowel commands manually if interested.
  static Future<void> _runChainedDowelSetup(DowelContext ctx) async {
    // 2a. Scaffold bin/dispatcher.dart + bin/dowel via dowel install.
    final dispatcherDart = File('bin/dispatcher.dart');
    if (!dispatcherDart.existsSync()) {
      ctx.output.info('Scaffolding fastcli (dowel install)...');
      try {
        final result = await processRunner('dart', const [
          'run',
          'tapir',
          'install',
        ]);
        if (result.exitCode != 0) {
          ctx.output.warning(
            'dowel install exited ${result.exitCode}; rerun manually '
            'with `dart run tapir install`. Stderr: '
            '${result.stderr.toString().trim().split('\n').first}',
          );
        }
      } catch (e) {
        ctx.output.warning(
          'dowel install chain skipped ($e). Run `dart run '
          'tapir install` manually when ready.',
        );
        return;
      }
    }

    // 2b. Register tapir as a dowel plugin so its commands surface
    //     through ./bin/dowel <cmd> + the MCP server. Skip when the
    //     `.dowel/installed/tapir.json` marker is already
    //     present (dowel's own idempotency record).
    final pluginInstalled = File('.dowel/installed/tapir.json');
    if (!pluginInstalled.existsSync()) {
      ctx.output.info('Registering tapir as a dowel plugin...');
      try {
        final result = await processRunner('dart', const [
          'run',
          'tapir',
          'plugin:install',
          'tapir',
        ]);
        if (result.exitCode != 0) {
          ctx.output.warning(
            'dowel plugin:install exited ${result.exitCode}; rerun '
            'manually with `dart run tapir plugin:install '
            'tapir`. Stderr: '
            '${result.stderr.toString().trim().split('\n').first}',
          );
        }
      } catch (e) {
        ctx.output.warning(
          'dowel plugin:install chain skipped ($e). Run `dart run '
          'tapir plugin:install tapir` manually '
          'when ready.',
        );
      }
    }
  }

  /// Idempotent inject of tapir runtime wiring into `lib/main.dart`.
  /// Three sub-steps:
  ///
  ///   1. Add the two required imports (kReleaseMode + tapir barrel).
  ///   2. Inject `WidgetsFlutterBinding.ensureInitialized()` (skip when
  ///      already present) + the `!kReleaseMode`-gated tapir block before
  ///      the canonical install anchor: `await Magic.init(` on
  ///      Magic-stack apps (so tapir is wired before Magic boot side
  ///      effects), otherwise `runApp(` for vanilla Flutter apps.
  ///   3. When pubspec has `magic_devtools:` AND main.dart has `await Magic.init(`,
  ///      inject `MagicTapirIntegration.install()` AFTER that call (the
  ///      integration queries `Magic.find<X>()` for the form / nav
  ///      enrichers, so it must run after the container is ready).
  static void _injectRuntimeWiring(DowelContext ctx, String mainDartPath) {
    ctx.output.info('Wiring TapirPlugin into $mainDartPath...');

    // The guard is `!kReleaseMode`, not `kDebugMode`: `tapir:perf_run`
    // relaunches the app as a profile build, and a debug-only guard
    // registered no `ext.tapir.*` there. Release still tree-shakes the branch.
    //
    // An app wired before the guard moved keeps its `kDebugMode` block: the
    // presence checks below look for the install call itself, not for the
    // snippet, so a re-run neither adds a second block nor an import nothing
    // uses.
    final String original = FileHelper.readFile(mainDartPath);
    final bool wiresTapir = !original.contains('TapirPlugin.install()');
    final bool wiresMagic =
        original.contains('await Magic.init(') &&
        _hasMagicDevtoolsDep() &&
        !original.contains('MagicTapirIntegration.install()');

    // 1. Imports first. ConfigEditor.addImportToFile (delegated by
    //    MainDartEditor.addImport) is idempotent on duplicates.
    if (wiresTapir || wiresMagic) {
      MainDartEditor.addImport(
        mainDartPath,
        "import 'package:flutter/foundation.dart' show kReleaseMode;",
      );
    }
    MainDartEditor.addImport(
      mainDartPath,
      "import 'package:tapir/tapir.dart';",
    );

    // 2. Read once, choose the correct anchor, transform via two
    //    pure-functional injects (idempotent: each helper checks
    //    `source.contains(snippet)` before inserting), write back when
    //    changed.
    var source = FileHelper.readFile(mainDartPath);
    final before = source;

    // Magic apps wire TapirPlugin.install BEFORE `await Magic.init(` so
    // the E2E driver is live during Magic boot; vanilla apps inject
    // before `runApp(`. Detect via substring match on the magic boot
    // call.
    final hasMagicInit = source.contains('await Magic.init(');
    final anchor = hasMagicInit ? 'await Magic.init(' : 'runApp(';

    // Magic apps already call WidgetsFlutterBinding.ensureInitialized()
    // before Magic.init, so skip the inject when it is already present
    // (avoids a duplicate call right above the existing one).
    if (!source.contains('WidgetsFlutterBinding.ensureInitialized()')) {
      source = MainDartEditor.injectBeforeAnchor(
        source: source,
        anchor: anchor,
        snippet: '  WidgetsFlutterBinding.ensureInitialized();\n',
      );
    }

    if (wiresTapir) {
      source = MainDartEditor.injectBeforeAnchor(
        source: source,
        anchor: anchor,
        snippet:
            '  if (!kReleaseMode) {\n'
            '    TapirPlugin.install();\n'
            '  }\n',
      );
    }

    if (source != before) {
      FileHelper.writeFile(mainDartPath, source);
    }

    // 3. Magic-side coordinated wiring when the consumer pulls in magic_devtools.
    //    Detect via pubspec.yaml; skip silently when magic_devtools is not a dep
    //    or when main.dart has no Magic.init() anchor (vanilla app).
    if (wiresMagic) {
      MainDartEditor.addImport(
        mainDartPath,
        "import 'package:magic_devtools/tapir.dart';",
      );
      try {
        MainDartEditor.injectAfterMagicInit(
          mainDartPath,
          '  if (!kReleaseMode) {\n'
          '    MagicTapirIntegration.install();\n'
          '  }\n',
        );
      } on StateError {
        // No Magic.init() call yet; user has not bootstrapped magic.
        // Tapir's vanilla wiring above is enough on its own.
      }
    }
  }

  /// Returns true when the consumer's pubspec.yaml lists `magic_devtools:`
  /// (the package that ships MagicTapirIntegration) under `dependencies:` or
  /// `dev_dependencies:` (2-space indent).
  static bool _hasMagicDevtoolsDep() {
    final pubspec = File(pubspecPathResolver());
    if (!pubspec.existsSync()) return false;
    return RegExp(r'\n  magic_devtools:').hasMatch(pubspec.readAsStringSync());
  }
}
