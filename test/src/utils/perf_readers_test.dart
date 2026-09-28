import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/utils/perf_readers.dart';

void main() {
  // Captured before any test assigns them, so tearDown restores the real
  // defaults rather than a copy that drifts from them.
  final Map<String, Object?> Function() defaultFramePerf = framePerfReader;
  final Map<String, Object?> Function() defaultExtras = perfExtrasReader;
  final void Function() defaultBegin = perfSessionBeginHook;
  final void Function() defaultEnd = perfSessionEndHook;

  tearDown(() {
    framePerfReader = defaultFramePerf;
    perfExtrasReader = defaultExtras;
    perfSessionBeginHook = defaultBegin;
    perfSessionEndHook = defaultEnd;
  });

  group('framePerfReader default', () {
    test('returns an empty frame list and a zero liveness counter, not null',
        () {
      final Map<String, Object?> result = framePerfReader();

      expect(result['frames'], <Map<String, Object?>>[]);
      expect(result['livenessCounter'], 0);
    });
  });

  group('perfExtrasReader default', () {
    test('returns an empty structure for every documented key, not null', () {
      final Map<String, Object?> result = perfExtrasReader();

      expect(result.keys.toSet(), <String>{
        'controllerNotifies',
        'notifyCauses',
        'queryReloads',
        'actions',
        'events',
        'casts',
        'timerTicks',
        'broadcasts',
        'routeTransitions',
      });
      expect(result['controllerNotifies'], <String, int>{});
      expect(result['broadcasts'], <String, int>{});
      expect(result['routeTransitions'], <Map<String, Object?>>[]);
    });
  });

  group('perfInsightContributors default', () {
    test('is an empty list, so a host without magic_devtools adds nothing', () {
      expect(perfInsightContributors, isEmpty);
    });
  });

  group('the session hooks default', () {
    test('both are no-ops that do not throw', () {
      expect(perfSessionBeginHook, returnsNormally);
      expect(perfSessionEndHook, returnsNormally);
    });
  });

  group('pointer isolation', () {
    test(
        'assigning framePerfReader disturbs neither the extras reader nor the hooks',
        () {
      bool resetCalled = false;
      framePerfReader = () => <String, Object?>{
            'frames': <Map<String, Object?>>[
              <String, Object?>{'frameNumber': 1},
            ],
            'livenessCounter': 7,
          };

      final Map<String, Object?> extras = perfExtrasReader();
      expect(extras['controllerNotifies'], <String, int>{});
      expect(extras['routeTransitions'], <Map<String, Object?>>[]);

      perfSessionBeginHook();
      perfSessionEndHook();
      expect(resetCalled, isFalse);

      final Map<String, Object?> frames = framePerfReader();
      expect(frames['livenessCounter'], 7);
    });

    test('assigning the session hooks does not disturb the two readers', () {
      bool began = false;
      bool ended = false;
      perfSessionBeginHook = () => began = true;
      perfSessionEndHook = () => ended = true;

      final Map<String, Object?> frames = framePerfReader();
      expect(frames['frames'], <Map<String, Object?>>[]);
      expect(frames['livenessCounter'], 0);

      final Map<String, Object?> extras = perfExtrasReader();
      expect(extras['controllerNotifies'], <String, int>{});

      perfSessionBeginHook();
      perfSessionEndHook();
      expect(began, isTrue);
      expect(ended, isTrue);
    });
  });
}
