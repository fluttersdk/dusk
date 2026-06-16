import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:install` — one-line bootstrap for the dusk plugin.
///
/// Single responsibility: inject the runtime wiring into the consumer's
/// `lib/main.dart` so the E2E driver is live whenever the app boots in
/// debug mode. The consumer continues to invoke dusk commands directly
/// via `dart run fluttersdk_dusk <cmd>` (the package ships its own
/// Flutter-free CLI wrapper at `bin/fluttersdk_dusk.dart`); no
/// consumer-side `bin/artisan.dart` dispatcher or `_plugins.g.dart`
/// codegen barrel is scaffolded. A vanilla Flutter app's only delta after
/// `dusk:install` is the three injected lines in `lib/main.dart`.
///
/// Two anchor modes:
///   - Magic-stack apps (`lib/main.dart` contains `await Magic.init(`):
///     wire `DuskPlugin.install()` BEFORE `Magic.init` so the driver is
///     live during Magic boot. When `magic_devtools:` is also a pubspec dep, ALSO
///     inject `MagicDuskIntegration.install()` AFTER `Magic.init` (the
///     integration queries `Magic.find<X>()` for the form / nav
///     enrichers, which only resolves once the container is ready).
///   - Vanilla apps: wire `DuskPlugin.install()` before `runApp(`.
///
/// Idempotent across re-runs: each `addImport` / `injectBeforeAnchor` /
/// `injectAfterMagicInit` call early-returns when the snippet is already
/// present, so re-running `dusk:install` is a safe no-op.
class DuskInstallCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:install';

  @override
  String get description =>
      'Wire DuskPlugin.install() into the consumer\'s lib/main.dart '
      '(idempotent; minimal — no bin/artisan.dart scaffold).';

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

  /// Hook for tests to disable the chained `artisan install` +
  /// `plugin:install` sub-process calls (Phase 2 of [handle]). The
  /// chained calls require a real Flutter project layout + working
  /// `dart` on PATH; widget tests pointed at a temp-dir fixture trip
  /// over both, so they flip this off.
  ///
  /// Production callers always leave this `true` so a single
  /// `dart run fluttersdk_dusk dusk:install` brings the consumer all the
  /// way to a working `./bin/fsa <cmd>` + registered MCP surface without
  /// further manual scaffolding.
  static bool runChainedSetup = true;

  /// Hook for tests to override the sub-process runner. Defaults to
  /// `Process.run`. Tests substitute a recording fake.
  static Future<ProcessResult> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) processRunner = Process.run;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final mainDartPath = mainDartPathResolver();
    final mainDart = File(mainDartPath);
    if (!mainDart.existsSync()) {
      ctx.output.error(
        'lib/main.dart not found at $mainDartPath. Run dusk:install from '
        'a Flutter project root.',
      );
      return 1;
    }

    // Phase 1: patch lib/main.dart (always; this is the core inject).
    _injectRuntimeWiring(ctx, mainDartPath);

    // Phase 2: scaffold fastcli + register dusk as an artisan plugin.
    //          Best-effort: failures here are logged but do NOT fail
    //          dusk:install, because `dart run fluttersdk_dusk <cmd>`
    //          (the package's own Flutter-free wrapper) still works
    //          without fastcli / plugin registration. The chain just
    //          unlocks the faster `./bin/fsa <cmd>` path.
    if (runChainedSetup) {
      await _runChainedArtisanSetup(ctx);
    }

    ctx.output.success(
      'dusk:install complete. Run `dart run fluttersdk_dusk <cmd>` to '
      'invoke dusk commands (or `./bin/fsa <cmd>` once fastcli is ready).',
    );
    return 0;
  }

  /// Chains `dart run fluttersdk_dusk install` (scaffold fastcli) +
  /// `dart run fluttersdk_dusk plugin:install fluttersdk_dusk`
  /// (register provider) when their outputs are missing.
  ///
  /// Each step is idempotent on the artisan side; we still guard with a
  /// file-existence check to keep dusk:install fast on re-runs (skip the
  /// ~3-second `dart run` startup when the artifact is already there).
  ///
  /// All failures swallowed with a single user-visible warn line; the
  /// consumer can run the artisan commands manually if interested.
  static Future<void> _runChainedArtisanSetup(ArtisanContext ctx) async {
    // 2a. Scaffold bin/dispatcher.dart + bin/fsa via artisan install.
    final dispatcherDart = File('bin/dispatcher.dart');
    if (!dispatcherDart.existsSync()) {
      ctx.output.info('Scaffolding fastcli (artisan install)...');
      try {
        final result = await processRunner(
          'dart',
          const ['run', 'fluttersdk_dusk', 'install'],
        );
        if (result.exitCode != 0) {
          ctx.output.warning(
            'artisan install exited ${result.exitCode}; rerun manually '
            'with `dart run fluttersdk_dusk install`. Stderr: '
            '${result.stderr.toString().trim().split('\n').first}',
          );
        }
      } catch (e) {
        ctx.output.warning(
          'artisan install chain skipped ($e). Run `dart run '
          'fluttersdk_dusk install` manually when ready.',
        );
        return;
      }
    }

    // 2b. Register dusk as an artisan plugin so its 32 commands surface
    //     through ./bin/fsa <cmd> + the MCP server. Skip when the
    //     `.artisan/installed/fluttersdk_dusk.json` marker is already
    //     present (artisan's own idempotency record).
    final pluginInstalled = File('.artisan/installed/fluttersdk_dusk.json');
    if (!pluginInstalled.existsSync()) {
      ctx.output.info('Registering dusk as an artisan plugin...');
      try {
        final result = await processRunner(
          'dart',
          const ['run', 'fluttersdk_dusk', 'plugin:install', 'fluttersdk_dusk'],
        );
        if (result.exitCode != 0) {
          ctx.output.warning(
            'artisan plugin:install exited ${result.exitCode}; rerun '
            'manually with `dart run fluttersdk_dusk plugin:install '
            'fluttersdk_dusk`. Stderr: '
            '${result.stderr.toString().trim().split('\n').first}',
          );
        }
      } catch (e) {
        ctx.output.warning(
          'artisan plugin:install chain skipped ($e). Run `dart run '
          'fluttersdk_dusk plugin:install fluttersdk_dusk` manually '
          'when ready.',
        );
      }
    }
  }

  /// Idempotent inject of dusk runtime wiring into `lib/main.dart`.
  /// Three sub-steps:
  ///
  ///   1. Add the two required imports (kDebugMode + dusk barrel).
  ///   2. Inject `WidgetsFlutterBinding.ensureInitialized()` (skip when
  ///      already present) + the `kDebugMode`-gated dusk block before
  ///      the canonical install anchor: `await Magic.init(` on
  ///      Magic-stack apps (so dusk is wired before Magic boot side
  ///      effects), otherwise `runApp(` for vanilla Flutter apps.
  ///   3. When pubspec has `magic_devtools:` AND main.dart has `await Magic.init(`,
  ///      inject `MagicDuskIntegration.install()` AFTER that call (the
  ///      integration queries `Magic.find<X>()` for the form / nav
  ///      enrichers, so it must run after the container is ready).
  static void _injectRuntimeWiring(ArtisanContext ctx, String mainDartPath) {
    ctx.output.info('Wiring DuskPlugin into $mainDartPath...');

    // 1. Imports first. ConfigEditor.addImportToFile (delegated by
    //    MainDartEditor.addImport) is idempotent on duplicates.
    MainDartEditor.addImport(
      mainDartPath,
      "import 'package:flutter/foundation.dart' show kDebugMode;",
    );
    MainDartEditor.addImport(
      mainDartPath,
      "import 'package:fluttersdk_dusk/dusk.dart';",
    );

    // 2. Read once, choose the correct anchor, transform via two
    //    pure-functional injects (idempotent: each helper checks
    //    `source.contains(snippet)` before inserting), write back when
    //    changed.
    var source = FileHelper.readFile(mainDartPath);
    final before = source;

    // Magic apps wire DuskPlugin.install BEFORE `await Magic.init(` so
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

    // Build the kDebugMode block.
    source = MainDartEditor.injectBeforeAnchor(
      source: source,
      anchor: anchor,
      snippet: '  if (kDebugMode) {\n'
          '    DuskPlugin.install();\n'
          '  }\n',
    );

    if (source != before) {
      FileHelper.writeFile(mainDartPath, source);
    }

    // 3. Magic-side coordinated wiring when the consumer pulls in magic.
    //    Detect via pubspec.yaml; skip silently when magic_devtools is not a dep
    //    or when main.dart has no Magic.init() anchor (vanilla app).
    if (_hasMagicDevtoolsDep()) {
      MainDartEditor.addImport(
        mainDartPath,
        "import 'package:magic_devtools/dusk.dart';",
      );
      try {
        MainDartEditor.injectAfterMagicInit(
          mainDartPath,
          '  if (kDebugMode) {\n'
          '    MagicDuskIntegration.install();\n'
          '  }\n',
        );
      } on StateError {
        // No Magic.init() call yet; user has not bootstrapped magic.
        // Dusk's vanilla wiring above is enough on its own.
      }
    }
  }

  /// Returns true when the consumer's pubspec.yaml lists `magic_devtools:`
  /// (the package that ships MagicDuskIntegration) as a dependency or
  /// dev_dependency (2-space indent).
  static bool _hasMagicDevtoolsDep() {
    final pubspec = File(pubspecPathResolver());
    if (!pubspec.existsSync()) return false;
    return RegExp(r'\n  magic_devtools:').hasMatch(pubspec.readAsStringSync());
  }
}
