import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:install` ; one-shot bootstrap for the dusk plugin.
///
/// Runs the canonical install sequence in the consumer project:
///
///   1. `dart run fluttersdk_artisan consumer:scaffold` (only when
///      `bin/artisan.dart` is missing; idempotent skip otherwise).
///   2. `dart run fluttersdk_artisan plugin:install fluttersdk_dusk`
///      (always; the underlying plugin:install + plugins:refresh are
///      idempotent so re-runs are safe).
///   3. Inject the runtime wiring into `lib/main.dart` via
///      [MainDartEditor]: imports plus the `kDebugMode`-gated
///      [DuskPlugin.install] + optional [WindDuskIntegration.install] block
///      before `runApp(` (vanilla) or `await Magic.init(` (Magic-stack apps,
///      so dusk install runs before any Magic boot side effect). When the
///      consumer's pubspec lists `magic:` as a dependency AND `lib/main.dart`
///      contains an `await Magic.init(` call, also injects
///      `MagicDuskIntegration.install()` after that anchor (so the
///      integration can query `Magic.find<X>()` for the form / nav enrichers).
///      All steps idempotent; re-runs are no-ops.
///
/// Steps 1 and 2 are invoked as subprocesses so this command does not
/// depend on the consumer wrapper already wiring `DuskArtisanProvider`
/// (the bootstrap chicken-and-egg case). Step 3 calls [MainDartEditor]
/// directly because it runs in the same process as the wrapper.
class DuskInstallCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:install';

  @override
  String get description =>
      'Bootstrap fluttersdk_dusk in the current project (scaffolds '
      'consumer wrapper if missing, then registers the plugin).';

  @override
  CommandBoot get boot => CommandBoot.none;

  /// Hook for tests to inject a custom subprocess runner without touching
  /// the live Dart toolchain. Defaults to [Process.run].
  static Future<ProcessResult> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) processRunner = _defaultProcessRunner;

  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) =>
      Process.run(executable, arguments,
          workingDirectory: workingDirectory, runInShell: false);

  /// Hook for tests to override the wrapper-presence check (default: real
  /// `bin/artisan.dart` File existence in the cwd).
  static bool Function() wrapperExistsCheck = _defaultWrapperExistsCheck;

  static bool _defaultWrapperExistsCheck() =>
      File('bin/artisan.dart').existsSync();

  /// Hook for tests to override the resolved `lib/main.dart` path so phase 3
  /// can run against a temp-dir fixture without leaking files into the
  /// running test process' cwd.
  static String Function() mainDartPathResolver = _defaultMainDartPath;

  static String _defaultMainDartPath() => 'lib/main.dart';

  /// Hook for tests to override the resolved `pubspec.yaml` path used for
  /// `magic:` / `wind:` dependency detection in phase 3.
  static String Function() pubspecPathResolver = _defaultPubspecPath;

  static String _defaultPubspecPath() => 'pubspec.yaml';

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Scaffold the consumer wrapper when missing. Re-runs are skipped so
    //    repeated `dusk:install` invocations on an already-bootstrapped
    //    project stay idempotent.
    if (!wrapperExistsCheck()) {
      ctx.output.info('Consumer wrapper missing; running consumer:scaffold...');
      final scaffold = await processRunner(
        'dart',
        ['run', 'fluttersdk_artisan', 'consumer:scaffold'],
      );
      stdout.write(scaffold.stdout);
      stderr.write(scaffold.stderr);
      if (scaffold.exitCode != 0) {
        ctx.output
            .error('consumer:scaffold failed (exit ${scaffold.exitCode}).');
        return scaffold.exitCode;
      }
    } else {
      ctx.output.info(
          'Consumer wrapper already present; skipping consumer:scaffold.');
    }

    // 2. Register fluttersdk_dusk via plugin:install. Reads the install.yaml
    //    manifest shipped in this package and writes the entry to
    //    .artisan/plugins.json + regenerates lib/app/_plugins.g.dart.
    ctx.output.info('Registering fluttersdk_dusk via plugin:install...');
    final install = await processRunner(
      'dart',
      [
        'run',
        'fluttersdk_artisan',
        'plugin:install',
        'fluttersdk_dusk',
      ],
    );
    stdout.write(install.stdout);
    stderr.write(install.stderr);
    if (install.exitCode != 0) {
      ctx.output.error('plugin:install failed (exit ${install.exitCode}).');
      return install.exitCode;
    }

    // 3. Wire the runtime install into lib/main.dart. Fail-soft: when the
    //    file is absent or the anchor is missing, log and continue; the
    //    consumer can wire by hand following the post_install message.
    final mainDartPath = mainDartPathResolver();
    final mainDart = File(mainDartPath);
    if (!mainDart.existsSync()) {
      ctx.output.info(
          'lib/main.dart not found at $mainDartPath; runtime wiring SKIPPED.'
          ' Wire manually: import fluttersdk_dusk + DuskPlugin.install()'
          ' before runApp().');
    } else {
      _injectRuntimeWiring(ctx, mainDartPath);
    }

    ctx.output.success('dusk:install complete.');
    return 0;
  }

  /// Step 3 ; idempotent inject of dusk runtime wiring into `lib/main.dart`.
  /// Three sub-steps:
  ///
  ///   3a. Add the two required imports (kDebugMode + dusk barrel).
  ///   3b. Inject `WidgetsFlutterBinding.ensureInitialized()` (skip when
  ///       already present) + the `kDebugMode`-gated dusk block before the
  ///       canonical install anchor: `await Magic.init(` on Magic-stack
  ///       apps (so dusk is wired before Magic boot side effects),
  ///       otherwise `runApp(` for vanilla Flutter apps. When `wind:` is a
  ///       pubspec dep, also wires `WindDuskIntegration.install()` inside
  ///       the same kDebugMode block.
  ///   3c. When pubspec has `magic:` AND main.dart has `await Magic.init(`,
  ///       inject `MagicDuskIntegration.install()` AFTER that call (the
  ///       integration queries `Magic.find<X>()` for the form / nav
  ///       enrichers, so it must run after the container is ready).
  static void _injectRuntimeWiring(ArtisanContext ctx, String mainDartPath) {
    ctx.output.info('Wiring DuskPlugin into $mainDartPath...');

    // 3a. Imports first. ConfigEditor.addImportToFile (delegated by
    //     MainDartEditor.addImport) is idempotent on duplicates.
    MainDartEditor.addImport(
      mainDartPath,
      "import 'package:flutter/foundation.dart' show kDebugMode;",
    );
    MainDartEditor.addImport(
      mainDartPath,
      "import 'package:fluttersdk_dusk/dusk.dart';",
    );

    // 3b. Read once, choose the correct anchor, transform via two
    //     pure-functional injects (idempotent: each helper checks
    //     `source.contains(snippet)` before inserting), write back when
    //     changed.
    var source = FileHelper.readFile(mainDartPath);
    final before = source;

    // Magic apps wire DuskPlugin.install BEFORE `await Magic.init(` so the
    // E2E driver is live during Magic boot; vanilla apps inject before
    // `runApp(`. Detect via substring match on the magic boot call.
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

    // Build the kDebugMode block. WindDuskIntegration.install lands inside
    // the same gate when `wind:` is a top-level dep of the consumer.
    final hasWind = _hasWindDep();
    final windLine = hasWind ? '    WindDuskIntegration.install();\n' : '';
    source = MainDartEditor.injectBeforeAnchor(
      source: source,
      anchor: anchor,
      snippet: '  if (kDebugMode) {\n'
          '    DuskPlugin.install();\n'
          '$windLine'
          '  }\n',
    );

    if (source != before) {
      FileHelper.writeFile(mainDartPath, source);
    }

    // 3c. Magic-side coordinated wiring when the consumer pulls in magic.
    //     Detect via pubspec.yaml; skip silently when magic is not a dep or
    //     when main.dart has no Magic.init() anchor (vanilla Flutter app).
    if (_hasMagicDep()) {
      MainDartEditor.addImport(
        mainDartPath,
        "import 'package:magic/magic.dart';",
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

  /// Returns true when the consumer's pubspec.yaml lists `magic:` as a
  /// top-level dependency (2-space indent under `dependencies:`).
  static bool _hasMagicDep() {
    final pubspec = File(pubspecPathResolver());
    if (!pubspec.existsSync()) return false;
    return RegExp(r'\n  magic:').hasMatch(pubspec.readAsStringSync());
  }

  /// Returns true when the consumer's pubspec.yaml lists `wind:` as a
  /// top-level dependency (2-space indent under `dependencies:`).
  static bool _hasWindDep() {
    final pubspec = File(pubspecPathResolver());
    if (!pubspec.existsSync()) return false;
    return RegExp(r'\n  wind:').hasMatch(pubspec.readAsStringSync());
  }
}
