import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/perf/scenario.dart';

/// A scenario every test mutates one axis of. It is valid as written, so a
/// test that expects a rejection proves the one line it changed is the cause.
const String _valid = '''
name: list-scroll-1440
viewport: {width: 1440, height: 900}
platforms: [chrome, android]
setup:
  - hot_restart
  - navigate: /monitors
  - wait_for_text: Monitors
  - wait_for_network_idle
steps:
  - tap: {target: {text: Monitors}}
  - fill: {target: {label: Search}, text: api}
  - drag: {target: {role: button, name: Row, index: 2}, dy: -600}
  - wheel: {target: {key: monitor-list}, dy: 1200}
    only: [chrome]
  - press_key: {key: Enter}
  - navigate: /monitors/1
  - wait: 400
repeat: 5
thresholds: {warn: 8, error: 20}
''';

/// Parses [source] and returns the problems it was rejected with.
List<String> _problems(String source) {
  try {
    PerfScenario.parse(source);
  } on PerfScenarioException catch (e) {
    return e.problems;
  }
  fail('expected the scenario to be rejected');
}

void main() {
  group('PerfScenario.parse()', () {
    test('reads every key of a valid scenario', () {
      final PerfScenario scenario = PerfScenario.parse(_valid);

      expect(scenario.name, 'list-scroll-1440');
      expect(scenario.viewport, (width: 1440, height: 900));
      expect(
        scenario.platforms,
        <PerfPlatform>{PerfPlatform.chrome, PerfPlatform.android},
      );
      expect(
        scenario.setup.map((PerfSetupStep s) => s.verb).toList(),
        <PerfSetupVerb>[
          PerfSetupVerb.hotRestart,
          PerfSetupVerb.navigate,
          PerfSetupVerb.waitForText,
          PerfSetupVerb.waitForNetworkIdle,
        ],
      );
      expect(scenario.setup[1].argument, '/monitors');
      expect(scenario.setup[2].argument, 'Monitors');
      expect(scenario.steps, hasLength(7));
      expect(scenario.repeat, 5);
      expect(scenario.thresholds.warnPct, 8);
      expect(scenario.thresholds.errorPct, 20);
    });

    test('maps each target form to its kind, value, role and index', () {
      final List<PerfStep> steps = PerfScenario.parse(_valid).steps;

      expect(steps[0].target!.kind, PerfTargetKind.text);
      expect(steps[0].target!.value, 'Monitors');
      expect(steps[1].target!.kind, PerfTargetKind.label);
      expect(steps[1].text, 'api');
      expect(steps[2].target!.kind, PerfTargetKind.role);
      expect(steps[2].target!.role, 'button');
      expect(steps[2].target!.value, 'Row');
      expect(steps[2].target!.index, 2);
      expect(steps[2].dy, -600);
      expect(steps[3].target!.kind, PerfTargetKind.key);
      expect(steps[3].only, <PerfPlatform>{PerfPlatform.chrome});
      expect(steps[4].key, 'Enter');
      expect(steps[5].route, '/monitors/1');
      expect(steps[6].ms, 400);
    });

    test('defaults platforms to all three, repeat to 3, thresholds to 10/25',
        () {
      final PerfScenario scenario = PerfScenario.parse('''
name: minimal
steps:
  - tap: {target: {text: Go}}
''');

      expect(scenario.platforms, PerfPlatform.values.toSet());
      expect(scenario.viewport, isNull);
      expect(scenario.setup, isEmpty);
      expect(scenario.repeat, 3);
      expect(scenario.thresholds.warnPct, 10);
      expect(scenario.thresholds.errorPct, 25);
    });

    test('a step runs only on the platforms its `only` names', () {
      final PerfStep wheel = PerfScenario.parse(_valid).steps[3];
      final PerfStep tap = PerfScenario.parse(_valid).steps[0];

      expect(wheel.runsOn(PerfPlatform.chrome), isTrue);
      expect(wheel.runsOn(PerfPlatform.android), isFalse);
      expect(tap.runsOn(PerfPlatform.android), isTrue);
    });

    test('rejects a literal e12 target', () {
      // A ref minted by one snapshot goes stale on the next navigate, so a
      // scenario that names one drives the wrong widget or none.
      final List<String> problems = _problems(
        _valid.replaceFirst(
          'tap: {target: {text: Monitors}}',
          'tap: {target: e12}',
        ),
      );

      expect(problems.join('\n'), contains('e12'));
      expect(problems.join('\n'), contains('resolved at run time'));
    });

    test('rejects a ref key in place of a target', () {
      final List<String> problems = _problems(
        _valid.replaceFirst(
          'tap: {target: {text: Monitors}}',
          'tap: {ref: q3}',
        ),
      );

      expect(problems.join('\n'), contains('steps[0]'));
    });

    test('rejects a wheel step without only: [chrome] when android is listed',
        () {
      final List<String> problems = _problems(
        _valid.replaceFirst('    only: [chrome]\n', ''),
      );

      expect(problems.join('\n'), contains('wheel'));
      expect(problems.join('\n'), contains('android'));
    });

    test('accepts a wheel step without only when chrome is the one platform',
        () {
      final PerfScenario scenario = PerfScenario.parse('''
name: web-only
platforms: [chrome]
steps:
  - wheel: {target: {text: List}, dy: 300}
''');

      expect(scenario.steps.single.verb, PerfStepVerb.wheel);
    });

    test('rejects a resize step that could run on ios', () {
      final List<String> problems = _problems('''
name: resize-everywhere
platforms: [chrome, ios]
steps:
  - resize: {width: 390, height: 844}
''');

      expect(problems.join('\n'), contains('resize'));
    });

    test('rejects a scenario name containing ../', () {
      final List<String> problems = _problems(
        _valid.replaceFirst('name: list-scroll-1440', 'name: ../escape'),
      );

      expect(problems.join('\n'), contains('name'));
      expect(problems.join('\n'), contains('[a-z0-9_-]'));
    });

    test('rejects a target naming two predicates at once', () {
      final List<String> problems = _problems(
        _valid.replaceFirst('{text: Monitors}', '{text: Monitors, key: k}'),
      );

      expect(problems.join('\n'), contains('exactly one of'));
    });

    test('rejects a role target without a name and an unknown role', () {
      final List<String> problems = _problems(
        _valid.replaceFirst(
          '{role: button, name: Row, index: 2}',
          '{role: slider}',
        ),
      );

      expect(problems.join('\n'), contains('name'));
      expect(problems.join('\n'), contains('slider'));
    });

    test('rejects an index on a key target, since a key names one widget', () {
      final List<String> problems = _problems(
        _valid.replaceFirst('{key: monitor-list}', '{key: k, index: 1}'),
      );

      expect(problems.join('\n'), contains('index'));
    });

    test('rejects an unknown verb, an empty step list and bad thresholds', () {
      final List<String> problems = _problems('''
name: broken
steps: []
thresholds: {warn: 30, error: 20}
''');

      expect(problems.join('\n'), contains('steps'));
      expect(problems.join('\n'), contains('warn'));

      final List<String> verb = _problems('''
name: broken
steps:
  - swipe: {target: {text: X}}
''');
      expect(verb.join('\n'), contains('swipe'));
    });

    test('reports every problem at once rather than the first', () {
      final List<String> problems = _problems('''
name: ../bad
repeat: 0
steps:
  - tap: {target: e1}
''');

      expect(problems.length, greaterThanOrEqualTo(3));
    });

    test('rejects a document that is not a map', () {
      expect(_problems('- just\n- a list\n'), isNotEmpty);
    });

    test('toJson carries the scenario for the run file', () {
      final Map<String, Object?> json = PerfScenario.parse(_valid).toJson();

      expect(json['name'], 'list-scroll-1440');
      expect(json['platforms'], <String>['chrome', 'android']);
      expect(json['repeat'], 5);
      expect(
        json['thresholds'],
        <String, Object?>{'warn': 8, 'error': 20},
      );
      expect((json['steps']! as List<Object?>).first, <String, Object?>{
        'tap': <String, Object?>{
          'target': <String, Object?>{'text': 'Monitors'},
        },
      });
    });
  });

  group('isSafePerfName()', () {
    test('accepts lowercase, digits, underscore and hyphen only', () {
      expect(isSafePerfName('before_fix-2'), isTrue);
      expect(isSafePerfName('../x'), isFalse);
      expect(isSafePerfName('A'), isFalse);
      expect(isSafePerfName(''), isFalse);
      expect(isSafePerfName('a/b'), isFalse);
    });
  });

  group('PerfThresholds', () {
    test('fromJson falls back to the defaults for a missing block', () {
      final PerfThresholds t = PerfThresholds.fromJson(null);
      expect(t.warnPct, 10);
      expect(t.errorPct, 25);
      expect(PerfThresholds.fromJson(<String, Object?>{'warn': 5}).warnPct, 5);
    });
  });
}
