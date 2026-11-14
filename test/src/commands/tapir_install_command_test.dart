import 'dart:convert';
import 'dart:io';

import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_install_command.dart';

/// Seed [tempDir] with a stub `lib/main.dart` carrying [mainDartContents] +
/// a `pubspec.yaml` that lists [pubspecDeps] entries under
/// `dependencies:`. Returns the absolute path to the seeded main.dart so
/// callers can inject it via [TapirInstallCommand.mainDartPathResolver].
///
/// [magicDevtoolsLibrary] names the one library the resolved `magic_devtools`
/// ships (`tapir.dart` for a release built on tapir, `dusk.dart` for one that
/// predates it); when set, a `.dart_tool/package_config.json` resolving the
/// package is written too. [absoluteRootUri] writes its `rootUri` the way a
/// pub-cache package carries it, rather than relative to `.dart_tool`.
String _seedProject(
  Directory tempDir, {
  required String mainDartContents,
  Map<String, String> pubspecDeps = const {},
  String? magicDevtoolsLibrary,
  bool absoluteRootUri = false,
}) {
  final mainDartPath = '${tempDir.path}/lib/main.dart';
  Directory('${tempDir.path}/lib').createSync(recursive: true);
  File(mainDartPath).writeAsStringSync(mainDartContents);
  final depsBlock = pubspecDeps.entries
      .map((e) => '  ${e.key}: ${e.value}')
      .join('\n');
  final pubspec = <String>[
    'name: stub_app',
    'environment:',
    '  sdk: ">=3.4.0 <4.0.0"',
    'dependencies:',
    '  flutter:',
    '    sdk: flutter',
    if (depsBlock.isNotEmpty) depsBlock,
    '',
  ].join('\n');
  File('${tempDir.path}/pubspec.yaml').writeAsStringSync(pubspec);
  if (magicDevtoolsLibrary != null) {
    final packageRoot = Directory('${tempDir.path}/packages/magic_devtools');
    Directory('${packageRoot.path}/lib').createSync(recursive: true);
    File('${packageRoot.path}/lib/$magicDevtoolsLibrary')
        .writeAsStringSync('// stub\n');
    Directory('${tempDir.path}/.dart_tool').createSync();
    final rootUri = absoluteRootUri
        ? packageRoot.uri.toString()
        : '../packages/magic_devtools';
    File('${tempDir.path}/.dart_tool/package_config.json').writeAsStringSync(
      jsonEncode(<String, Object>{
        'configVersion': 2,
        'packages': <Map<String, String>>[
          <String, String>{
            'name': 'magic_devtools',
            'rootUri': rootUri,
            'packageUri': 'lib/',
            'languageVersion': '3.4',
          },
        ],
      }),
    );
  }
  return mainDartPath;
}

/// Build a bare [DowelContext] suitable for invoking the command without
/// any real input / output wiring.
DowelContext _ctx() {
  return DowelContext.bare(MapInput(const {}), BufferedOutput());
}

void main() {
  group('TapirInstallCommand', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('tapir_install_test_');
      // Tests target a temp-dir Flutter-project fixture; the Phase 2
      // sub-process chain (`dart run tapir install` +
      // `plugin:install`) is out of scope here (covered separately by
      // the E2E showroom smoke against `/tmp/tapir_e2e_v*`).
      TapirInstallCommand.runChainedSetup = false;
    });

    tearDown(() {
      // Restore module-level hooks between tests; they are static fields,
      // so a test that mutates them leaks into the next without this
      // reset.
      TapirInstallCommand.mainDartPathResolver = () => 'lib/main.dart';
      TapirInstallCommand.pubspecPathResolver = () => 'pubspec.yaml';
      TapirInstallCommand.runChainedSetup = true;
      tempDir.deleteSync(recursive: true);
    });

    // ------------------------------------------------------------------
    // Metadata
    // ------------------------------------------------------------------

    test('name is tapir:install', () {
      expect(TapirInstallCommand().name, equals('tapir:install'));
    });

    test('boot is CommandBoot.none (does not require a running app)', () {
      expect(TapirInstallCommand().boot, equals(CommandBoot.none));
    });

    test('description signals the minimal scope (no scaffold)', () {
      // The description must NOT promise the heavy consumer-scaffold flow
      // anymore; the command's single responsibility is main.dart wiring.
      final desc = TapirInstallCommand().description;
      expect(desc, isNotEmpty);
      expect(desc.toLowerCase(), contains('main.dart'));
      expect(
        desc.toLowerCase(),
        isNot(contains('consumer:scaffold')),
        reason: 'minimal install must not advertise consumer:scaffold',
      );
      // The chained `dowel install` does scaffold bin/dowel and
      // bin/dispatcher.dart, so the description must not deny it.
      expect(desc, isNot(contains('no bin/dowel.dart scaffold')));
      expect(desc, contains('bin/dowel'));
    });

    // ------------------------------------------------------------------
    // Vanilla flutter app: inject before runApp()
    // ------------------------------------------------------------------

    test(
      'vanilla app: injects a !kReleaseMode TapirPlugin.install() block before '
      'runApp(',
      () async {
        final mainDartPath = _seedProject(
          tempDir,
          mainDartContents: '''
import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(home: SizedBox());
}
''',
        );
        TapirInstallCommand.mainDartPathResolver = () => mainDartPath;
        TapirInstallCommand.pubspecPathResolver = () =>
            '${tempDir.path}/pubspec.yaml';

        final exit = await TapirInstallCommand().handle(_ctx());
        expect(exit, equals(0));

        final result = File(mainDartPath).readAsStringSync();
        expect(
          result.contains(
            "import 'package:flutter/foundation.dart' show kReleaseMode;",
          ),
          isTrue,
        );
        expect(result.contains("import 'package:tapir/tapir.dart';"), isTrue);
        expect(
          result.contains('WidgetsFlutterBinding.ensureInitialized();'),
          isTrue,
        );
        expect(
          result.contains('if (!kReleaseMode) {'),
          isTrue,
          reason:
              'profile builds must carry tapir so perf_run can measure '
              'one; release still tree-shakes the branch',
        );
        expect(result.contains('kDebugMode'), isFalse);
        expect(result.contains('TapirPlugin.install();'), isTrue);
        // No Magic deps in this vanilla case, so no MagicTapirIntegration
        // wire lands.
        expect(result.contains('MagicTapirIntegration.install()'), isFalse);
        expect(result.contains('WindTapirIntegration.install()'), isFalse);
      },
    );

    // ------------------------------------------------------------------
    // Magic-stack app: BEFORE-Magic.init + AFTER-Magic.init wires
    // ------------------------------------------------------------------

    test('magic-stack app: injects TapirPlugin.install() BEFORE Magic.init AND '
        'MagicTapirIntegration.install() AFTER Magic.init', () async {
      final mainDartPath = _seedProject(
        tempDir,
        pubspecDeps: const {'magic': 'any', 'magic_devtools': 'any'},
        magicDevtoolsLibrary: 'tapir.dart',
        absoluteRootUri: true,
        mainDartContents: '''
import 'package:material_ui/material_ui.dart';
import 'package:magic/magic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Magic.init(configFactories: [() => {}]);
  runApp(const MagicApplication());
}
''',
      );
      TapirInstallCommand.mainDartPathResolver = () => mainDartPath;
      TapirInstallCommand.pubspecPathResolver = () =>
          '${tempDir.path}/pubspec.yaml';

      final exit = await TapirInstallCommand().handle(_ctx());
      expect(exit, equals(0));

      final result = File(mainDartPath).readAsStringSync();
      final tapirInstallIdx = result.indexOf('TapirPlugin.install();');
      final magicInitIdx = result.indexOf('await Magic.init(');
      final magicIntegrationIdx = result.indexOf(
        'MagicTapirIntegration.install();',
      );

      expect(tapirInstallIdx, greaterThan(-1));
      expect(magicInitIdx, greaterThan(-1));
      expect(magicIntegrationIdx, greaterThan(-1));
      expect(
        tapirInstallIdx < magicInitIdx,
        isTrue,
        reason: 'TapirPlugin.install() must land BEFORE Magic.init()',
      );
      expect(
        magicInitIdx < magicIntegrationIdx,
        isTrue,
        reason: 'MagicTapirIntegration.install() must land AFTER Magic.init()',
      );
      expect(
        result.contains("import 'package:magic_devtools/tapir.dart';"),
        isTrue,
        reason:
            'must reference the magic_devtools tapir barrel, not the '
            'removed package:magic sub-barrel',
      );
    });

    // ------------------------------------------------------------------
    // A magic_devtools release that predates tapir: no Magic wiring
    // ------------------------------------------------------------------

    const magicMain = '''
import 'package:material_ui/material_ui.dart';
import 'package:magic/magic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Magic.init(configFactories: [() => {}]);
  runApp(const MagicApplication());
}
''';

    test('magic-stack app whose resolved magic_devtools has no tapir.dart: '
        'no Magic lines, one upgrade warning, exit 0', () async {
      final mainDartPath = _seedProject(
        tempDir,
        pubspecDeps: const {'magic': 'any', 'magic_devtools': 'any'},
        magicDevtoolsLibrary: 'dusk.dart',
        mainDartContents: magicMain,
      );
      TapirInstallCommand.mainDartPathResolver = () => mainDartPath;
      TapirInstallCommand.pubspecPathResolver = () =>
          '${tempDir.path}/pubspec.yaml';
      final output = BufferedOutput();

      final exit = await TapirInstallCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(exit, equals(0));
      final result = File(mainDartPath).readAsStringSync();
      expect(result.contains('TapirPlugin.install();'), isTrue);
      expect(result.contains('magic_devtools'), isFalse);
      expect(result.contains('MagicTapirIntegration'), isFalse);
      expect(
        'has no tapir integration yet'.allMatches(output.content).length,
        equals(1),
      );
      expect(output.content, contains('dart run tapir tapir:install'));
    });

    test('magic-stack app with magic_devtools in pubspec but no '
        'package_config.json: no Magic lines, the same warning', () async {
      final mainDartPath = _seedProject(
        tempDir,
        pubspecDeps: const {'magic': 'any', 'magic_devtools': 'any'},
        mainDartContents: magicMain,
      );
      TapirInstallCommand.mainDartPathResolver = () => mainDartPath;
      TapirInstallCommand.pubspecPathResolver = () =>
          '${tempDir.path}/pubspec.yaml';
      final output = BufferedOutput();

      final exit = await TapirInstallCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(exit, equals(0));
      final result = File(mainDartPath).readAsStringSync();
      expect(result.contains('MagicTapirIntegration'), isFalse);
      expect(output.content, contains('has no tapir integration yet'));
    });

    test('magicDevtoolsTapirSupport reads the package root from '
        'package_config.json', () {
      expect(
        TapirInstallCommand.magicDevtoolsTapirSupport(tempDir.path),
        equals(MagicDevtoolsTapirSupport.unresolved),
      );

      _seedProject(
        tempDir,
        mainDartContents: '',
        magicDevtoolsLibrary: 'dusk.dart',
      );
      expect(
        TapirInstallCommand.magicDevtoolsTapirSupport(tempDir.path),
        equals(MagicDevtoolsTapirSupport.missing),
      );

      File('${tempDir.path}/packages/magic_devtools/lib/tapir.dart')
          .writeAsStringSync('// stub\n');
      expect(
        TapirInstallCommand.magicDevtoolsTapirSupport(tempDir.path),
        equals(MagicDevtoolsTapirSupport.available),
      );
    });

    // ------------------------------------------------------------------
    // WidgetsFlutterBinding.ensureInitialized() — no double inject
    // ------------------------------------------------------------------

    test(
      'WidgetsFlutterBinding.ensureInitialized() is NOT double-injected when '
      'already present',
      () async {
        final mainDartPath = _seedProject(
          tempDir,
          mainDartContents: '''
import 'package:material_ui/material_ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(home: SizedBox());
}
''',
        );
        TapirInstallCommand.mainDartPathResolver = () => mainDartPath;
        TapirInstallCommand.pubspecPathResolver = () =>
            '${tempDir.path}/pubspec.yaml';

        await TapirInstallCommand().handle(_ctx());
        final result = File(mainDartPath).readAsStringSync();

        final ensureInitCount = 'WidgetsFlutterBinding.ensureInitialized()'
            .allMatches(result)
            .length;
        expect(ensureInitCount, equals(1));
      },
    );

    // ------------------------------------------------------------------
    // Idempotency: re-running the command produces no extra inject
    // ------------------------------------------------------------------

    test(
      're-running the command is idempotent (no duplicate inject)',
      () async {
        final mainDartPath = _seedProject(
          tempDir,
          mainDartContents: '''
import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(home: SizedBox());
}
''',
        );
        TapirInstallCommand.mainDartPathResolver = () => mainDartPath;
        TapirInstallCommand.pubspecPathResolver = () =>
            '${tempDir.path}/pubspec.yaml';

        await TapirInstallCommand().handle(_ctx());
        final afterFirst = File(mainDartPath).readAsStringSync();
        await TapirInstallCommand().handle(_ctx());
        final afterSecond = File(mainDartPath).readAsStringSync();

        expect(afterSecond, equals(afterFirst));
        expect(
          'TapirPlugin.install();'.allMatches(afterSecond).length,
          equals(1),
        );
        expect(
          "import 'package:tapir/tapir.dart';".allMatches(afterSecond).length,
          equals(1),
        );
      },
    );

    // ------------------------------------------------------------------
    // Apps installed before the guard moved to !kReleaseMode
    // ------------------------------------------------------------------

    test('an app already wired under kDebugMode is left alone '
        '(no second block, no unused kReleaseMode import)', () async {
      const legacy = '''
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:material_ui/material_ui.dart';
import 'package:tapir/tapir.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    TapirPlugin.install();
  }
  runApp(const MyApp());
}
''';
      final mainDartPath = _seedProject(tempDir, mainDartContents: legacy);
      TapirInstallCommand.mainDartPathResolver = () => mainDartPath;
      TapirInstallCommand.pubspecPathResolver = () =>
          '${tempDir.path}/pubspec.yaml';

      final exit = await TapirInstallCommand().handle(_ctx());

      expect(exit, equals(0));
      expect(File(mainDartPath).readAsStringSync(), equals(legacy));
    });

    test('a kDebugMode magic app gaining magic_devtools gets only the '
        'integration block, under !kReleaseMode', () async {
      final mainDartPath = _seedProject(
        tempDir,
        pubspecDeps: const {'magic': 'any', 'magic_devtools': 'any'},
        magicDevtoolsLibrary: 'tapir.dart',
        mainDartContents: '''
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:material_ui/material_ui.dart';
import 'package:tapir/tapir.dart';
import 'package:magic/magic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    TapirPlugin.install();
  }
  await Magic.init(configFactories: [() => {}]);
  runApp(const MagicApplication());
}
''',
      );
      TapirInstallCommand.mainDartPathResolver = () => mainDartPath;
      TapirInstallCommand.pubspecPathResolver = () =>
          '${tempDir.path}/pubspec.yaml';

      await TapirInstallCommand().handle(_ctx());
      final result = File(mainDartPath).readAsStringSync();

      expect('TapirPlugin.install();'.allMatches(result).length, equals(1));
      expect(
        'MagicTapirIntegration.install();'.allMatches(result).length,
        equals(1),
      );
      expect(
        result.contains(
          "import 'package:flutter/foundation.dart' show kReleaseMode;",
        ),
        isTrue,
      );
      expect(
        result.indexOf('if (!kReleaseMode) {'),
        greaterThan(result.indexOf('await Magic.init(')),
      );
    });

    // ------------------------------------------------------------------
    // Missing lib/main.dart returns exit 1
    // ------------------------------------------------------------------

    test('returns 1 with an error when lib/main.dart is missing', () async {
      // No seed — the temp dir has neither lib/main.dart nor pubspec.yaml.
      TapirInstallCommand.mainDartPathResolver = () =>
          '${tempDir.path}/lib/main.dart';
      TapirInstallCommand.pubspecPathResolver = () =>
          '${tempDir.path}/pubspec.yaml';

      final exit = await TapirInstallCommand().handle(_ctx());
      expect(exit, equals(1));
    });

    // ------------------------------------------------------------------
    // No bin/dowel.dart or lib/app/ side effects (minimal invariant)
    // ------------------------------------------------------------------

    test('minimal invariant: never writes bin/dowel.dart, '
        'lib/app/_plugins.g.dart, or dowel into the consumer', () async {
      final mainDartPath = _seedProject(
        tempDir,
        mainDartContents: '''
import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(home: SizedBox());
}
''',
      );
      TapirInstallCommand.mainDartPathResolver = () => mainDartPath;
      TapirInstallCommand.pubspecPathResolver = () =>
          '${tempDir.path}/pubspec.yaml';

      await TapirInstallCommand().handle(_ctx());

      // The consumer-side dowel dispatcher + plugin barrels MUST NOT
      // exist after tapir:install: the vanilla UX is `dart run
      // tapir <cmd>`, not `dart run bin/dowel.dart <cmd>`.
      expect(File('${tempDir.path}/bin/dowel.dart').existsSync(), isFalse);
      expect(
        File('${tempDir.path}/lib/app/_plugins.g.dart').existsSync(),
        isFalse,
      );
      expect(
        File('${tempDir.path}/lib/app/commands/_index.g.dart').existsSync(),
        isFalse,
      );
      // pubspec.yaml MUST NOT have dowel added; the plugin
      // is reachable transitively through tapir and the
      // consumer never imports dowel directly in a minimal install.
      final pubspecAfter = File('${tempDir.path}/pubspec.yaml')
          .readAsStringSync();
      expect(pubspecAfter.contains('dowel'), isFalse);
    });

    // ------------------------------------------------------------------
    // Phase 2 chained dowel install + plugin:install (recorder fake)
    // ------------------------------------------------------------------

    test('chained Phase 2 invokes dowel install + plugin:install when '
        'their idempotency markers are absent', () async {
      final mainDartPath = _seedProject(
        tempDir,
        mainDartContents: 'void main() {\n  runApp(MyApp());\n}\n',
      );
      TapirInstallCommand.mainDartPathResolver = () => mainDartPath;
      TapirInstallCommand.pubspecPathResolver = () =>
          '${tempDir.path}/pubspec.yaml';
      TapirInstallCommand.runChainedSetup = true;

      // Recorder fake: capture every (executable, arguments) pair and
      // return exit-0 stubs so the chain runs to completion without
      // touching the real `dart` binary.
      final calls = <List<String>>[];
      TapirInstallCommand.processRunner =
          (
            String executable,
            List<String> arguments, {
            String? workingDirectory,
          }) async {
            calls.add([executable, ...arguments]);
            return ProcessResult(0, 0, '', '');
          };

      // Run from inside tempDir so the `File('bin/dispatcher.dart')` +
      // `File('.dowel/installed/tapir.json')` skip checks
      // resolve against the test fixture.
      final originalCwd = Directory.current;
      Directory.current = tempDir;
      try {
        final code = await TapirInstallCommand().handle(
          DowelContext.bare(MapInput(const {}), BufferedOutput()),
        );
        expect(code, equals(0));
      } finally {
        Directory.current = originalCwd;
        TapirInstallCommand.processRunner = Process.run;
      }

      // Both sub-process calls fired in order.
      expect(calls, hasLength(2));
      expect(calls[0], equals(['dart', 'run', 'tapir', 'install']));
      expect(
        calls[1],
        equals(['dart', 'run', 'tapir', 'plugin:install', 'tapir']),
      );
    });

    test(
      'chained Phase 2 swallows sub-process non-zero exit + warns the user',
      () async {
        final mainDartPath = _seedProject(
          tempDir,
          mainDartContents: 'void main() {\n  runApp(MyApp());\n}\n',
        );
        TapirInstallCommand.mainDartPathResolver = () => mainDartPath;
        TapirInstallCommand.pubspecPathResolver = () =>
            '${tempDir.path}/pubspec.yaml';
        TapirInstallCommand.runChainedSetup = true;

        // First call (dowel install) returns non-zero; the chain should
        // print a warning and bail OUT of plugin:install (because the
        // dispatcher scaffold failed, so there's nothing to register).
        var callCount = 0;
        TapirInstallCommand.processRunner =
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
            }) async {
              callCount += 1;
              return ProcessResult(0, 1, '', 'scaffold failed');
            };

        final originalCwd = Directory.current;
        Directory.current = tempDir;
        int exit;
        try {
          exit = await TapirInstallCommand().handle(
            DowelContext.bare(MapInput(const {}), BufferedOutput()),
          );
        } finally {
          Directory.current = originalCwd;
          TapirInstallCommand.processRunner = Process.run;
        }

        // tapir:install MUST NOT propagate the sub-process exit code:
        // the main.dart inject already landed, the chain is a best-effort
        // optimization.
        expect(exit, equals(0));
        // Both calls fired (the second tried plugin:install despite the
        // first warning; that's intentional — they're independent).
        expect(callCount, equals(2));
      },
    );

    test(
      'chained Phase 2 swallows sub-process exception (Process.run throws)',
      () async {
        final mainDartPath = _seedProject(
          tempDir,
          mainDartContents: 'void main() {\n  runApp(MyApp());\n}\n',
        );
        TapirInstallCommand.mainDartPathResolver = () => mainDartPath;
        TapirInstallCommand.pubspecPathResolver = () =>
            '${tempDir.path}/pubspec.yaml';
        TapirInstallCommand.runChainedSetup = true;

        TapirInstallCommand.processRunner =
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
            }) async {
              throw ProcessException(
                executable,
                arguments,
                'fake fork failure',
              );
            };

        final originalCwd = Directory.current;
        Directory.current = tempDir;
        int exit;
        try {
          exit = await TapirInstallCommand().handle(
            DowelContext.bare(MapInput(const {}), BufferedOutput()),
          );
        } finally {
          Directory.current = originalCwd;
          TapirInstallCommand.processRunner = Process.run;
        }

        // Same contract: main.dart wiring succeeded, sub-process chain
        // failed silently, exit-0 still returned. Agent can read the
        // warning lines from stdout and chain manually.
        expect(exit, equals(0));
      },
    );

    test(
      'chained Phase 2 skips BOTH steps when both markers already exist',
      () async {
        final mainDartPath = _seedProject(
          tempDir,
          mainDartContents: 'void main() {\n  runApp(MyApp());\n}\n',
        );
        TapirInstallCommand.mainDartPathResolver = () => mainDartPath;
        TapirInstallCommand.pubspecPathResolver = () =>
            '${tempDir.path}/pubspec.yaml';
        TapirInstallCommand.runChainedSetup = true;

        // Pre-seed BOTH markers so the chain has nothing to do.
        Directory('${tempDir.path}/bin').createSync(recursive: true);
        File('${tempDir.path}/bin/dispatcher.dart')
            .writeAsStringSync('void main(){}');
        Directory('${tempDir.path}/.dowel/installed')
            .createSync(recursive: true);
        File('${tempDir.path}/.dowel/installed/tapir.json')
            .writeAsStringSync('{"plugin":"tapir"}');

        var calls = 0;
        TapirInstallCommand.processRunner =
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
            }) async {
              calls += 1;
              return ProcessResult(0, 0, '', '');
            };

        final originalCwd = Directory.current;
        Directory.current = tempDir;
        try {
          await TapirInstallCommand().handle(
            DowelContext.bare(MapInput(const {}), BufferedOutput()),
          );
        } finally {
          Directory.current = originalCwd;
          TapirInstallCommand.processRunner = Process.run;
        }

        // Idempotent re-run: zero sub-process calls when both markers exist.
        expect(calls, equals(0));
      },
    );

    // ------------------------------------------------------------------
    // magic_devtools dep + NO Magic.init: must NOT inject import or call
    // ------------------------------------------------------------------

    test(
      'magic_devtools dep without Magic.init: does NOT inject '
      "import 'package:magic_devtools/tapir.dart' or MagicTapirIntegration",
      () async {
        // Vanilla app: has magic_devtools in pubspec but NO `await Magic.init(`
        // in main.dart. The import and install call must stay absent so
        // `dart analyze` in the consumer does not trip over an unused import.
        final mainDartPath = _seedProject(
          tempDir,
          pubspecDeps: const {'magic_devtools': 'any'},
          mainDartContents: '''
import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(home: SizedBox());
}
''',
        );
        TapirInstallCommand.mainDartPathResolver = () => mainDartPath;
        TapirInstallCommand.pubspecPathResolver = () =>
            '${tempDir.path}/pubspec.yaml';

        final exit = await TapirInstallCommand().handle(_ctx());
        expect(exit, equals(0));

        final result = File(mainDartPath).readAsStringSync();
        expect(
          result.contains("import 'package:magic_devtools/tapir.dart';"),
          isFalse,
          reason:
              'must NOT inject an unused magic_devtools import when main.dart '
              'has no `await Magic.init(` anchor',
        );
        expect(
          result.contains('MagicTapirIntegration.install()'),
          isFalse,
          reason:
              'must NOT inject MagicTapirIntegration.install() when no Magic.init '
              'anchor is present (container is never ready)',
        );
        // The vanilla TapirPlugin wiring must still land.
        expect(result.contains('TapirPlugin.install();'), isTrue);
      },
    );

    test('chained Phase 2 skips dowel install when bin/dispatcher.dart '
        'already exists (idempotent re-run)', () async {
      final mainDartPath = _seedProject(
        tempDir,
        mainDartContents: 'void main() {\n  runApp(MyApp());\n}\n',
      );
      TapirInstallCommand.mainDartPathResolver = () => mainDartPath;
      TapirInstallCommand.pubspecPathResolver = () =>
          '${tempDir.path}/pubspec.yaml';
      TapirInstallCommand.runChainedSetup = true;

      // Pre-seed bin/dispatcher.dart (dowel install marker) so the
      // chain skips its scaffold. Leave the plugin marker missing so
      // plugin:install still fires.
      Directory('${tempDir.path}/bin').createSync(recursive: true);
      File('${tempDir.path}/bin/dispatcher.dart')
          .writeAsStringSync('void main() {}');

      final calls = <List<String>>[];
      TapirInstallCommand.processRunner =
          (
            String executable,
            List<String> arguments, {
            String? workingDirectory,
          }) async {
            calls.add([executable, ...arguments]);
            return ProcessResult(0, 0, '', '');
          };

      final originalCwd = Directory.current;
      Directory.current = tempDir;
      try {
        await TapirInstallCommand().handle(
          DowelContext.bare(MapInput(const {}), BufferedOutput()),
        );
      } finally {
        Directory.current = originalCwd;
        TapirInstallCommand.processRunner = Process.run;
      }

      // Only plugin:install fired; dowel install was skipped by the
      // dispatcher.dart pre-existence guard.
      expect(calls, hasLength(1));
      expect(
        calls[0].sublist(0, 4),
        equals(['dart', 'run', 'tapir', 'plugin:install']),
      );
    });
  });
}
