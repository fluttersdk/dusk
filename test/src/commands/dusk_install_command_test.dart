import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_install_command.dart';

/// Recording subprocess runner ; captures every `(executable, args)` call so
/// tests can assert ordering and per-call exit codes without spawning the
/// real Dart toolchain.
class _RecordingRunner {
  _RecordingRunner({this.exits = const <int>[]});

  /// Per-call exit codes consumed in FIFO order. Missing entries default to 0.
  final List<int> exits;
  int _i = 0;

  final List<List<String>> calls = <List<String>>[];

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    calls.add(<String>[executable, ...arguments]);
    final code = _i < exits.length ? exits[_i++] : 0;
    return ProcessResult(0, code, '', code == 0 ? '' : 'mock-stderr');
  }
}

/// Seed [tempDir] with a stub [mainDartContents] file at lib/main.dart and a
/// pubspec.yaml that lists [pubspecDeps] entries under `dependencies:`. Returns
/// the absolute path to the seeded lib/main.dart.
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

void main() {
  group('DuskInstallCommand', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dusk_install_test_');
    });

    tearDown(() {
      // Restore module-level hooks between tests; they are static fields, so
      // a test that mutates them leaks into the next without this reset.
      DuskInstallCommand.wrapperExistsCheck =
          () => File('bin/artisan.dart').existsSync();
      DuskInstallCommand.mainDartPathResolver = () => 'lib/main.dart';
      DuskInstallCommand.pubspecPathResolver = () => 'pubspec.yaml';
      tempDir.deleteSync(recursive: true);
    });

    // -------------------------------------------------------------------------
    // Metadata
    // -------------------------------------------------------------------------

    test('name is dusk:install', () {
      expect(DuskInstallCommand().name, equals('dusk:install'));
    });

    test('boot is CommandBoot.none (does not require a running app)', () {
      expect(DuskInstallCommand().boot, equals(CommandBoot.none));
    });

    test('description is non-empty', () {
      expect(DuskInstallCommand().description, isNotEmpty);
    });

    // -------------------------------------------------------------------------
    // Wrapper-presence branch: skip consumer:scaffold when wrapper exists
    // -------------------------------------------------------------------------

    test(
        'skips consumer:scaffold when bin/artisan.dart already exists; '
        'plugin:install still runs', () async {
      final runner = _RecordingRunner();
      DuskInstallCommand.processRunner = runner.run;
      DuskInstallCommand.wrapperExistsCheck = () => true;
      // No main.dart so phase 3 is a no-op.
      DuskInstallCommand.mainDartPathResolver =
          () => '${tempDir.path}/lib/main.dart';
      DuskInstallCommand.pubspecPathResolver =
          () => '${tempDir.path}/pubspec.yaml';

      final exit = await DuskInstallCommand().handle(
        ArtisanContext.bare(MapInput(const {}), BufferedOutput()),
      );

      expect(exit, equals(0));
      expect(runner.calls, hasLength(1),
          reason: 'only plugin:install should run when wrapper present');
      expect(
          runner.calls.single,
          equals([
            'dart',
            'run',
            'fluttersdk_artisan',
            'plugin:install',
            'fluttersdk_dusk'
          ]));
    });

    // -------------------------------------------------------------------------
    // Wrapper-missing branch: run consumer:scaffold then plugin:install
    // -------------------------------------------------------------------------

    test(
        'runs consumer:scaffold then plugin:install when bin/artisan.dart '
        'is missing (correct ordering)', () async {
      final runner = _RecordingRunner();
      DuskInstallCommand.processRunner = runner.run;
      DuskInstallCommand.wrapperExistsCheck = () => false;
      DuskInstallCommand.mainDartPathResolver =
          () => '${tempDir.path}/lib/main.dart';
      DuskInstallCommand.pubspecPathResolver =
          () => '${tempDir.path}/pubspec.yaml';

      final exit = await DuskInstallCommand().handle(
        ArtisanContext.bare(MapInput(const {}), BufferedOutput()),
      );

      expect(exit, equals(0));
      expect(runner.calls, hasLength(2));
      expect(runner.calls[0],
          equals(['dart', 'run', 'fluttersdk_artisan', 'consumer:scaffold']),
          reason: 'consumer:scaffold must run first');
      expect(
          runner.calls[1],
          equals([
            'dart',
            'run',
            'fluttersdk_artisan',
            'plugin:install',
            'fluttersdk_dusk'
          ]),
          reason: 'plugin:install must run after scaffold');
    });

    // -------------------------------------------------------------------------
    // Failure propagation
    // -------------------------------------------------------------------------

    test(
        'returns scaffold exit code (and skips plugin:install) when '
        'consumer:scaffold fails', () async {
      final runner = _RecordingRunner(exits: <int>[2]);
      DuskInstallCommand.processRunner = runner.run;
      DuskInstallCommand.wrapperExistsCheck = () => false;
      DuskInstallCommand.mainDartPathResolver =
          () => '${tempDir.path}/lib/main.dart';
      DuskInstallCommand.pubspecPathResolver =
          () => '${tempDir.path}/pubspec.yaml';

      final exit = await DuskInstallCommand().handle(
        ArtisanContext.bare(MapInput(const {}), BufferedOutput()),
      );

      expect(exit, equals(2));
      expect(runner.calls, hasLength(1),
          reason:
              'plugin:install must not run after scaffold failure (fail-fast)');
      expect(runner.calls.single.contains('consumer:scaffold'), isTrue);
    });

    test(
        'returns plugin:install exit code when scaffold passes but '
        'plugin:install fails', () async {
      // First call (scaffold) succeeds; second call (plugin:install) fails.
      final runner = _RecordingRunner(exits: <int>[0, 3]);
      DuskInstallCommand.processRunner = runner.run;
      DuskInstallCommand.wrapperExistsCheck = () => false;
      DuskInstallCommand.mainDartPathResolver =
          () => '${tempDir.path}/lib/main.dart';
      DuskInstallCommand.pubspecPathResolver =
          () => '${tempDir.path}/pubspec.yaml';

      final exit = await DuskInstallCommand().handle(
        ArtisanContext.bare(MapInput(const {}), BufferedOutput()),
      );

      expect(exit, equals(3));
      expect(runner.calls, hasLength(2));
    });

    // -------------------------------------------------------------------------
    // Phase 3: vanilla anchor detection (runApp without Magic.init)
    // -------------------------------------------------------------------------

    test(
        'vanilla Flutter app: injects imports + DuskPlugin.install + '
        'WidgetsFlutterBinding.ensureInitialized before runApp(', () async {
      const stub = '''
import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp());
}
''';
      final mainDartPath = _seedProject(tempDir, mainDartContents: stub);
      final runner = _RecordingRunner();
      DuskInstallCommand.processRunner = runner.run;
      DuskInstallCommand.wrapperExistsCheck = () => true;
      DuskInstallCommand.mainDartPathResolver = () => mainDartPath;
      DuskInstallCommand.pubspecPathResolver =
          () => '${tempDir.path}/pubspec.yaml';

      final exit = await DuskInstallCommand().handle(
        ArtisanContext.bare(MapInput(const {}), BufferedOutput()),
      );

      expect(exit, equals(0));
      final updated = File(mainDartPath).readAsStringSync();
      expect(updated, contains("import 'package:flutter/foundation.dart'"));
      expect(updated, contains("import 'package:fluttersdk_dusk/dusk.dart'"));
      expect(updated, contains('WidgetsFlutterBinding.ensureInitialized()'));
      expect(updated, contains('if (kDebugMode) {'));
      expect(updated, contains('DuskPlugin.install();'));
      // No Magic.init anchor and no Magic dep, so no MagicDuskIntegration.
      expect(updated, isNot(contains('MagicDuskIntegration.install()')));
      // No wind dep, so no WindDuskIntegration.
      expect(updated, isNot(contains('WindDuskIntegration.install()')));

      final duskInstallPos = updated.indexOf('DuskPlugin.install()');
      final runAppPos = updated.indexOf('runApp(');
      expect(duskInstallPos, lessThan(runAppPos),
          reason: 'DuskPlugin.install() must appear BEFORE runApp(');
    });

    // -------------------------------------------------------------------------
    // Phase 3: Magic-stack anchor detection (await Magic.init present)
    // -------------------------------------------------------------------------

    test(
        'Magic-stack app: injects DuskPlugin.install before await Magic.init '
        'and MagicDuskIntegration.install after it', () async {
      const stub = '''
import 'package:flutter/material.dart';
import 'package:magic/magic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Magic.init();
  runApp(const MagicApplication());
}
''';
      final mainDartPath = _seedProject(
        tempDir,
        mainDartContents: stub,
        pubspecDeps: const {'magic': '^1.0.0'},
      );
      final runner = _RecordingRunner();
      DuskInstallCommand.processRunner = runner.run;
      DuskInstallCommand.wrapperExistsCheck = () => true;
      DuskInstallCommand.mainDartPathResolver = () => mainDartPath;
      DuskInstallCommand.pubspecPathResolver =
          () => '${tempDir.path}/pubspec.yaml';

      final exit = await DuskInstallCommand().handle(
        ArtisanContext.bare(MapInput(const {}), BufferedOutput()),
      );

      expect(exit, equals(0));
      final updated = File(mainDartPath).readAsStringSync();
      expect(updated, contains('DuskPlugin.install();'));
      expect(updated, contains('MagicDuskIntegration.install();'));

      final duskPos = updated.indexOf('DuskPlugin.install()');
      final magicInitPos = updated.indexOf('await Magic.init(');
      final magicIntegrationPos =
          updated.indexOf('MagicDuskIntegration.install()');
      expect(duskPos, lessThan(magicInitPos),
          reason: 'DuskPlugin.install must run BEFORE await Magic.init');
      expect(magicIntegrationPos, greaterThan(magicInitPos),
          reason: 'MagicDuskIntegration.install must run AFTER Magic.init');
    });

    // -------------------------------------------------------------------------
    // Phase 3: Wind dep adds WindDuskIntegration
    // -------------------------------------------------------------------------

    test(
        'wind dep present: injects WindDuskIntegration.install alongside '
        'DuskPlugin.install', () async {
      const stub = '''
import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp());
}
''';
      final mainDartPath = _seedProject(
        tempDir,
        mainDartContents: stub,
        pubspecDeps: const {'wind': '^1.0.0'},
      );
      final runner = _RecordingRunner();
      DuskInstallCommand.processRunner = runner.run;
      DuskInstallCommand.wrapperExistsCheck = () => true;
      DuskInstallCommand.mainDartPathResolver = () => mainDartPath;
      DuskInstallCommand.pubspecPathResolver =
          () => '${tempDir.path}/pubspec.yaml';

      final exit = await DuskInstallCommand().handle(
        ArtisanContext.bare(MapInput(const {}), BufferedOutput()),
      );

      expect(exit, equals(0));
      final updated = File(mainDartPath).readAsStringSync();
      expect(updated, contains('DuskPlugin.install();'));
      expect(updated, contains('WindDuskIntegration.install();'));
    });

    // -------------------------------------------------------------------------
    // Phase 3: WidgetsFlutterBinding.ensureInitialized is skipped when already
    // present (avoids a duplicate call)
    // -------------------------------------------------------------------------

    test(
        'does not duplicate WidgetsFlutterBinding.ensureInitialized when '
        'already present', () async {
      const stub = '''
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp());
}
''';
      final mainDartPath = _seedProject(tempDir, mainDartContents: stub);
      final runner = _RecordingRunner();
      DuskInstallCommand.processRunner = runner.run;
      DuskInstallCommand.wrapperExistsCheck = () => true;
      DuskInstallCommand.mainDartPathResolver = () => mainDartPath;
      DuskInstallCommand.pubspecPathResolver =
          () => '${tempDir.path}/pubspec.yaml';

      await DuskInstallCommand().handle(
        ArtisanContext.bare(MapInput(const {}), BufferedOutput()),
      );

      final updated = File(mainDartPath).readAsStringSync();
      final occurrences = 'WidgetsFlutterBinding.ensureInitialized()'
          .allMatches(updated)
          .length;
      expect(occurrences, equals(1),
          reason: 'must not double-inject the binding-ensure call');
    });

    // -------------------------------------------------------------------------
    // Phase 3: re-running is idempotent (no duplicates)
    // -------------------------------------------------------------------------

    test('re-running the command is idempotent (no duplicate inject)',
        () async {
      const stub = '''
import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp());
}
''';
      final mainDartPath = _seedProject(tempDir, mainDartContents: stub);
      final runner = _RecordingRunner();
      DuskInstallCommand.processRunner = runner.run;
      DuskInstallCommand.wrapperExistsCheck = () => true;
      DuskInstallCommand.mainDartPathResolver = () => mainDartPath;
      DuskInstallCommand.pubspecPathResolver =
          () => '${tempDir.path}/pubspec.yaml';

      await DuskInstallCommand().handle(
        ArtisanContext.bare(MapInput(const {}), BufferedOutput()),
      );
      final firstPass = File(mainDartPath).readAsStringSync();

      await DuskInstallCommand().handle(
        ArtisanContext.bare(MapInput(const {}), BufferedOutput()),
      );
      final secondPass = File(mainDartPath).readAsStringSync();

      expect(secondPass, equals(firstPass),
          reason: 'second run must not change the file');
      expect('DuskPlugin.install()'.allMatches(secondPass).length, equals(1),
          reason: 'DuskPlugin.install must appear exactly once');
    });

    // -------------------------------------------------------------------------
    // Phase 3: lib/main.dart missing is a soft-fail (still returns 0)
    // -------------------------------------------------------------------------

    test('missing lib/main.dart: skipped softly, exit code remains 0',
        () async {
      final runner = _RecordingRunner();
      DuskInstallCommand.processRunner = runner.run;
      DuskInstallCommand.wrapperExistsCheck = () => true;
      DuskInstallCommand.mainDartPathResolver =
          () => '${tempDir.path}/lib/missing.dart';
      DuskInstallCommand.pubspecPathResolver =
          () => '${tempDir.path}/pubspec.yaml';

      final exit = await DuskInstallCommand().handle(
        ArtisanContext.bare(MapInput(const {}), BufferedOutput()),
      );

      expect(exit, equals(0));
    });

    // -------------------------------------------------------------------------
    // Phase 3: three-step inject sequence (import, before-anchor, after-anchor)
    // verified across a single magic-stack run
    // -------------------------------------------------------------------------

    test(
        'magic-stack: imports + before-anchor + after-anchor inject sequence '
        'all land in main.dart', () async {
      const stub = '''
import 'package:flutter/material.dart';
import 'package:magic/magic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Magic.init();
  runApp(const MagicApplication());
}
''';
      final mainDartPath = _seedProject(
        tempDir,
        mainDartContents: stub,
        pubspecDeps: const {'magic': '^1.0.0', 'wind': '^1.0.0'},
      );
      final runner = _RecordingRunner();
      DuskInstallCommand.processRunner = runner.run;
      DuskInstallCommand.wrapperExistsCheck = () => true;
      DuskInstallCommand.mainDartPathResolver = () => mainDartPath;
      DuskInstallCommand.pubspecPathResolver =
          () => '${tempDir.path}/pubspec.yaml';

      await DuskInstallCommand().handle(
        ArtisanContext.bare(MapInput(const {}), BufferedOutput()),
      );

      final updated = File(mainDartPath).readAsStringSync();
      // Step 3a: imports.
      expect(updated,
          contains("import 'package:flutter/foundation.dart' show kDebugMode"));
      expect(updated, contains("import 'package:fluttersdk_dusk/dusk.dart'"));
      // Step 3b: DuskPlugin + WindDuskIntegration before Magic.init.
      expect(updated, contains('DuskPlugin.install();'));
      expect(updated, contains('WindDuskIntegration.install();'));
      // Step 3c: MagicDuskIntegration after Magic.init.
      expect(updated, contains('MagicDuskIntegration.install();'));

      final duskPos = updated.indexOf('DuskPlugin.install()');
      final windPos = updated.indexOf('WindDuskIntegration.install()');
      final magicInitPos = updated.indexOf('await Magic.init(');
      final magicIntegrationPos =
          updated.indexOf('MagicDuskIntegration.install()');

      expect(duskPos, lessThan(magicInitPos));
      expect(windPos, lessThan(magicInitPos));
      expect(magicIntegrationPos, greaterThan(magicInitPos));
    });
  });
}
