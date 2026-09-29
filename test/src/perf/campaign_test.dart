import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/perf/campaign.dart';
import 'package:fluttersdk_dusk/src/perf/scenario.dart';

/// A secret with both a quote and a dollar sign, so a redaction that masks
/// only the raw form (or only the JSON form) is caught.
const String _secret = r'ab"c$d';

/// The form [_secret] takes inside a JSON string.
const String _secretInJson = r'ab\"c$d';

const String _tap = '''
name: tap
steps:
  - wait: 400
''';

const String _variants = '''
name: list-scroll
platforms: [chrome, android]
steps:
  - wait: 400
variants:
  1440: {viewport: {width: 1440, height: 900}, platforms: [chrome]}
  390: {viewport: {width: 390, height: 844}}
''';

/// A login fragment: a plain param and a secret one.
const String _login = r'''
params:
  user: {}
  password: {secret: true}
steps:
  - fill: {target: {label: Email}, text: "${user}"}
  - fill: {target: {label: Password}, text: "${password}"}
''';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('dusk_campaign_'));
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
      await loadPerfCampaign(path, env: env);
    } on PerfCampaignException catch (e) {
      return e.problems.join('\n');
    }
    fail('expected $path to be rejected');
  }

  group('loadPerfCampaign()', () {
    group('scenarios', () {
      test('a basename glob expands against its directory, sorted', () async {
        write('scenarios/b.yaml', _tap.replaceFirst('tap', 'b'));
        write('scenarios/a.yaml', _tap.replaceFirst('tap', 'a'));
        write('scenarios/c.yaml', _tap.replaceFirst('tap', 'c'));
        write('scenarios/notes.txt', 'not a scenario');
        write('scenarios/nested/d.yaml', _tap.replaceFirst('tap', 'd'));
        final String path = write('campaign.yaml', '''
scenarios: [scenarios/*.yaml]
''');

        final PerfCampaign campaign = await loadPerfCampaign(path);

        expect(
          campaign.scenarios.map((PerfCampaignScenario s) => s.scenario.name),
          <String>['a', 'b', 'c'],
        );
        expect(
          campaign.scenarios.map((PerfCampaignScenario s) => s.path),
          <String>[
            '${dir.path}/scenarios/a.yaml',
            '${dir.path}/scenarios/b.yaml',
            '${dir.path}/scenarios/c.yaml',
          ].map((String p) => File(p).absolute.path),
        );
      });

      test('a literal path keeps the order the campaign wrote', () async {
        write('scenarios/a.yaml', _tap.replaceFirst('tap', 'a'));
        write('scenarios/b.yaml', _tap.replaceFirst('tap', 'b'));
        final String path = write('campaign.yaml', '''
scenarios: [scenarios/b.yaml, scenarios/a.yaml]
''');

        final PerfCampaign campaign = await loadPerfCampaign(path);

        expect(
          campaign.scenarios.map((PerfCampaignScenario s) => s.scenario.name),
          <String>['b', 'a'],
        );
      });

      test('a glob metacharacter in the basename matches literally', () async {
        write('scenarios/a.yaml', _tap.replaceFirst('tap', 'a'));
        write('scenarios/aXyaml', _tap.replaceFirst('tap', 'x'));
        final String path = write('campaign.yaml', '''
scenarios: ["scenarios/a.y*"]
''');

        final PerfCampaign campaign = await loadPerfCampaign(path);

        expect(
          campaign.scenarios.map((PerfCampaignScenario s) => s.scenario.name),
          <String>['a'],
        );
      });

      test('a variants file expands to one entry per key, with its variant',
          () async {
        write('scenarios/list-scroll.yaml', _variants);
        write('scenarios/tap.yaml', _tap);
        final String path = write('campaign.yaml', '''
scenarios: [scenarios/list-scroll.yaml, scenarios/tap.yaml]
''');

        final PerfCampaign campaign = await loadPerfCampaign(path);

        expect(
          campaign.scenarios.map((PerfCampaignScenario s) => s.scenario.name),
          <String>['list-scroll-1440', 'list-scroll-390', 'tap'],
        );
        expect(
          campaign.scenarios.map((PerfCampaignScenario s) => s.variant),
          <String?>['1440', '390', null],
        );
        expect(campaign.scenarios[0].platforms, <PerfPlatform>{
          PerfPlatform.chrome,
        });
        expect(campaign.scenarios[1].platforms, <PerfPlatform>{
          PerfPlatform.chrome,
          PerfPlatform.android,
        });
        expect(
          campaign.scenarios[0].path,
          File('${dir.path}/scenarios/list-scroll.yaml').absolute.path,
        );
      });

      test('a variant key that ends with the base name is still the key',
          () async {
        write('scenarios/a.yaml', '''
name: a-1
steps:
  - wait: 400
variants:
  1: {}
  b-2: {}
''');
        final String path = write('campaign.yaml', '''
scenarios: [scenarios/a.yaml]
''');

        final PerfCampaign campaign = await loadPerfCampaign(path);

        expect(
          campaign.scenarios.map((PerfCampaignScenario s) => s.variant),
          <String?>['1', 'b-2'],
        );
      });

      test('an empty match, a missing file and a bad glob are all reported',
          () async {
        write('scenarios/a.yaml', _tap.replaceFirst('tap', 'a'));
        final String path = write('campaign.yaml', '''
scenarios:
  - scenarios/*.nope
  - scenarios/missing.yaml
  - "*/a.yaml"
  - scenarios/**/a.yaml
  - absent/*.yaml
''');

        final String problems = await problemsOf(path);

        expect(problems, contains('scenarios/*.nope'));
        expect(problems, contains('matches no file'));
        expect(problems, contains('scenarios/missing.yaml'));
        expect(problems, contains('*/a.yaml'));
        expect(problems, contains('scenarios/**/a.yaml'));
        expect(problems, contains('absent/*.yaml'));
        expect(problems.split('\n'), hasLength(5));
      });

      test('a scenario file that fails to load is named, with every problem',
          () async {
        write('scenarios/a.yaml', 'name: a\nsteps: nope\n');
        write('scenarios/b.yaml', 'name: "B!"\nsteps:\n  - wait: 400\n');
        write('scenarios/c.yaml', _tap.replaceFirst('tap', 'c'));
        final String path = write('campaign.yaml', '''
scenarios: [scenarios/*.yaml]
''');

        final List<String> problems = (await problemsOf(path)).split('\n');

        expect(
          problems.where((String p) => p.startsWith('scenarios/a.yaml: ')),
          isNotEmpty,
        );
        expect(
          problems.where((String p) => p.startsWith('scenarios/b.yaml: ')),
          isNotEmpty,
        );
        expect(problems.where((String p) => p.contains('c.yaml')), isEmpty);
      });

      test('two files that yield one name are reported', () async {
        write('scenarios/a.yaml', _tap);
        write('scenarios/b.yaml', _tap);
        final String path = write('campaign.yaml', '''
scenarios: [scenarios/a.yaml, scenarios/b.yaml]
''');

        final String problems = await problemsOf(path);

        expect(problems, contains('duplicate scenario name "tap"'));
        expect(problems, contains('scenarios/a.yaml'));
        expect(problems, contains('scenarios/b.yaml'));
      });

      test('a file listed twice yields a duplicate name', () async {
        write('scenarios/a.yaml', _tap);
        final String path = write('campaign.yaml', '''
scenarios: [scenarios/a.yaml, scenarios/*.yaml]
''');

        expect(await problemsOf(path), contains('duplicate scenario name'));
      });

      test('a missing or empty scenarios list is a problem', () async {
        expect(
          await problemsOf(write('missing.yaml', 'retries: 1\n')),
          contains('scenarios must be a non-empty list'),
        );
        expect(
          await problemsOf(write('empty.yaml', 'scenarios: []\n')),
          contains('scenarios must be a non-empty list'),
        );
        expect(
          await problemsOf(write('bad.yaml', 'scenarios: [1, ""]\n')),
          allOf(contains('scenarios[0]'), contains('scenarios[1]')),
        );
      });
    });

    group('keys', () {
      test('an unknown key is listed with every other problem', () async {
        write('scenarios/a.yaml', _tap);
        final String path = write('campaign.yaml', '''
scenarios: [scenarios/*.nope]
bogus: 1
hooks: {before_all: "true"}
android: {device: pixel}
''');

        final String problems = await problemsOf(path);

        expect(problems, contains('unknown key "bogus"'));
        expect(problems, contains('hooks: unknown key "before_all"'));
        expect(problems, contains('android: unknown key "device"'));
        expect(problems, contains('matches no file'));
      });

      test('retries defaults to 1 and accepts 0', () async {
        write('scenarios/a.yaml', _tap);
        final PerfCampaign defaulted = await loadPerfCampaign(
          write('one.yaml', 'scenarios: [scenarios/a.yaml]\n'),
        );
        final PerfCampaign none = await loadPerfCampaign(
          write('none.yaml', 'scenarios: [scenarios/a.yaml]\nretries: 0\n'),
        );

        expect(defaulted.retries, 1);
        expect(none.retries, 0);
      });

      test('retries must be a non-negative integer', () async {
        write('scenarios/a.yaml', _tap);
        for (final String bad in <String>['-1', '1.5', 'twice']) {
          expect(
            await problemsOf(
              write('c.yaml', 'scenarios: [scenarios/a.yaml]\nretries: $bad\n'),
            ),
            contains('retries must be a non-negative integer'),
          );
        }
      });

      test('android reads the avd, the reverse ports and the grants', () async {
        write('scenarios/a.yaml', _tap);
        final PerfCampaign campaign = await loadPerfCampaign(write('c.yaml', '''
scenarios: [scenarios/a.yaml]
android:
  avd: uptizm_pixel8_api35
  reverse: [8001, 8080]
  grant: [android.permission.POST_NOTIFICATIONS]
'''));

        expect(campaign.android.avd, 'uptizm_pixel8_api35');
        expect(campaign.android.reverse, <int>[8001, 8080]);
        expect(
          campaign.android.grant,
          <String>['android.permission.POST_NOTIFICATIONS'],
        );
      });

      test('android is empty when the campaign leaves it out', () async {
        write('scenarios/a.yaml', _tap);
        final PerfCampaign campaign = await loadPerfCampaign(
          write('c.yaml', 'scenarios: [scenarios/a.yaml]\n'),
        );

        expect(campaign.android.avd, isNull);
        expect(campaign.android.reverse, isEmpty);
        expect(campaign.android.grant, isEmpty);
        expect(campaign.hooks.beforeCampaign, isNull);
        expect(campaign.hooks.beforeScenario, isNull);
        expect(campaign.afterStart, isEmpty);
      });

      test('android reverse and grant are checked entry by entry', () async {
        write('scenarios/a.yaml', _tap);
        final String problems = await problemsOf(write('c.yaml', '''
scenarios: [scenarios/a.yaml]
android:
  avd: ""
  reverse: [8001, 0, http]
  grant: [ok, 3]
'''));

        expect(problems, contains('android.avd'));
        expect(problems, contains('android.reverse[1]'));
        expect(problems, contains('android.reverse[2]'));
        expect(problems, contains('android.grant[1]'));
        expect(problems, isNot(contains('android.reverse[0]')));
      });

      test(
          'a grant that is not a plain permission name is refused: the '
          'device shell reads it', () async {
        write('scenarios/a.yaml', _tap);
        final String problems = await problemsOf(write('c.yaml', r'''
scenarios: [scenarios/a.yaml]
android:
  grant:
    - android.permission.CAMERA
    - "android.permission.CAMERA; reboot"
    - "$(id)"
'''));

        expect(problems, isNot(contains('android.grant[0]')));
        expect(problems, contains('android.grant[1]'));
        expect(problems, contains('android.grant[2]'));
      });
    });

    group('hooks', () {
      test('a hook is read as the shell string it is', () async {
        write('scenarios/a.yaml', _tap);
        final PerfCampaign campaign =
            await loadPerfCampaign(write('c.yaml', r'''
scenarios: [scenarios/a.yaml]
hooks:
  before_campaign: ./services.sh up
  before_scenario: echo "$DUSK_PERF_SCENARIO"
'''));

        expect(campaign.hooks.beforeCampaign, './services.sh up');
        expect(campaign.hooks.beforeScenario, r'echo "$DUSK_PERF_SCENARIO"');
      });

      test(r'a ${ inside a hook is rejected, and the hook is not echoed',
          () async {
        write('scenarios/a.yaml', _tap);
        final String problems = await problemsOf(
          write('c.yaml', r'''
scenarios: [scenarios/a.yaml]
hooks:
  before_campaign: "login --password ${env.PASSWORD}"
  before_scenario: "echo ${DUSK_PERF_SCENARIO}"
'''),
          env: <String, String>{'PASSWORD': _secret},
        );

        expect(problems, contains('hooks.before_campaign'));
        expect(problems, contains('hooks.before_scenario'));
        expect(
          problems,
          contains(r'hooks run in a shell; read the variable there as $NAME'),
        );
        expect(problems, isNot(contains('login --password')));
        expect(problems, isNot(contains(_secret)));
      });

      test('a hook must be a non-empty string', () async {
        write('scenarios/a.yaml', _tap);
        final String problems = await problemsOf(write('c.yaml', '''
scenarios: [scenarios/a.yaml]
hooks: {before_campaign: [up], before_scenario: ""}
'''));

        expect(problems, contains('hooks.before_campaign'));
        expect(problems, contains('hooks.before_scenario'));
      });
    });

    group('after_start', () {
      test('an include with a secret env value produces a masked toJson',
          () async {
        write('scenarios/a.yaml', _tap);
        write('fragments/login.yaml', _login);
        final String path = write('campaign.yaml', r'''
scenarios: [scenarios/a.yaml]
after_start:
  - hot_restart
  - include: fragments/login.yaml
    with: {user: demo@example.com, password: "${env.PASSWORD}"}
  - tap: {target: {role: button, name: Sign in}}
''');

        final PerfCampaign campaign = await loadPerfCampaign(
          path,
          env: <String, String>{'PASSWORD': _secret},
        );
        final String json = jsonEncode(
          campaign.afterStart.map((PerfSetupStep s) => s.toJson()).toList(),
        );

        expect(campaign.afterStart, hasLength(4));
        expect(json, contains('***'));
        expect(json, contains('demo@example.com'));
        expect(json, isNot(contains(_secret)));
        expect(json, isNot(contains(_secretInJson)));
        expect(campaign.secrets, <String>{_secret});
        expect(
          campaign.afterStart[1].origin,
          'fragments/login.yaml steps[0]',
        );
      });

      test('a problem in after_start never carries the secret', () async {
        write('scenarios/a.yaml', _tap);
        final String problems = await problemsOf(
          write('c.yaml', r'''
scenarios: [scenarios/a.yaml]
after_start:
  - navigate: "/login?p=${env.PASSWORD}"
'''),
          env: <String, String>{'PASSWORD': _secret},
        );

        expect(problems, contains('after_start[0]'));
        expect(problems, isNot(contains(_secret)));
        expect(problems, isNot(contains(_secretInJson)));
      });

      test('an include resolves against the campaign file', () async {
        write('scenarios/a.yaml', _tap);
        write('tool/fragments/login.yaml', _login);
        final String path = write('tool/campaign.yaml', r'''
scenarios: [../scenarios/a.yaml]
after_start:
  - include: fragments/login.yaml
    with: {user: me, password: "${env.PASSWORD}"}
''');

        final PerfCampaign campaign = await loadPerfCampaign(
          path,
          env: <String, String>{'PASSWORD': _secret},
        );

        expect(campaign.afterStart, hasLength(2));
      });
    });

    group('secrets', () {
      test('the union covers every scenario and after_start', () async {
        write('scenarios/a.yaml', r'''
name: a
setup:
  - fill: {target: {label: Token}, text: "${env.TOKEN}"}
steps:
  - wait: 400
''');
        write('fragments/login.yaml', _login);
        final String path = write('campaign.yaml', r'''
scenarios: [scenarios/a.yaml]
after_start:
  - include: fragments/login.yaml
    with: {user: me, password: "${env.PASSWORD}"}
''');

        final PerfCampaign campaign = await loadPerfCampaign(
          path,
          env: <String, String>{'TOKEN': 'tok"1', 'PASSWORD': _secret},
        );

        expect(campaign.secrets, <String>{'tok"1', _secret});
      });

      test('a secret in a scenario problem stays masked', () async {
        write('scenarios/a.yaml', r'''
name: a
setup:
  - navigate: "/x?p=${env.PASSWORD}"
steps:
  - wait: 400
''');
        final String problems = await problemsOf(
          write('campaign.yaml', 'scenarios: [scenarios/a.yaml]\n'),
          env: <String, String>{'PASSWORD': _secret},
        );

        expect(problems, startsWith('scenarios/a.yaml: '));
        expect(problems, isNot(contains(_secret)));
        expect(problems, isNot(contains(_secretInJson)));
      });
    });

    group('the file itself', () {
      test('a campaign that is not a map is a problem', () async {
        expect(
          await problemsOf(write('c.yaml', '- scenarios\n')),
          contains('the campaign must be a map'),
        );
      });

      test('a YAML syntax error is a problem', () async {
        expect(
          await problemsOf(write('c.yaml', 'scenarios: [a\n')),
          contains('not valid YAML'),
        );
      });

      test('an unreadable campaign throws the FileSystemException', () {
        expect(
          loadPerfCampaign('${dir.path}/absent.yaml'),
          throwsA(isA<FileSystemException>()),
        );
      });
    });
  });

  group('PerfCampaignException', () {
    test('prints every problem under one header', () {
      final PerfCampaignException e = PerfCampaignException(<String>[
        'a',
        'b',
      ]);

      expect(e.toString(), 'Invalid perf campaign:\n- a\n- b');
    });
  });
}
