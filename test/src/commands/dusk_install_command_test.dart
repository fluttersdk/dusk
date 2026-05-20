import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_install_command.dart';

/// Seed [tempDir] with a stub `lib/main.dart` carrying [mainDartContents] +
/// a `pubspec.yaml` that lists [pubspecDeps] entries under
/// `dependencies:`. Returns the absolute path to the seeded main.dart so
/// callers can inject it via [DuskInstallCommand.mainDartPathResolver].
String _seedProject(
  Directory tempDir, {
  required String mainDartContents,
  Map<String, String> pubspecDeps = const {},
}) {
  final mainDartPath = '${tempDir.path}/lib/main.dart';
  Directory('${tempDir.path}/lib').createSync(recursive: true);
  File(mainDartPath).writeAsStringSync(mainDartContents);
  final depsBlock =
      pubspecDeps.entries.map((e) => '  ${e.key}: ${e.value}').join('\n');
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
  return mainDartPath;
}

/// Build a bare [ArtisanContext] suitable for invoking the command without
/// any real input / output wiring.
ArtisanContext _ctx() {
  return ArtisanContext.bare(MapInput(const {}), BufferedOutput());
}

void main() {
  group('DuskInstallCommand', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dusk_install_test_');
    });

    tearDown(() {
      // Restore module-level hooks between tests; they are static fields,
      // so a test that mutates them leaks into the next without this
      // reset.
      DuskInstallCommand.mainDartPathResolver = () => 'lib/main.dart';
      DuskInstallCommand.pubspecPathResolver = () => 'pubspec.yaml';
      tempDir.deleteSync(recursive: true);
    });

    // ------------------------------------------------------------------
    // Metadata
    // ------------------------------------------------------------------

    test('name is dusk:install', () {
      expect(DuskInstallCommand().name, equals('dusk:install'));
    });

    test('boot is CommandBoot.none (does not require a running app)', () {
      expect(DuskInstallCommand().boot, equals(CommandBoot.none));
    });

    test('description signals the minimal scope (no scaffold)', () {
      // The description must NOT promise the heavy consumer-scaffold flow
      // anymore; the command's single responsibility is main.dart wiring.
      final desc = DuskInstallCommand().description;
      expect(desc, isNotEmpty);
      expect(desc.toLowerCase(), contains('main.dart'));
      expect(
        desc.toLowerCase(),
        isNot(contains('consumer:scaffold')),
        reason: 'minimal install must not advertise consumer:scaffold',
      );
    });

    // ------------------------------------------------------------------
    // Vanilla flutter app: inject before runApp()
    // ------------------------------------------------------------------

    test(
      'vanilla app: injects kDebugMode + DuskPlugin.install() block before '
      'runApp(',
      () async {
        final mainDartPath = _seedProject(
          tempDir,
          mainDartContents: '''
import 'package:flutter/material.dart';

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
        DuskInstallCommand.mainDartPathResolver = () => mainDartPath;
        DuskInstallCommand.pubspecPathResolver =
            () => '${tempDir.path}/pubspec.yaml';

        final exit = await DuskInstallCommand().handle(_ctx());
        expect(exit, equals(0));

        final result = File(mainDartPath).readAsStringSync();
        expect(
          result.contains(
            "import 'package:flutter/foundation.dart' show kDebugMode;",
          ),
          isTrue,
        );
        expect(
          result.contains("import 'package:fluttersdk_dusk/dusk.dart';"),
          isTrue,
        );
        expect(
          result.contains('WidgetsFlutterBinding.ensureInitialized();'),
          isTrue,
        );
        expect(
          result.contains('if (kDebugMode) {'),
          isTrue,
        );
        expect(
          result.contains('DuskPlugin.install();'),
          isTrue,
        );
        // No Magic deps in this vanilla case, so no MagicDuskIntegration
        // wire lands.
        expect(result.contains('MagicDuskIntegration.install()'), isFalse);
        expect(result.contains('WindDuskIntegration.install()'), isFalse);
      },
    );

    // ------------------------------------------------------------------
    // Magic-stack app: BEFORE-Magic.init + AFTER-Magic.init wires
    // ------------------------------------------------------------------

    test(
      'magic-stack app: injects DuskPlugin.install() BEFORE Magic.init AND '
      'MagicDuskIntegration.install() AFTER Magic.init',
      () async {
        final mainDartPath = _seedProject(
          tempDir,
          pubspecDeps: const {'magic': 'any'},
          mainDartContents: '''
import 'package:flutter/material.dart';
import 'package:magic/magic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Magic.init(configFactories: [() => {}]);
  runApp(const MagicApplication());
}
''',
        );
        DuskInstallCommand.mainDartPathResolver = () => mainDartPath;
        DuskInstallCommand.pubspecPathResolver =
            () => '${tempDir.path}/pubspec.yaml';

        final exit = await DuskInstallCommand().handle(_ctx());
        expect(exit, equals(0));

        final result = File(mainDartPath).readAsStringSync();
        final duskInstallIdx = result.indexOf('DuskPlugin.install();');
        final magicInitIdx = result.indexOf('await Magic.init(');
        final magicIntegrationIdx =
            result.indexOf('MagicDuskIntegration.install();');

        expect(duskInstallIdx, greaterThan(-1));
        expect(magicInitIdx, greaterThan(-1));
        expect(magicIntegrationIdx, greaterThan(-1));
        expect(
          duskInstallIdx < magicInitIdx,
          isTrue,
          reason: 'DuskPlugin.install() must land BEFORE Magic.init()',
        );
        expect(
          magicInitIdx < magicIntegrationIdx,
          isTrue,
          reason: 'MagicDuskIntegration.install() must land AFTER Magic.init()',
        );
        expect(
          result.contains("import 'package:magic/dusk_integration.dart';"),
          isTrue,
          reason: 'magic-stack inject must reference the new dusk_integration '
              'sub-barrel, not the legacy magic.dart main barrel',
        );
      },
    );

    // ------------------------------------------------------------------
    // Wind dep: WindDuskIntegration wires alongside DuskPlugin
    // ------------------------------------------------------------------

    test(
      'wind dep present (fluttersdk_wind): wires WindDuskIntegration in the '
      'same kDebugMode block',
      () async {
        final mainDartPath = _seedProject(
          tempDir,
          pubspecDeps: const {'fluttersdk_wind': 'any'},
          mainDartContents: '''
import 'package:flutter/material.dart';

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
        DuskInstallCommand.mainDartPathResolver = () => mainDartPath;
        DuskInstallCommand.pubspecPathResolver =
            () => '${tempDir.path}/pubspec.yaml';

        await DuskInstallCommand().handle(_ctx());
        final result = File(mainDartPath).readAsStringSync();
        expect(result.contains('WindDuskIntegration.install()'), isTrue);
      },
    );

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
import 'package:flutter/material.dart';

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
        DuskInstallCommand.mainDartPathResolver = () => mainDartPath;
        DuskInstallCommand.pubspecPathResolver =
            () => '${tempDir.path}/pubspec.yaml';

        await DuskInstallCommand().handle(_ctx());
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

    test('re-running the command is idempotent (no duplicate inject)',
        () async {
      final mainDartPath = _seedProject(
        tempDir,
        mainDartContents: '''
import 'package:flutter/material.dart';

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
      DuskInstallCommand.mainDartPathResolver = () => mainDartPath;
      DuskInstallCommand.pubspecPathResolver =
          () => '${tempDir.path}/pubspec.yaml';

      await DuskInstallCommand().handle(_ctx());
      final afterFirst = File(mainDartPath).readAsStringSync();
      await DuskInstallCommand().handle(_ctx());
      final afterSecond = File(mainDartPath).readAsStringSync();

      expect(afterSecond, equals(afterFirst));
      expect(
        'DuskPlugin.install();'.allMatches(afterSecond).length,
        equals(1),
      );
      expect(
        "import 'package:fluttersdk_dusk/dusk.dart';"
            .allMatches(afterSecond)
            .length,
        equals(1),
      );
    });

    // ------------------------------------------------------------------
    // Missing lib/main.dart returns exit 1
    // ------------------------------------------------------------------

    test('returns 1 with an error when lib/main.dart is missing', () async {
      // No seed — the temp dir has neither lib/main.dart nor pubspec.yaml.
      DuskInstallCommand.mainDartPathResolver =
          () => '${tempDir.path}/lib/main.dart';
      DuskInstallCommand.pubspecPathResolver =
          () => '${tempDir.path}/pubspec.yaml';

      final exit = await DuskInstallCommand().handle(_ctx());
      expect(exit, equals(1));
    });

    // ------------------------------------------------------------------
    // No bin/artisan.dart or lib/app/ side effects (minimal invariant)
    // ------------------------------------------------------------------

    test(
      'minimal invariant: never writes bin/artisan.dart, '
      'lib/app/_plugins.g.dart, or fluttersdk_artisan into the consumer',
      () async {
        final mainDartPath = _seedProject(
          tempDir,
          mainDartContents: '''
import 'package:flutter/material.dart';

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
        DuskInstallCommand.mainDartPathResolver = () => mainDartPath;
        DuskInstallCommand.pubspecPathResolver =
            () => '${tempDir.path}/pubspec.yaml';

        await DuskInstallCommand().handle(_ctx());

        // The consumer-side artisan dispatcher + plugin barrels MUST NOT
        // exist after dusk:install: the vanilla UX is `dart run
        // fluttersdk_dusk <cmd>`, not `dart run bin/artisan.dart <cmd>`.
        expect(
          File('${tempDir.path}/bin/artisan.dart').existsSync(),
          isFalse,
        );
        expect(
          File('${tempDir.path}/lib/app/_plugins.g.dart').existsSync(),
          isFalse,
        );
        expect(
          File('${tempDir.path}/lib/app/commands/_index.g.dart').existsSync(),
          isFalse,
        );
        // pubspec.yaml MUST NOT have fluttersdk_artisan added; the plugin
        // is reachable transitively through fluttersdk_dusk and the
        // consumer never imports artisan directly in a minimal install.
        final pubspecAfter =
            File('${tempDir.path}/pubspec.yaml').readAsStringSync();
        expect(pubspecAfter.contains('fluttersdk_artisan'), isFalse);
      },
    );
  });
}
