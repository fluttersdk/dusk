import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/perf/scenario.dart';

/// A copy of uptizm's `tool/perf/scenarios/dashboard-load-390.yaml`: a file
/// written before fragments and variants existed must load to the same
/// scenario it always parsed to.
const String _dashboardLoad390 = '''
# Mobile-width counterpart of dashboard-load-1440.yaml; see its header comment
# for why the dashboard is reached in `steps`, not `setup`.
name: dashboard-load-390
viewport: {width: 390, height: 844}
platforms: [chrome, android, ios]
setup:
  - hot_restart
  - navigate: /monitors
  - wait_for_text: "Uptizm'in bölgeler genelinde izlediği uç noktalar."
  - wait_for_network_idle
steps:
  - navigate: /
  - wait: 800
''';

/// A login fragment with a required param, a secret one and a defaulted one.
const String _loginFragment = r'''
params:
  user: {}
  password: {secret: true}
  submit: {default: Sign in}
steps:
  - fill: {target: {label: Email}, text: "${user}"}
  - fill: {target: {label: Password}, text: "${password}"}
  - tap: {target: {role: button, name: "${submit}"}}
''';

/// A secret with both a quote and a dollar sign, so a redaction that masks
/// only the raw form (or only the JSON form) is caught.
const String _secret = r'ab"c$d';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('dusk_scenario_'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// Writes [content] under the temp dir and returns its absolute path.
  String write(String name, String content) {
    final File file = File('${dir.path}/$name')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
    return file.path;
  }

  /// Loads [path] and returns the problems it was rejected with.
  Future<String> problemsOf(
    String path, {
    Map<String, String> env = const <String, String>{},
  }) async {
    try {
      await loadPerfScenarios(path, env: env);
    } on PerfScenarioException catch (e) {
      return e.problems.join('\n');
    }
    fail('expected $path to be rejected');
  }

  group('loadPerfScenarios()', () {
    test('an existing scenario loads to the toJson it always parsed to',
        () async {
      final PerfLoadResult result = await loadPerfScenarios(
        write('dashboard-load-390.yaml', _dashboardLoad390),
      );

      expect(result.scenarios, hasLength(1));
      expect(result.secrets, isEmpty);
      expect(
        result.scenarios.single.toJson(),
        PerfScenario.parse(_dashboardLoad390).toJson(),
      );
      expect(result.scenarios.single.toJson(), <String, Object?>{
        'name': 'dashboard-load-390',
        'viewport': <String, Object?>{'width': 390, 'height': 844},
        'platforms': <String>['chrome', 'android', 'ios'],
        'setup': <Object?>[
          'hot_restart',
          <String, Object?>{'navigate': '/monitors'},
          <String, Object?>{
            'wait_for_text': <String, Object?>{
              'text': "Uptizm'in bölgeler genelinde izlediği uç noktalar.",
              'timeout_ms': kPerfWaitForTextTimeoutMs,
            },
          },
          'wait_for_network_idle',
        ],
        'steps': <Object?>[
          <String, Object?>{'navigate': '/'},
          <String, Object?>{'wait': 800},
        ],
        'repeat': 3,
        'thresholds': <String, Object?>{'warn': 10, 'error': 25},
      });
    });

    group('an include', () {
      test('flattens the fragment into setup with its params and defaults',
          () async {
        write('fragments/login.yaml', _loginFragment);
        final PerfLoadResult result = await loadPerfScenarios(
          write('login-flow.yaml', '''
name: login-flow
setup:
  - hot_restart
  - include: fragments/login.yaml
    with: {user: demo@uptizm.test, password: hunter2}
  - wait_for_network_idle
steps:
  - tap: {target: {text: Monitors}}
'''),
        );

        final List<PerfSetupStep> setup = result.scenarios.single.setup;
        expect(
          setup.map((PerfSetupStep s) => s.verb).toList(),
          <PerfSetupVerb>[
            PerfSetupVerb.hotRestart,
            PerfSetupVerb.gesture,
            PerfSetupVerb.gesture,
            PerfSetupVerb.gesture,
            PerfSetupVerb.waitForNetworkIdle,
          ],
        );
        expect(setup[1].gesture!.text, 'demo@uptizm.test');
        expect(setup[1].gesture!.secret, isFalse);
        expect(setup[2].gesture!.text, 'hunter2');
        expect(setup[2].gesture!.secret, isTrue);
        expect(setup[3].gesture!.target!.value, 'Sign in');
        expect(
          setup.map((PerfSetupStep s) => s.origin).toList(),
          <String>[
            'setup[0]',
            'fragments/login.yaml steps[0]',
            'fragments/login.yaml steps[1]',
            'fragments/login.yaml steps[2]',
            'setup[2]',
          ],
        );
        expect(
          (result.scenarios.single.toJson()['setup']! as List<Object?>)[2],
          <String, Object?>{
            'fill': <String, Object?>{
              'target': <String, Object?>{'label': 'Password'},
              'text': '***',
            },
          },
        );
      });

      test('nests, each fragment resolving against its own file', () async {
        write('fragments/login.yaml', _loginFragment);
        write('fragments/auth/sign-in.yaml', r'''
params:
  who: {}
steps:
  - navigate: /login
  - include: ../login.yaml
    with: {user: "${who}", password: pw}
''');
        final PerfLoadResult result = await loadPerfScenarios(
          write('nested.yaml', '''
name: nested
setup:
  - include: fragments/auth/sign-in.yaml
    with: {who: ops@uptizm.test}
steps:
  - wait: 100
'''),
        );

        final List<PerfSetupStep> setup = result.scenarios.single.setup;
        expect(setup, hasLength(4));
        expect(setup[0].argument, '/login');
        expect(setup[1].gesture!.text, 'ops@uptizm.test');
        expect(setup[0].origin, 'fragments/auth/sign-in.yaml steps[0]');
        expect(setup[3].origin, 'fragments/login.yaml steps[2]');
      });

      test('refuses a cycle', () async {
        write('a.yaml', 'steps:\n  - include: b.yaml\n');
        write('b.yaml', 'steps:\n  - include: a.yaml\n');
        final String problems = await problemsOf(
          write('cycle.yaml', '''
name: cycle
setup:
  - include: a.yaml
steps:
  - wait: 100
'''),
        );

        expect(problems, contains('include cycle'));
        expect(problems, contains('a.yaml -> b.yaml -> a.yaml'));
      });

      test('refuses nesting deeper than 8', () async {
        for (int i = 1; i <= 9; i++) {
          write(
            'f$i.yaml',
            i == 9
                ? 'steps:\n  - wait: 10\n'
                : 'steps:\n  - include: f${i + 1}.yaml\n',
          );
        }
        final String problems = await problemsOf(
          write('deep.yaml', '''
name: deep
setup:
  - include: f1.yaml
steps:
  - wait: 100
'''),
        );

        expect(problems, contains('deeper than 8'));
      });

      test('accepts nesting exactly 8 deep', () async {
        for (int i = 1; i <= 8; i++) {
          write(
            'f$i.yaml',
            i == 8
                ? 'steps:\n  - wait: 10\n'
                : 'steps:\n  - include: f${i + 1}.yaml\n',
          );
        }
        final PerfLoadResult result = await loadPerfScenarios(
          write('deep.yaml', '''
name: deep
setup:
  - include: f1.yaml
steps:
  - wait: 100
'''),
        );

        expect(result.scenarios.single.setup.single.origin, 'f8.yaml steps[0]');
      });

      test('refuses an unknown param, a missing one and an unknown key',
          () async {
        write('fragments/login.yaml', _loginFragment);
        write('fragments/odd.yaml', 'steps:\n  - wait: 10\nname: odd\n');
        final String problems = await problemsOf(
          write('bad-params.yaml', '''
name: bad-params
setup:
  - include: fragments/login.yaml
    with: {user: demo, pasword: x}
  - include: fragments/odd.yaml
steps:
  - wait: 100
'''),
        );

        expect(problems, contains('setup[0].with.pasword'));
        expect(problems, contains('unknown param'));
        expect(problems,
            contains('setup[0]: fragments/login.yaml needs password'));
        expect(problems, contains('fragments/odd.yaml: unknown key "name"'));
      });

      test('is refused inside the measured steps', () async {
        write('fragments/login.yaml', _loginFragment);
        final String problems = await problemsOf(
          write('in-steps.yaml', '''
name: in-steps
steps:
  - include: fragments/login.yaml
    with: {user: a, password: b}
'''),
        );

        expect(problems, contains('steps[0]'));
        expect(problems, contains('include is a setup entry'));
      });

      test('reads a when guard, the include overriding the fragment', () async {
        write('fragments/guarded.yaml', '''
when: {text: Sign in, unless_text: Monitors, timeout_ms: 5000}
steps:
  - tap: {target: {text: Sign in}}
  - include: inner.yaml
''');
        write('fragments/inner.yaml', '''
when: {text: Accept cookies}
steps:
  - tap: {target: {text: Accept}}
''');
        final PerfLoadResult result = await loadPerfScenarios(
          write('guarded.yaml', '''
name: guarded
setup:
  - include: fragments/guarded.yaml
  - include: fragments/guarded.yaml
    when: {text: Log in}
steps:
  - wait: 100
'''),
        );

        final List<PerfSetupStep> setup = result.scenarios.single.setup;
        expect(setup, hasLength(4));
        final PerfSetupGuard outer = setup[0].guard!;
        expect(outer.text, 'Sign in');
        expect(outer.unlessText, 'Monitors');
        expect(outer.timeoutMs, 5000);
        expect(outer.parent, isNull);
        final PerfSetupGuard inner = setup[1].guard!;
        expect(inner.text, 'Accept cookies');
        expect(inner.unlessText, isNull);
        expect(inner.timeoutMs, kPerfWhenTimeoutMs);
        expect(identical(inner.parent, outer), isTrue);

        final PerfSetupGuard overridden = setup[2].guard!;
        expect(overridden.text, 'Log in');
        expect(overridden.unlessText, isNull);
        expect(identical(overridden, outer), isFalse);
        expect(identical(setup[3].guard!.parent, overridden), isTrue);
      });
    });

    group('interpolation', () {
      test(r'resolves $$ and an env value holding ${ exactly once', () async {
        write('fragments/outer.yaml', r'''
params:
  a: {}
  b: {}
steps:
  - include: inner.yaml
    with: {a: "${a}", b: "${b}"}
''');
        write('fragments/inner.yaml', r'''
params:
  a: {}
  b: {}
steps:
  - fill: {target: {label: A}, text: "${a}"}
  - type: {target: {label: B}, text: "${b}"}
''');
        final PerfLoadResult result = await loadPerfScenarios(
          write('once.yaml', r'''
name: once
setup:
  - include: fragments/outer.yaml
    with: {a: "Pa$$w0rd", b: "${env.TOKEN}"}
steps:
  - wait: 100
'''),
          env: <String, String>{'TOKEN': r'a${b}'},
        );

        final List<PerfSetupStep> setup = result.scenarios.single.setup;
        expect(setup[0].gesture!.text, r'Pa$w0rd');
        expect(setup[0].gesture!.secret, isFalse);
        expect(setup[1].gesture!.text, r'a${b}');
        expect(setup[1].gesture!.secret, isTrue);
      });

      test('an undefined name is refused with the file and the path', () async {
        write('fragments/typo.yaml', r'''
params:
  password: {}
steps:
  - fill: {target: {label: Password}, text: "${passwrd}"}
''');
        final String problems = await problemsOf(
          write('typo.yaml', r'''
name: typo
setup:
  - include: fragments/typo.yaml
    with: {password: x}
steps:
  - navigate: "${env.MISSING}"
'''),
        );

        expect(problems, contains('fragments/typo.yaml steps[0].fill.text'));
        expect(problems, contains(r'${passwrd}'));
        expect(problems, contains('typo.yaml steps[0].navigate'));
        expect(problems, contains(r'${env.MISSING}'));
      });
    });

    group('a secret', () {
      test('is refused anywhere but the text of fill or type', () async {
        final String problems = await problemsOf(
          write('leak.yaml', r'''
name: leak
setup:
  - navigate: "/login?token=${env.TOKEN}"
  - wait_for_text: "${env.TOKEN}"
steps:
  - tap: {target: {text: "${env.TOKEN}"}}
'''),
          env: <String, String>{'TOKEN': 'tok'},
        );

        expect(problems,
            contains('a secret may only be typed: setup[0].navigate'));
        expect(problems,
            contains('a secret may only be typed: setup[1].wait_for_text'));
        expect(problems,
            contains('a secret may only be typed: steps[0].tap.target.text'));
      });

      test('never reaches a parse error, raw or JSON-encoded', () async {
        write('fragments/secret.yaml', r'''
params:
  password: {secret: true}
steps:
  - wait: "${password}"
  - fill: {target: {label: Password}, text: "${password}", dx: "${password}"}
''');
        final String problems = await problemsOf(
          write('secret-error.yaml', r'''
name: secret-error
setup:
  - include: fragments/secret.yaml
    with: {password: "${env.PASSWORD}"}
repeat: 'ab"c$d'
steps:
  - wait: "${env.PASSWORD}"
  - navigate: "x${env.PASSWORD}"
  - tap: {target: {role: 'ab\"c$d', name: Go}}
'''),
          env: <String, String>{'PASSWORD': _secret},
        );

        // The literal copies in repeat and role reach problems that quote
        // their value, so only the redactor stands between them and the
        // output, in both the raw and the JSON-encoded form.
        expect(problems, contains('repeat must be a positive integer'));
        expect(problems, contains('role "***" is not one of'));
        expect(problems, contains('a secret may only be typed'));
        expect(problems, isNot(contains(_secret)));
        expect(problems, isNot(contains(r'ab\"c$d')));
      });

      test('is collected with every secret param value', () async {
        write('fragments/login.yaml', _loginFragment);
        final PerfLoadResult result = await loadPerfScenarios(
          write('secrets.yaml', r'''
name: secrets
setup:
  - include: fragments/login.yaml
    with: {user: "${env.USER_EMAIL}", password: hunter2}
steps:
  - fill: {target: {label: Search}, text: "${env.SEARCH}"}
'''),
          env: <String, String>{
            'USER_EMAIL': 'ops@uptizm.test',
            'SEARCH': _secret,
            'UNUSED': 'never-read',
          },
        );

        expect(result.secrets, contains('ops@uptizm.test'));
        expect(result.secrets, contains('hunter2'));
        expect(result.secrets, contains(_secret));
        expect(result.secrets, isNot(contains('never-read')));
        expect(result.scenarios.single.steps.single.secret, isTrue);
        expect(
          result.scenarios.single.steps.single.toJson()['fill'],
          containsPair('text', '***'),
        );
      });
    });

    group('variants', () {
      test('yield one scenario per key, each key replacing the base', () async {
        final PerfLoadResult result = await loadPerfScenarios(
          write('list.yaml', '''
name: list
viewport: {width: 1440, height: 900}
platforms: [chrome]
setup:
  - navigate: /monitors
steps:
  - wheel: {target: {key: list}, dy: 600}
repeat: 5
variants:
  1440: {}
  "390":
    viewport: {width: 390, height: 844}
    platforms: [chrome, android]
    repeat: 2
    steps:
      - drag: {target: {key: list}, dy: -600}
'''),
        );

        expect(
          result.scenarios.map((PerfScenario s) => s.name).toList(),
          <String>['list-1440', 'list-390'],
        );
        final PerfScenario wide = result.scenarios[0];
        final PerfScenario narrow = result.scenarios[1];
        expect(wide.viewport, (width: 1440, height: 900));
        expect(wide.platforms, <PerfPlatform>{PerfPlatform.chrome});
        expect(wide.repeat, 5);
        expect(wide.steps.single.verb, PerfStepVerb.wheel);
        expect(narrow.viewport, (width: 390, height: 844));
        expect(
          narrow.platforms,
          <PerfPlatform>{PerfPlatform.chrome, PerfPlatform.android},
        );
        expect(narrow.repeat, 2);
        expect(narrow.steps.single.verb, PerfStepVerb.drag);
        expect(narrow.setup.single.argument, '/monitors');
      });

      test("validate each variant's steps against its own platforms", () async {
        final String problems = await problemsOf(
          write('scroll.yaml', '''
name: scroll
platforms: [chrome]
steps:
  - wheel: {target: {key: list}, dy: 600}
variants:
  "1440": {}
  "390":
    steps:
      - wait: 100
      - drag: {target: {key: list}, dy: -600}
        only: [android, ios]
'''),
        );

        expect(problems, contains('variants.390.steps[1].only'));
        expect(problems, isNot(contains('scroll-1440')));
      });

      test('refuse a key that cannot name a file and a key given twice',
          () async {
        final String problems = await problemsOf(
          write('keys.yaml', '''
name: keys
steps:
  - wait: 100
variants:
  Wide: {}
  390: {}
  "390": {}
  "1440": {name: other}
'''),
        );

        expect(problems, contains('variants: key "Wide"'));
        expect(problems, contains('variants: key "390" appears twice'));
        expect(problems, contains('variants.1440: unknown key "name"'));
      });
    });
  });

  group('loadPerfSetup()', () {
    test('flattens a bare entry list resolved against the given file', () {
      write('fragments/login.yaml', _loginFragment);
      final String campaign = write('campaign.yaml', '# the campaign\n');

      final PerfSetupLoadResult result = loadPerfSetup(
        <Object?>[
          <Object?, Object?>{
            'include': 'fragments/login.yaml',
            'with': <Object?, Object?>{
              'user': r'${env.USER_EMAIL}',
              'password': r'${env.PASSWORD}',
            },
            'when': <Object?, Object?>{'text': 'Sign in'},
          },
          'wait_for_network_idle',
        ],
        path: campaign,
        env: <String, String>{
          'USER_EMAIL': 'ops@uptizm.test',
          'PASSWORD': _secret,
        },
        at: 'after_start',
      );

      expect(result.setup, hasLength(4));
      expect(result.setup[0].origin, 'fragments/login.yaml steps[0]');
      expect(result.setup[0].guard!.text, 'Sign in');
      expect(result.setup[1].gesture!.text, _secret);
      expect(result.setup[1].gesture!.secret, isTrue);
      expect(result.setup[3].origin, 'after_start[1]');
      expect(result.setup[3].guard, isNull);
      expect(result.secrets, containsAll(<String>['ops@uptizm.test', _secret]));
    });
  });
}
