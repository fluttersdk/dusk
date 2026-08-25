import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/utils/perf_readers.dart';

void main() {
  tearDown(() {
    // Restore every pointer to its no-op default so a leaked assignment
    // does not poison the next test file that reads these globals.
    framePerfReader = () => <String, Object?>{
          'frames': <Map<String, Object?>>[],
          'livenessCounter': 0,
        };
    perfExtrasReader = () => <String, Object?>{
          'controllerNotifies': <String, int>{},
          'routeTransitions': <Map<String, Object?>>[],
        };
    perfSessionResetHook = () {};
  });

  group('framePerfReader default', () {
    test('returns an empty frame list and a zero liveness counter, not null', () {
      final Map<String, Object?> result = framePerfReader();

      expect(result['frames'], <Map<String, Object?>>[]);
      expect(result['livenessCounter'], 0);
    });
  });

  group('perfExtrasReader default', () {
    test('returns empty structures for both keys, not null', () {
      final Map<String, Object?> result = perfExtrasReader();

      expect(result['controllerNotifies'], <String, int>{});
      expect(result['routeTransitions'], <Map<String, Object?>>[]);
    });
  });

  group('perfSessionResetHook default', () {
    test('is a no-op that does not throw', () {
      expect(perfSessionResetHook, returnsNormally);
    });
  });

  group('pointer isolation', () {
    test('assigning framePerfReader does not disturb perfExtrasReader or perfSessionResetHook', () {
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

      perfSessionResetHook();
      expect(resetCalled, isFalse);

      final Map<String, Object?> frames = framePerfReader();
      expect(frames['livenessCounter'], 7);
    });

    test('assigning perfSessionResetHook does not disturb the two readers', () {
      bool called = false;
      perfSessionResetHook = () => called = true;

      final Map<String, Object?> frames = framePerfReader();
      expect(frames['frames'], <Map<String, Object?>>[]);
      expect(frames['livenessCounter'], 0);

      final Map<String, Object?> extras = perfExtrasReader();
      expect(extras['controllerNotifies'], <String, int>{});

      perfSessionResetHook();
      expect(called, isTrue);
    });
  });
}
