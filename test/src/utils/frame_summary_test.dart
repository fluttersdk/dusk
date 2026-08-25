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

void main() {
  group('summarizeFramePerf percentiles', () {
    test(
      'a 10-element list puts p90 and p99 on different elements',
      () {
        // Build times 1..9ms then a 50ms outlier, sorted ascending already.
        // Percentile index = ((n - 1) * p).round(), matching
        // frame_timing_summarizer.dart's _findPercentile exactly.
        // n=10: p90 index = (9 * 0.90).round() = 8 -> value 9ms.
        //       p99 index = (9 * 0.99).round() = 9 -> value 50ms (last).
        final List<int> buildMsValues = <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 50];
        final List<Map<String, Object?>> frames = <Map<String, Object?>>[
          for (int i = 0; i < buildMsValues.length; i++)
            _frame(frameNumber: i + 1, buildMicros: buildMsValues[i] * 1000),
        ];

        final Map<String, Object?> summary = summarizeFramePerf(frames);

        expect(
          summary['90th_percentile_frame_build_time_millis'],
          9.0,
          reason: 'p90 index 8 must land on the 9ms element, not the 50ms one',
        );
        expect(
          summary['99th_percentile_frame_build_time_millis'],
          50.0,
          reason: 'p99 index 9 must land on the last (50ms) element',
        );
        expect(summary['worst_frame_build_time_millis'], 50.0);
        expect(summary['average_frame_build_time_millis'], 9.5);
      },
    );
  });

  group('summarizeFramePerf budget count', () {
    test(
      'a frame at exactly the 16ms budget does not count, one past it does',
      () {
        final List<Map<String, Object?>> frames = <Map<String, Object?>>[
          _frame(frameNumber: 1, buildMicros: 16000), // exactly 16ms
          _frame(frameNumber: 2, buildMicros: 16001), // one microsecond over
        ];

        final Map<String, Object?> summary = summarizeFramePerf(frames);

        expect(summary['missed_frame_build_budget_count'], 1);
      },
    );
  });

  group('summarizeFramePerf empty input', () {
    test('an empty list returns zeros rather than throwing or dividing by zero',
        () {
      final Map<String, Object?> summary =
          summarizeFramePerf(<Map<String, Object?>>[]);

      expect(summary['average_frame_build_time_millis'], 0.0);
      expect(summary['90th_percentile_frame_build_time_millis'], 0.0);
      expect(summary['99th_percentile_frame_build_time_millis'], 0.0);
      expect(summary['worst_frame_build_time_millis'], 0.0);
      expect(summary['missed_frame_build_budget_count'], 0);
      expect(summary['average_frame_rasterizer_time_millis'], 0.0);
      expect(summary['stddev_frame_rasterizer_time_millis'], 0.0);
      expect(summary['90th_percentile_frame_rasterizer_time_millis'], 0.0);
      expect(summary['99th_percentile_frame_rasterizer_time_millis'], 0.0);
      expect(summary['worst_frame_rasterizer_time_millis'], 0.0);
      expect(summary['missed_frame_rasterizer_budget_count'], 0);
      expect(summary['frame_count'], 0);
      expect(summary['frame_rasterizer_count'], 0);
      expect(summary['dropped_frame_count'], 0);
      expect(summary['worst_frames'], <Map<String, Object?>>[]);
    });
  });

  group('summarizeFramePerf dropped-frame detection', () {
    test(
        'a gap in the frameNumber sequence [10, 11, 13, 14] reports exactly one dropped frame',
        () {
      final List<Map<String, Object?>> frames = <Map<String, Object?>>[
        _frame(frameNumber: 10, buildMicros: 1000),
        _frame(frameNumber: 11, buildMicros: 1000),
        _frame(frameNumber: 13, buildMicros: 1000),
        _frame(frameNumber: 14, buildMicros: 1000),
      ];

      final Map<String, Object?> summary = summarizeFramePerf(frames);

      expect(summary['dropped_frame_count'], 1);
    });

    test('a contiguous sequence reports zero dropped frames', () {
      final List<Map<String, Object?>> frames = <Map<String, Object?>>[
        _frame(frameNumber: 1, buildMicros: 1000),
        _frame(frameNumber: 2, buildMicros: 1000),
        _frame(frameNumber: 3, buildMicros: 1000),
      ];

      final Map<String, Object?> summary = summarizeFramePerf(frames);

      expect(summary['dropped_frame_count'], 0);
    });

    test('a non-monotonic or duplicate sequence never reports a negative count',
        () {
      final List<Map<String, Object?>> frames = <Map<String, Object?>>[
        _frame(frameNumber: 5, buildMicros: 1000),
        _frame(frameNumber: 5, buildMicros: 1000),
        _frame(frameNumber: 3, buildMicros: 1000),
      ];

      final Map<String, Object?> summary = summarizeFramePerf(frames);

      expect(summary['dropped_frame_count'], 0);
    });
  });

  group('summarizeFramePerf worst-N attribution', () {
    test(
        'the worst-N list carries each frame\'s block attribution, ranked by build time',
        () {
      final List<Map<String, Object?>> frames = <Map<String, Object?>>[
        _frame(
          frameNumber: 1,
          buildMicros: 1000,
          blocks: <String, Object?>{
            'WDiv': <String, Object?>{'micros': 100, 'count': 1},
          },
        ),
        _frame(
          frameNumber: 2,
          buildMicros: 9000,
          blocks: <String, Object?>{
            'WText': <String, Object?>{'micros': 8000, 'count': 3},
          },
        ),
        _frame(
          frameNumber: 3,
          buildMicros: 5000,
          blocks: <String, Object?>{
            'WDiv': <String, Object?>{'micros': 4000, 'count': 2},
          },
        ),
      ];

      final Map<String, Object?> summary =
          summarizeFramePerf(frames, worstFrameCount: 2);

      final List<Object?> worst = summary['worst_frames'] as List<Object?>;
      expect(worst.length, 2);

      final Map<String, Object?> first = worst[0] as Map<String, Object?>;
      expect(first['frameNumber'], 2);
      expect(first['buildMicros'], 9000);
      expect(first['blocks'], isNotEmpty);

      final Map<String, Object?> second = worst[1] as Map<String, Object?>;
      expect(second['frameNumber'], 3);
      expect(second['buildMicros'], 5000);
      expect(second['blocks'], isNotEmpty);
    });
  });
  group('a malformed frame costs its row, not the report', () {
    test('a frame missing buildMicros does not throw', () {
      // These maps are built in another repository and arrive over a function
      // pointer, so a renamed or absent key does not fail to compile. An
      // `as num` cast used to turn one bad row into a TypeError that perf_end
      // reported as an opaque error envelope, losing the whole session.
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

      expect(summary['frame_count'], 2);
      expect(summary['worst_frame_build_time_millis'], 8.0);
    });

    test('a null frameNumber mid-sequence does not manufacture drops', () {
      // The single-element version of this test could not show the bug: with
      // no adjacent pair there is no gap to compute. Zeroing a sequence
      // POSITION is not the graceful degradation that zeroing a duration is,
      // and this reported 101 drops against a truth of 1 before the fix.
      final Map<String, Object?> summary = summarizeFramePerf(
        <Map<String, Object?>>[
          <String, Object?>{
            'frameNumber': 100,
            'buildMicros': 1000,
            'rasterMicros': 500,
          },
          <String, Object?>{
            'frameNumber': null,
            'buildMicros': 1000,
            'rasterMicros': 500,
          },
          <String, Object?>{
            'frameNumber': 102,
            'buildMicros': 1000,
            'rasterMicros': 500,
          },
        ],
      );

      expect(summary['dropped_frame_count'], 1);
      expect(summary['frame_count'], 3);
    });

    test('a frame with a null frameNumber does not throw', () {
      final Map<String, Object?> summary = summarizeFramePerf(
        <Map<String, Object?>>[
          <String, Object?>{
            'frameNumber': null,
            'buildMicros': 1000,
            'rasterMicros': 500,
          },
        ],
      );

      expect(summary['frame_count'], 1);
      expect(summary['dropped_frame_count'], 0);
    });
  });
}
