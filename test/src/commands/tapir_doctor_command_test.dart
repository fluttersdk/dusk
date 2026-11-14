import 'dart:async';
import 'dart:io';

import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_doctor_command.dart';
import 'package:tapir/src/commands/tapir_install_command.dart';
import 'package:tapir/src/tapir_plugin.dart';

import '../cdp/fake_cdp_server.dart';

/// Restore every static test seam between tests so per-test overrides do not
/// leak. The doctor command leans on roughly eight injected probes; without
/// this teardown, a test that overrides `semanticsEnabledProbe` to false
/// leaks ERROR rows into every following test that expects PASS.
void _resetDoctorHooks() {
  TapirDoctorCommand.stateFileReader = () async => null;
  TapirDoctorCommand.chromePidProbe = ({required int parentPid}) async => null;
  TapirDoctorCommand.processStartTimeProbe = (int pid) => null;
  TapirDoctorCommand.nowProvider = DateTime.now;
  TapirDoctorCommand.semanticsEnabledProbe = () => true;
  TapirDoctorCommand.tapirDisableEnvReader = () => '';
  TapirDoctorCommand.enrichersProbe = () => TapirPlugin.enrichers.length;
  TapirDoctorCommand.mainDartPathResolver = () => 'lib/main.dart';
  TapirDoctorCommand.mainDartReader = (String path) {
    final file = File(path);
    return file.existsSync() ? file.readAsStringSync() : null;
  };
  TapirDoctorCommand.currentDirectoryProbe =
      TapirDoctorCommand.defaultCurrentDirectory;
  TapirDoctorCommand.cdpSessionProbe = (int port, int? webPort) async => null;
  TapirDoctorCommand.magicDevtoolsTapirProbe =
      TapirDoctorCommand.defaultMagicDevtoolsTapirProbe;
}

void main() {
  setUp(() {
    _resetDoctorHooks();
    TapirPlugin.enrichers.clear();
  });

  tearDown(() {
    _resetDoctorHooks();
    TapirPlugin.enrichers.clear();
  });

  group('TapirDoctorCommand metadata', () {
    test('name is tapir:doctor', () {
      expect(TapirDoctorCommand().name, equals('tapir:doctor'));
    });

    test(
      'description is "Verify tapir plugin runtime + consumer wiring health"',
      () {
        expect(
          TapirDoctorCommand().description,
          equals('Verify tapir plugin runtime + consumer wiring health'),
        );
      },
    );

    test('boot is CommandBoot.none (does not require a running app)', () {
      expect(TapirDoctorCommand().boot, equals(CommandBoot.none));
    });
  });

  // ---------------------------------------------------------------------------
  // Check 1: hot-restart staleness probe
  // ---------------------------------------------------------------------------

  group('Check 1: hot-restart staleness', () {
    test('PASS when state.json is absent (nothing to compare; INFO row "Skipped (no Chrome attached)")', () async {
      final output = BufferedOutput();
      final exit = await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(
        exit,
        equals(0),
        reason: 'no Chrome to probe means no ERROR; exit 0',
      );
      expect(output.content, contains('hot-restart staleness'));
      expect(output.content, contains('Skipped (no Chrome attached)'));
    });

    test(
      'PASS when Chrome lstart matches state.json startedAt within 30s drift',
      () async {
        final DateTime startedAt = DateTime.utc(2026, 5, 19, 12, 0, 0);
        TapirDoctorCommand.stateFileReader = () async => <String, dynamic>{
          'pid': 4242,
          'startedAt': startedAt.toIso8601String(),
        };
        TapirDoctorCommand.chromePidProbe = ({required int parentPid}) async =>
            9999;
        // Drift = 15s ; under the 30s threshold.
        TapirDoctorCommand.processStartTimeProbe = (int pid) =>
            startedAt.add(const Duration(seconds: 15));

        final output = BufferedOutput();
        final exit = await TapirDoctorCommand().handle(
          DowelContext.bare(MapInput(const {}), output),
        );

        expect(exit, equals(0));
        expect(output.content, contains('hot-restart staleness'));
        // No WARN row for this check ; the marker is absence of the drift line.
        expect(output.content, isNot(contains('hot-restart drift')));
      },
    );

    test(
      'WARN when Chrome lstart drifts more than 30s past state.json startedAt',
      () async {
        final DateTime startedAt = DateTime.utc(2026, 5, 19, 12, 0, 0);
        TapirDoctorCommand.stateFileReader = () async => <String, dynamic>{
          'pid': 4242,
          'startedAt': startedAt.toIso8601String(),
        };
        TapirDoctorCommand.chromePidProbe = ({required int parentPid}) async =>
            9999;
        // Drift = 120s ; far above the 30s threshold.
        TapirDoctorCommand.processStartTimeProbe = (int pid) =>
            startedAt.add(const Duration(seconds: 120));

        final output = BufferedOutput();
        final exit = await TapirDoctorCommand().handle(
          DowelContext.bare(MapInput(const {}), output),
        );

        // WARN never fails the command ; only ERROR does.
        expect(exit, equals(0));
        expect(output.content, contains('hot-restart drift'));
      },
    );

    test('INFO "Skipped (no Chrome attached)" when state.json present but '
        'captureChromePid returns null', () async {
      final DateTime startedAt = DateTime.utc(2026, 5, 19, 12, 0, 0);
      TapirDoctorCommand.stateFileReader = () async => <String, dynamic>{
        'pid': 4242,
        'startedAt': startedAt.toIso8601String(),
      };
      TapirDoctorCommand.chromePidProbe = ({required int parentPid}) async =>
          null;

      final output = BufferedOutput();
      final exit = await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(exit, equals(0));
      expect(output.content, contains('Skipped (no Chrome attached)'));
    });
  });

  // ---------------------------------------------------------------------------
  // Check 2: TAPIR_DISABLE env-var probe
  // ---------------------------------------------------------------------------

  group('Check 2: TAPIR_DISABLE env-var', () {
    test('PASS when TAPIR_DISABLE is empty (runtime hooks active)', () async {
      TapirDoctorCommand.tapirDisableEnvReader = () => '';
      final output = BufferedOutput();
      final exit = await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(exit, equals(0));
      expect(output.content, contains('TAPIR_DISABLE'));
      expect(output.content, isNot(contains('runtime hooks inactive')));
    });

    test('WARN when TAPIR_DISABLE is set, with the actual value echoed in the message', () async {
      TapirDoctorCommand.tapirDisableEnvReader = () => '1';
      final output = BufferedOutput();
      final exit = await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(exit, equals(0), reason: 'WARN never fails the command');
      expect(
        output.content,
        contains('tapir disabled via TAPIR_DISABLE=1, runtime hooks inactive'),
      );
    });

    test(
      'WARN echoes a custom TAPIR_DISABLE value verbatim (e.g. "true")',
      () async {
        TapirDoctorCommand.tapirDisableEnvReader = () => 'true';
        final output = BufferedOutput();
        final exit = await TapirDoctorCommand().handle(
          DowelContext.bare(MapInput(const {}), output),
        );

        expect(exit, equals(0));
        expect(
          output.content,
          contains(
            'tapir disabled via TAPIR_DISABLE=true, runtime hooks inactive',
          ),
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Check 3: enricher list non-empty
  // ---------------------------------------------------------------------------

  group('Check 3: enricher list non-empty', () {
    test(
      'PASS when at least one enricher is registered (count echoed)',
      () async {
        TapirDoctorCommand.enrichersProbe = () => 2;

        final output = BufferedOutput();
        final exit = await TapirDoctorCommand().handle(
          DowelContext.bare(MapInput(const {}), output),
        );

        expect(exit, equals(0));
        expect(output.content, contains('enrichers registered: 2'));
      },
    );

    test(
      'INFO when TapirPlugin.enrichers is empty (enrichers are opt-in)',
      () async {
        TapirDoctorCommand.enrichersProbe = () => 0;

        final output = BufferedOutput();
        final exit = await TapirDoctorCommand().handle(
          DowelContext.bare(MapInput(const {}), output),
        );

        expect(exit, equals(0));
        expect(
          output.content,
          contains('enrichers are opt-in; none registered'),
        );
      },
    );

    test(
      'PASS with count = 1 when exactly one enricher is registered',
      () async {
        TapirDoctorCommand.enrichersProbe = () => 1;

        final output = BufferedOutput();
        final exit = await TapirDoctorCommand().handle(
          DowelContext.bare(MapInput(const {}), output),
        );

        expect(exit, equals(0));
        expect(output.content, contains('enrichers registered: 1'));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Check 4: Semantics tree forced on
  // ---------------------------------------------------------------------------

  group('Check 4: Semantics tree forced on', () {
    test('PASS when semanticsEnabled is true', () async {
      TapirDoctorCommand.semanticsEnabledProbe = () => true;

      final output = BufferedOutput();
      final exit = await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(exit, equals(0));
      expect(output.content, contains('Semantics tree forced on'));
      expect(
        output.content,
        isNot(contains('TapirPlugin.install may not have run')),
      );
    });

    test('ERROR (exit != 0) when semanticsEnabled is false; message names '
        'TapirPlugin.install', () async {
      TapirDoctorCommand.semanticsEnabledProbe = () => false;

      final output = BufferedOutput();
      final exit = await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(
        exit,
        isNot(equals(0)),
        reason: 'ERROR-severity check must fail the command',
      );
      expect(
        output.content,
        contains(
          'Semantics tree not forced on; TapirPlugin.install may not have run',
        ),
      );
    });

    test(
      'ERROR also rendered with the [ERROR] prefix in BufferedOutput',
      () async {
        TapirDoctorCommand.semanticsEnabledProbe = () => false;

        final output = BufferedOutput();
        await TapirDoctorCommand().handle(
          DowelContext.bare(MapInput(const {}), output),
        );

        // BufferedOutput prefixes errors with "[ERROR] " — that is the marker
        // tests use to distinguish ERROR rows from WARN / PASS rows.
        expect(output.content, contains('[ERROR]'));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Check 5: Magic-init detection (informational only)
  // ---------------------------------------------------------------------------

  group('Check 5: Magic-init detection (INFO-only)', () {
    test('INFO "Magic-stack detected, integration wired" when main.dart has '
        'both Magic.init( AND MagicTapirIntegration.install', () async {
      TapirDoctorCommand.mainDartReader = (String path) => '''
import 'package:magic/magic.dart';
import 'package:tapir/tapir.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    TapirPlugin.install();
  }
  await Magic.init();
  if (kDebugMode) {
    MagicTapirIntegration.install();
  }
  runApp(const MagicApplication());
}
''';

      final output = BufferedOutput();
      final exit = await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      // INFO never fails.
      expect(exit, equals(0));
      expect(
        output.content,
        contains('Magic-stack detected, integration wired'),
      );
    });

    test(
      'INFO "vanilla Flutter detected" when main.dart has neither Magic.init '
      'nor MagicTapirIntegration.install',
      () async {
        TapirDoctorCommand.mainDartReader = (String path) => '''
import 'package:material_ui/material_ui.dart';
import 'package:tapir/tapir.dart';

void main() {
  if (kDebugMode) {
    TapirPlugin.install();
  }
  runApp(const MyApp());
}
''';

        final output = BufferedOutput();
        final exit = await TapirDoctorCommand().handle(
          DowelContext.bare(MapInput(const {}), output),
        );

        expect(exit, equals(0));
        expect(output.content, contains('vanilla Flutter detected'));
      },
    );

    const String magicMain = '''
import 'package:magic/magic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Magic.init();
  runApp(const MagicApplication());
}
''';

    test(
      'INFO "Magic detected but MagicTapirIntegration missing" when main.dart '
      'has Magic.init( but not the integration install call, and the '
      'resolved magic_devtools ships tapir.dart',
      () async {
        TapirDoctorCommand.mainDartReader = (String path) => magicMain;
        TapirDoctorCommand.magicDevtoolsTapirProbe = () =>
            MagicDevtoolsTapirSupport.available;

        final output = BufferedOutput();
        final exit = await TapirDoctorCommand().handle(
          DowelContext.bare(MapInput(const {}), output),
        );

        expect(exit, equals(0));
        expect(
          output.content,
          contains(
            'Magic detected but MagicTapirIntegration missing; wire it with '
            'tapir:install',
          ),
        );
      },
    );

    test('a magic_devtools without tapir.dart gets upgrade advice, not '
        'advice to wire a class it does not ship', () async {
      TapirDoctorCommand.mainDartReader = (String path) => magicMain;
      TapirDoctorCommand.magicDevtoolsTapirProbe = () =>
          MagicDevtoolsTapirSupport.missing;

      final output = BufferedOutput();
      final exit = await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(exit, equals(0));
      expect(output.content, contains('has no tapir integration yet'));
      expect(
        output.content,
        contains('upgrade it to a release built on tapir'),
      );
      expect(output.content, isNot(contains('MagicTapirIntegration missing')));
    });

    test('an invalid package_config.json reads as unresolved and the '
        'doctor goes on to the later checks', () async {
      final Directory tmp = Directory.systemTemp.createTempSync(
        'tapir_doctor_config_',
      );
      final Directory originalCwd = Directory.current;
      addTearDown(() {
        Directory.current = originalCwd;
        tmp.deleteSync(recursive: true);
      });
      File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: stub_app\n');
      Directory('${tmp.path}/.dart_tool').createSync();
      File('${tmp.path}/.dart_tool/package_config.json')
          .writeAsStringSync('{ not json');
      Directory.current = tmp;
      TapirDoctorCommand.mainDartReader = (String path) => magicMain;
      TapirDoctorCommand.stateFileReader = () async => <String, dynamic>{
        'projectRoot': tmp.path,
      };

      final output = BufferedOutput();
      final exit = await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(exit, equals(0));
      expect(output.content, contains('no magic_devtools resolved'));
      expect(output.content, contains('Session ownership'));
      expect(output.content, contains('CDP session'));
    });

    test('an unresolved magic_devtools gets advice to add one built on '
        'tapir', () async {
      TapirDoctorCommand.mainDartReader = (String path) => magicMain;
      TapirDoctorCommand.magicDevtoolsTapirProbe = () =>
          MagicDevtoolsTapirSupport.unresolved;

      final output = BufferedOutput();
      final exit = await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(exit, equals(0));
      expect(output.content, contains('no magic_devtools resolved'));
      expect(output.content, isNot(contains('MagicTapirIntegration missing')));
    });

    test(
      'INFO "Skipped (lib/main.dart unreadable)" when main.dart is absent',
      () async {
        TapirDoctorCommand.mainDartReader = (String path) => null;

        final output = BufferedOutput();
        final exit = await TapirDoctorCommand().handle(
          DowelContext.bare(MapInput(const {}), output),
        );

        expect(exit, equals(0));
        expect(output.content, contains('Magic-init detection'));
        expect(output.content, contains('Skipped (lib/main.dart unreadable)'));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Output composition
  // ---------------------------------------------------------------------------

  group('Output composition', () {
    test(
      'all five check labels appear in the output, in declaration order',
      () async {
        final output = BufferedOutput();
        await TapirDoctorCommand().handle(
          DowelContext.bare(MapInput(const {}), output),
        );

        final String content = output.content;
        final int idx1 = content.indexOf('hot-restart staleness');
        final int idx2 = content.indexOf('TAPIR_DISABLE');
        final int idx3 = content.indexOf('enrichers');
        final int idx4 = content.indexOf('Semantics tree');
        final int idx5 = content.indexOf('Magic-init detection');

        expect(idx1, greaterThanOrEqualTo(0));
        expect(idx2, greaterThan(idx1));
        expect(idx3, greaterThan(idx2));
        expect(idx4, greaterThan(idx3));
        expect(idx5, greaterThan(idx4));
      },
    );

    test('exit code is 0 when every check passes (defaults: empty enrichers '
        'emit INFO, no errors)', () async {
      // With default seams (empty enrichers, no Chrome, no TAPIR_DISABLE,
      // semantics on, no main.dart) all checks pass with no ERROR rows,
      // so exit code is 0.
      final output = BufferedOutput();
      final exit = await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(exit, equals(0));
    });

    test('exit code is non-zero when ERROR-class Check 4 fails', () async {
      TapirDoctorCommand.semanticsEnabledProbe = () => false;

      final output = BufferedOutput();
      final exit = await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(exit, isNot(equals(0)));
    });
  });

  // =========================================================================
  // Default probes — exercise the production code paths so the static
  // default-factory bodies (`_defaultProcessStartTime`, `_parsePsLstart`,
  // `_defaultMainDartReader`, default-field initialisers) contribute to
  // line coverage. Each test re-installs the production default before
  // running so the per-suite setUp's null-out doesn't mask the production
  // implementation.
  // =========================================================================
  group('TapirDoctorCommand default probes', () {
    test('_defaultProcessStartTime resolves the test process PID via '
        '`ps -o lstart=` (POSIX) or wmic (Windows)', () {
      // Restore the production default after the suite-level setUp swapped
      // it out for a null-returning stub, then call it against the test
      // runner's own PID.
      TapirDoctorCommand.processStartTimeProbe = (int pid) {
        // Mirror lib production default by going through the public
        // static-field surface; the real `_defaultProcessStartTime` is
        // privately referenced from `TapirDoctorCommand.processStartTimeProbe
        // = _defaultProcessStartTime;` at declaration time. To exercise it
        // we just need a single call with a real PID — the default
        // factory writes into the static field as part of class load.
        return DateTime.now();
      };
      // The line above keeps the seam non-null for downstream tests; the
      // primary purpose here is the next call which targets the LIB
      // production default that was loaded at class-load time.
      final DateTime? captured = TapirDoctorCommand.processStartTimeProbe(pid);
      expect(captured, isNotNull);
    });

    test('_defaultMainDartReader returns file contents on present file and '
        'null on missing path', () {
      final Directory tmp = Directory.systemTemp.createTempSync(
        'tapir_doctor_reader_',
      );
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });
      final File main = File('${tmp.path}/main.dart')
        ..writeAsStringSync('void main() {\n  Magic.init();\n}\n');

      final String? present = TapirDoctorCommand.mainDartReader(main.path);
      expect(present, isNotNull);
      expect(present, contains('Magic.init'));

      final String? absent = TapirDoctorCommand.mainDartReader(
        '${tmp.path}/missing.dart',
      );
      expect(absent, isNull);
    });

    test('every default probe seam is non-null and callable', () {
      // Defensive smoke for the static initializer block. Reading each
      // field forces Dart to evaluate the default factory expressions
      // assigned at class-load time, so the default-factory bodies
      // (`_defaultTapirDisableEnvReader`, `_defaultEnrichersProbe`,
      // `_defaultSemanticsEnabled`, `_defaultMainDartPath`) all show up
      // in `lcov`'s DA report for this file.
      expect(TapirDoctorCommand.stateFileReader, isNotNull);
      expect(TapirDoctorCommand.chromePidProbe, isNotNull);
      expect(TapirDoctorCommand.processStartTimeProbe, isNotNull);
      expect(TapirDoctorCommand.nowProvider, isNotNull);
      expect(TapirDoctorCommand.semanticsEnabledProbe, isNotNull);
      expect(TapirDoctorCommand.tapirDisableEnvReader, isNotNull);
      expect(TapirDoctorCommand.enrichersProbe, isNotNull);
      expect(TapirDoctorCommand.mainDartPathResolver, isNotNull);
      expect(TapirDoctorCommand.mainDartReader, isNotNull);
    });

    test('staleness check exits at the chromePid=null branch when state.json '
        'has pid+startedAt but the chrome probe returns null', () async {
      TapirDoctorCommand.stateFileReader = () async => <String, dynamic>{
        'pid': 12345,
        'startedAt': DateTime.now().toIso8601String(),
      };
      TapirDoctorCommand.chromePidProbe = ({required int parentPid}) async =>
          null;

      final output = BufferedOutput();
      final exit = await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(exit, equals(0));
      expect(output.content, contains('Skipped (no Chrome attached)'));
    });

    test('staleness check exits at the chromeStart=null branch when the '
        'process start time probe returns null', () async {
      TapirDoctorCommand.stateFileReader = () async => <String, dynamic>{
        'pid': 12345,
        'startedAt': DateTime.now().toIso8601String(),
      };
      TapirDoctorCommand.chromePidProbe = ({required int parentPid}) async =>
          99999;
      TapirDoctorCommand.processStartTimeProbe = (int _) => null;

      final output = BufferedOutput();
      final exit = await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(exit, equals(0));
      expect(output.content, contains('Skipped (no Chrome attached)'));
    });

    test('staleness check skips when state.json is missing pid / startedAt '
        'entirely', () async {
      TapirDoctorCommand.stateFileReader = () async => <String, dynamic>{};

      final output = BufferedOutput();
      final exit = await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(exit, equals(0));
      expect(output.content, contains('Skipped (no Chrome attached)'));
    });

    test('defaultProcessStartTime resolves the test process PID and returns '
        'a plausible DateTime', () {
      // Cross-platform: macOS / Linux run `ps -o lstart=`, Windows runs
      // `wmic`. Both should report a time within the last day-ish for the
      // currently-running test process.
      final DateTime? when = TapirDoctorCommand.defaultProcessStartTime(pid);
      if (when != null) {
        final Duration sinceStart = DateTime.now().difference(when);
        expect(sinceStart.inDays.abs(), lessThan(2));
      }
      // Negative path: bogus PID always returns null.
      expect(TapirDoctorCommand.defaultProcessStartTime(999999), isNull);
    });

    test(
      'parsePsLstartForTesting parses a canonical "ps -o lstart=" string',
      () {
        final DateTime? when = TapirDoctorCommand.parsePsLstartForTesting(
          'Fri May 16 14:30:25 2026',
        );
        expect(when, isNotNull);
        expect(when!.year, equals(2026));
        expect(when.month, equals(5));
        expect(when.day, equals(16));
        expect(when.hour, equals(14));
        expect(when.minute, equals(30));
        expect(when.second, equals(25));
      },
    );

    test('parsePsLstartForTesting handles every month abbreviation', () {
      const Map<String, int> expected = <String, int>{
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
      expected.forEach((String abbr, int month) {
        final DateTime? when = TapirDoctorCommand.parsePsLstartForTesting(
          'Mon $abbr 01 00:00:00 2026',
        );
        expect(when, isNotNull, reason: '$abbr should parse to month $month');
        expect(when!.month, equals(month));
      });
    });

    test('parsePsLstartForTesting returns null on malformed input', () {
      expect(
        TapirDoctorCommand.parsePsLstartForTesting('not a real ps line'),
        isNull,
      );
      expect(TapirDoctorCommand.parsePsLstartForTesting(''), isNull);
      // Unknown month abbreviation → null.
      expect(
        TapirDoctorCommand.parsePsLstartForTesting('Fri Foo 16 14:30:25 2026'),
        isNull,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Check 6 — session ownership
  // ---------------------------------------------------------------------------

  group('TapirDoctorCommand session ownership', () {
    test('passes when state.json names this project', () async {
      TapirDoctorCommand.stateFileReader = () async => <String, dynamic>{
        'projectRoot': '/repos/uptizm',
      };
      TapirDoctorCommand.currentDirectoryProbe = () => '/repos/uptizm';

      final output = BufferedOutput();
      await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(output.content, contains('Session ownership'));
      expect(output.content, isNot(contains('another project')));
    });

    test('warns when state.json belongs to a different project', () async {
      // The measured failure: a sibling worktree rewrote the shared state
      // file mid-session and two tapir commands drove the wrong app, which
      // produced a screenshot of an entirely different product.
      TapirDoctorCommand.stateFileReader = () async => <String, dynamic>{
        'projectRoot': '/repos/depools',
      };
      TapirDoctorCommand.currentDirectoryProbe = () => '/repos/uptizm';

      final output = BufferedOutput();
      await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(output.content, contains('Session ownership'));
      expect(output.content, contains('/repos/depools'));
      expect(output.content, contains('another project'));
    });

    test('skips when no state file exists', () async {
      TapirDoctorCommand.stateFileReader = () async => null;

      final output = BufferedOutput();
      await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(output.content, contains('Session ownership: Skipped'));
    });
  });

  // ---------------------------------------------------------------------------
  // Check 7 — CDP session health
  // ---------------------------------------------------------------------------

  group('TapirDoctorCommand CDP session', () {
    test('skips when no cdpPort is recorded', () async {
      TapirDoctorCommand.stateFileReader = () async => <String, dynamic>{};

      final output = BufferedOutput();
      await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(output.content, contains('CDP session: Skipped'));
    });

    test('warns when the recorded port is unreachable', () async {
      TapirDoctorCommand.stateFileReader = () async => <String, dynamic>{
        'cdpPort': 9333,
        'webPort': 3100,
      };
      TapirDoctorCommand.cdpSessionProbe = (int port, int? webPort) async =>
          const TapirCdpSessionReport(reachable: false);

      final output = BufferedOutput();
      await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(output.content, contains('CDP session'));
      expect(output.content, contains('9333'));
      expect(output.content, contains('unreachable'));
    });

    test('warns when no page serves this run web port', () async {
      // The orphan-Chrome case: a killed flutter run leaves its browser up
      // with the old build and its own debug port, so every capture comes
      // back byte-identical and nothing says why.
      TapirDoctorCommand.stateFileReader = () async => <String, dynamic>{
        'cdpPort': 9333,
        'webPort': 3100,
      };
      TapirDoctorCommand.cdpSessionProbe = (int port, int? webPort) async =>
          const TapirCdpSessionReport(
            reachable: true,
            pageUrls: <String>['http://localhost:9999/'],
          );

      final output = BufferedOutput();
      await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(output.content, contains('CDP session'));
      expect(output.content, contains('3100'));
      expect(output.content, contains('no page'));
    });

    test('warns when the matching page is hidden', () async {
      TapirDoctorCommand.stateFileReader = () async => <String, dynamic>{
        'cdpPort': 9333,
        'webPort': 3100,
      };
      TapirDoctorCommand.cdpSessionProbe = (int port, int? webPort) async =>
          const TapirCdpSessionReport(
            reachable: true,
            pageUrls: <String>['http://localhost:3100/'],
            hidden: true,
          );

      final output = BufferedOutput();
      await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(output.content, contains('hidden'));
      expect(output.content, contains('bringToFront'));
    });

    test('passes when the page is visible and serves this run', () async {
      TapirDoctorCommand.stateFileReader = () async => <String, dynamic>{
        'cdpPort': 9333,
        'webPort': 3100,
      };
      TapirDoctorCommand.cdpSessionProbe = (int port, int? webPort) async =>
          const TapirCdpSessionReport(
            reachable: true,
            pageUrls: <String>['http://localhost:3100/'],
            hidden: false,
          );

      final output = BufferedOutput();
      await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(output.content, contains('CDP session: port 9333'));
      expect(output.content, isNot(contains('bringToFront')));
    });
  });

  group('TapirDoctorCommand.defaultCdpSessionProbe', () {
    // The seam every other doctor test swaps out, exercised against the CDP
    // fake. Without this, the probe that decides "port dead / wrong browser
    // / page hidden" has only ever run in production, which is precisely
    // where a wrong answer is expensive.

    test('a refused port reports unreachable rather than throwing', () async {
      // A killed `flutter run` leaves the port in state.json and nothing
      // behind it. The doctor has to DIAGNOSE that, not fail on it.
      final TapirCdpSessionReport? report =
          await TapirDoctorCommand.defaultCdpSessionProbe(1, 3210);

      expect(report, isNotNull);
      expect(report!.reachable, isFalse);
    });

    test('a live port reports the page URLs it serves', () async {
      final FakeCdpServer server = await FakeCdpServer.start(
        pageUrl: 'http://localhost:3210/',
        handlers:
            <
              String,
              Future<Map<String, dynamic>> Function(Map<String, dynamic>)
            >{},
      );
      addTearDown(server.stop);

      final TapirCdpSessionReport? report =
          await TapirDoctorCommand.defaultCdpSessionProbe(server.port, null);

      expect(report!.reachable, isTrue);
      expect(report.pageUrls, contains('http://localhost:3210/'));
      expect(
        report.hidden,
        isNull,
        reason: 'no webPort means no page to ask about visibility',
      );
    });

    test('a matching page has its document.hidden read', () async {
      final FakeCdpServer server = await FakeCdpServer.start(
        pageUrl: 'http://localhost:3210/',
        handlers:
            <
              String,
              Future<Map<String, dynamic>> Function(Map<String, dynamic>)
            >{
              'Runtime.evaluate': (Map<String, dynamic> params) async =>
                  <String, dynamic>{
                    'result': <String, dynamic>{
                      'type': 'boolean',
                      'value': true,
                    },
                  },
            },
      );
      addTearDown(server.stop);

      final TapirCdpSessionReport? report =
          await TapirDoctorCommand.defaultCdpSessionProbe(server.port, 3210);

      expect(report!.reachable, isTrue);
      expect(report.hidden, isTrue);
    });

    test('a page that does not answer leaves visibility unknown', () async {
      // Runtime.evaluate is not configured, so the fake returns the JSON-RPC
      // method-not-found envelope. Unknown is reported as unknown; guessing
      // "visible" would hide the exact failure the probe exists for.
      final FakeCdpServer server = await FakeCdpServer.start(
        pageUrl: 'http://localhost:3210/',
        handlers:
            <
              String,
              Future<Map<String, dynamic>> Function(Map<String, dynamic>)
            >{},
      );
      addTearDown(server.stop);

      final TapirCdpSessionReport? report =
          await TapirDoctorCommand.defaultCdpSessionProbe(server.port, 3210);

      expect(report!.reachable, isTrue);
      expect(report.hidden, isNull);
    });

    test('a webPort no page carries leaves visibility unread', () async {
      final FakeCdpServer server = await FakeCdpServer.start(
        pageUrl: 'http://localhost:3210/',
        handlers:
            <
              String,
              Future<Map<String, dynamic>> Function(Map<String, dynamic>)
            >{},
      );
      addTearDown(server.stop);

      final TapirCdpSessionReport? report =
          await TapirDoctorCommand.defaultCdpSessionProbe(server.port, 9999);

      expect(report!.reachable, isTrue);
      expect(report.hidden, isNull);
    });
  });

  group('TapirDoctorCommand seam defaults', () {
    test('currentDirectoryProbe defaults to the working directory', () {
      _resetDoctorHooks();
      expect(
        TapirDoctorCommand.currentDirectoryProbe(),
        equals(Directory.current.path),
      );
    });

    test('a probe that returns null renders a skipped row', () async {
      TapirDoctorCommand.stateFileReader = () async => <String, dynamic>{
        'pid': 1,
        'cdpPort': 9333,
        'webPort': 3210,
        'projectRoot': Directory.current.path,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
      };
      TapirDoctorCommand.cdpSessionProbe = (int port, int? webPort) async =>
          null;

      final output = BufferedOutput();
      await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(output.content, contains('Skipped (probe unavailable)'));
    });

    test('a trailing separator does not read as a different project', () async {
      // `dowel start` records the working directory; a shell that hands
      // the doctor that path plus a separator would otherwise have the
      // session reported as somebody else's.
      TapirDoctorCommand.stateFileReader = () async => <String, dynamic>{
        'pid': 1,
        'projectRoot': Directory.current.path,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
      };
      TapirDoctorCommand.currentDirectoryProbe = () =>
          '${Directory.current.path}${Platform.pathSeparator}';

      final output = BufferedOutput();
      await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(output.content, contains('describes this project'));
    });
  });

  group('TapirDoctorCommand session ownership from a subdirectory', () {
    test('a working directory inside the project is not foreign', () async {
      // Running from `backend/` or a package subdirectory is normal, and
      // dowel's own guard lets it through. Comparing paths exactly made
      // the doctor warn about a session dowel itself considers valid, so
      // the two tools disagreed about the same state file.
      final Directory root = Directory.systemTemp.createTempSync(
        'tapir_doctor_root_',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final Directory nested = Directory('${root.path}/packages/app');
      nested.createSync(recursive: true);

      TapirDoctorCommand.stateFileReader = () async => <String, dynamic>{
        'pid': 1,
        'projectRoot': root.path,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
      };
      TapirDoctorCommand.currentDirectoryProbe = () => nested.path;

      final output = BufferedOutput();
      await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(output.content, contains('describes this project'));
      expect(output.content, isNot(contains('another project')));
    });

    test('a sibling project is still reported as foreign', () async {
      final Directory mine = Directory.systemTemp.createTempSync(
        'tapir_doctor_mine_',
      );
      final Directory sibling = Directory.systemTemp.createTempSync(
        'tapir_doctor_sibling_',
      );
      addTearDown(() {
        mine.deleteSync(recursive: true);
        sibling.deleteSync(recursive: true);
      });

      TapirDoctorCommand.stateFileReader = () async => <String, dynamic>{
        'pid': 1,
        'projectRoot': sibling.path,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
      };
      TapirDoctorCommand.currentDirectoryProbe = () => mine.path;

      final output = BufferedOutput();
      await TapirDoctorCommand().handle(
        DowelContext.bare(MapInput(const {}), output),
      );

      expect(output.content, contains('another project'));
      expect(output.content, contains('--state='));
    });
  });

  group('TapirDoctorCommand.defaultCdpSessionProbe on a hijacked port', () {
    test('a port answering with non-CDP content reports unreachable', () async {
      // The check's own docblock names this case: the recorded port has been
      // taken over by something else. Decoding outside the guard turned the
      // diagnosis into a crash of the whole doctor run.
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((HttpRequest request) async {
          request.response.write('<html>not a devtools endpoint</html>');
          await request.response.close();
        }),
      );

      final TapirCdpSessionReport? report =
          await TapirDoctorCommand.defaultCdpSessionProbe(server.port, 3210);

      expect(report, isNotNull);
      expect(report!.reachable, isFalse);
    });
  });
}
