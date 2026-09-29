import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/utils/frame_summary.dart';
import 'package:fluttersdk_dusk/src/utils/perf_insights.dart';
import 'package:fluttersdk_dusk/src/utils/perf_readers.dart';

const Map<String, Object?> _env = <String, Object?>{
  'platform': 'macOS',
  'isWeb': true,
  'buildMode': 'debug',
  'semanticsEnabled': true,
  'phases': false,
};

/// One frame shaped like telescope's `FramePerfRecord.toJson()`.
Map<String, Object?> _frame({
  required int frameNumber,
  int buildMicros = 4000,
  int rasterMicros = 2000,
  Map<String, Object?> blocks = const <String, Object?>{},
}) =>
    <String, Object?>{
      'frameNumber': frameNumber,
      'buildMicros': buildMicros,
      'rasterMicros': rasterMicros,
      'vsyncOverheadMicros': 0,
      'totalSpanMicros': buildMicros + rasterMicros,
      'time': '2026-09-28T10:00:00.000Z',
      'atUs': frameNumber * 16700,
      'blocks': blocks,
    };

Map<String, Object?> _block(int micros, int selfMicros, int count) =>
    <String, Object?>{
      'micros': micros,
      'selfMicros': selfMicros,
      'count': count,
    };

Map<String, Object?> _perf(List<Map<String, Object?>> frames) =>
    <String, Object?>{
      'frames': frames,
      'livenessCounter': frames.length,
    };

Map<String, int> _names(String prefix, int n) => <String, int>{
      for (int i = 0; i < n; i++) '$prefix$i': (i + 1) * 37,
    };

/// A realistic worst case: an hour-long 60 fps session's worth of frames (3600)
/// over 520 distinct nested block names, every wind and magic counter family
/// populated past its ranked limit, and every built-in rule firing.
Map<String, Object?> _bigPerf() {
  const int distinctNames = 520;
  const int blocksPerFrame = 12;
  final List<Map<String, Object?>> frames = <Map<String, Object?>>[];
  int frameNumber = 1000;
  for (int i = 0; i < 3600; i++) {
    // Every 97th frame leaves a two-frame gap in the sequence.
    frameNumber += i % 97 == 0 ? 3 : 1;
    final Map<String, Object?> blocks = <String, Object?>{
      for (int j = 0; j < blocksPerFrame; j++)
        'NestedWidgetTypeNumber${(i * blocksPerFrame + j) % distinctNames}':
            _block(900 + j * 10, 100 + j * 5, 1 + j % 3),
      // A dominant self-time block and a count outlier, so every rule fires.
      'DominantSlowWidget': _block(12000, 9000, 1),
      'ChattyTinyWidget': _block(400, 300, 60),
    };
    frames.add(
      _frame(
        frameNumber: frameNumber,
        buildMicros: i % 100 == 0 ? 30000 : 5000,
        rasterMicros: 2000,
        blocks: blocks,
      ),
    );
  }
  return <String, Object?>{
    'frames': frames,
    'livenessCounter': 3700,
  };
}

Map<String, Object?> _bigWind() => <String, Object?>{
      'cacheHits': 91234,
      'cacheMisses': 1234,
      'cacheBypasses': 40321,
      'cacheSize': 700,
      'wDivBuilds': 88123,
      'wTextBuilds': 64123,
      'widgetBuilds': _names('WWidgetType', 40),
      'wrapperEmissions': _names('FlutterWrapperType', 20),
      'inheritedReads': <String, int>{
        'mediaQuerySize': 4000,
        'mediaQueryBrightness': 3000,
        'windTheme': 9000,
        'defaultTextStyle': 7000,
      },
    };

Map<String, Object?> _bigExtras() => <String, Object?>{
      'controllerNotifies': _names('SomeFeatureController', 30),
      'notifyCauses': _names('cause.kind.', 30),
      'queryReloads': _names('QueryName', 30),
      'actions': _names('DoSomethingAction', 30),
      'events': _names('SomethingHappenedEvent', 30),
      'casts': _names('SomeCast', 30),
      'timerTicks': _names('TimerOwner', 30),
      'broadcasts': _names('private-teams.1.Event', 30),
      'routeTransitions': <Map<String, Object?>>[
        for (int i = 0; i < 12; i++)
          <String, Object?>{
            'route': '/monitors/$i',
            'durationMicros': 120000 + i,
            'time': '2026-09-28T10:00:00.000Z',
          },
      ],
    };

List<Map<String, dynamic>> _insights(Map<String, Object?> report) =>
    (report['insights']! as List<Object?>).cast<Map<String, dynamic>>();

void main() {
  tearDown(() {
    perfInsightContributors =
        <List<Map<String, Object?>> Function(Map<String, Object?>)>[];
  });

  group('buildPerfReport()', () {
    test('carries exactly the LLM-first top-level keys and none of the old',
        () {
      final Map<String, Object?> report = buildPerfReport(
        _perf(<Map<String, Object?>>[
          _frame(frameNumber: 1),
          _frame(frameNumber: 2),
        ]),
        const <String, Object?>{},
        null,
        env: _env,
      );

      expect(
        report.keys.toSet(),
        <String>{
          'mode',
          'env',
          'coverage',
          'summary',
          'counters',
          'insights',
          'omitted',
        },
      );
      expect(report['mode'], 'attribution');
      expect(report['env'], _env);
      final Map<String, Object?> summary =
          report['summary']! as Map<String, Object?>;
      expect(summary['budgetMs'], 16.7);
      final Map<String, Object?> frames =
          summary['frames']! as Map<String, Object?>;
      expect(frames['painted'], 2);
      expect(frames['count'], 2);
      expect(
        (frames['buildMs']! as Map<String, Object?>).keys,
        containsAll(<String>['p50', 'p90', 'p99', 'worst']),
      );
    });

    test('forwards sessionClockMismatch into coverage, as analysePerf does',
        () {
      final Map<String, Object?> report = buildPerfReport(
        _perf(<Map<String, Object?>>[
          _frame(frameNumber: 1),
        ]),
        const <String, Object?>{},
        null,
        env: _env,
        sessionClockMismatch: true,
      );

      expect(
        (report['coverage']! as Map<String, Object?>)['sessionClockMismatch'],
        isTrue,
      );
    });

    test(
        'a 3600-frame session over 500+ block names stays under 6 KB, counts '
        'what it cut, and gives every insight its five keys', () {
      // magic_devtools adds its own rules; fill past the insight cap so the
      // budget holds for the report a real host produces, not only for the
      // built-in rules.
      perfInsightContributors =
          <List<Map<String, Object?>> Function(Map<String, Object?>)>[
        (Map<String, Object?> report) => <Map<String, Object?>>[
              for (int i = 0; i < 4; i++)
                <String, Object?>{
                  'severity': 'warn',
                  'title': 'SomeFeatureController notifies 14.2 times per '
                      'painted frame',
                  'evidence': <String, Object?>{
                    'metric': 'magic.controllerNotifies',
                    'value': 51120,
                    'perFrame': 14.2,
                    'threshold': <String, Object?>{'maxPerFrame': 1.0},
                  },
                  'estimatedSavingsMs': 120.5 + i,
                  'nextStep': 'Narrow what SomeFeatureController listens to; '
                      'drill in for the causes.',
                },
            ],
      ];
      final Map<String, Object?> report = buildPerfReport(
        _bigPerf(),
        _bigExtras(),
        _bigWind(),
        env: _env,
        framesDrawn: 3700,
        durationMs: 61234.5,
      );

      final int bytes = jsonEncode(report).length;
      expect(bytes, lessThan(6144), reason: 'the report was $bytes bytes');

      // 520 fixture names plus the two planted ones.
      final Map<String, Object?> omitted =
          report['omitted']! as Map<String, Object?>;
      expect(omitted['blocksBySelf'], 522 - kRankedBlockLimit);
      expect(omitted['blocksByCount'], 522 - kRankedBlockLimit);
      expect(omitted['blocksBySelf'], greaterThan(0));

      final List<Map<String, dynamic>> insights = _insights(report);
      expect(insights, isNotEmpty);
      // Five built-in rules fire plus four contributed insights.
      expect(omitted['insights'], 9 - insights.length);
      expect(omitted['magic.controllerNotifies'], 30 - 3);
      for (final Map<String, dynamic> insight in insights) {
        expect(
          insight.keys,
          containsAll(
              <String>['id', 'severity', 'title', 'evidence', 'nextStep']),
        );
        expect(
          (insight['evidence'] as Map<String, dynamic>).keys,
          containsAll(<String>['metric', 'value', 'perFrame', 'threshold']),
        );
        expect(
          <String>['info', 'warn', 'error'],
          contains(insight['severity']),
        );
      }
    });

    test(
        'full=true lifts every cut: every block, counter row and insight, '
        'omitted all zero; the default stays under 6 KB', () {
      final Map<String, Object?> bounded = buildPerfReport(
        _bigPerf(),
        _bigExtras(),
        _bigWind(),
        env: _env,
        framesDrawn: 3700,
      );
      final Map<String, Object?> full = buildPerfReport(
        _bigPerf(),
        _bigExtras(),
        _bigWind(),
        env: _env,
        framesDrawn: 3700,
        full: true,
      );

      expect(jsonEncode(bounded).length, lessThan(6144));

      final Map<String, Object?> omitted =
          full['omitted']! as Map<String, Object?>;
      expect(omitted, isNotEmpty);
      for (final MapEntry<String, Object?> cut in omitted.entries) {
        expect(cut.value, 0, reason: '${cut.key} still cut rows');
      }

      final Map<String, Object?> summary =
          full['summary']! as Map<String, Object?>;
      final Set<String> ranked = <String>{
        for (final Object? row in summary['blocksBySelf']! as List<Object?>)
          (row! as Map<String, Object?>)['name']! as String,
      };
      final Set<String> expected = <String>{
        for (int i = 0; i < 520; i++) 'NestedWidgetTypeNumber$i',
        'DominantSlowWidget',
        'ChattyTinyWidget',
      };
      expect(ranked, expected);
      expect(summary['blocksByCount'] as List<Object?>, hasLength(522));
      expect(summary['routeTransitions'] as List<Object?>, hasLength(12));

      final Map<String, Object?> magic = (full['counters']!
          as Map<String, Object?>)['magic']! as Map<String, Object?>;
      expect(magic['controllerNotifies'] as List<Object?>, hasLength(30));
      final Map<String, Object?> wind = (full['counters']!
          as Map<String, Object?>)['wind']! as Map<String, Object?>;
      expect(wind['widgetBuilds'] as List<Object?>, hasLength(40));
    });

    test('ranks blocks by selfMicros, never by the nested micros', () {
      // Outer has the larger inclusive time only because Inner runs inside
      // it; ranking by `micros` would blame the parent for its child's work.
      final Map<String, Object?> report = buildPerfReport(
        _perf(<Map<String, Object?>>[
          _frame(
            frameNumber: 1,
            blocks: <String, Object?>{
              'Outer': _block(10000, 100, 1),
              'Inner': _block(5000, 4000, 1),
            },
          ),
          _frame(
            frameNumber: 2,
            blocks: <String, Object?>{
              'Outer': _block(10000, 100, 1),
              'Inner': _block(5000, 4000, 1),
            },
          ),
        ]),
        const <String, Object?>{},
        null,
        env: _env,
      );

      final Map<String, Object?> summary =
          report['summary']! as Map<String, Object?>;
      final List<Object?> bySelf = summary['blocksBySelf']! as List<Object?>;
      expect((bySelf.first! as Map<String, Object?>)['name'], 'Inner');
      expect((bySelf.first! as Map<String, Object?>)['selfMs'], 8.0);
      expect((bySelf[1]! as Map<String, Object?>)['name'], 'Outer');
    });

    test('ranks counts per painted frame, not per drawn frame', () {
      final Map<String, Object?> report = buildPerfReport(
        _perf(<Map<String, Object?>>[
          _frame(
            frameNumber: 1,
            blocks: <String, Object?>{'Row': _block(100, 100, 30)},
          ),
          _frame(
            frameNumber: 2,
            blocks: <String, Object?>{'Row': _block(100, 100, 10)},
          ),
        ]),
        const <String, Object?>{},
        null,
        env: _env,
        framesDrawn: 10,
      );

      final List<Object?> byCount = (report['summary']!
          as Map<String, Object?>)['blocksByCount']! as List<Object?>;
      expect(byCount.single, <String, Object?>{
        'name': 'Row',
        'count': 40,
        'perFrame': 20.0,
      });
    });

    test('reports counters.wind null and names wind as missing without it', () {
      final Map<String, Object?> report = buildPerfReport(
        _perf(<Map<String, Object?>>[
          _frame(frameNumber: 1, blocks: <String, Object?>{
            'A': _block(10, 10, 1),
          }),
          _frame(frameNumber: 2, blocks: <String, Object?>{
            'A': _block(10, 10, 1),
          }),
        ]),
        const <String, Object?>{},
        null,
        env: _env,
      );

      final Map<String, Object?> counters =
          report['counters']! as Map<String, Object?>;
      expect(counters.containsKey('wind'), isTrue);
      expect(counters['wind'], isNull);
      expect(
        (report['coverage']! as Map<String, Object?>)['missing'],
        <String>['wind'],
      );
    });

    test('gives every counter raw and per painted frame', () {
      final Map<String, Object?> report = buildPerfReport(
        _perf(<Map<String, Object?>>[
          _frame(frameNumber: 1),
          _frame(frameNumber: 2),
        ]),
        <String, Object?>{
          'controllerNotifies': <String, int>{'A': 2, 'B': 10},
        },
        <String, Object?>{
          'cacheHits': 8,
          'cacheSize': 5,
          'widgetBuilds': <String, int>{'WDiv': 6},
        },
        env: _env,
      );

      final Map<String, Object?> counters =
          report['counters']! as Map<String, Object?>;
      final Map<String, Object?> wind =
          counters['wind']! as Map<String, Object?>;
      expect(wind['cacheHits'], <String, Object?>{'count': 8, 'perFrame': 4.0});
      // A size is a gauge, not a count: per frame would mean nothing.
      expect(wind['cacheSize'], 5);
      expect(counters['columns'], <String>['name', 'count', 'perFrame']);
      expect(wind['widgetBuilds'], <Object?>[
        <Object?>['WDiv', 6, 3.0],
      ]);
      final Map<String, Object?> magic =
          counters['magic']! as Map<String, Object?>;
      expect(
        (magic['controllerNotifies']! as List<Object?>).first,
        <Object?>['B', 10, 5.0],
      );
    });

    test('timing mode reports frame timings only', () {
      final Map<String, Object?> report = buildPerfReport(
        _perf(<Map<String, Object?>>[
          _frame(frameNumber: 1, blocks: <String, Object?>{
            'A': _block(10, 10, 1),
          }),
          _frame(frameNumber: 2),
        ]),
        <String, Object?>{
          'controllerNotifies': <String, int>{'A': 2},
        },
        <String, Object?>{'cacheHits': 8},
        env: _env,
        mode: PerfMode.timing,
      );

      expect(report['mode'], 'timing');
      expect(report['counters'], isNull);
      final Map<String, Object?> summary =
          report['summary']! as Map<String, Object?>;
      expect(summary.containsKey('blocksBySelf'), isFalse);
      expect(summary.containsKey('blocksByCount'), isFalse);
      expect(summary['frames'], isA<Map<String, Object?>>());
      expect(
        (report['coverage']! as Map<String, Object?>)['missing'],
        isEmpty,
        reason: 'timing leaves counters out by design, not by absence',
      );
    });

    test('fires the over-budget rule with its budget stated as evidence', () {
      final Map<String, Object?> report = buildPerfReport(
        _perf(<Map<String, Object?>>[
          _frame(frameNumber: 1, buildMicros: 30000),
          _frame(frameNumber: 2),
        ]),
        const <String, Object?>{},
        null,
        env: _env,
        mode: PerfMode.timing,
      );

      final Map<String, dynamic> overBudget = _insights(report).firstWhere(
        (Map<String, dynamic> i) =>
            (i['evidence'] as Map<String, dynamic>)['metric'] ==
            'framesOverBudget',
      );
      final Map<String, dynamic> evidence =
          overBudget['evidence'] as Map<String, dynamic>;
      expect(evidence['value'], 1);
      expect(evidence['perFrame'], 0.5);
      expect(
        (evidence['threshold'] as Map<String, dynamic>)['budgetMs'],
        16.7,
      );
      // Half the painted frames missed: past the 10% error share.
      expect(overBudget['severity'], 'error');
      expect(overBudget['estimatedSavingsMs'], 13.3);
    });

    test('fires the dropped-frame rule from frameNumber gaps', () {
      final Map<String, Object?> report = buildPerfReport(
        _perf(<Map<String, Object?>>[
          _frame(frameNumber: 1),
          _frame(frameNumber: 4),
          _frame(frameNumber: 5),
        ]),
        const <String, Object?>{},
        null,
        env: _env,
        mode: PerfMode.timing,
      );

      final Map<String, Object?> frames = (report['summary']!
          as Map<String, Object?>)['frames']! as Map<String, Object?>;
      expect(frames['dropped'], 2);
      expect(frames['painted'], 3);
      expect(frames['count'], 5);
      expect(
        _insights(report).map(
          (Map<String, dynamic> i) =>
              (i['evidence'] as Map<String, dynamic>)['metric'],
        ),
        contains('framesDropped'),
      );
    });

    test('a quiet, complete, measured session raises no insight', () {
      final Map<String, Object?> report = buildPerfReport(
        _perf(<Map<String, Object?>>[
          for (int i = 1; i <= 10; i++)
            _frame(
              frameNumber: i,
              blocks: <String, Object?>{
                for (int b = 0; b < 5; b++) 'B$b': _block(200, 200, 1),
              },
            ),
        ]),
        const <String, Object?>{},
        const <String, Object?>{'cacheHits': 1},
        env: _env,
      );

      expect(report['insights'], isEmpty);
    });

    test('assigns ids in generation order, then sorts by severity', () {
      perfInsightContributors =
          <List<Map<String, Object?>> Function(Map<String, Object?>)>[
        (Map<String, Object?> report) => <Map<String, Object?>>[
              <String, Object?>{
                'severity': 'info',
                'title': 'contributed info',
                'evidence': <String, Object?>{
                  'metric': 'x',
                  'value': 1,
                  'perFrame': null,
                  'threshold': null,
                },
                'nextStep': 'nothing',
                'detail': <String, Object?>{
                  'rows': <int>[1, 2, 3]
                },
              },
            ],
      ];

      final Map<String, Object?> report = buildPerfReport(
        _perf(<Map<String, Object?>>[
          _frame(frameNumber: 1, buildMicros: 30000),
          _frame(frameNumber: 2),
        ]),
        const <String, Object?>{},
        null,
        env: _env,
      );

      final List<Map<String, dynamic>> insights = _insights(report);
      expect(insights.first['severity'], 'error');
      expect(insights.last['title'], 'contributed info');
      final Set<String> ids =
          insights.map((Map<String, dynamic> i) => i['id'] as String).toSet();
      expect(ids, hasLength(insights.length));
      expect(ids.every((String id) => RegExp(r'^I\d+$').hasMatch(id)), isTrue);
      // The contributor's drill-down rows stay behind the drill-down.
      expect(insights.last.containsKey('detail'), isFalse);
    });

    test('a throwing contributor becomes a warn insight, never a throw', () {
      perfInsightContributors =
          <List<Map<String, Object?>> Function(Map<String, Object?>)>[
        (Map<String, Object?> report) => throw StateError('rule is broken'),
      ];

      late Map<String, Object?> report;
      expect(
        () => report = buildPerfReport(
          _perf(<Map<String, Object?>>[
            _frame(frameNumber: 1),
            _frame(frameNumber: 2),
          ]),
          const <String, Object?>{},
          const <String, Object?>{'cacheHits': 1},
          env: _env,
          // Timing mode keeps the coverage rule quiet, so the failure is the
          // only insight left to find.
          mode: PerfMode.timing,
        ),
        returnsNormally,
      );

      final Map<String, dynamic> failure = _insights(report).single;
      expect(failure['severity'], 'warn');
      expect(
        (failure['evidence'] as Map<String, dynamic>)['metric'],
        'contributorErrors',
      );
    });

    test('a malformed contributor insight is reported, not passed through', () {
      perfInsightContributors =
          <List<Map<String, Object?>> Function(Map<String, Object?>)>[
        (Map<String, Object?> report) => <Map<String, Object?>>[
              <String, Object?>{'title': 'no severity, no evidence'},
            ],
      ];

      final Map<String, Object?> report = buildPerfReport(
        _perf(<Map<String, Object?>>[
          _frame(frameNumber: 1),
          _frame(frameNumber: 2),
        ]),
        const <String, Object?>{},
        const <String, Object?>{'cacheHits': 1},
        env: _env,
        mode: PerfMode.timing,
      );

      final Map<String, dynamic> failure = _insights(report).single;
      expect(failure['severity'], 'warn');
      expect(failure['title'], isNot('no severity, no evidence'));
    });
  });

  group('analysePerf().drillDown()', () {
    test('returns the rows behind an insight, worst frames included', () {
      final PerfAnalysis analysis = analysePerf(
        _perf(<Map<String, Object?>>[
          _frame(
            frameNumber: 1,
            buildMicros: 30000,
            blocks: <String, Object?>{'Slow': _block(9000, 8000, 1)},
          ),
          _frame(frameNumber: 2),
        ]),
        const <String, Object?>{},
        null,
        env: _env,
      );
      final String id = (analysis.report['insights']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .firstWhere(
            (Map<String, Object?> i) =>
                (i['evidence']! as Map<String, Object?>)['metric'] ==
                'framesOverBudget',
          )['id']! as String;

      final Map<String, Object?> drill = analysis.drillDown(id)!;

      expect(
        drill.keys,
        containsAll(<String>[
          'id',
          'title',
          'summary',
          'detail',
          'estimatedSavingsMs',
          'nextStep',
        ]),
      );
      final Map<String, Object?> detail =
          drill['detail']! as Map<String, Object?>;
      final Map<String, Object?> worst =
          (detail['worstFrames']! as List<Object?>).first!
              as Map<String, Object?>;
      expect(worst['frameNumber'], 1);
      expect(
        ((worst['blocks']! as List<Object?>).first!
            as Map<String, Object?>)['name'],
        'Slow',
      );
    });

    test('answers null for an id the session never issued', () {
      final PerfAnalysis analysis = analysePerf(
        _perf(<Map<String, Object?>>[
          _frame(frameNumber: 1),
          _frame(frameNumber: 2),
        ]),
        const <String, Object?>{},
        null,
        env: _env,
      );

      expect(analysis.drillDown('I999'), isNull);
    });
  });
}
