import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_perf_run_command.dart';
import 'package:fluttersdk_dusk/src/perf/scenario.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// One call the runner made, in order.
typedef _Call = ({String method, Map<String, dynamic> params});

/// A driver that answers every extension from a script and records the
/// order of everything the runner did.
final class _FakeDriver implements PerfRunDriver {
  _FakeDriver({
    List<Map<String, dynamic>>? perfEnds,
    this.unresolved = const <String>{},
    this.observed = _kObserved,
  }) : perfEnds = perfEnds ?? <Map<String, dynamic>>[];

  /// The interactive nodes `ext.dusk.observe` lists, as `dusk:snap` shows
  /// them: a role and the merged label.
  final List<Map<String, dynamic>> observed;

  /// Answers to successive `ext.dusk.perf_end` calls; the last repeats.
  final List<Map<String, dynamic>> perfEnds;

  /// Texts `ext.dusk.find` reports no match for.
  final Set<String> unresolved;

  final List<_Call> calls = <_Call>[];
  int restarts = 0;
  bool closed = false;
  int _ends = 0;

  List<String> get methods => calls.map((_Call c) => c.method).toList();

  List<_Call> callsTo(String method) =>
      calls.where((_Call c) => c.method == method).toList();

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, String> params = const <String, String>{},
  ]) async {
    calls.add((method: method, params: params));
    switch (method) {
      case 'ext.dusk.find':
        final bool miss = unresolved.contains(params['text']);
        return <String, dynamic>{
          'ref': miss ? null : 'q1',
          'matched': !miss,
        };
      case 'ext.dusk.find_by_label':
        // What the live app answers: find_by_label walks only the root
        // pipeline owner, which holds no semantics tree, so it finds nothing.
        return <String, dynamic>{'refs': <String>[]};
      case 'ext.dusk.find_by_text':
        return <String, dynamic>{
          'refs': <String>['e1', 'e2', 'e3'],
        };
      case 'ext.dusk.observe':
        final Set<String> roles = (params['roles'] ?? '').split(',').toSet();
        return <String, dynamic>{
          'candidates': <Map<String, dynamic>>[
            for (final Map<String, dynamic> c in observed)
              if (roles.contains(c['role'])) c,
          ],
        };
      case 'ext.dusk.tap':
      case 'ext.dusk.hover':
        return <String, dynamic>{
          'ref': params['ref'],
          if (params['reportPoint'] == 'true')
            'point': <String, dynamic>{'x': 11.0, 'y': 22.0},
        };
      case 'ext.dusk.drag':
        return <String, dynamic>{
          if (params['reportPoint'] == 'true') ...<String, dynamic>{
            'from': <String, dynamic>{'x': 5.0, 'y': 300.0},
            'to': <String, dynamic>{'x': 5.0, 'y': 0.0},
          },
        };
      case 'ext.dusk.wait_for':
        return <String, dynamic>{'matched': true};
      case 'ext.dusk.perf_begin':
        return <String, dynamic>{'sessionToken': 'perf-${calls.length}'};
      case 'ext.dusk.perf_end':
        if (perfEnds.isEmpty) return _report(painted: 40);
        final Map<String, dynamic> next =
            perfEnds[_ends < perfEnds.length ? _ends : perfEnds.length - 1];
        _ends++;
        return next;
      default:
        return <String, dynamic>{'ok': true};
    }
  }

  @override
  Future<Map<String, dynamic>> cdp(
    String method, [
    Map<String, dynamic> params = const <String, dynamic>{},
  ]) async {
    calls.add((method: 'cdp:$method', params: params));
    return <String, dynamic>{};
  }

  @override
  Future<void> restart() async {
    restarts++;
    calls.add((method: 'restart', params: const <String, dynamic>{}));
  }

  @override
  Future<void> pause(Duration duration) async {
    calls.add((
      method: 'pause',
      params: <String, dynamic>{'ms': duration.inMilliseconds},
    ));
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

/// A screen with a heading and three buttons, two of them named `Row`.
const List<Map<String, dynamic>> _kObserved = <Map<String, dynamic>>[
  <String, dynamic>{'ref': 'q1', 'role': 'heading', 'label': 'Row'},
  <String, dynamic>{'ref': 'q2', 'role': 'button', 'label': 'Row'},
  <String, dynamic>{'ref': 'q3', 'role': 'button', 'label': 'Add'},
  <String, dynamic>{'ref': 'q4', 'role': 'button', 'label': 'Row'},
];

/// A bounded-shape `perf_end` report with a block and a wind counter whose
/// per-frame values are derived from [painted].
Map<String, dynamic> _report({
  required int painted,
  double rowsPerFrame = 2,
  double wDivPerFrame = 30,
  double buildP50 = 4,
  String mode = 'attribution',
  List<Map<String, dynamic>> insights = const <Map<String, dynamic>>[],
}) {
  return <String, dynamic>{
    'sessionToken': 'perf-x',
    'refused': false,
    'mode': mode,
    'env': <String, dynamic>{
      'platform': 'macOS',
      'isWeb': true,
      'buildMode': 'debug',
      'semanticsEnabled': true,
    },
    'coverage': <String, dynamic>{
      'framesDrawn': painted,
      'framesSummarized': painted,
      'complete': true,
      'missing': <String>[],
    },
    'summary': <String, dynamic>{
      'budgetMs': 16.7,
      'frames': <String, dynamic>{
        'count': painted,
        'painted': painted,
        'dropped': 0,
        'overBudget': 1,
        'buildMs': <String, dynamic>{
          'p50': buildP50,
          'p90': buildP50 * 2,
          'p99': 20.0,
          'worst': 30.0,
        },
        'rasterMs': <String, dynamic>{
          'p50': 3.0,
          'p90': 5.0,
          'p99': 9.0,
          'worst': 12.0,
        },
      },
      if (mode == 'attribution')
        'blocksByCount': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'MonitorRow',
            'count': (rowsPerFrame * painted).round(),
            'perFrame': rowsPerFrame,
          },
        ],
    },
    'counters': mode == 'attribution'
        ? <String, dynamic>{
            'columns': <String>['name', 'count', 'perFrame'],
            'wind': <String, dynamic>{
              'wDivBuilds': <String, dynamic>{
                'count': (wDivPerFrame * painted).round(),
                'perFrame': wDivPerFrame,
              },
              'cacheSize': 12,
            },
            'magic': <String, dynamic>{
              'controllerNotifies': <List<Object?>>[
                <Object?>['MonitorController', painted, 1.0],
              ],
            },
          }
        : null,
    'insights': insights,
    'omitted': <String, dynamic>{},
  };
}

const Map<String, dynamic> _refused = <String, dynamic>{
  'sessionToken': 'perf-r',
  'refused': true,
  'mode': 'attribution',
  'reason': 'the liveness counter advanced by 1',
};

const String _scenario = '''
name: list-scroll
viewport: {width: 1440, height: 900}
platforms: [chrome, android]
setup:
  - hot_restart
  - navigate: /monitors
  - wait_for_text: Monitors
steps:
  - tap: {target: {text: Monitors}}
  - wheel: {target: {text: List}, dy: 1200}
    only: [chrome]
  - drag: {target: {role: button, name: Row, index: 1}, dy: -300}
    only: [android]
  - wait: 200
repeat: 3
''';

/// Runs the command against [driver] with [options], [platform] as the
/// connected target.
Future<(int, String)> _run(
  _FakeDriver driver,
  Map<String, dynamic> options, {
  PerfPlatform platform = PerfPlatform.chrome,
  String restartMode = 'hot_restart',
}) async {
  final BufferedOutput output = BufferedOutput();
  final DuskPerfRunCommand command = DuskPerfRunCommand(
    connector: (ArtisanContext ctx, PerfPlatform? requested) async => (
      driver,
      PerfRunEnvironment(
        platform: requested ?? platform,
        device: 'chrome',
        restartMode: restartMode,
        host: const <String, Object?>{'uname': 'Darwin 25.0 arm64'},
        renderer: 'unknown',
      ),
    ),
  );
  final int code = await command.handle(
    ArtisanContext.bare(MapInput(options), output),
  );
  return (code, output.content);
}

void main() {
  late Directory temp;
  late String scenarioPath;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dusk_perf_run_test_');
    scenarioPath = '${temp.path}/list-scroll.yaml';
    await File(scenarioPath).writeAsString(_scenario);
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Map<String, dynamic> readRun(String name, String label) =>
      jsonDecode(File('${temp.path}/out/$name-$label.json').readAsStringSync())
          as Map<String, dynamic>;

  Map<String, dynamic> options([Map<String, dynamic> extra = const {}]) =>
      <String, dynamic>{
        'scenario': scenarioPath,
        'label': 'base',
        'out': '${temp.path}/out',
        ...extra,
      };

  // -------------------------------------------------------------------------
  // Statistics
  // -------------------------------------------------------------------------

  group('perfMedian()', () {
    test('is the middle value, or the mean of the two middle ones', () {
      expect(perfMedian(<num>[3, 1, 2]), 2);
      expect(perfMedian(<num>[4, 1, 3, 2]), 2.5);
      expect(perfMedian(<num>[7]), 7);
    });
  });

  group('perfSpread()', () {
    test('reports min, max and the range as a share of the median', () {
      expect(perfSpread(<num>[9, 10, 11]), <String, Object?>{
        'min': 9,
        'max': 11,
        'rangePct': 20.0,
      });
    });

    test('a zero median has no relative range', () {
      expect(perfSpread(<num>[0, 0])['rangePct'], isNull);
    });
  });

  group('perfPerFrameMetrics()', () {
    test('flattens blocks and counters to per-frame values, gauges excluded',
        () {
      final Map<String, double> metrics = perfPerFrameMetrics(
        _report(painted: 40, rowsPerFrame: 2.5, wDivPerFrame: 31),
      );

      expect(metrics['blocks.MonitorRow'], 2.5);
      expect(metrics['wind.wDivBuilds'], 31);
      expect(metrics['magic.controllerNotifies.MonitorController'], 1.0);
      expect(metrics.containsKey('wind.cacheSize'), isFalse);
    });

    test('divides a raw count by painted frames when perFrame is absent', () {
      final Map<String, dynamic> report = _report(painted: 10);
      ((report['summary'] as Map<String, dynamic>)['blocksByCount']
              as List<Map<String, dynamic>>)
          .first
          .remove('perFrame');

      expect(perfPerFrameMetrics(report)['blocks.MonitorRow'], 2);
    });
  });

  group('summarizePerfSeries()', () {
    test('takes medians over measured repeats and leaves refusals out', () {
      final Map<String, Object?> summary = summarizePerfSeries(
        <Map<String, dynamic>>[
          _report(painted: 40, rowsPerFrame: 2),
          _refused,
          _report(painted: 44, rowsPerFrame: 3),
          _report(painted: 42, rowsPerFrame: 2.2),
        ],
      );

      expect(summary['repeats'], 3);
      expect(summary['refused'], 1);
      expect((summary['frames']! as Map<String, Object?>)['painted'], 42);
      expect(
        (summary['perFrame']! as Map<String, Object?>)['blocks.MonitorRow'],
        2.2,
      );
      final Map<String, Object?> spread =
          summary['spread']! as Map<String, Object?>;
      expect(
        (spread['perFrame']! as Map<String, Object?>)['blocks.MonitorRow'],
        <String, Object?>{'min': 2.0, 'max': 3.0, 'rangePct': 45.5},
      );
      expect((summary['ms']! as Map<String, Object?>)['buildMs.p50'], 4);
    });

    test('a metric missing from one repeat counts as zero there', () {
      final Map<String, dynamic> without = _report(painted: 10);
      (without['summary'] as Map<String, dynamic>)['blocksByCount'] =
          <Map<String, dynamic>>[];

      final Map<String, Object?> summary = summarizePerfSeries(
        <Map<String, dynamic>>[
          _report(painted: 10, rowsPerFrame: 4),
          without,
          without,
        ],
      );

      expect(
        (summary['perFrame']! as Map<String, Object?>)['blocks.MonitorRow'],
        0,
      );
    });

    test('a series of refusals only has counts', () {
      expect(
        summarizePerfSeries(<Map<String, dynamic>>[_refused, _refused]),
        <String, Object?>{'repeats': 0, 'refused': 2},
      );
    });
  });

  // -------------------------------------------------------------------------
  // Environment helpers
  // -------------------------------------------------------------------------

  group('resolvePerfPlatform()', () {
    test('an explicit platform wins', () {
      expect(
        resolvePerfPlatform(<String, dynamic>{'device': 'chrome'}, 'android'),
        PerfPlatform.android,
      );
    });

    test('reads chrome, an android emulator and an iOS simulator UDID', () {
      expect(
        resolvePerfPlatform(<String, dynamic>{'device': 'web-server'}, null),
        PerfPlatform.chrome,
      );
      expect(
        resolvePerfPlatform(<String, dynamic>{'device': 'emulator-5554'}, null),
        PerfPlatform.android,
      );
      expect(
        resolvePerfPlatform(
          <String, dynamic>{'device': '0D5E3E4C-7A2B-4C47-9E5B-1B6F5B0F9A11'},
          null,
        ),
        PerfPlatform.ios,
      );
    });

    test('an unknown device throws naming --platform', () {
      expect(
        () => resolvePerfPlatform(<String, dynamic>{'device': 'R5CT'}, null),
        throwsA(
          isA<PerfRunException>().having(
            (PerfRunException e) => e.message,
            'message',
            contains('--platform'),
          ),
        ),
      );
    });
  });

  group('perfRestartMode()', () {
    test('a profile build relaunches, a debug build hot restarts', () {
      expect(perfRestartMode(<String, dynamic>{'profile': 'debug'}),
          'hot_restart');
      expect(
          perfRestartMode(<String, dynamic>{'profile': 'static'}), 'relaunch');
      expect(
        perfRestartMode(<String, dynamic>{
          'profile': 'debug',
          'flutterArgs': <String>['--profile'],
        }),
        'relaunch',
      );
    });
  });

  group('scrapePerfRenderer()', () {
    test('reads the Impeller backend line, else unknown', () {
      expect(
        scrapePerfRenderer(
          'I/flutter: Using the Impeller rendering backend (Vulkan).',
        ),
        'impeller-vulkan',
      );
      expect(scrapePerfRenderer('nothing here'), 'unknown');
      expect(scrapePerfRenderer(null), 'unknown');
    });
  });

  // -------------------------------------------------------------------------
  // handle()
  // -------------------------------------------------------------------------

  group('DuskPerfRunCommand', () {
    test('name is dusk:perf_run and boot is connected', () {
      expect(DuskPerfRunCommand().name, 'dusk:perf_run');
      expect(DuskPerfRunCommand().boot, CommandBoot.connected);
    });

    test('writes the run file with summary, insights, repeats and env',
        () async {
      final _FakeDriver driver = _FakeDriver(
        perfEnds: <Map<String, dynamic>>[
          _report(painted: 40, rowsPerFrame: 2),
          _report(
            painted: 42,
            rowsPerFrame: 2.1,
            insights: <Map<String, dynamic>>[
              <String, dynamic>{'id': 'I1', 'severity': 'warn', 'title': 'x'},
            ],
          ),
          _report(painted: 44, rowsPerFrame: 2.4),
        ],
      );

      final (int code, String out) = await _run(driver, options());

      expect(code, 0);
      final Map<String, dynamic> run = readRun('list-scroll', 'base');
      expect(run['label'], 'base');
      expect((run['scenario'] as Map<String, dynamic>)['name'], 'list-scroll');
      expect((run['repeats'] as List<dynamic>), hasLength(3));
      expect((run['summary'] as Map<String, dynamic>)['repeats'], 3);
      final Map<String, dynamic> env = run['env'] as Map<String, dynamic>;
      expect(env['buildMode'], 'debug');
      expect(env['restartMode'], 'hot_restart');
      expect(env['renderer'], 'unknown');
      expect(env['host'], <String, dynamic>{'uname': 'Darwin 25.0 arm64'});
      expect(env['target'], 'chrome');
      // The median repeat by per-frame counts is the second one.
      expect((run['insights'] as List<dynamic>).single['id'], 'I1');
      expect(out, contains('list-scroll-base.json'));
      expect(driver.closed, isTrue);
    });

    test('the default connector refuses a context with no running app',
        () async {
      final BufferedOutput output = BufferedOutput();

      final int code = await DuskPerfRunCommand().handle(
        ArtisanContext.bare(MapInput(options()), output),
      );

      expect(code, 1);
      expect(output.content, contains('artisan start'));
    });

    test('a --repeat that is not a positive integer is rejected', () async {
      final (int code, String out) =
          await _run(_FakeDriver(), options(<String, dynamic>{'repeat': '0'}));

      expect(code, 1);
      expect(out, contains('--repeat'));
    });

    test('perf_end is asked for the full report', () async {
      final _FakeDriver driver = _FakeDriver();

      await _run(driver, options());

      expect(
        driver.callsTo('ext.dusk.perf_end').first.params['full'],
        'true',
      );
    });

    test('--json prints the same object minus repeats[]', () async {
      final _FakeDriver driver = _FakeDriver();

      final (int code, String out) =
          await _run(driver, options(<String, dynamic>{'json': true}));

      expect(code, 0);
      final Map<String, dynamic> printed =
          jsonDecode(out.trim()) as Map<String, dynamic>;
      expect(printed.containsKey('repeats'), isFalse);
      expect(printed['summary'], readRun('list-scroll', 'base')['summary']);
      expect(printed['path'], endsWith('list-scroll-base.json'));
    });

    test('setup runs before every repeat and each session is brought to front',
        () async {
      final _FakeDriver driver = _FakeDriver();

      await _run(driver, options());

      expect(driver.restarts, 3);
      final List<String> m = driver.methods;
      // Viewport, restart, viewport again, navigate, wait, front, begin.
      final int firstBegin = m.indexOf('ext.dusk.perf_begin');
      expect(
        m.sublist(0, firstBegin),
        <String>[
          'cdp:Emulation.setDeviceMetricsOverride',
          'restart',
          'cdp:Emulation.setDeviceMetricsOverride',
          'ext.dusk.navigate',
          'ext.dusk.wait_for',
          'cdp:Page.bringToFront',
        ],
      );
      expect(driver.callsTo('cdp:Page.bringToFront'), hasLength(3));
    });

    test('drives chrome steps and skips the android-only drag', () async {
      final _FakeDriver driver = _FakeDriver();

      await _run(driver, options(<String, dynamic>{'repeat': '1'}));

      final List<String> m = driver.methods;
      final int begin = m.indexOf('ext.dusk.perf_begin');
      final int end = m.indexOf('ext.dusk.perf_end');
      expect(
        m.sublist(begin + 1, end),
        <String>[
          'ext.dusk.find',
          'ext.dusk.tap',
          'ext.dusk.find',
          'ext.dusk.hover',
          'cdp:Input.dispatchMouseEvent',
          'pause',
          'pause',
        ],
      );
      final _Call wheel = driver.callsTo('cdp:Input.dispatchMouseEvent').single;
      expect(wheel.params['type'], 'mouseWheel');
      expect(wheel.params['x'], 11.0);
      expect(wheel.params['deltaY'], 1200.0);
      expect(
        driver.callsTo('ext.dusk.tap').single.params['includeSnapshot'],
        'false',
      );
    });

    test('on android the drag resolves its role target and runs by offset',
        () async {
      final _FakeDriver driver = _FakeDriver();

      await _run(
        driver,
        options(<String, dynamic>{'repeat': '1'}),
        platform: PerfPlatform.android,
      );

      expect(driver.callsTo('cdp:Input.dispatchMouseEvent'), isEmpty);
      expect(driver.callsTo('cdp:Page.bringToFront'), isEmpty);
      final _Call observe = driver.callsTo('ext.dusk.observe').single;
      expect(observe.params['roles'], 'button');
      expect(observe.params['includeEnrichers'], 'false');
      final _Call drag = driver.callsTo('ext.dusk.drag').single;
      // The second button named Row: the heading shares the name, not the
      // role, and the Add button shares neither.
      expect(drag.params['startRef'], 'q4');
      expect(drag.params['dy'], '-300.0');
    });

    test('a role target matching no role and name fails naming the target',
        () async {
      final _FakeDriver driver = _FakeDriver(
        observed: const <Map<String, dynamic>>[
          <String, dynamic>{'ref': 'q1', 'role': 'button', 'label': 'Row'},
        ],
      );

      final (int code, String out) = await _run(
        driver,
        options(<String, dynamic>{'repeat': '1'}),
        platform: PerfPlatform.android,
      );

      expect(code, 1);
      expect(out, contains('"role":"button","name":"Row","index":1'));
      expect(out, contains('matched nothing'));
    });

    test('a gesture in setup runs before perf_begin, outside the window',
        () async {
      await File(scenarioPath).writeAsString(
        _scenario.replaceFirst(
          '  - wait_for_text: Monitors\n',
          '  - wait_for_text: Monitors\n'
              '  - tap: {target: {text: perf-monitor-0000}}\n'
              '  - wait: 150\n',
        ),
      );
      final _FakeDriver driver = _FakeDriver();

      final (int code, _) =
          await _run(driver, options(<String, dynamic>{'repeat': '1'}));

      expect(code, 0);
      final List<String> m = driver.methods;
      final int begin = m.indexOf('ext.dusk.perf_begin');
      expect(
        m.sublist(0, begin),
        <String>[
          'cdp:Emulation.setDeviceMetricsOverride',
          'restart',
          'cdp:Emulation.setDeviceMetricsOverride',
          'ext.dusk.navigate',
          'ext.dusk.wait_for',
          'ext.dusk.find',
          'ext.dusk.tap',
          'pause',
          'cdp:Page.bringToFront',
        ],
      );
      expect(
        driver.callsTo('ext.dusk.find').first.params,
        <String, dynamic>{'text': 'perf-monitor-0000'},
      );
      expect(
        driver.callsTo('ext.dusk.tap').first.params['includeSnapshot'],
        'false',
      );
    });

    test('a setup gesture that matches nothing fails before perf_begin',
        () async {
      await File(scenarioPath).writeAsString(
        _scenario.replaceFirst(
          '  - wait_for_text: Monitors\n',
          '  - wait_for_text: Monitors\n'
              '  - tap: {target: {text: Gone}}\n',
        ),
      );
      final _FakeDriver driver = _FakeDriver(unresolved: <String>{'Gone'});

      final (int code, String out) = await _run(driver, options());

      expect(code, 1);
      expect(out, contains('list-scroll setup[3] (tap)'));
      expect(out, contains('Gone'));
      expect(driver.callsTo('ext.dusk.perf_begin'), isEmpty);
    });

    test('a refused repeat is recorded, not averaged, and the run exits 0',
        () async {
      final _FakeDriver driver = _FakeDriver(
        perfEnds: <Map<String, dynamic>>[
          _report(painted: 40),
          _refused,
          _report(painted: 50),
        ],
      );

      final (int code, _) = await _run(driver, options());

      expect(code, 0);
      final Map<String, dynamic> run = readRun('list-scroll', 'base');
      expect((run['summary'] as Map<String, dynamic>)['refused'], 1);
      expect((run['summary'] as Map<String, dynamic>)['repeats'], 2);
      expect(
        ((run['summary'] as Map<String, dynamic>)['frames']
            as Map<String, dynamic>)['painted'],
        45,
      );
      expect((run['repeats'] as List<dynamic>)[1]['refused'], isTrue);
    });

    test('every repeat refused exits 1 and still writes the file', () async {
      final _FakeDriver driver = _FakeDriver(
        perfEnds: <Map<String, dynamic>>[_refused],
      );

      final (int code, String out) = await _run(driver, options());

      expect(code, 1);
      expect(out, contains('refused'));
      expect(readRun('list-scroll', 'base')['repeats'], hasLength(3));
    });

    test('a label outside [a-z0-9_-] is rejected before anything runs',
        () async {
      final _FakeDriver driver = _FakeDriver();

      final (int code, String out) = await _run(
        driver,
        options(<String, dynamic>{'label': '../escape'}),
      );

      expect(code, 1);
      expect(out, contains('[a-z0-9_-]'));
      expect(driver.calls, isEmpty);
    });

    test('an invalid scenario lists its problems and runs nothing', () async {
      await File(scenarioPath).writeAsString('name: ../x\nsteps: []\n');
      final _FakeDriver driver = _FakeDriver();

      final (int code, String out) = await _run(driver, options());

      expect(code, 1);
      expect(out, contains('name'));
      expect(out, contains('steps'));
      expect(driver.calls, isEmpty);
    });

    test('a missing scenario argument exits 1', () async {
      final (int code, String out) = await _run(
        _FakeDriver(),
        <String, dynamic>{'label': 'base'},
      );

      expect(code, 1);
      expect(out, contains('scenario'));
    });

    test('a platform the scenario does not list is refused', () async {
      final _FakeDriver driver = _FakeDriver();

      final (int code, String out) = await _run(
        driver,
        options(),
        platform: PerfPlatform.ios,
      );

      expect(code, 1);
      expect(out, contains('ios'));
      expect(driver.calls, isEmpty);
    });

    test(
        'a target that matches nothing fails the run after closing the '
        'session', () async {
      final _FakeDriver driver = _FakeDriver(unresolved: <String>{'List'});

      final (int code, String out) = await _run(driver, options());

      expect(code, 1);
      expect(out, contains('List'));
      expect(driver.callsTo('ext.dusk.perf_end'), hasLength(1));
      expect(driver.closed, isTrue);
    });

    test('--timing interleaves timing repeats, alternating the order',
        () async {
      final _FakeDriver driver = _FakeDriver(
        perfEnds: <Map<String, dynamic>>[
          _report(painted: 40),
          _report(painted: 40, mode: 'timing', buildP50: 2),
          _report(painted: 40, mode: 'timing', buildP50: 3),
          _report(painted: 40),
          _report(painted: 40),
          _report(painted: 40, mode: 'timing', buildP50: 4),
        ],
      );

      final (int code, _) =
          await _run(driver, options(<String, dynamic>{'timing': true}));

      expect(code, 0);
      expect(
        driver
            .callsTo('ext.dusk.perf_begin')
            .map((_Call c) => c.params['mode'])
            .toList(),
        <String>[
          'attribution',
          'timing',
          'timing',
          'attribution',
          'attribution',
          'timing',
        ],
      );
      final Map<String, dynamic> timing =
          (readRun('list-scroll', 'base')['summary']
              as Map<String, dynamic>)['timing'] as Map<String, dynamic>;
      expect(timing['repeats'], 3);
      expect((timing['ms'] as Map<String, dynamic>)['buildMs.p50'], 3);
    });

    test('--against runs both scenarios interleaved and writes both files',
        () async {
      final String baseline = '${temp.path}/baseline.yaml';
      await File(baseline).writeAsString(
        _scenario.replaceFirst('name: list-scroll', 'name: list-baseline'),
      );
      final _FakeDriver driver = _FakeDriver();

      final (int code, _) = await _run(
        driver,
        options(<String, dynamic>{'against': baseline, 'repeat': '2'}),
      );

      expect(code, 0);
      expect(
          readRun('list-scroll', 'base')['interleavedWith'], 'list-baseline');
      expect(
          readRun('list-baseline', 'base')['interleavedWith'], 'list-scroll');
      // Round 0 runs A then B, round 1 runs B then A: navigate is the first
      // setup call of each unit, so its count tracks the units.
      expect(driver.callsTo('ext.dusk.perf_begin'), hasLength(4));
    });

    group('--semantics-pass', () {
      test('replays recorded points with the handle released in the window',
          () async {
        final _FakeDriver driver = _FakeDriver();

        final (int code, _) = await _run(
          driver,
          options(<String, dynamic>{'semantics-pass': true, 'repeat': '1'}),
        );

        expect(code, 0);
        final List<String> m = driver.methods;
        final int release = m.indexWhere(
          (String s) => s == 'ext.dusk.semantics_hold',
        );
        final List<_Call> holds = driver.callsTo('ext.dusk.semantics_hold');
        expect(
          holds.map((_Call c) => c.params['action']).toList(),
          <String>['release', 'acquire'],
        );
        // Released after the second perf_begin, acquired before its perf_end.
        expect(m.lastIndexOf('ext.dusk.perf_begin'), lessThan(release));
        final int acquire = m.lastIndexOf('ext.dusk.semantics_hold');
        expect(acquire, lessThan(m.lastIndexOf('ext.dusk.perf_end')));
        // Inside the window nothing resolves a target: coordinates only.
        final List<String> window = m.sublist(release, acquire);
        expect(window, isNot(contains('ext.dusk.find')));
        expect(window, isNot(contains('ext.dusk.hover')));
        final _Call tap = driver.callsTo('ext.dusk.tap').last;
        expect(tap.params, <String, dynamic>{'x': '11.0', 'y': '22.0'});

        final Map<String, dynamic> run = readRun('list-scroll', 'base');
        expect(run['semanticsPass'], 'measured');
        final Map<String, dynamic> off =
            run['semanticsOff'] as Map<String, dynamic>;
        expect((off['summary'] as Map<String, dynamic>)['repeats'], 1);
        expect(off['repeats'], hasLength(1));
      });

      test('the tap in the recording pass asked for its point', () async {
        final _FakeDriver driver = _FakeDriver();

        await _run(
          driver,
          options(<String, dynamic>{'semantics-pass': true, 'repeat': '1'}),
        );

        expect(
          driver.callsTo('ext.dusk.tap').first.params['reportPoint'],
          'true',
        );
      });

      test('on android the drag replays between its recorded points', () async {
        final _FakeDriver driver = _FakeDriver();

        await _run(
          driver,
          options(<String, dynamic>{'semantics-pass': true, 'repeat': '1'}),
          platform: PerfPlatform.android,
        );

        expect(driver.callsTo('ext.dusk.drag').last.params, <String, dynamic>{
          'x': '5.0',
          'y': '300.0',
          'toX': '5.0',
          'toY': '0.0',
        });
      });

      test('a step it cannot replay records unsupported and skips the pass',
          () async {
        await File(scenarioPath).writeAsString(
          _scenario.replaceFirst(
            '  - wait: 200',
            '  - fill: {target: {label: Search}, text: api}',
          ),
        );
        final _FakeDriver driver = _FakeDriver();

        final (int code, _) = await _run(
          driver,
          options(<String, dynamic>{'semantics-pass': true, 'repeat': '1'}),
        );

        expect(code, 0);
        expect(driver.callsTo('ext.dusk.semantics_hold'), isEmpty);
        final Map<String, dynamic> run = readRun('list-scroll', 'base');
        expect(run['semanticsPass'], 'unsupported');
        expect(run['semanticsPassReason'], contains('fill'));
        expect(run.containsKey('semanticsOff'), isFalse);
      });

      test('a failed acquire still closes the session with perf_end', () async {
        final _FakeDriver driver = _FailingAcquireDriver();

        final (int code, _) = await _run(
          driver,
          options(<String, dynamic>{'semantics-pass': true, 'repeat': '1'}),
        );

        expect(code, 0);
        final List<String> m = driver.methods;
        expect(
          m.lastIndexOf('ext.dusk.perf_end'),
          greaterThan(m.lastIndexOf('ext.dusk.semantics_hold')),
        );
        expect(
          readRun('list-scroll', 'base')['semanticsPassReason'],
          contains('acquire failed'),
        );
      });

      test('a replay that fails re-acquires, closes and records unsupported',
          () async {
        final _FakeDriver driver = _FailingReplayDriver();

        final (int code, _) = await _run(
          driver,
          options(<String, dynamic>{'semantics-pass': true, 'repeat': '1'}),
        );

        expect(code, 0);
        expect(
          driver
              .callsTo('ext.dusk.semantics_hold')
              .map((_Call c) => c.params['action'])
              .toList(),
          <String>['release', 'acquire'],
        );
        expect(driver.callsTo('ext.dusk.perf_end'), hasLength(2));
        final Map<String, dynamic> run = readRun('list-scroll', 'base');
        expect(run['semanticsPass'], 'unsupported');
        expect(run['semanticsPassReason'], contains('coordinates'));
      });
    });
  });

  // -------------------------------------------------------------------------
  // The restart wait
  // -------------------------------------------------------------------------

  group('awaitDuskBoot()', () {
    const Duration tick = Duration(milliseconds: 1);

    test(
        'returns once the boot id changes, though the isolate id stays "1" '
        'as it does under DWDS', () async {
      final _FakeVmClient vm = _FakeVmClient(<Object>[
        'boot-a',
        Exception('RPCError -32603: ext.dusk.boot_id is not registered'),
        StateError('VM Service reported no isolates'),
        'boot-b',
      ]);

      await awaitDuskBoot(
        vm,
        replacing: 'boot-a',
        timeout: const Duration(seconds: 5),
        pollInterval: tick,
      );

      expect(vm.isolateIds.toSet(), <String>{'1'});
      expect(vm.answered, 4);
    });

    test('times out with the restart message while the boot id never changes',
        () async {
      final _FakeVmClient vm = _FakeVmClient(<Object>['boot-a']);

      await expectLater(
        awaitDuskBoot(
          vm,
          replacing: 'boot-a',
          timeout: const Duration(milliseconds: 50),
          pollInterval: tick,
        ),
        throwsA(
          isA<PerfRunException>().having(
            (PerfRunException e) => e.message,
            'message',
            contains('the app did not come back within 0 s of the restart'),
          ),
        ),
      );
    });

    test('names the last error when the app never answers', () async {
      final _FakeVmClient vm = _FakeVmClient(<Object>[
        Exception('RPCError -32601: method not found'),
      ]);

      await expectLater(
        awaitDuskBoot(
          vm,
          replacing: 'boot-a',
          timeout: const Duration(milliseconds: 50),
          pollInterval: tick,
        ),
        throwsA(
          isA<PerfRunException>().having(
            (PerfRunException e) => e.message,
            'message',
            contains('-32601'),
          ),
        ),
      );
    });

    test('after a relaunch the first boot id that answers is enough', () async {
      final _FakeVmClient vm = _FakeVmClient(<Object>[
        StateError('VM Service reported no isolates'),
        'boot-z',
      ]);

      await awaitDuskBoot(
        vm,
        replacing: null,
        timeout: const Duration(seconds: 5),
        pollInterval: tick,
      );

      expect(vm.answered, 2);
    });
  });

  group('readDuskBootId()', () {
    test('asks the main isolate for ext.dusk.boot_id', () async {
      final _FakeVmClient vm = _FakeVmClient(<Object>['boot-a']);

      expect(await readDuskBootId(vm), 'boot-a');
      expect(vm.methods.single, 'ext.dusk.boot_id');
    });
  });
}

/// A VM Service client whose main isolate is always `"1"`, as DWDS reports
/// it across a hot restart, and whose `ext.dusk.boot_id` answers come from
/// a script: a String is a boot id, anything else is thrown. The last entry
/// repeats.
final class _FakeVmClient implements VmServiceClient {
  _FakeVmClient(this.script);

  final List<Object> script;
  final List<String> isolateIds = <String>[];
  final List<String> methods = <String>[];
  int answered = 0;

  @override
  Future<String> getMainIsolateId() async => '1';

  @override
  Future<List<String>> getExtensionRPCs(String isolateId) async =>
      const <String>['ext.dusk.perf_begin', 'ext.dusk.boot_id'];

  @override
  Future<T> callServiceExtension<T>(
    String method, {
    required String isolateId,
    Map<String, dynamic>? params,
  }) async {
    methods.add(method);
    isolateIds.add(isolateId);
    final Object next =
        script[answered < script.length ? answered : script.length - 1];
    answered++;
    if (next is String) return <String, dynamic>{'bootId': next} as T;
    throw next;
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Fails the re-acquire at the end of the semantics window.
final class _FailingAcquireDriver extends _FakeDriver {
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, String> params = const <String, String>{},
  ]) async {
    if (method == 'ext.dusk.semantics_hold' && params['action'] == 'acquire') {
      calls.add((method: method, params: params));
      throw Exception('acquire failed');
    }
    return super.call(method, params);
  }
}

/// Fails the coordinate tap the semantics pass replays.
final class _FailingReplayDriver extends _FakeDriver {
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, String> params = const <String, String>{},
  ]) async {
    if (method == 'ext.dusk.tap' && params.containsKey('x')) {
      calls.add((method: method, params: params));
      throw Exception('coordinates rejected');
    }
    return super.call(method, params);
  }
}
