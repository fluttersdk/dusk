import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_perf_campaign_command.dart';
import 'package:fluttersdk_dusk/src/commands/dusk_perf_run_command.dart';
import 'package:fluttersdk_dusk/src/commands/json_output.dart';
import 'package:fluttersdk_dusk/src/perf/perf_run_driver.dart';
import 'package:fluttersdk_dusk/src/perf/scenario.dart';

/// A secret with both a quote and a dollar sign, so a redaction that masks
/// only the raw form (or only the JSON form) is caught.
const String _secret = r'ab"c$d';

/// The form [_secret] takes inside a JSON string.
const String _secretInJson = r'ab\"c$d';

/// The environment every campaign loads against: the secret the scenarios
/// read through `${env.DEMO_PASSWORD}`.
const Map<String, String> _env = <String, String>{
  'DEMO_PASSWORD': _secret,
  'HOME': '/home/perf',
};

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// One process the command ran.
typedef _Run = ({
  String executable,
  List<String> arguments,
  String workingDirectory,
  Map<String, String> environment,
});

/// Answers a process run: exit code, stdout, stderr.
typedef _RunHandler = (int, String, String) Function(
  String executable,
  List<String> arguments,
);

/// Answers `dusk:perf_run`: the exit code, after writing to [output].
typedef _PerfRunHandler = Future<int> Function(
  Map<String, dynamic> options,
  ArtisanOutput output,
);

/// Records everything the campaign asked of its host, in one ordered log.
final class _FakeHost implements PerfCampaignHost {
  _FakeHost({
    this.onRun,
    this.onPerfRun,
    this.startCode = 0,
    this.bootMisses = 0,
    this.lingering = false,
  });

  final _RunHandler? onRun;
  final _PerfRunHandler? onPerfRun;

  /// What `start` answers; non-zero records no session.
  int startCode;

  /// Written to the start output, as artisan's start prints its own lines.
  String startOutput = 'flutter run pid=1';

  /// How many `ext.dusk.boot_id` reads throw after each start.
  final int bootMisses;

  /// Whether a stopped app keeps its pid alive and its ports held for one
  /// more read, the race between artisan's SIGTERM and the next start.
  final bool lingering;

  /// The session the next `readSession` answers.
  Map<String, dynamic>? session;

  /// The session log a failed start leaves.
  String? sessionLog;

  /// What `ext.dusk.exceptions` lists to a setup failure's diagnostics.
  List<Map<String, dynamic>> exceptions = <Map<String, dynamic>>[];

  /// Every event, in order: `run <exe> <args>`, `stop`, `start`,
  /// `alive:<pid>=<bool>`, `free:<port>=<bool>`, `pause`, `connect`,
  /// `boot:miss`, `boot:ok`, `driver open`, `driver <method>`,
  /// `perf_run <scenario>`, `driver close`, `close`.
  final List<String> events = <String>[];
  final List<_Run> runs = <_Run>[];
  final List<Map<String, dynamic>> starts = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> perfRuns = <Map<String, dynamic>>[];

  /// Every driver an attempt opened, and the one each perf_run was handed.
  final List<PerfRunDriver> openedDrivers = <PerfRunDriver>[];
  final List<PerfRunDriver> perfRunDrivers = <PerfRunDriver>[];

  /// Reads left for which a pid still answers alive, by pid.
  final Map<int, int> aliveReads = <int, int>{};

  /// Reads left for which a port still answers held, by port.
  final Map<int, int> busyReads = <int, int>{};

  int _pid = 100;

  List<String> get commandLines => <String>[
        for (final _Run run in runs)
          <String>[run.executable, ...run.arguments].join(' '),
      ];

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    required Map<String, String> environment,
  }) async {
    runs.add((
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    ));
    events.add('run ${<String>[executable, ...arguments].join(' ')}');
    final (int code, String out, String err) =
        onRun?.call(executable, arguments) ?? (0, '', '');
    return ProcessResult(0, code, out, err);
  }

  @override
  Future<Map<String, dynamic>?> readSession() async => session;

  @override
  Future<String?> readSessionLog() async => sessionLog;

  @override
  Future<int> stop(ArtisanOutput output) async {
    events.add('stop');
    final Map<String, dynamic>? previous = session;
    if (lingering && previous != null) {
      aliveReads[previous['pid'] as int] = 1;
      busyReads[previous['webPort'] as int] = 1;
    }
    session = null;
    return 0;
  }

  @override
  Future<int> start(Map<String, dynamic> options, ArtisanOutput output) async {
    events.add('start');
    starts.add(options);
    output.writeln(startOutput);
    if (startCode != 0) return startCode;
    final Object? cdp = options['cdp-port'];
    session = <String, dynamic>{
      'pid': _pid++,
      'vmServiceUri': 'ws://127.0.0.1:8181/token/ws',
      'webPort': 3100,
      'vmServicePort': 8181,
      'cdpPort': cdp is String ? int.parse(cdp) : null,
      'device': options['device'],
    };
    return 0;
  }

  @override
  bool isAlive(int pid) {
    final int left = aliveReads[pid] ?? 0;
    if (left > 0) aliveReads[pid] = left - 1;
    events.add('alive:$pid=${left > 0}');
    return left > 0;
  }

  @override
  Future<bool> isPortFree(int port) async {
    final int left = busyReads[port] ?? 0;
    if (left > 0) busyReads[port] = left - 1;
    events.add('free:$port=${left == 0}');
    return left == 0;
  }

  @override
  Future<void> pause(Duration duration) async => events.add('pause');

  @override
  Future<PerfCampaignApp> connect(String vmServiceUri) async {
    events.add('connect');
    return _FakeApp(this);
  }
}

/// The app one start connected to.
final class _FakeApp implements PerfCampaignApp {
  _FakeApp(this.host) : _misses = host.bootMisses;

  final _FakeHost host;
  int _misses;

  @override
  Future<String> bootId() async {
    if (_misses > 0) {
      _misses--;
      host.events.add('boot:miss');
      throw StateError('no isolate yet');
    }
    host.events.add('boot:ok');
    return 'boot-1';
  }

  @override
  Future<(PerfRunDriver, PerfRunEnvironment)> driver(
    PerfPlatform platform,
  ) async {
    host.events.add('driver open');
    final _FakeDriver driver = _FakeDriver(host);
    host.openedDrivers.add(driver);
    return (driver, PerfRunEnvironment(platform: platform));
  }

  @override
  Future<int> perfRun(
    Map<String, dynamic> options,
    ArtisanOutput output, {
    required PerfRunDriver driver,
    required PerfRunEnvironment environment,
  }) async {
    host.perfRuns.add(options);
    host.perfRunDrivers.add(driver);
    host.events.add('perf_run ${_stem(options['scenario'] as String)}');
    final int code = await host.onPerfRun?.call(options, output) ?? 0;
    // A perf_run that exits 0 has written its run file; one a handler wrote
    // itself is left as it is.
    final File runFile = _runFileOf(options);
    if (code == 0 && !runFile.existsSync()) {
      runFile
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode(<String, Object?>{
            'scenario': <String, Object?>{'name': _nameOf(options)},
          }),
        );
    }
    return code;
  }

  @override
  Future<void> close() async => host.events.add('close');
}

/// A driver whose Router is mounted and whose network is always idle.
final class _FakeDriver implements PerfRunDriver {
  _FakeDriver(this.host);

  final _FakeHost host;

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, String> params = const <String, String>{},
  ]) async {
    host.events.add('driver $method');
    return switch (method) {
      'ext.dusk.get_routes' => <String, dynamic>{'uri': '/'},
      'ext.dusk.wait_for_network_idle' => <String, dynamic>{'matched': true},
      'ext.dusk.exceptions' => <String, dynamic>{
          'exceptions': host.exceptions,
        },
      _ => <String, dynamic>{},
    };
  }

  @override
  Future<Map<String, dynamic>> cdp(
    String method, [
    Map<String, dynamic> params = const <String, dynamic>{},
  ]) async =>
      <String, dynamic>{};

  @override
  Future<void> restart() async {}

  @override
  Future<void> pause(Duration duration) async {}

  @override
  Future<void> close() async => host.events.add('driver close');
}

/// Thrown by a stubbed process starter once artisan's start has read every
/// option and built its argv, which is as far as a unit test may let it go.
final class _Reached implements Exception {
  _Reached(this.arguments);

  final List<String> arguments;
}

String _stem(String path) =>
    path.split('/').last.replaceFirst(RegExp(r'\.yaml$'), '');

/// The scenario name perf_run writes under: every fixture names a scenario
/// after its file, and a variant appends its key.
String _nameOf(Map<String, dynamic> options) {
  final Object? variant = options['variant'];
  final String stem = _stem(options['scenario'] as String);
  return variant == null ? stem : '$stem-$variant';
}

/// `<out>/<scenario>-<label>.json`, the run file perf_run writes.
File _runFileOf(Map<String, dynamic> options) => File(
      '${options['out']}/${_nameOf(options)}-${options['label']}.json',
    ).absolute;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// A scenario whose one step fills the secret, so the campaign's redactor
/// holds it.
String _scenario(String name, List<String> platforms) => '''
name: $name
platforms: [${platforms.join(', ')}]
steps:
  - fill: {target: {label: Password}, text: "\${env.DEMO_PASSWORD}"}
''';

void main() {
  late Directory dir;
  late Directory previousCwd;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dusk_perf_campaign_');
    previousCwd = Directory.current;
    Directory.current = dir;
  });

  tearDown(() {
    Directory.current = previousCwd;
    dir.deleteSync(recursive: true);
  });

  /// Writes [content] under the temp dir and returns its absolute path.
  String write(String name, String content) {
    final File file = File('${dir.path}/$name')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
    return file.path;
  }

  /// A campaign over [scenarios] (name to platforms), plus [extra] YAML.
  String campaign(
    Map<String, List<String>> scenarios, {
    String extra = '',
  }) {
    for (final MapEntry<String, List<String>> s in scenarios.entries) {
      write('scenarios/${s.key}.yaml', _scenario(s.key, s.value));
    }
    return write('campaign.yaml', '''
scenarios:
${scenarios.keys.map((String n) => '  - scenarios/$n.yaml').join('\n')}
$extra
''');
  }

  Future<(int, String)> handle(
    _FakeHost host,
    String path, {
    String platform = 'chrome',
    Map<String, dynamic> options = const <String, dynamic>{},
    Map<String, String> env = _env,
  }) async {
    final BufferedOutput output = BufferedOutput();
    final int code = await DuskPerfCampaignCommand(
      host: host,
      environment: env,
    ).handle(
      ArtisanContext.bare(
        MapInput(
          <String, dynamic>{'platform': platform, ...options},
          positional: <String>[path],
        ),
        output,
      ),
    );
    return (code, output.content);
  }

  String errOf(String name) =>
      File('build/perf/$name-run.err').readAsStringSync();

  void expectMasked(String text) {
    expect(text, isNot(contains(_secret)));
    expect(text, isNot(contains(_secretInJson)));
  }

  group('DuskPerfCampaignCommand', () {
    test('is dusk:perf_campaign and boots without a running app', () {
      final DuskPerfCampaignCommand command = DuskPerfCampaignCommand();

      expect(command.name, 'dusk:perf_campaign');
      expect(command.boot, CommandBoot.none);
    });

    group('.handle() filtering', () {
      test(
          '--only matching nothing prints the sentence, exits 1 and runs no '
          'hook or process', () async {
        final _FakeHost host = _FakeHost();
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['chrome'],
          },
          extra: 'hooks: {before_campaign: ./services.sh up}',
        );

        final (int code, String out) = await handle(
          host,
          path,
          options: <String, dynamic>{'only': 'zzz'},
        );

        expect(code, 1);
        expect(out, contains('No scenario matched --only=zzz on chrome.'));
        expect(host.events, isEmpty);
      });

      test('a platform no scenario lists says so and runs nothing', () async {
        final _FakeHost host = _FakeHost();
        final String path = campaign(<String, List<String>>{
          'a': <String>['chrome'],
        });

        final (int code, String out) = await handle(
          host,
          path,
          platform: 'android',
          options: <String, dynamic>{'device': 'emulator-5554'},
        );

        expect(code, 1);
        expect(out, contains('No scenario lists android.'));
        expect(host.events, isEmpty);
      });

      test('runs only the scenarios the platform and --only select', () async {
        final _FakeHost host = _FakeHost();
        final String path = campaign(<String, List<String>>{
          'list-a': <String>['chrome'],
          'list-b': <String>['android'],
          'detail-c': <String>['chrome', 'android'],
          'list-d': <String>['chrome', 'android'],
        });

        final (int code, _) = await handle(
          host,
          path,
          options: <String, dynamic>{'only': 'list'},
        );

        expect(code, 0);
        expect(
          host.events.where((String e) => e.startsWith('perf_run')),
          <String>['perf_run list-a', 'perf_run list-d'],
        );
      });

      test('ios without --device is refused before anything runs', () async {
        final _FakeHost host = _FakeHost();
        final String path = campaign(<String, List<String>>{
          'a': <String>['ios'],
        });

        final (int code, String out) = await handle(
          host,
          path,
          platform: 'ios',
        );

        expect(code, 1);
        expect(out, contains('--platform=ios needs --device'));
        expect(host.events, isEmpty);
      });

      test('an unsafe --label is refused before anything runs', () async {
        final _FakeHost host = _FakeHost();
        final String path = campaign(<String, List<String>>{
          'a': <String>['chrome'],
        });

        final (int code, String out) = await handle(
          host,
          path,
          options: <String, dynamic>{'label': 'Bad Label'},
        );

        expect(code, 1);
        expect(out, contains('--label "Bad Label"'));
        expect(host.events, isEmpty);
      });

      test(
          'a --cdp-port that is not a port exits 1 before any hook or '
          'process', () async {
        for (final String bad in <String>['abc', '0', '70000']) {
          final _FakeHost host = _FakeHost();
          final String path = campaign(
            <String, List<String>>{
              'a': <String>['chrome'],
            },
            extra: 'hooks: {before_campaign: ./services.sh up}',
          );

          final (int code, String out) = await handle(
            host,
            path,
            options: <String, dynamic>{'cdp-port': bad},
          );

          expect(code, 1, reason: bad);
          expect(out, contains('--cdp-port "$bad"'), reason: bad);
          expect(host.events, isEmpty, reason: bad);
        }
      });

      test('an invalid campaign names its problems and exits 1', () async {
        final _FakeHost host = _FakeHost();
        final String path = write('campaign.yaml', 'retries: -1\n');

        final (int code, String out) = await handle(host, path);

        expect(code, 1);
        expect(out, contains('Invalid perf campaign'));
        expect(out, contains('retries must be a non-negative integer'));
        expect(host.events, isEmpty);
      });
    });

    group('.handle() hooks', () {
      test(
          'a failing before_campaign stops the campaign with its output in '
          'campaign-<label>.err', () async {
        final _FakeHost host = _FakeHost(
          onRun: (String exe, List<String> args) =>
              exe == '/bin/sh' ? (3, 'redis down\n', 'boom\n') : (0, '', ''),
        );
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['chrome'],
          },
          extra: 'hooks: {before_campaign: ./services.sh up}',
        );

        final (int code, String out) = await handle(host, path);

        expect(code, 1);
        expect(host.commandLines, <String>['/bin/sh -c ./services.sh up']);
        expect(host.events, isNot(contains('start')));
        final String err =
            File('build/perf/campaign-run.err').readAsStringSync();
        expect(err, contains('redis down'));
        expect(err, contains('boom'));
        expect(err, contains('exited 3'));
        expect(out, contains('hooks.before_campaign exited 3'));
      });

      test('hook output holding the secret is masked in the .err', () async {
        final _FakeHost host = _FakeHost(
          onRun: (String exe, List<String> args) => exe == '/bin/sh'
              ? (1, 'password $_secret\n', 'json {"p":"$_secretInJson"}\n')
              : (0, '', ''),
        );
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['chrome'],
          },
          extra: 'hooks: {before_campaign: ./services.sh up}',
        );

        final (int code, String out) = await handle(host, path);

        expect(code, 1);
        final String err =
            File('build/perf/campaign-run.err').readAsStringSync();
        expect(err, contains('password ***'));
        expect(err, contains('json {"p":"***"}'));
        expectMasked(err);
        expectMasked(out);
      });

      test(
          'hooks run through /bin/sh in the invoking directory with '
          'DUSK_PERF_* on top of the inherited environment, minus every '
          'variable the campaign read', () async {
        final _FakeHost host = _FakeHost();
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['chrome'],
          },
          extra: '''
hooks:
  before_campaign: ./services.sh up
  before_scenario: ./services.sh reset
''',
        );

        final (int code, _) = await handle(
          host,
          path,
          options: <String, dynamic>{'label': 'base', 'out': 'out/perf'},
          env: <String, String>{..._env, 'COPY': _secret},
        );

        expect(code, 0);
        final List<_Run> hooks =
            host.runs.where((_Run r) => r.executable == '/bin/sh').toList();
        expect(hooks, hasLength(2));
        for (final _Run hook in hooks) {
          expect(hook.environment, isNot(contains('DEMO_PASSWORD')));
          // Filtered by name, not by value: a variable the campaign never
          // read stays, whatever it holds.
          expect(hook.environment, containsPair('COPY', _secret));
        }
        expect(hooks[0].arguments, <String>['-c', './services.sh up']);
        expect(hooks[1].arguments, <String>['-c', './services.sh reset']);
        for (final _Run hook in hooks) {
          expect(hook.workingDirectory, Directory.current.path);
          expect(hook.environment, containsPair('HOME', '/home/perf'));
          expect(
              hook.environment, containsPair('DUSK_PERF_PLATFORM', 'chrome'));
          expect(hook.environment, containsPair('DUSK_PERF_LABEL', 'base'));
          expect(hook.environment, containsPair('DUSK_PERF_OUT', 'out/perf'));
        }
        expect(hooks[0].environment, isNot(contains('DUSK_PERF_SCENARIO')));
        expect(hooks[1].environment, containsPair('DUSK_PERF_SCENARIO', 'a'));
      });

      test('a failing before_scenario stops the campaign at that scenario',
          () async {
        final _FakeHost host = _FakeHost(
          onRun: (String exe, List<String> args) =>
              exe == '/bin/sh' ? (2, 'reset failed', '') : (0, '', ''),
        );
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['chrome'],
            'b': <String>['chrome'],
          },
          extra: 'hooks: {before_scenario: ./services.sh reset}',
        );

        final (int code, String out) = await handle(host, path);

        expect(code, 1);
        expect(host.events, isNot(contains('start')));
        expect(host.events.where((String e) => e.startsWith('run /bin/sh')),
            hasLength(1));
        expect(errOf('a'), contains('reset failed'));
        expect(out, contains('hooks.before_scenario exited 2'));
      });

      test(
          'a before_scenario hook whose shell cannot start stops the campaign '
          'with the reason', () async {
        final _FakeHost host = _FakeHost(
          onRun: (String exe, List<String> args) => exe == '/bin/sh'
              ? throw const ProcessException(
                  '/bin/sh',
                  <String>[],
                  'No such file or directory',
                  2,
                )
              : (0, '', ''),
        );
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['chrome'],
            'b': <String>['chrome'],
          },
          extra: 'hooks: {before_scenario: ./services.sh reset}',
        );

        final (int code, String out) = await handle(host, path);

        expect(code, 1);
        expect(out, contains('/bin/sh could not start: No such file'));
        expect(errOf('a'), contains('/bin/sh could not start'));
        expect(host.events, isNot(contains('start')));
        expect(host.events, isNot(contains('perf_run b')));
      });
    });

    group('.handle() preparation', () {
      test('runs flutter pub get before the first start', () async {
        final _FakeHost host = _FakeHost();
        final String path = campaign(<String, List<String>>{
          'a': <String>['chrome'],
        });

        await handle(host, path);

        expect(host.events.first, 'run flutter pub get');
        expect(host.runs.first.workingDirectory, Directory.current.path);
      });

      test(
          'every preparation process gets the whole environment minus the '
          'variables the campaign read, and no DUSK_PERF_*', () async {
        final _FakeHost host = _FakeHost();
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['android'],
          },
          extra: 'android: {reverse: [8001]}',
        );

        final (int code, _) = await handle(
          host,
          path,
          platform: 'android',
          options: <String, dynamic>{'device': 'emulator-5554'},
        );

        expect(code, 0);
        expect(host.runs, hasLength(2));
        for (final _Run run in host.runs) {
          expect(run.environment, <String, String>{'HOME': '/home/perf'});
        }
      });

      test('a failing flutter pub get stops the campaign', () async {
        final _FakeHost host = _FakeHost(
          onRun: (String exe, List<String> args) => exe == 'flutter'
              ? (1, '', 'version solving failed')
              : (0, '', ''),
        );
        final String path = campaign(<String, List<String>>{
          'a': <String>['chrome'],
        });

        final (int code, String out) = await handle(host, path);

        expect(code, 1);
        expect(out, contains('flutter pub get exited 1'));
        expect(
          File('build/perf/campaign-run.err').readAsStringSync(),
          contains('version solving failed'),
        );
        expect(host.events, isNot(contains('start')));
      });

      test('a flutter that cannot start stops the campaign with the reason',
          () async {
        final _FakeHost host = _FakeHost(
          onRun: (String exe, List<String> args) => exe == 'flutter'
              ? throw const ProcessException(
                  'flutter',
                  <String>['pub', 'get'],
                  'No such file or directory',
                  2,
                )
              : (0, '', ''),
        );
        final String path = campaign(<String, List<String>>{
          'a': <String>['chrome'],
        });

        final (int code, String out) = await handle(host, path);

        expect(code, 1);
        expect(out, contains('flutter could not start: No such file'));
        expect(host.events, isNot(contains('start')));
      });

      test('an adb that cannot start while matching the AVD stops the campaign',
          () async {
        final _FakeHost host = _FakeHost(
          onRun: (String exe, List<String> args) {
            if (args.contains('devices')) {
              return (0, 'emulator-5554\tdevice\n', '');
            }
            if (args.contains('emu')) {
              throw const ProcessException(
                'adb',
                <String>[],
                'Permission denied',
                13,
              );
            }
            return (0, '', '');
          },
        );
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['android'],
          },
          extra: 'android: {avd: perf_avd}',
        );

        final (int code, String out) = await handle(
          host,
          path,
          platform: 'android',
        );

        expect(code, 1);
        expect(out, contains('adb could not start: Permission denied'));
        expect(host.events, isNot(contains('start')));
      });

      test(
          'an applicationId Gradle interpolates is refused before anything '
          'reaches the device', () async {
        write(
          'android/app/build.gradle',
          'android {\n  defaultConfig {\n    applicationId '
              '"com.example.\${flavor}"\n  }\n}\n',
        );
        final _FakeHost host = _FakeHost();
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['android'],
          },
          extra: 'android: {grant: [android.permission.CAMERA]}',
        );

        final (int code, String out) = await handle(
          host,
          path,
          platform: 'android',
          options: <String, dynamic>{'device': 'emulator-5554'},
        );

        expect(code, 1);
        expect(out, contains('could not be used'));
        expect(out, contains(r'com.example.${flavor}'));
        expect(host.commandLines, <String>['flutter pub get']);
        expect(host.events, isNot(contains('start')));
      });

      test(
          'android boots the AVD beside another emulator, waits for '
          'boot_completed, reverses, builds, installs and grants, in order',
          () async {
        final String adb = write('sdk/platform-tools/adb', '');
        write(
          'android/app/build.gradle',
          'android {\n  defaultConfig {\n    applicationId "com.example.perf"'
              '\n  }\n}\n',
        );
        // Another AVD is already up as emulator-5580; perf_avd appears as
        // emulator-5554 once launched, listed after it.
        bool launched = false;
        int bootReads = 0;
        final _FakeHost host = _FakeHost(
          onRun: (String exe, List<String> args) {
            if (args.contains('--launch')) launched = true;
            if (args.contains('devices')) {
              return (
                0,
                'List of devices attached\nemulator-5580\tdevice\n'
                    '${launched ? 'emulator-5554\tdevice\n' : ''}\n',
                '',
              );
            }
            if (args.contains('emu')) {
              final String name =
                  args[1] == 'emulator-5580' ? 'other_avd' : 'perf_avd';
              return (0, '$name\r\nOK\r\n', '');
            }
            if (args.contains('sys.boot_completed')) {
              return (0, bootReads++ == 0 ? '\n' : '1\r\n', '');
            }
            return (0, '', '');
          },
        );
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['android'],
          },
          extra: '''
android:
  avd: perf_avd
  reverse: [8001, 8080]
  grant: [android.permission.POST_NOTIFICATIONS]
''',
        );

        final (int code, _) = await handle(
          host,
          path,
          platform: 'android',
          env: <String, String>{..._env, 'ANDROID_HOME': '${dir.path}/sdk'},
        );

        expect(code, 0);
        expect(
          host.commandLines,
          <String>[
            'flutter pub get',
            '$adb devices',
            '$adb -s emulator-5580 emu avd name',
            'flutter emulators --launch perf_avd',
            '$adb devices',
            '$adb -s emulator-5580 emu avd name',
            '$adb -s emulator-5554 emu avd name',
            '$adb -s emulator-5554 shell getprop sys.boot_completed',
            '$adb -s emulator-5554 shell getprop sys.boot_completed',
            '$adb -s emulator-5554 reverse tcp:8001 tcp:8001',
            '$adb -s emulator-5554 reverse tcp:8080 tcp:8080',
            'flutter build apk --profile',
            '$adb -s emulator-5554 install -r '
                'build/app/outputs/flutter-apk/app-profile.apk',
            '$adb -s emulator-5554 shell pm grant com.example.perf '
                'android.permission.POST_NOTIFICATIONS',
          ],
        );
        expect(host.starts.single['device'], 'emulator-5554');
        expect(host.starts.single['profile-static'], isTrue);
        expect(host.starts.single.containsKey('cdp-port'), isFalse);
      });

      test('android reuses the AVD when it already runs', () async {
        final _FakeHost host = _FakeHost(
          onRun: (String exe, List<String> args) {
            if (args.contains('devices')) {
              return (
                0,
                'List of devices attached\nemulator-5580\tdevice\n'
                    'emulator-5554\tdevice\n\n',
                '',
              );
            }
            if (args.contains('emu')) {
              final String name =
                  args[1] == 'emulator-5580' ? 'other_avd' : 'perf_avd';
              return (0, '$name\r\nOK\r\n', '');
            }
            if (args.contains('sys.boot_completed')) return (0, '1\n', '');
            return (0, '', '');
          },
        );
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['android'],
          },
          extra: 'android: {avd: perf_avd}',
        );

        final (int code, _) = await handle(host, path, platform: 'android');

        expect(code, 0);
        expect(host.commandLines, isNot(contains(contains('--launch'))));
        expect(host.starts.single['device'], 'emulator-5554');
      });

      test('android falls back to adb on PATH and honours --device', () async {
        final _FakeHost host = _FakeHost();
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['android'],
          },
          extra: 'android: {reverse: [8001]}',
        );

        final (int code, _) = await handle(
          host,
          path,
          platform: 'android',
          options: <String, dynamic>{'device': 'R5CT1234'},
        );

        expect(code, 0);
        expect(host.commandLines, <String>[
          'flutter pub get',
          'adb -s R5CT1234 reverse tcp:8001 tcp:8001',
        ]);
        expect(host.starts.single['device'], 'R5CT1234');
      });

      test('android with no emulator serial and no --device stops', () async {
        final _FakeHost host = _FakeHost(
          onRun: (String exe, List<String> args) =>
              (0, 'List of devices attached\n\n', ''),
        );
        final String path = campaign(<String, List<String>>{
          'a': <String>['android'],
        });

        final (int code, String out) = await handle(
          host,
          path,
          platform: 'android',
        );

        expect(code, 1);
        expect(out, contains('no emulator'));
        expect(host.events, isNot(contains('start')));
      });

      test('android grant without an applicationId stops', () async {
        final _FakeHost host = _FakeHost();
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['android'],
          },
          extra: 'android: {grant: [android.permission.CAMERA]}',
        );

        final (int code, String out) = await handle(
          host,
          path,
          platform: 'android',
          options: <String, dynamic>{'device': 'emulator-5554'},
        );

        expect(code, 1);
        expect(out, contains('applicationId'));
        expect(host.events, isNot(contains('start')));
      });
    });

    group('.handle() cold start', () {
      test(
          'reads the session before stop, waits for the pid and the ports, '
          'then starts', () async {
        final _FakeHost host = _FakeHost()
          ..session = <String, dynamic>{
            'pid': 41,
            'webPort': 3100,
            'cdpPort': 9222,
            'vmServicePort': 8181,
            'device': 'chrome',
          };
        host.aliveReads[41] = 1;
        host.busyReads[9222] = 3;
        final String path = campaign(<String, List<String>>{
          'a': <String>['chrome'],
        });

        final (int code, _) = await handle(host, path);

        expect(code, 0);
        final List<String> events = host.events;
        final int stop = events.indexOf('stop');
        final int start = events.indexOf('start');
        final List<String> between = events.sublist(stop + 1, start);
        expect(
            between.where((String e) => e == 'free:9222=false'), hasLength(3));
        expect(between, contains('free:9222=true'));
        expect(between, contains('alive:41=false'));
        expect(between, contains('free:3100=true'));
        expect(between, isNot(contains(startsWith('free:8181'))));
        expect(between.where((String e) => e == 'pause'), hasLength(3));
        expect(events.lastIndexOf('free:9222=true'), lessThan(start));
      });

      test(
          'a VM Service port adb still forwards does not hold the start: '
          'artisan start never probes it', () async {
        final _FakeHost host = _FakeHost()
          ..session = <String, dynamic>{
            'pid': 41,
            'vmServicePort': 8181,
            'device': 'emulator-5554',
          };
        host.busyReads[8181] = 1 << 20;
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['android'],
          },
          extra: 'retries: 0',
        );

        final (int code, _) = await handle(
          host,
          path,
          platform: 'android',
          options: <String, dynamic>{'device': 'emulator-5554'},
        );

        expect(code, 0);
        expect(host.starts, hasLength(1));
      });

      test(
          'a browser session with no CDP port still waits for its web port, '
          'told by its device', () async {
        final _FakeHost host = _FakeHost()
          ..session = <String, dynamic>{
            'pid': 41,
            'webPort': 3100,
            'vmServicePort': 8181,
            'device': 'web-server',
          };
        host.busyReads[3100] = 2;
        final String path = campaign(<String, List<String>>{
          'a': <String>['chrome'],
        });

        final (int code, _) = await handle(host, path);

        expect(code, 0);
        final List<String> between = host.events.sublist(
          host.events.indexOf('stop') + 1,
          host.events.indexOf('start'),
        );
        expect(
          between.where((String e) => e == 'free:3100=false'),
          hasLength(2),
        );
        expect(between.last, 'free:3100=true');
      });

      test('a port that never frees fails the attempt', () async {
        final _FakeHost host = _FakeHost()
          ..session = <String, dynamic>{
            'pid': 41,
            'webPort': 3100,
            'cdpPort': 9222,
            'vmServicePort': 8181,
            'device': 'chrome',
          };
        host.busyReads[9222] = 1 << 20;
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['chrome'],
          },
          extra: 'retries: 0',
        );

        final (int code, _) = await handle(host, path);

        expect(code, 1);
        expect(host.starts, isEmpty);
        expect(errOf('a'), contains('9222'));
      });

      test('ten chained cycles each wait out the previous app', () async {
        final _FakeHost host = _FakeHost(lingering: true);
        final Map<String, List<String>> scenarios = <String, List<String>>{
          for (int i = 0; i < 10; i++) 's$i': <String>['chrome'],
        };
        final String path = campaign(scenarios);

        final (int code, _) = await handle(host, path);

        expect(code, 0);
        expect(host.starts, hasLength(10));
        // Every start after the first had a held port and a live pid to
        // wait out, and started only once both answered free.
        final List<String> events = host.events;
        int from = events.indexOf('start') + 1;
        for (int cycle = 1; cycle < 10; cycle++) {
          final int start = events.indexOf('start', from);
          final List<String> window = events.sublist(from, start);
          expect(window, contains('free:3100=false'), reason: 'cycle $cycle');
          expect(
            window.lastIndexOf('free:3100=true'),
            greaterThan(window.lastIndexOf('free:3100=false')),
            reason: 'cycle $cycle',
          );
          expect(window, contains('alive:${99 + cycle}=false'));
          from = start + 1;
        }
      });

      test('polls ext.dusk.boot_id until it answers, then runs perf_run',
          () async {
        final _FakeHost host = _FakeHost(bootMisses: 2);
        final String path = campaign(<String, List<String>>{
          'a': <String>['chrome'],
        });

        final (int code, _) = await handle(host, path);

        expect(code, 0);
        final List<String> events = host.events;
        final int connect = events.indexOf('connect');
        expect(
          events.sublist(connect + 1, events.indexOf('driver open')),
          <String>['boot:miss', 'pause', 'boot:miss', 'pause', 'boot:ok'],
        );
      });

      test('an app that never answers boot_id fails the attempt', () async {
        final _FakeHost host = _FakeHost(bootMisses: 1 << 20);
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['chrome'],
          },
          extra: 'retries: 0',
        );

        final (int code, _) = await handle(host, path);

        expect(code, 1);
        expect(host.perfRuns, isEmpty);
        expect(errOf('a'), contains('ext.dusk.boot_id'));
      });

      test('runs after_start once per cold start, the Router awaited first',
          () async {
        final _FakeHost host = _FakeHost();
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['chrome'],
            'b': <String>['chrome'],
          },
          extra: 'after_start: [wait_for_network_idle]',
        );

        final (int code, _) = await handle(host, path);

        expect(code, 0);
        final List<String> events = host.events;
        final int bootA = events.indexOf('boot:ok');
        expect(
          events.sublist(bootA + 1, events.indexOf('close')),
          <String>[
            'driver open',
            'driver ext.dusk.get_routes',
            'driver ext.dusk.wait_for_network_idle',
            'perf_run a',
            'driver close',
          ],
        );
        expect(
          events.where(
              (String e) => e == 'driver ext.dusk.wait_for_network_idle'),
          hasLength(2),
        );
      });

      test(
          'opens one driver per attempt, hands perf_run the one after_start '
          'drove, and closes it once the run is done', () async {
        int calls = 0;
        final _FakeHost host = _FakeHost(
          onPerfRun:
              (Map<String, dynamic> options, ArtisanOutput output) async =>
                  calls++ == 0 ? 1 : 0,
        );
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['chrome'],
          },
          extra: 'after_start: [wait_for_network_idle]',
        );

        final (int code, _) = await handle(host, path);

        expect(code, 0);
        expect(host.openedDrivers, hasLength(2));
        expect(host.perfRunDrivers, hasLength(2));
        for (int i = 0; i < 2; i++) {
          expect(host.perfRunDrivers[i], same(host.openedDrivers[i]));
        }
        expect(
          host.events.where((String e) => e == 'driver close'),
          hasLength(2),
        );
      });

      test('chrome starts with the CDP port and perf_run gets the options',
          () async {
        final _FakeHost host = _FakeHost();
        final String path = campaign(<String, List<String>>{
          'a': <String>['chrome'],
        });

        final (int code, _) = await handle(
          host,
          path,
          options: <String, dynamic>{
            'cdp-port': '9333',
            'label': 'base',
            'out': 'out/perf',
            'timing': true,
            'semantics-pass': true,
          },
        );

        expect(code, 0);
        expect(host.starts.single, <String, dynamic>{
          'device': 'chrome',
          'cdp-port': '9333',
          'profile-static': false,
          'flutter-arg': <String>[],
        });
        expect(host.perfRuns.single, <String, dynamic>{
          'scenario': '${dir.path}/scenarios/a.yaml',
          'variant': null,
          'label': 'base',
          'out': 'out/perf',
          'platform': 'chrome',
          'timing': true,
          'semantics-pass': true,
          'json': false,
        });
      });
    });

    group('.handle() attempts', () {
      test(
          'a scenario that throws a non-PerfRunException is a failed attempt '
          'and the next scenario still runs', () async {
        final _FakeHost host = _FakeHost(
          onPerfRun:
              (Map<String, dynamic> options, ArtisanOutput output) async {
            if (_stem(options['scenario'] as String) == 'a') {
              throw StateError('the isolate went away');
            }
            return 0;
          },
        );
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['chrome'],
            'b': <String>['chrome'],
          },
          extra: 'retries: 0',
        );

        final (int code, String out) = await handle(host, path);

        expect(code, 1);
        expect(host.events, contains('perf_run b'));
        expect(errOf('a'), contains('the isolate went away'));
        expect(
            out,
            matches(RegExp(r'^\s*a\s+FAILED \(see .*a-run\.err\)$',
                multiLine: true)));
        expect(out, matches(RegExp(r'^\s*b\s+ok$', multiLine: true)));
      });

      test('one retry, then FAILED with both attempts in the .err', () async {
        final _FakeHost host = _FakeHost(
          onPerfRun:
              (Map<String, dynamic> options, ArtisanOutput output) async {
            output.error('Scenario a steps[0] (fill): matched nothing');
            return 1;
          },
        );
        final String path = campaign(<String, List<String>>{
          'a': <String>['chrome'],
        });

        final (int code, String out) = await handle(host, path);

        expect(code, 1);
        expect(host.starts, hasLength(2));
        expect(host.perfRuns, hasLength(2));
        final String err = errOf('a');
        expect(err, contains('attempt 1 of 2'));
        expect(err, contains('attempt 2 of 2'));
        expect(err, contains('matched nothing'));
        expect(out, contains('1 of 1 scenarios failed'));
      });

      test('a retry that passes is ok on its second attempt', () async {
        int calls = 0;
        final _FakeHost host = _FakeHost(
          onPerfRun:
              (Map<String, dynamic> options, ArtisanOutput output) async =>
                  calls++ == 0 ? 1 : 0,
        );
        final String path = campaign(<String, List<String>>{
          'a': <String>['chrome'],
        });

        final (int code, String out) = await handle(
          host,
          path,
          options: <String, dynamic>{'json': true},
        );

        expect(code, 0);
        final Map<String, dynamic> envelope =
            jsonDecode(out.trim()) as Map<String, dynamic>;
        final Map<String, dynamic> result =
            (envelope['results'] as List<dynamic>).single
                as Map<String, dynamic>;
        expect(result['status'], 'ok');
        expect(result['attempts'], 2);
        expect(result['errFile'], File('build/perf/a-run.err').absolute.path);
      });

      test('a retry that passes names its attempt and its .err in the summary',
          () async {
        int calls = 0;
        final _FakeHost host = _FakeHost(
          onPerfRun:
              (Map<String, dynamic> options, ArtisanOutput output) async =>
                  calls++ == 0 ? 1 : 0,
        );
        final String path = campaign(<String, List<String>>{
          'a': <String>['chrome'],
          'bb': <String>['chrome'],
        });

        final (int code, String out) = await handle(host, path);

        expect(code, 0);
        expect(
          out,
          matches(
            RegExp(
              r'^\s*a\s+ok \(attempt 2, see .*/build/perf/a-run\.err\)$',
              multiLine: true,
            ),
          ),
        );
        expect(out, matches(RegExp(r'^\s*bb\s+ok$', multiLine: true)));
      });

      test(
          'the run file perf_run wrote is masked for the campaign\'s secrets '
          'and stays valid JSON', () async {
        final _FakeHost host = _FakeHost(
          onPerfRun:
              (Map<String, dynamic> options, ArtisanOutput output) async {
            // perf_run masks only its own scenario's secrets; an app
            // exception quoting the after_start credential is not one.
            _runFileOf(options)
              ..createSync(recursive: true)
              ..writeAsStringSync(
                const JsonEncoder.withIndent('  ').convert(<String, Object?>{
                  'scenario': <String, Object?>{'name': 'a'},
                  'semanticsPassReason': 'login failed for $_secret',
                  'summary': <String, Object?>{'repeats': 3, 'refused': 0},
                }),
              );
            return 0;
          },
        );
        final String path = campaign(<String, List<String>>{
          'a': <String>['chrome'],
        });

        final (int code, _) = await handle(host, path);

        expect(code, 0);
        final String text = File('build/perf/a-run.json').readAsStringSync();
        expectMasked(text);
        final Map<String, dynamic> run =
            jsonDecode(text) as Map<String, dynamic>;
        expect(run['semanticsPassReason'], 'login failed for ***');
        expect(run['summary'], <String, dynamic>{'repeats': 3, 'refused': 0});
        expect(
            run.keys, <String>['scenario', 'semanticsPassReason', 'summary']);
      });

      test(
          'a secret that spells an envelope key leaves the --json envelope '
          'with its keys and numbers intact', () async {
        int calls = 0;
        final _FakeHost host = _FakeHost(
          onPerfRun:
              (Map<String, dynamic> options, ArtisanOutput output) async =>
                  calls++ == 0 ? 1 : 0,
        );
        final String path = campaign(<String, List<String>>{
          'a': <String>['chrome'],
        });

        // `attempts` is a key of the envelope: a text pass over the encoded
        // envelope would turn `"attempts":2` into `"***":2`.
        final (int code, String out) = await handle(
          host,
          path,
          options: <String, dynamic>{'json': true},
          env: <String, String>{'DEMO_PASSWORD': 'attempts'},
        );

        expect(code, 0);
        final Map<String, dynamic> envelope =
            jsonDecode(out.trim()) as Map<String, dynamic>;
        final Map<String, dynamic> result =
            (envelope['results'] as List<dynamic>).single
                as Map<String, dynamic>;
        expect(result['attempts'], 2);
        expect(result['status'], 'ok');
      });

      test('a failed start attaches the session log to the .err', () async {
        final _FakeHost host = _FakeHost(startCode: 1)
          ..sessionLog = 'Launching lib/main.dart\nGradle task failed\n';
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['chrome'],
          },
          extra: 'retries: 0',
        );

        final (int code, _) = await handle(host, path);

        expect(code, 1);
        final String err = errOf('a');
        expect(err, contains('start exited 1'));
        expect(err, contains('flutter run pid=1'));
        expect(err, contains('Gradle task failed'));
      });

      test('the summary and the --json envelope report every scenario',
          () async {
        final _FakeHost host = _FakeHost(
          onPerfRun:
              (Map<String, dynamic> options, ArtisanOutput output) async =>
                  _stem(options['scenario'] as String) == 'b' ? 1 : 0,
        );
        final String path = campaign(<String, List<String>>{
          'a': <String>['chrome'],
          'b': <String>['chrome'],
        });

        final (int code, String out) = await handle(
          host,
          path,
          options: <String, dynamic>{'json': true},
        );

        expect(code, 1);
        final Map<String, dynamic> envelope =
            jsonDecode(out.split('\n').first) as Map<String, dynamic>;
        expect(envelope['results'], <Map<String, dynamic>>[
          <String, dynamic>{
            'scenario': 'a',
            'status': 'ok',
            'attempts': 1,
            'runFile': File('build/perf/a-run.json').absolute.path,
            'errFile': null,
          },
          <String, dynamic>{
            'scenario': 'b',
            'status': 'failed',
            'attempts': 2,
            'runFile': null,
            'errFile': File('build/perf/b-run.err').absolute.path,
          },
        ]);
        // The app is stopped once the last scenario is done.
        expect(host.events.last, 'stop');
      });

      test('a clean campaign exits 0 and stops the app at the end', () async {
        final _FakeHost host = _FakeHost();
        final String path = campaign(<String, List<String>>{
          'a': <String>['chrome'],
        });
        write('build/perf/a-run.err', 'a stale failure from the last run');

        final (int code, String out) = await handle(host, path);

        expect(code, 0);
        expect(out, matches(RegExp(r'^\s*a\s+ok$', multiLine: true)));
        expect(host.events.last, 'stop');
        expect(File('build/perf/a-run.err').existsSync(), isFalse);
      });
    });

    group('.handle() secrets', () {
      test(
          'no .err, output line or envelope carries the secret, raw or '
          'JSON-encoded, and no command line does', () async {
        final _FakeHost host = _FakeHost(
          onPerfRun:
              (Map<String, dynamic> options, ArtisanOutput output) async {
            output
                .error('fill failed for "$_secret" in {"t":"$_secretInJson"}');
            if (_stem(options['scenario'] as String) == 'a') return 1;
            throw StateError('isolate died holding $_secret');
          },
        );
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['chrome'],
            'b': <String>['chrome'],
          },
          extra: 'retries: 0',
        );

        final (int code, String out) = await handle(
          host,
          path,
          options: <String, dynamic>{'json': true},
        );

        expect(code, 1);
        expect(errOf('a'), contains('***'));
        expect(errOf('b'), contains('isolate died holding ***'));
        expectMasked(errOf('a'));
        expectMasked(errOf('b'));
        expectMasked(out);
        for (final _Run run in host.runs) {
          for (final String arg in run.arguments) {
            expectMasked(arg);
          }
        }
        for (final Map<String, dynamic> start in host.starts) {
          expectMasked(jsonEncode(start));
        }
      });

      test(
          'an after_start failure masks a secret its diagnostics quote before '
          'cutting the exception message', () async {
        // The secret straddles the 200-character cut: a mask after the cut
        // no longer matches, and its prefix would leak.
        final String head = 'x' * 197;
        final _FakeHost host = _FakeHost()
          ..exceptions = <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'StateError',
              'message': '$head$_secret was refused',
            },
          ];
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['chrome'],
          },
          extra: '''
retries: 0
after_start:
  - wait_for_text: {text: Never, timeout_ms: 10}
''',
        );

        final (int code, String out) = await handle(host, path);

        expect(code, 1);
        final String err = errOf('a');
        expect(err, contains('$head***'));
        for (final String sink in <String>[err, out]) {
          expect(sink, isNot(contains('${head}ab')));
        }
      });

      test('a failed start masks the secret in the copied session log',
          () async {
        final _FakeHost host = _FakeHost(startCode: 1)
          ..startOutput = 'start saw $_secret'
          ..sessionLog = 'dart-define PASSWORD=$_secret\n'
              '{"password":"$_secretInJson"}\n';
        final String path = campaign(
          <String, List<String>>{
            'a': <String>['chrome'],
          },
          extra: 'retries: 0',
        );

        final (int code, String out) = await handle(host, path);

        expect(code, 1);
        final String err = errOf('a');
        expect(err, contains('PASSWORD=***'));
        expect(err, contains('start saw ***'));
        expectMasked(err);
        expectMasked(out);
      });
    });

    group('the options it hands artisan and perf_run', () {
      late Map<String, Object?> saved;

      setUp(() {
        saved = <String, Object?>{
          'runner': StartCommand.cdpProcessRunner,
          'chrome': StartCommand.cdpChromeBinaryResolver,
          'probe': StartCommand.cdpPortProbe,
          'starter': StartCommand.cdpProcessStarter,
          'fifo': StartCommand.cdpFifoMaker,
          'home': StateFile.debugHomeOverride,
          'root': StateFile.debugProjectRootOverride,
        };
        StartCommand.cdpProcessRunner = (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
          Map<String, String>? environment,
          bool includeParentEnvironment = true,
          bool runInShell = false,
          Encoding? stdoutEncoding,
          Encoding? stderrEncoding,
        }) async =>
            ProcessResult(0, 0, '{"frameworkVersion":"3.35.0"}', '');
        StartCommand.cdpChromeBinaryResolver = (_) => '/fake/chrome';
        StartCommand.cdpPortProbe = (_) async => true;
        StartCommand.cdpProcessStarter = (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
          ProcessStartMode? mode,
        }) async =>
            throw _Reached(arguments);
        StartCommand.cdpFifoMaker = (_) async {};
        StateFile.debugHomeOverride = dir.path;
        StateFile.debugProjectRootOverride = dir.path;
      });

      tearDown(() {
        StartCommand.cdpProcessRunner = saved['runner']! as CdpProcessRunner;
        StartCommand.cdpChromeBinaryResolver =
            saved['chrome']! as CdpChromeBinaryResolver;
        StartCommand.cdpPortProbe = saved['probe']! as CdpPortProbe;
        StartCommand.cdpProcessStarter = saved['starter']! as CdpProcessStarter;
        StartCommand.cdpFifoMaker = saved['fifo'] as CdpFifoMaker?;
        StateFile.debugHomeOverride = saved['home'] as String?;
        StateFile.debugProjectRootOverride = saved['root'] as String?;
      });

      test('the chrome start map parses in StartCommand, CDP branch', () async {
        final _FakeHost host = _FakeHost();
        final String path = campaign(<String, List<String>>{
          'a': <String>['chrome'],
        });
        await handle(host, path);

        await expectLater(
          StartCommand().handle(
            ArtisanContext.bare(MapInput(host.starts.single), BufferedOutput()),
          ),
          throwsA(
            isA<_Reached>().having(
              (_Reached r) => r.arguments,
              'Chrome argv',
              contains('--remote-debugging-port=9222'),
            ),
          ),
        );
      });

      test('the android start map parses in StartCommand as a profile build',
          () async {
        final _FakeHost host = _FakeHost();
        final String path = campaign(<String, List<String>>{
          'a': <String>['android'],
        });
        await handle(
          host,
          path,
          platform: 'android',
          options: <String, dynamic>{'device': 'emulator-5554'},
        );

        await expectLater(
          StartCommand().handle(
            ArtisanContext.bare(MapInput(host.starts.single), BufferedOutput()),
          ),
          throwsA(
            isA<_Reached>().having(
              (_Reached r) => r.arguments.join(' '),
              'flutter wrapper',
              allOf(contains('emulator-5554'), contains('--profile')),
            ),
          ),
        );
      });

      test('the perf_run map parses in DuskPerfRunCommand', () async {
        write('scenarios/list.yaml', '''
name: list
platforms: [chrome]
steps:
  - wait: 400
variants:
  1440: {viewport: {width: 1440, height: 900}}
''');
        final String path = write('campaign.yaml', '''
scenarios: [scenarios/list.yaml]
''');
        final _FakeHost host = _FakeHost();
        await handle(
          host,
          path,
          options: <String, dynamic>{'timing': true, 'json': true},
        );
        final Map<String, dynamic> options = host.perfRuns.single;
        expect(options['variant'], '1440');

        final BufferedOutput output = BufferedOutput();
        final int code = await DuskPerfRunCommand(
          connector: (ArtisanContext ctx, PerfPlatform? platform) async =>
              throw PerfRunException('reached with ${platform?.name}'),
        ).handle(ArtisanContext.bare(MapInput(options), output));

        expect(output.content, contains('reached with chrome'));
        expect(code, 1);
        expect(
          wantsJson(ArtisanContext.bare(MapInput(options), BufferedOutput())),
          isFalse,
        );
      });
    });
  });
}
