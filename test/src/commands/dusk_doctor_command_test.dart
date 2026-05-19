import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_doctor_command.dart';
import 'package:fluttersdk_dusk/src/dusk_plugin.dart';

/// Restore every static test seam between tests so per-test overrides do not
/// leak. The doctor command leans on roughly eight injected probes; without
/// this teardown, a test that overrides `semanticsEnabledProbe` to false
/// leaks ERROR rows into every following test that expects PASS.
void _resetDoctorHooks() {
  DuskDoctorCommand.stateFileReader = () async => null;
  DuskDoctorCommand.chromePidProbe = ({required int parentPid}) async => null;
  DuskDoctorCommand.processStartTimeProbe = (int pid) => null;
  DuskDoctorCommand.nowProvider = DateTime.now;
  DuskDoctorCommand.semanticsEnabledProbe = () => true;
  DuskDoctorCommand.duskDisableEnvReader = () => '';
  DuskDoctorCommand.enrichersProbe = () => DuskPlugin.enrichers.length;
  DuskDoctorCommand.mainDartPathResolver = () => 'lib/main.dart';
  DuskDoctorCommand.mainDartReader = (String path) {
    final file = File(path);
    return file.existsSync() ? file.readAsStringSync() : null;
  };
}

void main() {
  setUp(() {
    _resetDoctorHooks();
    DuskPlugin.enrichers.clear();
  });

  tearDown(() {
    _resetDoctorHooks();
    DuskPlugin.enrichers.clear();
  });

  group('DuskDoctorCommand metadata', () {
    test('name is dusk:doctor', () {
      expect(DuskDoctorCommand().name, equals('dusk:doctor'));
    });

    test('description is "Verify dusk plugin runtime + consumer wiring health"',
        () {
      expect(
        DuskDoctorCommand().description,
        equals('Verify dusk plugin runtime + consumer wiring health'),
      );
    });

    test('boot is CommandBoot.none (does not require a running app)', () {
      expect(DuskDoctorCommand().boot, equals(CommandBoot.none));
    });
  });

  // ---------------------------------------------------------------------------
  // Check 1: hot-restart staleness probe
  // ---------------------------------------------------------------------------

  group('Check 1: hot-restart staleness', () {
    test(
        'PASS when state.json is absent (nothing to compare; INFO row "Skipped (no Chrome attached)")',
        () async {
      final output = BufferedOutput();
      final exit = await DuskDoctorCommand()
          .handle(ArtisanContext.bare(MapInput(const {}), output));

      expect(exit, equals(0),
          reason: 'no Chrome to probe means no ERROR; exit 0');
      expect(output.content, contains('hot-restart staleness'));
      expect(output.content, contains('Skipped (no Chrome attached)'));
    });

    test(
        'PASS when Chrome lstart matches state.json startedAt within 30s drift',
        () async {
      final DateTime startedAt = DateTime.utc(2026, 5, 19, 12, 0, 0);
      DuskDoctorCommand.stateFileReader = () async => <String, dynamic>{
            'pid': 4242,
            'startedAt': startedAt.toIso8601String(),
          };
      DuskDoctorCommand.chromePidProbe =
          ({required int parentPid}) async => 9999;
      // Drift = 15s ; under the 30s threshold.
      DuskDoctorCommand.processStartTimeProbe =
          (int pid) => startedAt.add(const Duration(seconds: 15));

      final output = BufferedOutput();
      final exit = await DuskDoctorCommand()
          .handle(ArtisanContext.bare(MapInput(const {}), output));

      expect(exit, equals(0));
      expect(output.content, contains('hot-restart staleness'));
      // No WARN row for this check ; the marker is absence of the drift line.
      expect(output.content, isNot(contains('hot-restart drift')));
    });

    test(
        'WARN when Chrome lstart drifts more than 30s past state.json startedAt',
        () async {
      final DateTime startedAt = DateTime.utc(2026, 5, 19, 12, 0, 0);
      DuskDoctorCommand.stateFileReader = () async => <String, dynamic>{
            'pid': 4242,
            'startedAt': startedAt.toIso8601String(),
          };
      DuskDoctorCommand.chromePidProbe =
          ({required int parentPid}) async => 9999;
      // Drift = 120s ; far above the 30s threshold.
      DuskDoctorCommand.processStartTimeProbe =
          (int pid) => startedAt.add(const Duration(seconds: 120));

      final output = BufferedOutput();
      final exit = await DuskDoctorCommand()
          .handle(ArtisanContext.bare(MapInput(const {}), output));

      // WARN never fails the command ; only ERROR does.
      expect(exit, equals(0));
      expect(output.content, contains('hot-restart drift'));
    });

    test(
        'INFO "Skipped (no Chrome attached)" when state.json present but '
        'captureChromePid returns null', () async {
      final DateTime startedAt = DateTime.utc(2026, 5, 19, 12, 0, 0);
      DuskDoctorCommand.stateFileReader = () async => <String, dynamic>{
            'pid': 4242,
            'startedAt': startedAt.toIso8601String(),
          };
      DuskDoctorCommand.chromePidProbe =
          ({required int parentPid}) async => null;

      final output = BufferedOutput();
      final exit = await DuskDoctorCommand()
          .handle(ArtisanContext.bare(MapInput(const {}), output));

      expect(exit, equals(0));
      expect(output.content, contains('Skipped (no Chrome attached)'));
    });
  });

  // ---------------------------------------------------------------------------
  // Check 2: DUSK_DISABLE env-var probe
  // ---------------------------------------------------------------------------

  group('Check 2: DUSK_DISABLE env-var', () {
    test('PASS when DUSK_DISABLE is empty (runtime hooks active)', () async {
      DuskDoctorCommand.duskDisableEnvReader = () => '';
      final output = BufferedOutput();
      final exit = await DuskDoctorCommand()
          .handle(ArtisanContext.bare(MapInput(const {}), output));

      expect(exit, equals(0));
      expect(output.content, contains('DUSK_DISABLE'));
      expect(output.content, isNot(contains('runtime hooks inactive')));
    });

    test(
        'WARN when DUSK_DISABLE is set, with the actual value echoed in the message',
        () async {
      DuskDoctorCommand.duskDisableEnvReader = () => '1';
      final output = BufferedOutput();
      final exit = await DuskDoctorCommand()
          .handle(ArtisanContext.bare(MapInput(const {}), output));

      expect(exit, equals(0), reason: 'WARN never fails the command');
      expect(
        output.content,
        contains('dusk disabled via DUSK_DISABLE=1, runtime hooks inactive'),
      );
    });

    test('WARN echoes a custom DUSK_DISABLE value verbatim (e.g. "true")',
        () async {
      DuskDoctorCommand.duskDisableEnvReader = () => 'true';
      final output = BufferedOutput();
      final exit = await DuskDoctorCommand()
          .handle(ArtisanContext.bare(MapInput(const {}), output));

      expect(exit, equals(0));
      expect(
        output.content,
        contains('dusk disabled via DUSK_DISABLE=true, runtime hooks inactive'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Check 3: enricher list non-empty
  // ---------------------------------------------------------------------------

  group('Check 3: enricher list non-empty', () {
    test('PASS when at least one enricher is registered (count echoed)',
        () async {
      DuskDoctorCommand.enrichersProbe = () => 2;

      final output = BufferedOutput();
      final exit = await DuskDoctorCommand()
          .handle(ArtisanContext.bare(MapInput(const {}), output));

      expect(exit, equals(0));
      expect(output.content, contains('enrichers registered: 2'));
    });

    test('WARN when DuskPlugin.enrichers is empty', () async {
      DuskDoctorCommand.enrichersProbe = () => 0;

      final output = BufferedOutput();
      final exit = await DuskDoctorCommand()
          .handle(ArtisanContext.bare(MapInput(const {}), output));

      expect(exit, equals(0));
      expect(
        output.content,
        contains(
          'no enrichers registered; install Magic + Wind integrations for '
          'richer snapshots',
        ),
      );
    });

    test('PASS with count = 1 when exactly one enricher is registered',
        () async {
      DuskDoctorCommand.enrichersProbe = () => 1;

      final output = BufferedOutput();
      final exit = await DuskDoctorCommand()
          .handle(ArtisanContext.bare(MapInput(const {}), output));

      expect(exit, equals(0));
      expect(output.content, contains('enrichers registered: 1'));
    });
  });

  // ---------------------------------------------------------------------------
  // Check 4: Semantics tree forced on
  // ---------------------------------------------------------------------------

  group('Check 4: Semantics tree forced on', () {
    test('PASS when semanticsEnabled is true', () async {
      DuskDoctorCommand.semanticsEnabledProbe = () => true;

      final output = BufferedOutput();
      final exit = await DuskDoctorCommand()
          .handle(ArtisanContext.bare(MapInput(const {}), output));

      expect(exit, equals(0));
      expect(output.content, contains('Semantics tree forced on'));
      expect(
        output.content,
        isNot(contains('DuskPlugin.install may not have run')),
      );
    });

    test(
        'ERROR (exit != 0) when semanticsEnabled is false; message names '
        'DuskPlugin.install', () async {
      DuskDoctorCommand.semanticsEnabledProbe = () => false;

      final output = BufferedOutput();
      final exit = await DuskDoctorCommand()
          .handle(ArtisanContext.bare(MapInput(const {}), output));

      expect(exit, isNot(equals(0)),
          reason: 'ERROR-severity check must fail the command');
      expect(
        output.content,
        contains(
          'Semantics tree not forced on; DuskPlugin.install may not have run',
        ),
      );
    });

    test('ERROR also rendered with the [ERROR] prefix in BufferedOutput',
        () async {
      DuskDoctorCommand.semanticsEnabledProbe = () => false;

      final output = BufferedOutput();
      await DuskDoctorCommand()
          .handle(ArtisanContext.bare(MapInput(const {}), output));

      // BufferedOutput prefixes errors with "[ERROR] " — that is the marker
      // tests use to distinguish ERROR rows from WARN / PASS rows.
      expect(output.content, contains('[ERROR]'));
    });
  });

  // ---------------------------------------------------------------------------
  // Check 5: Magic-init detection (informational only)
  // ---------------------------------------------------------------------------

  group('Check 5: Magic-init detection (INFO-only)', () {
    test(
        'INFO "Magic-stack detected, integration wired" when main.dart has '
        'both Magic.init( AND MagicDuskIntegration.install', () async {
      DuskDoctorCommand.mainDartReader = (String path) => '''
import 'package:magic/magic.dart';
import 'package:fluttersdk_dusk/dusk.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    DuskPlugin.install();
  }
  await Magic.init();
  if (kDebugMode) {
    MagicDuskIntegration.install();
  }
  runApp(const MagicApplication());
}
''';

      final output = BufferedOutput();
      final exit = await DuskDoctorCommand()
          .handle(ArtisanContext.bare(MapInput(const {}), output));

      // INFO never fails.
      expect(exit, equals(0));
      expect(
        output.content,
        contains('Magic-stack detected, integration wired'),
      );
    });

    test(
        'INFO "vanilla Flutter detected" when main.dart has neither Magic.init '
        'nor MagicDuskIntegration.install', () async {
      DuskDoctorCommand.mainDartReader = (String path) => '''
import 'package:flutter/material.dart';
import 'package:fluttersdk_dusk/dusk.dart';

void main() {
  if (kDebugMode) {
    DuskPlugin.install();
  }
  runApp(const MyApp());
}
''';

      final output = BufferedOutput();
      final exit = await DuskDoctorCommand()
          .handle(ArtisanContext.bare(MapInput(const {}), output));

      expect(exit, equals(0));
      expect(output.content, contains('vanilla Flutter detected'));
    });

    test(
        'INFO "Magic detected but MagicDuskIntegration missing" when main.dart '
        'has Magic.init( but not the integration install call', () async {
      DuskDoctorCommand.mainDartReader = (String path) => '''
import 'package:magic/magic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Magic.init();
  runApp(const MagicApplication());
}
''';

      final output = BufferedOutput();
      final exit = await DuskDoctorCommand()
          .handle(ArtisanContext.bare(MapInput(const {}), output));

      expect(exit, equals(0));
      expect(
        output.content,
        contains(
          'Magic detected but MagicDuskIntegration missing — install via '
          'dusk:install',
        ),
      );
    });

    test('INFO "Skipped (lib/main.dart unreadable)" when main.dart is absent',
        () async {
      DuskDoctorCommand.mainDartReader = (String path) => null;

      final output = BufferedOutput();
      final exit = await DuskDoctorCommand()
          .handle(ArtisanContext.bare(MapInput(const {}), output));

      expect(exit, equals(0));
      expect(output.content, contains('Magic-init detection'));
      expect(output.content, contains('Skipped (lib/main.dart unreadable)'));
    });
  });

  // ---------------------------------------------------------------------------
  // Output composition
  // ---------------------------------------------------------------------------

  group('Output composition', () {
    test('all five check labels appear in the output, in declaration order',
        () async {
      final output = BufferedOutput();
      await DuskDoctorCommand()
          .handle(ArtisanContext.bare(MapInput(const {}), output));

      final String content = output.content;
      final int idx1 = content.indexOf('hot-restart staleness');
      final int idx2 = content.indexOf('DUSK_DISABLE');
      final int idx3 = content.indexOf('enrichers');
      final int idx4 = content.indexOf('Semantics tree');
      final int idx5 = content.indexOf('Magic-init detection');

      expect(idx1, greaterThanOrEqualTo(0));
      expect(idx2, greaterThan(idx1));
      expect(idx3, greaterThan(idx2));
      expect(idx4, greaterThan(idx3));
      expect(idx5, greaterThan(idx4));
    });

    test(
        'exit code is 0 when every check passes (defaults: empty enrichers '
        'flip to WARN, but WARN never fails)', () async {
      // With default seams (empty enrichers, no Chrome, no DUSK_DISABLE,
      // semantics on, no main.dart) the only ERROR-class check (#4) passes,
      // so exit code is 0 even with multiple WARN / INFO rows below.
      final output = BufferedOutput();
      final exit = await DuskDoctorCommand()
          .handle(ArtisanContext.bare(MapInput(const {}), output));

      expect(exit, equals(0));
    });

    test('exit code is non-zero when ERROR-class Check 4 fails', () async {
      DuskDoctorCommand.semanticsEnabledProbe = () => false;

      final output = BufferedOutput();
      final exit = await DuskDoctorCommand()
          .handle(ArtisanContext.bare(MapInput(const {}), output));

      expect(exit, isNot(equals(0)));
    });
  });
}
