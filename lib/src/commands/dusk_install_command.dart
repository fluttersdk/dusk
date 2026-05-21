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
///     live during Magic boot. When `magic:` is also a pubspec dep, ALSO
///     inject `MagicDuskIntegration.install()` AFTER `Magic.init` (the
///     integration queries `Magic.find<X>()` for the form / nav
///     enrichers, which only resolves once the container is ready).
///   - Vanilla apps: wire `DuskPlugin.install()` before `runApp(`.
///
/// Wind enricher integration: when the consumer's pubspec lists
/// `fluttersdk_wind:` as a dep, `WindDuskIntegration.install()` lands
/// inside the same `kDebugMode` block as `DuskPlugin.install()`.
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
  /// for `magic:` / `fluttersdk_wind:` dependency detection.
  static String Function() pubspecPathResolver = _defaultPubspecPath;

  static String _defaultPubspecPath() => 'pubspec.yaml';

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
    _injectRuntimeWiring(ctx, mainDartPath);
    ctx.output.success(
      'dusk:install complete. Run `dart run fluttersdk_dusk <cmd>` to '
      'invoke dusk commands.',
    );
    return 0;
  }

  /// Idempotent inject of dusk runtime wiring into `lib/main.dart`.
  /// Three sub-steps:
  ///
  ///   1. Add the two required imports (kDebugMode + dusk barrel).
  ///   2. Inject `WidgetsFlutterBinding.ensureInitialized()` (skip when
  ///      already present) + the `kDebugMode`-gated dusk block before
  ///      the canonical install anchor: `await Magic.init(` on
  ///      Magic-stack apps (so dusk is wired before Magic boot side
  ///      effects), otherwise `runApp(` for vanilla Flutter apps. When
  ///      `fluttersdk_wind:` is a pubspec dep, also wires
  ///      `WindDuskIntegration.install()` inside the same kDebugMode
  ///      block.
  ///   3. When pubspec has `magic:` AND main.dart has `await Magic.init(`,
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
    // Wind sub-barrel import lands here (before the readFile + in-memory
    // transform below) so the cached `source` includes it when the final
    // writeFile flushes back. wind alpha-9 dropped the main-barrel
    // re-export; consumers reach WindDuskIntegration via this sub-barrel.
    if (_hasWindDep()) {
      MainDartEditor.addImport(
        mainDartPath,
        "import 'package:fluttersdk_wind/dusk_integration.dart';",
      );
    }

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

    // Build the kDebugMode block. WindDuskIntegration.install lands
    // inside the same gate when `fluttersdk_wind:` is a top-level dep of
    // the consumer (the import for the sub-barrel was already added
    // before the readFile above).
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

    // 3. Magic-side coordinated wiring when the consumer pulls in magic.
    //    Detect via pubspec.yaml; skip silently when magic is not a dep
    //    or when main.dart has no Magic.init() anchor (vanilla app).
    if (_hasMagicDep()) {
      MainDartEditor.addImport(
        mainDartPath,
        "import 'package:magic/dusk_integration.dart';",
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

  /// Returns true when the consumer's pubspec.yaml lists `fluttersdk_wind:`
  /// as a top-level dependency (2-space indent under `dependencies:`).
  /// The actual package name is `fluttersdk_wind` per the wind repo's own
  /// pubspec; the historical alias `wind:` is NOT a valid package import.
  static bool _hasWindDep() {
    final pubspec = File(pubspecPathResolver());
    if (!pubspec.existsSync()) return false;
    return RegExp(r'\n  fluttersdk_wind:').hasMatch(pubspec.readAsStringSync());
  }
}
