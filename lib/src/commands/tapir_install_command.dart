import 'dart:convert';
import 'dart:io';

import 'package:dowel/dowel.dart';

/// `dowel tapir:install`: one-line bootstrap for the tapir plugin.
///
/// Injects the runtime wiring into the consumer's `lib/main.dart` so the E2E
/// driver is live whenever the app boots outside release mode, then chains
/// `dowel install` (which scaffolds `bin/dowel` and `bin/dispatcher.dart`)
/// and `plugin:install tapir`, best-effort. The consumer can always invoke
/// tapir commands directly via `dart run tapir <cmd>` (the package ships its
/// own Flutter-free CLI wrapper at `bin/tapir.dart`).
///
/// Two anchor modes:
///   - Magic-stack apps (`lib/main.dart` contains `await Magic.init(`):
///     wire `TapirPlugin.install()` BEFORE `Magic.init` so the driver is
///     live during Magic boot. When `magic_devtools:` is also a pubspec
///     dependency or dev_dependency AND the resolved release ships
///     `lib/tapir.dart`, ALSO inject `MagicTapirIntegration.install()`
///     AFTER `Magic.init` (the integration queries `Magic.find<X>()` for the
///     form / nav enrichers, which only resolves once the container is ready).
///     A release without `lib/tapir.dart` gets a warning instead.
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
      'Wire TapirPlugin.install() into the consumer\'s lib/main.dart, then '
      'scaffold bin/dowel and bin/dispatcher.dart and register tapir as a '
      'dowel plugin (idempotent).';

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

    // A project moving from fluttersdk_dusk keeps its old dispatcher, which
    // also makes Phase 2 skip `dowel install`; say what to clear first.
    final List<String> leftovers = legacyDuskLeftovers(
      File(pubspecPathResolver()).parent.path,
    );
    if (leftovers.isNotEmpty) {
      ctx.output.warning(
        'Leftovers from fluttersdk_dusk found:\n'
        '${leftovers.map((String line) => '  - $line').join('\n')}\n'
        '$legacyDuskFix',
      );
    }

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
  ///   3. When pubspec has `magic_devtools:`, its resolved release ships
  ///      `lib/tapir.dart` AND main.dart has `await Magic.init(`,
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
    final bool wantsMagic =
        original.contains('await Magic.init(') &&
        _hasMagicDevtoolsDep() &&
        !original.contains('MagicTapirIntegration.install()');
    // A magic_devtools release that predates tapir has no `tapir.dart`; its
    // import would leave a lib/main.dart that does not compile.
    final MagicDevtoolsTapirSupport magicSupport = wantsMagic
        ? magicDevtoolsTapirSupport(File(pubspecPathResolver()).parent.path)
        : MagicDevtoolsTapirSupport.unresolved;
    final bool wiresMagic = magicSupport == MagicDevtoolsTapirSupport.available;

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
    //    or when main.dart has no Magic.init() anchor (vanilla app), and with
    //    a warning when the resolved release has no tapir integration.
    if (wantsMagic && !wiresMagic) {
      final String why = magicSupport == MagicDevtoolsTapirSupport.unresolved
          ? 'no lib/tapir.dart resolved; run `flutter pub get` if it has not '
                'run'
          : 'no lib/tapir.dart';
      ctx.output.warning(
        'Skipped MagicTapirIntegration: the installed magic_devtools has no '
        'tapir integration yet ($why). Upgrade magic_devtools to a release '
        'built on tapir, then rerun `dart run tapir tapir:install` (it is '
        'idempotent).',
      );
    }
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

  /// Whether the `magic_devtools` that [projectRoot] resolves ships
  /// `lib/tapir.dart`, the library `MagicTapirIntegration` lives in.
  ///
  /// The pubspec only says the package is wanted; a release that predates
  /// tapir ships `lib/dusk.dart` instead, and wiring its integration leaves a
  /// `lib/main.dart` that does not compile. So the answer comes from the
  /// package pub actually resolved, through `.dart_tool/package_config.json`.
  static MagicDevtoolsTapirSupport magicDevtoolsTapirSupport(
    String projectRoot,
  ) {
    // 1. No package config means `pub get` has not run: nothing is resolved.
    final File? config = _nearestPackageConfig(projectRoot);
    if (config == null) return MagicDevtoolsTapirSupport.unresolved;

    // 2. Find the entry pub wrote for magic_devtools. A config that cannot
    //    be read or parsed tells nothing either way, which is what
    //    `unresolved` says; the install and the doctor carry on from there.
    final Object? decoded;
    try {
      decoded = jsonDecode(config.readAsStringSync());
    } on FormatException {
      return MagicDevtoolsTapirSupport.unresolved;
    } on FileSystemException {
      return MagicDevtoolsTapirSupport.unresolved;
    }
    final List<Object?> packages = switch (decoded) {
      {'packages': final List<Object?> list} => list,
      _ => const <Object?>[],
    };
    for (final Object? package in packages) {
      if (package is! Map<String, Object?> ||
          package['name'] != 'magic_devtools') {
        continue;
      }

      // 3. `rootUri` is relative to the `.dart_tool` directory (or an
      //    absolute file URI for a pub-cache package); `packageUri`, `lib/`
      //    as pub writes it, is relative to the root and defaults to it. An
      //    entry that breaks that shape is as unreadable as a broken file.
      final Object? rootUri = package['rootUri'];
      final Object packageUri = package['packageUri'] ?? '';
      if (rootUri is! String || packageUri is! String) {
        return MagicDevtoolsTapirSupport.unresolved;
      }
      // A file path round trip decodes `%20` and friends once, and the
      // Directory's own uri gives the trailing slash `resolve` needs.
      final File tapirLibrary;
      try {
        final Directory root = Directory(
          config.parent.uri.resolve(rootUri).toFilePath(),
        );
        tapirLibrary = File.fromUri(
          root.uri.resolve(packageUri).resolve('tapir.dart'),
        );
      } on FormatException {
        return MagicDevtoolsTapirSupport.unresolved;
      }
      return tapirLibrary.existsSync()
          ? MagicDevtoolsTapirSupport.available
          : MagicDevtoolsTapirSupport.missing;
    }
    return MagicDevtoolsTapirSupport.unresolved;
  }

  /// The package config that governs [projectRoot]: the first
  /// `.dart_tool/package_config.json` at or above it, the way the Dart tools
  /// find it. A pub workspace member has none of its own, since `pub get`
  /// writes one shared config at the workspace root. Null when the walk
  /// reaches the filesystem root without finding one.
  static File? _nearestPackageConfig(String projectRoot) {
    // Walk on directory URIs: a file path round trip keeps the trailing
    // separator, and the `<root>//.dart_tool` it leads to makes a relative
    // `rootUri` resolve one level too deep.
    Uri dir = Directory(projectRoot).absolute.uri.normalizePath();
    while (true) {
      final config = File.fromUri(
        dir.resolve('.dart_tool/package_config.json'),
      );
      if (config.existsSync()) return config;
      final Uri parent = dir.resolve('..');
      if (parent == dir) return null;
      dir = parent;
    }
  }

  /// What a `fluttersdk_dusk` install left in [projectRoot] that stops the
  /// dowel setup working, one line per item naming the file: a
  /// `bin/dispatcher.dart` that imports `fluttersdk_artisan` (Phase 2 keeps
  /// it, and `bin/` no longer analyses), `bin/fsa`,
  /// `lib/app/commands/_index.g.dart`, an app command still written against
  /// the `Artisan*` classes, and the `fluttersdk` server in `.mcp.json`.
  /// Empty on a clean project. `tapir:doctor` reports the same list.
  static List<String> legacyDuskLeftovers(String projectRoot) {
    final List<String> found = <String>[];
    final String root = Directory(projectRoot).absolute.path;

    final File dispatcher = File('$root/bin/dispatcher.dart');
    if (dispatcher.existsSync() &&
        dispatcher.readAsStringSync().contains('fluttersdk_artisan')) {
      found.add('bin/dispatcher.dart (imports fluttersdk_artisan): delete it');
    }
    if (File('$root/bin/fsa').existsSync()) {
      found.add('bin/fsa: delete it');
    }
    if (File('$root/lib/app/commands/_index.g.dart').existsSync()) {
      found.add('lib/app/commands/_index.g.dart: delete it');
    }

    final Directory commands = Directory('$root/lib/app/commands');
    if (commands.existsSync()) {
      final RegExp artisanClass = RegExp(r'\bArtisan[A-Z]\w*');
      final List<File> files =
          commands
              .listSync(recursive: true)
              .whereType<File>()
              .where(
                (File file) =>
                    file.path.endsWith('.dart') &&
                    !file.path.endsWith('_index.g.dart'),
              )
              .toList()
            ..sort((File a, File b) => a.path.compareTo(b.path));
      for (final File file in files) {
        if (artisanClass.hasMatch(file.readAsStringSync())) {
          found.add(
            '${file.path.substring(root.length + 1)} (uses Artisan* '
            'classes): port it to the Dowel* classes',
          );
        }
      }
    }

    final File mcp = File('$root/.mcp.json');
    if (mcp.existsSync() &&
        RegExp(r'"fluttersdk"\s*:').hasMatch(mcp.readAsStringSync())) {
      found.add('.mcp.json: delete the "fluttersdk" server entry');
    }
    return found;
  }

  /// The steps that follow clearing [legacyDuskLeftovers], in order.
  static const String legacyDuskFix =
      'Then run `dart run dowel install`, `dart run dowel commands:refresh` '
      'and `dart run tapir tapir:install`.';

  /// Returns true when the consumer's pubspec.yaml lists `magic_devtools:`
  /// (the package that ships MagicTapirIntegration) under `dependencies:` or
  /// `dev_dependencies:` (2-space indent).
  static bool _hasMagicDevtoolsDep() {
    final pubspec = File(pubspecPathResolver());
    if (!pubspec.existsSync()) return false;
    return RegExp(r'\n  magic_devtools:').hasMatch(pubspec.readAsStringSync());
  }
}

/// What the consumer's resolved `magic_devtools` offers tapir, read by
/// [TapirInstallCommand.magicDevtoolsTapirSupport].
enum MagicDevtoolsTapirSupport {
  /// No `magic_devtools` in `.dart_tool/package_config.json`, or no package
  /// config at all because `pub get` has not run.
  unresolved,

  /// Resolved, but a release that predates tapir: it has no `lib/tapir.dart`.
  missing,

  /// Resolved and ships `lib/tapir.dart`, so `MagicTapirIntegration` imports.
  available,
}
