import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/utils/frame_summary.dart';

/// Builds a minimal frame map matching `FramePerfRecord.toJson()`'s shape
/// (telescope repo), the exact input contract `summarizeFramePerf` consumes.
Map<String, Object?> _frame({
  required int frameNumber,
  required int buildMicros,
  int rasterMicros = 0,
  Map<String, Object?> blocks = const <String, Object?>{},
}) {
  return <String, Object?>{
    'frameNumber': frameNumber,
    'buildMicros': buildMicros,
    'rasterMicros': rasterMicros,
    'vsyncOverheadMicros': 0,
    'totalSpanMicros': buildMicros + rasterMicros,
    'time': DateTime(2026, 8, 25).toIso8601String(),
    'blocks': blocks,
  };
}

Map<String, Object?> _block(int micros, int selfMicros, int count) =>
    <String, Object?>{
      'micros': micros,
      'selfMicros': selfMicros,
      'count': count,
    };

Map<String, Object?> _ms(Map<String, Object?> summary, String key) =>
    summary[key]! as Map<String, Object?>;

void main() {
  group('summarizeFramePerf percentiles', () {
    test(
      'a 10-element list puts p50, p90 and p99 on different elements',
      () {
        // Percentile index = ((n - 1) * p).round(), matching
        // frame_timing_summarizer.dart's _findPercentile exactly.
        // n=10: p50 index 5 (4.5 rounds up) -> 6ms, p90 index 8 -> 9ms,
        //       p99 index 9 -> 50ms (last).
        final List<int> buildMsValues = <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 50];
        final List<Map<String, Object?>> frames = <Map<String, Object?>>[
          for (int i = 0; i < buildMsValues.length; i++)
            _frame(frameNumber: i + 1, buildMicros: buildMsValues[i] * 1000),
        ];

        final Map<String, Object?> build =
            _ms(summarizeFramePerf(frames), 'buildMs');

        expect(build['p50'], 6.0);
        expect(
          build['p90'],
          9.0,
          reason: 'p90 index 8 must land on the 9ms element, not the 50ms one',
        );
        expect(build['p99'], 50.0);
        expect(build['worst'], 50.0);
      },
    );
  });

  group('summarizeFramePerf budget count', () {
    test(
      'a frame at exactly the 16.7ms budget does not count, one past it does',
      () {
        final Map<String, Object?> summary = summarizeFramePerf(
          <Map<String, Object?>>[
            _frame(frameNumber: 1, buildMicros: 16700),
            _frame(frameNumber: 2, buildMicros: 16701),
            _frame(frameNumber: 3, buildMicros: 1000, rasterMicros: 20000),
          ],
        );

        expect(kFrameBudgetMs, 16.7);
        expect(summary['overBudgetBuild'], 1);
        expect(summary['overBudgetRaster'], 1);
        // A frame is over budget when EITHER thread is.
        expect(summary['overBudget'], 2);
      },
    );
  });

  group('summarizeFramePerf empty input', () {
    test('an empty list returns zeros rather than throwing or dividing by zero',
        () {
      final Map<String, Object?> summary =
          summarizeFramePerf(<Map<String, Object?>>[]);

      expect(summary['count'], 0);
      expect(summary['painted'], 0);
      expect(summary['dropped'], 0);
      expect(summary['overBudget'], 0);
      expect(_ms(summary, 'buildMs'), <String, Object?>{
        'p50': 0.0,
        'p90': 0.0,
        'p99': 0.0,
        'worst': 0.0,
      });
      expect(_ms(summary, 'rasterMs')['worst'], 0.0);
    });
  });

  group('summarizeFramePerf dropped-frame detection', () {
    test('a gap in [10, 11, 13, 14] reports exactly one dropped frame', () {
      final Map<String, Object?> summary = summarizeFramePerf(
        <Map<String, Object?>>[
          _frame(frameNumber: 10, buildMicros: 1000),
          _frame(frameNumber: 11, buildMicros: 1000),
          _frame(frameNumber: 13, buildMicros: 1000),
          _frame(frameNumber: 14, buildMicros: 1000),
        ],
      );

      expect(summary['dropped'], 1);
      expect(summary['painted'], 4);
      expect(summary['count'], 5);
    });

    test('a non-monotonic or duplicate sequence never reports a negative count',
        () {
      final Map<String, Object?> summary = summarizeFramePerf(
        <Map<String, Object?>>[
          _frame(frameNumber: 5, buildMicros: 1000),
          _frame(frameNumber: 5, buildMicros: 1000),
          _frame(frameNumber: 3, buildMicros: 1000),
        ],
      );

      expect(summary['dropped'], 0);
    });

    test('frameGaps names each gap and how many frames it swallowed', () {
      expect(
        frameGaps(<Map<String, Object?>>[
          _frame(frameNumber: 1, buildMicros: 1),
          _frame(frameNumber: 4, buildMicros: 1),
          _frame(frameNumber: 5, buildMicros: 1),
        ]),
        <Map<String, Object?>>[
          <String, Object?>{'after': 1, 'next': 4, 'missing': 2},
        ],
      );
    });
  });

  group('a malformed frame costs its row, not the report', () {
    test('a frame missing buildMicros does not throw', () {
      final Map<String, Object?> summary = summarizeFramePerf(
        <Map<String, Object?>>[
          <String, Object?>{'frameNumber': 1, 'rasterMicros': 2000},
          <String, Object?>{
            'frameNumber': 2,
            'buildMicros': 8000,
            'rasterMicros': 2000,
          },
        ],
      );

      expect(summary['painted'], 2);
      expect(_ms(summary, 'buildMs')['worst'], 8.0);
    });

    test('a null frameNumber mid-sequence does not manufacture drops', () {
      // Zeroing a sequence POSITION is not the graceful degradation that
      // zeroing a duration is: this reported 101 drops against a truth of 1
      // before the fix.
      final Map<String, Object?> summary = summarizeFramePerf(
        <Map<String, Object?>>[
          <String, Object?>{'frameNumber': 100, 'buildMicros': 1000},
          <String, Object?>{'frameNumber': null, 'buildMicros': 1000},
          <String, Object?>{'frameNumber': 102, 'buildMicros': 1000},
        ],
      );

      expect(summary['dropped'], 1);
      expect(summary['painted'], 3);
    });
  });

  group('aggregateFrameBlocks()', () {
    test('sums self time, inclusive time, counts and frames per name', () {
      final List<PerfBlockTotal> totals = aggregateFrameBlocks(
        <Map<String, Object?>>[
          _frame(
            frameNumber: 1,
            buildMicros: 1,
            blocks: <String, Object?>{'A': _block(900, 300, 2)},
          ),
          _frame(
            frameNumber: 2,
            buildMicros: 1,
            blocks: <String, Object?>{
              'A': _block(100, 50, 1),
              'B': 'not a block',
            },
          ),
          <String, Object?>{'frameNumber': 3, 'blocks': 'not a map'},
        ],
      );

      final PerfBlockTotal a = totals.single;
      expect(a.name, 'A');
      expect(a.micros, 1000);
      expect(a.selfMicros, 350);
      expect(a.count, 3);
      expect(a.frames, 2);
    });
  });

  group('worstFrames()', () {
    test('ranks by the slower thread and carries top blocks by self time', () {
      final List<Map<String, Object?>> worst = worstFrames(
        <Map<String, Object?>>[
          _frame(frameNumber: 1, buildMicros: 1000),
          _frame(
            frameNumber: 2,
            buildMicros: 2000,
            rasterMicros: 30000,
            blocks: <String, Object?>{
              'Parent': _block(9000, 100, 1),
              'Child': _block(8000, 7000, 1),
            },
          ),
        ],
        count: 1,
      );

      expect(worst, hasLength(1));
      expect(worst.single['frameNumber'], 2);
      expect(worst.single['rasterMs'], 30.0);
      final List<Object?> blocks = worst.single['blocks']! as List<Object?>;
      expect((blocks.first! as Map<String, Object?>)['name'], 'Child');
    });
  });
}
