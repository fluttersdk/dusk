import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/utils/frame_sync.dart';

/// Tests for the bounded frame awaits every action handler settles on.
///
/// The contract has two halves: resolve on the real frame when the engine is
/// producing them, and fall through on a timer when it is not. The second
/// half is what a backgrounded browser tab hits, and `tester.runAsync` is the
/// only harness mode that reproduces it (real clock, no automatic pumping).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('awaitFrameOrTimeout', () {
    testWidgets('resolves on the frame when one is produced', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      final Future<void> pending = awaitFrameOrTimeout();
      await tester.pump();

      await expectLater(pending, completes);
    });

    testWidgets('falls through when no frame is produced', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      await tester.runAsync(() async {
        final Stopwatch stopwatch = Stopwatch()..start();
        await awaitFrameOrTimeout(
          timeout: const Duration(milliseconds: 50),
        );
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(40));
      });
    });
  });

  group('awaitFramesOrTimeout', () {
    testWidgets('bounds each frame separately when none are produced', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      await tester.runAsync(() async {
        final Stopwatch stopwatch = Stopwatch()..start();
        await awaitFramesOrTimeout(
          3,
          timeout: const Duration(milliseconds: 30),
        );
        stopwatch.stop();

        // Three awaits at 30ms each, so the floor is ~90ms rather than the
        // single-frame 30ms: the bound is per frame, not per call.
        expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(80));
      });
    });

    testWidgets('resolves immediately for a zero count', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      await tester.runAsync(() async {
        await expectLater(awaitFramesOrTimeout(0), completes);
      });
    });
  });

  test('kFrameSyncTimeout leaves room for a real reflow', () {
    // 12 frames at 60Hz. A production reflow lands in ~16ms, so the real
    // frame always wins on a healthy engine and the timer only fires when
    // frame production is genuinely off.
    expect(kFrameSyncTimeout, equals(const Duration(milliseconds: 200)));
  });
}
