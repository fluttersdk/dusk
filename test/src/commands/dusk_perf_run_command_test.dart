import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_perf_run_command.dart';
import 'package:fluttersdk_dusk/src/perf/perf_run_driver.dart';
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
    this.waitMisses = 0,
    Map<String, int>? findMisses,
    this.navigateHonoured = true,
    this.redirectOnIdle,
    this.exceptions = const <Map<String, dynamic>>[],
    this.routerMountReads = 0,
    this.answersUri = true,
    this.landingReads,
    this.landsOn,
    this.releaseAnswer = _kReleasedOff,
  })  : perfEnds = perfEnds ?? <Map<String, dynamic>>[],
        findMisses = findMisses ?? <String, int>{};

  /// What `ext.dusk.semantics_hold action=release` answers. The default is a
  /// release that turned the tree off, what a native app with no screen
  /// reader answers.
  final Map<String, dynamic> releaseAnswer;

  /// How many `ext.dusk.wait_for` calls answer `matched: false` before the
  /// text shows up.
  int waitMisses;

  /// How many `ext.dusk.find` calls for a text answer no match before the
  /// text shows up, by text.
  final Map<String, int> findMisses;

  /// Whether `ext.dusk.navigate` answers `navigated: true`.
  final bool navigateHonoured;

  /// The route the app moves to once the network goes idle, as an auth
  /// redirect does after the first fetch answers 401; null stays put.
  final String? redirectOnIdle;

  /// What `ext.dusk.exceptions` lists, newest first.
  final List<Map<String, dynamic>> exceptions;

  /// What `ext.dusk.get_routes` answers as the location: the top page's
  /// name, which a Router-based app leaves empty on every screen.
  String location = '';

  /// The mounted Router's URI, `ext.dusk.get_routes`'s `uri`.
  String uri = '/';

  /// How many `ext.dusk.get_routes` reads after each restart answer
  /// `uri: null`: the app answers ext.dusk.* from `main()` before `runApp`
  /// has mounted its Router, and a navigate in that gap is not honoured.
  final int routerMountReads;

  /// Whether `ext.dusk.get_routes` carries `uri` at all; false is an app
  /// built with a dusk older than the CLI.
  final bool answersUri;

  int _unmountedReads = 0;

  /// When set, `ext.dusk.navigate` answers `navigated: false` and the route
  /// lands only after this many further `ext.dusk.get_routes` reads: a
  /// Router still applying its first location right after it mounts.
  final int? landingReads;

  /// Where a late landing ([landingReads]) puts the Router instead of the
  /// requested route: a child path is an app a hot restart left on a detail
  /// page while the navigate itself was dropped.
  final String? landsOn;

  String? _landing;
  int _landingLeft = 0;

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
      case 'ext.dusk.navigate':
        if (landingReads != null) {
          _landing = landsOn ?? params['route'];
          _landingLeft = landingReads!;
          return <String, dynamic>{
            'navigated': false,
            'route': params['route'],
            'reason': 'router did not honor the new route',
          };
        }
        if (!navigateHonoured || _unmountedReads > 0) {
          return <String, dynamic>{
            'navigated': false,
            'route': params['route'],
            'reason': 'router did not honor the new route',
          };
        }
        uri = params['route']!;
        return <String, dynamic>{'navigated': true, 'route': uri};
      case 'ext.dusk.get_routes':
        if (_landing != null && _landingLeft-- <= 0) {
          uri = _landing!;
          _landing = null;
        }
        final bool mounted = _unmountedReads == 0;
        if (!mounted) _unmountedReads--;
        return <String, dynamic>{
          'location': location,
          'title': '',
          if (answersUri) 'uri': mounted ? uri : null,
        };
      case 'ext.dusk.wait_for_network_idle':
        uri = redirectOnIdle ?? uri;
        return <String, dynamic>{'matched': true, 'idleAchievedMs': 500};
      case 'ext.dusk.exceptions':
        return <String, dynamic>{
          'exceptions': exceptions,
          'count': exceptions.length,
        };
      case 'ext.dusk.find':
        final int misses = findMisses[params['text']] ?? 0;
        if (misses > 0) {
          findMisses[params['text']!] = misses - 1;
          return <String, dynamic>{'ref': null, 'matched': false};
        }
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
        if (waitMisses > 0) {
          waitMisses--;
          return <String, dynamic>{'matched': false};
        }
        return <String, dynamic>{'matched': true};
      case 'ext.dusk.semantics_hold':
        return params['action'] == 'release'
            ? releaseAnswer
            : <String, dynamic>{
                'action': params['action'],
                'acquired': true,
                'semanticsEnabled': true,
                'treeReady': true,
              };
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
    _unmountedReads = routerMountReads;
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

/// A release that turned the semantics tree off.
const Map<String, dynamic> _kReleasedOff = <String, dynamic>{
  'action': 'release',
  'released': true,
  'semanticsEnabled': false,
  'heldByPlatform': false,
};

/// A release the platform outlived: Flutter web's engine keeps semantics on
/// once the app has sent a tree.
const Map<String, dynamic> _kHeldByPlatform = <String, dynamic>{
  'action': 'release',
  'released': true,
  'semanticsEnabled': true,
  'heldByPlatform': true,
};

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

/// The list scroll at two viewports, one scenario per key.
const String _kVariantsScenario = '''
name: list-scroll
viewport: {width: 1440, height: 900}
platforms: [chrome]
steps:
  - tap: {target: {text: Monitors}}
repeat: 1
variants:
  1440: {}
  390:
    viewport: {width: 390, height: 844}
''';

/// A secret with both characters that change under `jsonEncode` or a shell.
const String _kSecret = r'hun"ter$2';

/// How [_kSecret] reads inside a JSON string.
const String _kSecretJsonInner = r'hun\"ter$2';

/// A login form behind a `when` guard, its password a secret param.
const String _kLoginFragment = r'''
params:
  password: {secret: true}
steps:
  - fill: {target: {label: Email Address}, text: me@example.com}
  - fill: {target: {label: Password}, text: "${password}"}
''';

/// [_scenario] with the login fragment included right after the restart.
const String _kLoginScenario = r'''
name: list-scroll
viewport: {width: 1440, height: 900}
platforms: [chrome, android]
setup:
  - hot_restart
  - include: fragments/login.yaml
    with: {password: 'hun"ter$$2'}
    when: {text: Email Address, timeout_ms: 2000}
  - navigate: /monitors
  - wait_for_text: Monitors
steps:
  - tap: {target: {text: Monitors}}
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
  String renderer = 'unknown',
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
        renderer: renderer,
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
        (summary['frames']! as Map<String, Object?>)['count'],
        42,
        reason: 'same key as a single perf_end report, so one reader fits both',
      );
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

    test('leaves out a repeat whose frames could not be placed, and counts it',
        () {
      // A unit that kept every frame because the clocks disagreed describes
      // frames from outside its session; a median over it is not a
      // measurement of the scenario.
      final Map<String, dynamic> unplaced =
          _report(painted: 90, rowsPerFrame: 9)
            ..['coverage'] = <String, dynamic>{
              'framesDrawn': 90,
              'framesSummarized': 90,
              'sessionClockMismatch': true,
              'complete': false,
              'missing': <String>[],
            };
      final Map<String, Object?> summary = summarizePerfSeries(
        <Map<String, dynamic>>[
          _report(painted: 40, rowsPerFrame: 2),
          unplaced,
          _report(painted: 42, rowsPerFrame: 2),
        ],
      );

      expect(summary['repeats'], 2);
      expect(summary['unplaced'], 1);
      expect(
        (summary['frames']! as Map<String, Object?>)['painted'],
        41,
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

    test(
        '.connected runs on the driver it was handed and leaves it open for '
        'its owner', () async {
      final _FakeDriver driver = _FakeDriver();
      final BufferedOutput output = BufferedOutput();

      final int code = await DuskPerfRunCommand.connected(
        driver,
        const PerfRunEnvironment(platform: PerfPlatform.chrome),
      ).handle(ArtisanContext.bare(MapInput(options()), output));

      expect(code, 0, reason: output.content);
      expect(driver.callsTo('ext.dusk.perf_end'), isNotEmpty);
      expect(driver.closed, isFalse);
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
      // Viewport, restart, viewport again, a mounted Router, navigate and
      // its route check across network idle, wait, front, then the first step's target,
      // which nothing before it can move, and begin.
      final int firstBegin = m.indexOf('ext.dusk.perf_begin');
      expect(
        m.sublist(0, firstBegin),
        <String>[
          'cdp:Emulation.setDeviceMetricsOverride',
          'restart',
          'cdp:Emulation.setDeviceMetricsOverride',
          'ext.dusk.get_routes',
          'ext.dusk.navigate',
          'ext.dusk.get_routes',
          'ext.dusk.wait_for_network_idle',
          'ext.dusk.get_routes',
          'ext.dusk.wait_for',
          'cdp:Page.bringToFront',
          'ext.dusk.find',
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
      // The tap's target was resolved before begin; the wheel's, which the
      // tap can move, inside the window.
      expect(
        m.sublist(begin + 1, end),
        <String>[
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

    test('wait_for_text waits in slices DWDS lets finish, until the budget',
        () async {
      // DWDS cuts any service extension call at 10 s, so one in-app wait of
      // the full 15 s budget died as a -32603 on a slow restart.
      final _FakeDriver driver = _FakeDriver(waitMisses: 2);

      final (int code, _) =
          await _run(driver, options(<String, dynamic>{'repeat': '1'}));

      expect(code, 0);
      final List<_Call> waits = driver.callsTo('ext.dusk.wait_for');
      expect(waits, hasLength(3));
      for (final _Call w in waits) {
        expect(int.parse(w.params['timeoutMs']!), lessThanOrEqualTo(8000));
      }
    });

    test('wait_for_text still gives up once its whole budget is spent',
        () async {
      final _FakeDriver driver = _FakeDriver(waitMisses: 1000);

      final (int code, String out) =
          await _run(driver, options(<String, dynamic>{'repeat': '1'}));

      expect(code, isNot(0));
      expect(out, contains('did not appear within'));
      expect(driver.callsTo('ext.dusk.wait_for').length, lessThan(10));
    });

    test('a wheel with ticks sends that many events at one resolved point',
        () async {
      await File(scenarioPath).writeAsString('''
name: list-scroll
viewport: {width: 1440, height: 900}
platforms: [chrome]
steps:
  - wheel: {target: {text: List}, dy: 120, ticks: 4}
repeat: 1
''');
      final _FakeDriver driver = _FakeDriver();

      await _run(driver, options(<String, dynamic>{'repeat': '1'}));

      final List<_Call> wheels = driver.callsTo('cdp:Input.dispatchMouseEvent');
      expect(wheels, hasLength(4));
      expect(wheels.map((_Call c) => c.params['deltaY']).toSet(), <num>{120.0});
      expect(wheels.map((_Call c) => c.params['x']).toSet(), hasLength(1));
      expect(driver.callsTo('ext.dusk.find'), hasLength(1));
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
          'ext.dusk.get_routes',
          'ext.dusk.navigate',
          'ext.dusk.get_routes',
          'ext.dusk.wait_for_network_idle',
          'ext.dusk.get_routes',
          'ext.dusk.wait_for',
          'ext.dusk.find',
          'ext.dusk.tap',
          'pause',
          'cdp:Page.bringToFront',
          'ext.dusk.find',
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

    group('setup diagnostics', () {
      test('a setup navigate answering navigated:false fails with the payload',
          () async {
        final _FakeDriver driver = _FakeDriver(navigateHonoured: false);

        final (int code, String out) =
            await _run(driver, options(<String, dynamic>{'repeat': '1'}));

        expect(code, 1);
        expect(out, contains('list-scroll setup[1] (navigate)'));
        expect(out, contains('"navigated":false'));
        expect(out, contains('router did not honor the new route'));
        expect(out, contains('route "/"'));
        expect(driver.callsTo('ext.dusk.navigate'), hasLength(1));
        expect(driver.callsTo('ext.dusk.get_routes').length, lessThan(40));
        expect(driver.callsTo('ext.dusk.wait_for'), isEmpty);
        expect(driver.callsTo('ext.dusk.perf_begin'), isEmpty);
      });

      test('a navigate right after a restart waits for the Router to mount',
          () async {
        // The boot id answers from main(), before runApp mounts the Router
        // the navigate is verified against: navigating then answered
        // navigated:false on every Chrome scenario.
        final _FakeDriver driver = _FakeDriver(routerMountReads: 3);

        final (int code, String out) =
            await _run(driver, options(<String, dynamic>{'repeat': '1'}));

        expect(code, 0, reason: out);
        final List<String> m = driver.methods;
        final int navigate = m.indexOf('ext.dusk.navigate');
        expect(
          m.sublist(m.indexOf('restart'), navigate).where(
                (String method) => method == 'ext.dusk.get_routes',
              ),
          hasLength(4),
        );
        expect(driver.callsTo('ext.dusk.navigate'), hasLength(1));
      });

      test('a navigate that lands just after its answer is held to the route',
          () async {
        // Measured on uptizm after a web hot restart: a navigate sent as the
        // Router mounts answers false, and the route lands a moment later.
        final _FakeDriver driver = _FakeDriver(landingReads: 3);

        final (int code, String out) =
            await _run(driver, options(<String, dynamic>{'repeat': '1'}));

        expect(code, 0, reason: out);
        expect(driver.callsTo('ext.dusk.navigate'), hasLength(1));
        expect(driver.callsTo('ext.dusk.perf_begin'), hasLength(1));
        final List<dynamic> repeats =
            readRun('list-scroll', 'base')['repeats'] as List<dynamic>;
        expect(
          (repeats.single as Map<String, dynamic>)['setupLandedLate'],
          isTrue,
        );
      });

      test('a unit whose navigate landed at once carries no late mark',
          () async {
        final _FakeDriver driver = _FakeDriver();

        final (int code, String out) =
            await _run(driver, options(<String, dynamic>{'repeat': '1'}));

        expect(code, 0, reason: out);
        final List<dynamic> repeats =
            readRun('list-scroll', 'base')['repeats'] as List<dynamic>;
        expect(
          (repeats.single as Map<String, dynamic>)
              .containsKey('setupLandedLate'),
          isFalse,
        );
      });

      test('a late landing on a page under the route does not count', () async {
        // A web hot restart keeps the URL: a dropped navigate to /monitors
        // while the app still sits on /monitors/7 is not a landing.
        final _FakeDriver driver = _FakeDriver(
          landingReads: 1,
          landsOn: '/monitors/7',
        );

        final (int code, String out) =
            await _run(driver, options(<String, dynamic>{'repeat': '1'}));

        expect(code, 1);
        expect(out, contains('the router did not honor "/monitors"'));
        expect(driver.callsTo('ext.dusk.perf_begin'), isEmpty);
      });

      test('a query the page adds once the network is idle is not a move',
          () async {
        final _FakeDriver driver =
            _FakeDriver(redirectOnIdle: '/monitors?page=1');

        final (int code, String out) =
            await _run(driver, options(<String, dynamic>{'repeat': '1'}));

        expect(code, 0, reason: out);
        expect(driver.callsTo('ext.dusk.perf_begin'), hasLength(1));
      });

      test('a Router that never mounts fails before navigating', () async {
        final _FakeDriver driver = _FakeDriver(routerMountReads: 1 << 20);

        final (int code, String out) =
            await _run(driver, options(<String, dynamic>{'repeat': '1'}));

        expect(code, 1);
        expect(out, contains('list-scroll setup[1] (navigate)'));
        expect(out, contains('no Router'));
        expect(out, contains('route none (no Router mounted)'));
        expect(driver.callsTo('ext.dusk.navigate'), isEmpty);
        expect(driver.callsTo('ext.dusk.get_routes').length, lessThan(200));
      });

      test('an app whose get_routes carries no uri is told to relaunch',
          () async {
        final _FakeDriver driver = _FakeDriver(answersUri: false);

        final (int code, String out) =
            await _run(driver, options(<String, dynamic>{'repeat': '1'}));

        expect(code, 1);
        expect(out, contains('older'));
        expect(driver.callsTo('ext.dusk.navigate'), isEmpty);
        expect(driver.callsTo('ext.dusk.get_routes'), hasLength(2));
      });

      test('a route that moves once the network is idle fails naming both',
          () async {
        // The page name stays '' across the redirect, as in a Router-based
        // app; only the router's uri moves.
        final _FakeDriver driver = _FakeDriver(redirectOnIdle: '/login');

        final (int code, String out) =
            await _run(driver, options(<String, dynamic>{'repeat': '1'}));

        expect(code, 1);
        expect(out, contains('/monitors'));
        expect(out, contains('/login'));
        expect(driver.callsTo('ext.dusk.perf_begin'), isEmpty);
      });

      test(
          'a setup wait that fails reports the route, the navigate payload '
          'and the last exceptions', () async {
        final _FakeDriver driver = _FakeDriver(
          waitMisses: 1000,
          exceptions: const <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'FlutterError',
              'message': 'RenderFlex overflowed by 12 pixels',
              'time': '2026-09-28T20:00:00.000Z',
            },
          ],
        );

        final (int code, String out) =
            await _run(driver, options(<String, dynamic>{'repeat': '1'}));

        expect(code, 1);
        expect(out, contains('did not appear within'));
        expect(out, contains('route "/monitors"'));
        expect(out, contains('"navigated":true'));
        expect(out, contains('RenderFlex overflowed by 12 pixels'));
        expect(driver.callsTo('ext.dusk.exceptions'), hasLength(1));
      });

      test('a setup gesture that matches nothing reports the diagnostics too',
          () async {
        await File(scenarioPath).writeAsString(
          _scenario.replaceFirst(
            '  - wait_for_text: Monitors\n',
            '  - wait_for_text: Monitors\n'
                '  - tap: {target: {text: Gone}}\n',
          ),
        );
        final _FakeDriver driver = _FakeDriver(unresolved: <String>{'Gone'});

        final (int code, String out) =
            await _run(driver, options(<String, dynamic>{'repeat': '1'}));

        expect(code, 1);
        expect(out, contains('route "/monitors"'));
        expect(out, contains('last exceptions: none'));
      });
    });

    group('target resolution', () {
      test('a target found on the second poll resolves', () async {
        final _FakeDriver driver = _FakeDriver(
          findMisses: <String, int>{'List': 1},
        );

        final (int code, _) =
            await _run(driver, options(<String, dynamic>{'repeat': '1'}));

        expect(code, 0);
        final List<_Call> finds = driver
            .callsTo('ext.dusk.find')
            .where((_Call c) => c.params['text'] == 'List')
            .toList();
        expect(finds, hasLength(2));
        expect(driver.callsTo('cdp:Input.dispatchMouseEvent'), hasLength(1));
      });

      test('a target that never shows up gives up after a bounded wait',
          () async {
        final _FakeDriver driver = _FakeDriver(unresolved: <String>{'List'});

        final (int code, String out) =
            await _run(driver, options(<String, dynamic>{'repeat': '1'}));

        expect(code, 1);
        expect(out, contains('matched nothing'));
        expect(out, contains('3 s'));
        final int polls = driver
            .callsTo('ext.dusk.find')
            .where((_Call c) => c.params['text'] == 'List')
            .length;
        expect(polls, greaterThan(1));
        expect(polls, lessThanOrEqualTo(30));
      });

      test(
          'a target an earlier step opens resolves inside the window, just '
          'before its step, and records resolveMs', () async {
        // locale-switch-390: the first tap opens the overlay `English` lives
        // in, so `English` cannot exist before perf_begin.
        await File(scenarioPath).writeAsString('''
name: list-scroll
viewport: {width: 390, height: 844}
platforms: [chrome]
steps:
  - tap: {target: {text: 'Select an option'}}
  - wait: 300
  - tap: {target: {text: 'English'}}
repeat: 1
''');
        final _FakeDriver driver = _FakeDriver();

        final (int code, _) =
            await _run(driver, options(<String, dynamic>{'repeat': '1'}));

        expect(code, 0);
        int findOf(String text) => driver.calls.indexWhere(
              (_Call c) =>
                  c.method == 'ext.dusk.find' && c.params['text'] == text,
            );
        final List<String> m = driver.methods;
        final int begin = m.indexOf('ext.dusk.perf_begin');
        final int firstTap = m.indexOf('ext.dusk.tap');
        final int secondTap = m.lastIndexOf('ext.dusk.tap');
        expect(findOf('Select an option'), lessThan(begin));
        expect(findOf('English'), greaterThan(firstTap));
        expect(findOf('English'), lessThan(secondTap));
        expect(findOf('English'), greaterThan(begin));

        final Map<String, dynamic> repeat =
            (readRun('list-scroll', 'base')['repeats'] as List<dynamic>).single
                as Map<String, dynamic>;
        final List<dynamic> resolves = repeat['resolves'] as List<dynamic>;
        expect(
          resolves
              .map((dynamic r) => <Object?>[r['step'], r['phase']])
              .toList(),
          <List<Object?>>[
            <Object?>[0, 'beforeBegin'],
            <Object?>[2, 'inWindow'],
          ],
        );
        for (final dynamic r in resolves) {
          expect(r['resolveMs'], isA<num>());
        }
      });

      test(
          'a wheel no earlier step can move takes its hover point before begin',
          () async {
        await File(scenarioPath).writeAsString('''
name: list-scroll
viewport: {width: 1440, height: 900}
platforms: [chrome]
steps:
  - wait: 100
  - wheel: {target: {text: List}, dy: 120, ticks: 2}
repeat: 1
''');
        final _FakeDriver driver = _FakeDriver();

        final (int code, _) =
            await _run(driver, options(<String, dynamic>{'repeat': '1'}));

        expect(code, 0);
        final List<String> m = driver.methods;
        final int begin = m.indexOf('ext.dusk.perf_begin');
        expect(m.indexOf('ext.dusk.find'), lessThan(begin));
        expect(m.indexOf('ext.dusk.hover'), lessThan(begin));
        expect(m.lastIndexOf('ext.dusk.hover'), lessThan(begin));
        final List<_Call> wheels =
            driver.callsTo('cdp:Input.dispatchMouseEvent');
        expect(wheels, hasLength(2));
        expect(wheels.first.params['x'], 11.0);
      });
    });

    group('env.renderer', () {
      test('prefers the renderer the app reported', () async {
        final Map<String, dynamic> report = _report(painted: 40);
        (report['env'] as Map<String, dynamic>)['renderer'] = 'canvaskit';
        final _FakeDriver driver = _FakeDriver(
          perfEnds: <Map<String, dynamic>>[report],
        );

        await _run(
          driver,
          options(<String, dynamic>{'repeat': '1'}),
          renderer: 'impeller-vulkan',
        );

        expect(
          (readRun('list-scroll', 'base')['env']
              as Map<String, dynamic>)['renderer'],
          'canvaskit',
        );
      });

      test('falls back to the host scrape when the app answers unknown',
          () async {
        final Map<String, dynamic> report = _report(painted: 40);
        (report['env'] as Map<String, dynamic>)['renderer'] = 'unknown';
        final _FakeDriver driver = _FakeDriver(
          perfEnds: <Map<String, dynamic>>[report],
        );

        await _run(
          driver,
          options(<String, dynamic>{'repeat': '1'}),
          renderer: 'impeller-vulkan',
        );

        expect(
          (readRun('list-scroll', 'base')['env']
              as Map<String, dynamic>)['renderer'],
          'impeller-vulkan',
        );
      });
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
        // Released after the second perf_begin, and re-acquired only once its
        // perf_end has closed the session: the acquire's full tree rebuild is
        // a frame, and perf_end reads semanticsEnabled for its env.
        expect(m.lastIndexOf('ext.dusk.perf_begin'), lessThan(release));
        final int end = m.lastIndexOf('ext.dusk.perf_end');
        final int acquire = m.lastIndexOf('ext.dusk.semantics_hold');
        expect(release, lessThan(end));
        expect(end, lessThan(acquire));
        // Inside the window nothing resolves a target: coordinates only.
        final List<String> window = m.sublist(release, end);
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

      test('a failed acquire after perf_end records unsupported', () async {
        final _FakeDriver driver = _FailingAcquireDriver();

        final (int code, _) = await _run(
          driver,
          options(<String, dynamic>{'semantics-pass': true, 'repeat': '1'}),
        );

        expect(code, 0);
        final List<String> m = driver.methods;
        expect(
          m.lastIndexOf('ext.dusk.perf_end'),
          lessThan(m.lastIndexOf('ext.dusk.semantics_hold')),
        );
        final Map<String, dynamic> run = readRun('list-scroll', 'base');
        expect(run['semanticsPass'], 'unsupported');
        expect(run['semanticsPassReason'], contains('acquire failed'));
      });

      test('a perf_end that throws still re-acquires the handle', () async {
        final _FakeDriver driver = _FailingReleasedEndDriver();

        final (int code, _) = await _run(
          driver,
          options(<String, dynamic>{'semantics-pass': true, 'repeat': '1'}),
        );

        expect(code, 0);
        final List<String> m = driver.methods;
        expect(
          driver
              .callsTo('ext.dusk.semantics_hold')
              .map((_Call c) => c.params['action'])
              .toList(),
          <String>['release', 'acquire'],
        );
        expect(
          m.lastIndexOf('ext.dusk.perf_end'),
          lessThan(m.lastIndexOf('ext.dusk.semantics_hold')),
        );
        final Map<String, dynamic> run = readRun('list-scroll', 'base');
        expect(run['semanticsPass'], 'unsupported');
        expect(run['semanticsPassReason'], contains('perf_end failed'));
      });

      test(
          'a release the platform outlives on chrome records unsupported, '
          'naming the web engine, and replays nothing', () async {
        final _FakeDriver driver = _FakeDriver(
          releaseAnswer: _kHeldByPlatform,
        );

        final (int code, _) = await _run(
          driver,
          options(<String, dynamic>{'semantics-pass': true, 'repeat': '2'}),
        );

        expect(code, 0);
        // One release: the pass stops at the first one that left the tree
        // on, and that window still closes and re-acquires.
        final List<String> m = driver.methods;
        expect(
          driver
              .callsTo('ext.dusk.semantics_hold')
              .map((_Call c) => c.params['action'])
              .toList(),
          <String>['release', 'acquire'],
        );
        final int release = m.indexOf('ext.dusk.semantics_hold');
        final int end = m.lastIndexOf('ext.dusk.perf_end');
        expect(release, lessThan(end));
        expect(end, lessThan(m.lastIndexOf('ext.dusk.semantics_hold')));
        expect(
          driver
              .callsTo('ext.dusk.tap')
              .where((_Call c) => c.params.containsKey('x')),
          isEmpty,
        );

        final Map<String, dynamic> run = readRun('list-scroll', 'base');
        expect(run['semanticsPass'], 'unsupported');
        expect(run['semanticsPassReason'], contains('on chrome'));
        expect(run['semanticsPassReason'], contains('Flutter web'));
        expect(run.containsKey('semanticsOff'), isFalse);
      });

      test('a release the platform outlives on android names accessibility',
          () async {
        final _FakeDriver driver = _FakeDriver(
          releaseAnswer: _kHeldByPlatform,
        );

        await _run(
          driver,
          options(<String, dynamic>{'semantics-pass': true, 'repeat': '1'}),
          platform: PerfPlatform.android,
        );

        final Map<String, dynamic> run = readRun('list-scroll', 'base');
        expect(run['semanticsPass'], 'unsupported');
        expect(run['semanticsPassReason'], contains('on android'));
        expect(run['semanticsPassReason'], contains('accessibility'));
      });

      test('a release another handle outlives names that handle', () async {
        final _FakeDriver driver = _FakeDriver(
          releaseAnswer: <String, dynamic>{
            ..._kReleasedOff,
            'semanticsEnabled': true,
          },
        );

        await _run(
          driver,
          options(<String, dynamic>{'semantics-pass': true, 'repeat': '1'}),
        );

        final Map<String, dynamic> run = readRun('list-scroll', 'base');
        expect(run['semanticsPass'], 'unsupported');
        expect(run['semanticsPassReason'], contains('ensureSemantics'));
      });

      test(
          'a release that does not say whether the tree went off is unsupported',
          () async {
        final _FakeDriver driver = _FakeDriver(
          releaseAnswer: <String, dynamic>{'action': 'release'},
        );

        await _run(
          driver,
          options(<String, dynamic>{'semantics-pass': true, 'repeat': '1'}),
        );

        final Map<String, dynamic> run = readRun('list-scroll', 'base');
        expect(run['semanticsPass'], 'unsupported');
        expect(run['semanticsPassReason'], contains('older'));
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
        expect(
          driver.methods.lastIndexOf('ext.dusk.perf_end'),
          lessThan(driver.methods.lastIndexOf('ext.dusk.semantics_hold')),
        );
        final Map<String, dynamic> run = readRun('list-scroll', 'base');
        expect(run['semanticsPass'], 'unsupported');
        expect(run['semanticsPassReason'], contains('coordinates'));
      });
    });

    group('--variant', () {
      late String variantsPath;

      setUp(() async {
        variantsPath = '${temp.path}/variants.yaml';
        await File(variantsPath).writeAsString(_kVariantsScenario);
      });

      test('is required when the file declares variants, naming the keys',
          () async {
        final _FakeDriver driver = _FakeDriver();

        final (int code, String out) = await _run(
          driver,
          options(<String, dynamic>{'scenario': variantsPath}),
        );

        expect(code, 1);
        expect(out, contains('--variant'));
        expect(out, contains('1440, 390'));
        expect(driver.calls, isEmpty);
      });

      test('is rejected when the file declares none', () async {
        final _FakeDriver driver = _FakeDriver();

        final (int code, String out) = await _run(
          driver,
          options(<String, dynamic>{'variant': '390'}),
        );

        expect(code, 1);
        expect(out, contains('--variant "390"'));
        expect(out, contains('declares no variants'));
        expect(driver.calls, isEmpty);
      });

      test('names the keys when it matches none of them', () async {
        final _FakeDriver driver = _FakeDriver();

        final (int code, String out) = await _run(
          driver,
          options(<String, dynamic>{
            'scenario': variantsPath,
            'variant': '800',
          }),
        );

        expect(code, 1);
        expect(out, contains('--variant "800"'));
        expect(out, contains('1440, 390'));
        expect(driver.calls, isEmpty);
      });

      test('selects one variant and records it in the file and the envelope',
          () async {
        final _FakeDriver driver = _FakeDriver();

        final (int code, String out) = await _run(
          driver,
          options(<String, dynamic>{
            'scenario': variantsPath,
            'variant': '390',
            'json': true,
          }),
        );

        expect(code, 0, reason: out);
        final Map<String, dynamic> run = readRun('list-scroll-390', 'base');
        expect(run['variant'], '390');
        expect(
          (run['scenario'] as Map<String, dynamic>)['name'],
          'list-scroll-390',
        );
        expect(
          driver.callsTo('cdp:Emulation.setDeviceMetricsOverride').first.params,
          containsPair('width', 390),
        );
        final Map<String, dynamic> printed =
            jsonDecode(out.trim()) as Map<String, dynamic>;
        expect(printed['variant'], '390');
      });

      test('takes a numeric key as the text YAML reads it as', () async {
        final (int code, String out) = await _run(
          _FakeDriver(),
          options(<String, dynamic>{
            'scenario': variantsPath,
            'variant': 390,
          }),
        );

        expect(code, 0, reason: out);
        expect(readRun('list-scroll-390', 'base')['variant'], '390');
      });

      test('a run of a file without variants carries no variant key', () async {
        final (int code, _) = await _run(
          _FakeDriver(),
          options(<String, dynamic>{'repeat': '1'}),
        );

        expect(code, 0);
        expect(readRun('list-scroll', 'base').containsKey('variant'), isFalse);
      });

      test('applies to --against too', () async {
        final String baseline = '${temp.path}/baseline.yaml';
        await File(baseline).writeAsString(
          _kVariantsScenario.replaceFirst(
            'name: list-scroll',
            'name: list-baseline',
          ),
        );
        final _FakeDriver driver = _FakeDriver();

        final (int code, String out) = await _run(
          driver,
          options(<String, dynamic>{
            'scenario': variantsPath,
            'against': baseline,
            'variant': '1440',
          }),
        );

        expect(code, 0, reason: out);
        expect(readRun('list-scroll-1440', 'base')['variant'], '1440');
        expect(
          readRun('list-baseline-1440', 'base')['interleavedWith'],
          'list-scroll-1440',
        );
      });

      test('is rejected when --against declares no variants', () async {
        final _FakeDriver driver = _FakeDriver();

        final (int code, String out) = await _run(
          driver,
          options(<String, dynamic>{
            'scenario': variantsPath,
            'against': scenarioPath,
            'variant': '1440',
          }),
        );

        expect(code, 1);
        expect(out, contains(scenarioPath));
        expect(out, contains('declares no variants'));
        expect(driver.calls, isEmpty);
      });
    });

    group('fragments', () {
      setUp(() async {
        await Directory('${temp.path}/fragments').create();
        await File('${temp.path}/fragments/login.yaml')
            .writeAsString(_kLoginFragment);
        await File(scenarioPath).writeAsString(_kLoginScenario);
      });

      test(
          'a when guard polls until its text shows, then runs the fragment '
          'before the rest of the setup', () async {
        // The login form draws "Email Address" on the third poll.
        final _FakeDriver driver = _FakeDriver(
          findMisses: <String, int>{'Email Address': 2},
        );

        final (int code, String out) =
            await _run(driver, options(<String, dynamic>{'repeat': '1'}));

        expect(code, 0, reason: out);
        final List<String> m = driver.methods;
        final int firstFill = m.indexOf('ext.dusk.fill');
        final List<_Call> polls = driver.calls
            .sublist(m.indexOf('restart'), firstFill)
            .where(
              (_Call c) =>
                  c.method == 'ext.dusk.find' &&
                  c.params['text'] == 'Email Address',
            )
            .toList();
        expect(polls, hasLength(3));
        expect(driver.callsTo('ext.dusk.fill'), hasLength(2));
        expect(firstFill, lessThan(m.indexOf('ext.dusk.navigate')));
      });

      test('a failing secret fill leaves the secret out of the error',
          () async {
        final _FakeDriver driver = _FailingSecretFillDriver(failFrom: 1);

        final (int code, String out) =
            await _run(driver, options(<String, dynamic>{'repeat': '1'}));

        expect(code, 1);
        expect(out, contains('fragments/login.yaml steps[1] (fill)'));
        expect(out, contains('***'));
        expect(out, isNot(contains(_kSecret)));
        expect(out, isNot(contains(_kSecretJsonInner)));
      });

      test(
          'a secret fill that fails in the semantics pass leaves the secret '
          'out of the envelope and the run file', () async {
        // The pass records the failure as semanticsPassReason, which both the
        // run file and the --json envelope carry.
        final _FakeDriver driver = _FailingSecretFillDriver(failFrom: 2);

        final (int code, String out) = await _run(
          driver,
          options(<String, dynamic>{
            'repeat': '1',
            'semantics-pass': true,
            'json': true,
          }),
        );

        expect(code, 0, reason: out);
        final String file =
            File('${temp.path}/out/list-scroll-base.json').readAsStringSync();
        for (final String sink in <String>[out, file]) {
          expect(sink, isNot(contains(_kSecret)));
          expect(sink, isNot(contains(_kSecretJsonInner)));
        }
        final Map<String, dynamic> run = readRun('list-scroll', 'base');
        expect(run['semanticsPass'], 'unsupported');
        expect(run['semanticsPassReason'], contains('***'));
        final Map<String, dynamic> printed =
            jsonDecode(out.trim()) as Map<String, dynamic>;
        expect(printed['semanticsPassReason'], contains('***'));
        expect(printed.keys, contains('path'));
        expect(
          (run['scenario'] as Map<String, dynamic>)['setup'],
          contains(
            equals(<String, dynamic>{
              'fill': <String, dynamic>{
                'target': <String, dynamic>{'label': 'Password'},
                'text': '***',
              },
            }),
          ),
        );
      });

      test(
          'a setup failure masks the secret an app exception quotes before '
          'its diagnostics cut the message', () async {
        // The secret straddles the 200-character cut, so a mask applied
        // after the cut would leave its prefix behind.
        final String head = 'x' * 195;
        final _FakeDriver driver = _FakeDriver(
          waitMisses: 1 << 20,
          exceptions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'StateError',
              'message': '$head$_kSecret was refused',
            },
          ],
        );

        final (int code, String out) =
            await _run(driver, options(<String, dynamic>{'repeat': '1'}));

        expect(code, 1);
        expect(out, contains('$head***'));
        expect(out, isNot(contains('${head}hun')));
      });

      test(
          'a numeric secret leaves the --json envelope parseable with its '
          'numbers intact', () async {
        await File(scenarioPath).writeAsString(
          _kLoginScenario.replaceFirst(r"'hun" r'"ter$$2' "'", "'1234'"),
        );
        final _FakeDriver driver = _FakeDriver(
          perfEnds: <Map<String, dynamic>>[_report(painted: 1234)],
        );

        final (int code, String out) = await _run(
          driver,
          options(<String, dynamic>{'repeat': '1', 'json': true}),
        );

        expect(code, 0, reason: out);
        final Map<String, dynamic> printed =
            jsonDecode(out.trim()) as Map<String, dynamic>;
        final Map<String, dynamic> frames = (printed['summary']
            as Map<String, dynamic>)['frames'] as Map<String, dynamic>;
        expect(frames['painted'], 1234);
        expect(
          driver.callsTo('ext.dusk.fill').map((_Call c) => c.params['text']),
          contains('1234'),
          reason: 'the secret param is the one the envelope must not mangle',
        );
      });
    });
  });
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

/// Fails the `perf_end` that closes a window the handle was released in.
final class _FailingReleasedEndDriver extends _FakeDriver {
  bool _released = false;

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, String> params = const <String, String>{},
  ]) async {
    if (method == 'ext.dusk.semantics_hold' && params['action'] == 'release') {
      _released = true;
    }
    if (method == 'ext.dusk.perf_end' && _released) {
      _released = false;
      calls.add((method: method, params: params));
      throw Exception('perf_end exploded');
    }
    return super.call(method, params);
  }
}

/// Fails the [failFrom]th fill of [_kSecret] and every later one, echoing
/// the text raw and JSON-encoded as an RPC error that quotes its params does.
final class _FailingSecretFillDriver extends _FakeDriver {
  _FailingSecretFillDriver({required this.failFrom});

  final int failFrom;
  int _secretFills = 0;

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, String> params = const <String, String>{},
  ]) async {
    if (method == 'ext.dusk.fill' &&
        params['text'] == _kSecret &&
        ++_secretFills >= failFrom) {
      calls.add((method: method, params: params));
      throw Exception(
        'fill refused text=${params['text']} in ${jsonEncode(params)}',
      );
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
