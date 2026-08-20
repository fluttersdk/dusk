import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Ceiling for a single [awaitFrameOrTimeout] await.
///
/// Twelve frames at 60Hz. Long enough that a healthy app always resolves on
/// the real frame (a production reflow lands in ~16ms) and short enough that
/// a starved engine falls through before the caller's shell timeout fires.
const Duration kFrameSyncTimeout = Duration(milliseconds: 200);

/// Awaits the next painted frame, falling through after [timeout] when the
/// engine is not producing frames.
///
/// `WidgetsBinding.instance.endOfFrame` schedules a frame only when
/// `SchedulerBinding.framesEnabled` is true. A backgrounded browser tab
/// reports `document.visibilityState: "hidden"` and Flutter Web disables
/// frame production, so a bare `await endOfFrame` there never completes: the
/// extension blocks until the calling CLI's own timeout kills it, with no
/// output and no error. The same happens under `flutter_test` when nothing
/// pumps the harness.
///
/// Every extension handler that settles a gesture, a text edit, or a
/// navigation goes through this instead of awaiting the binding directly, so
/// a starved engine degrades into an early return rather than a hang.
Future<void> awaitFrameOrTimeout({
  Duration timeout = kFrameSyncTimeout,
}) {
  return WidgetsBinding.instance.endOfFrame.timeout(
    timeout,
    onTimeout: () {},
  );
}

/// Awaits [count] consecutive frames, each bounded by [timeout].
///
/// Handlers that dispatch a pointer sequence await two frames: the first
/// settles the gesture recognizer arena, the second completes any implicit
/// animation the gesture started. On a starved engine the total wait is
/// `count * timeout` and the handler still returns.
Future<void> awaitFramesOrTimeout(
  int count, {
  Duration timeout = kFrameSyncTimeout,
}) async {
  for (int i = 0; i < count; i++) {
    await awaitFrameOrTimeout(timeout: timeout);
  }
}

/// The `warnings` block a response carries while the engine has stopped
/// producing frames, or `null` on a healthy engine.
///
/// `SchedulerBinding.framesEnabled` is false for `AppLifecycleState.hidden`,
/// `paused` and `detached`. Flutter Web reports `hidden` as soon as Chrome
/// sets `document.visibilityState: "hidden"`, which a backgrounded tab or a
/// window that fell behind another does on its own.
///
/// Two separate readings go wrong in that state and neither looks like a
/// harness problem. The semantics tree stops being rebuilt, so a snapshot
/// returns a screen with its buttons and none of its text and the screen
/// reads as empty. And a dispatched gesture cannot produce the frame that
/// would apply it, so an action reports a clean dispatch and changes
/// nothing. Both have been mistaken for product defects.
///
/// The block is omitted entirely when frames are flowing, so a healthy run
/// carries no extra bytes and the presence of the key is itself the signal.
Map<String, dynamic>? frameProductionWarning() {
  if (SchedulerBinding.instance.framesEnabled) return null;

  return <String, dynamic>{
    'framesEnabled': false,
    'lifecycleState': SchedulerBinding.instance.lifecycleState?.name,
    'hint': 'The engine is not producing frames, so the semantics tree is '
        'not being rebuilt and dispatched gestures cannot take effect. A '
        'backgrounded browser tab is the usual cause. Bring the page to '
        'front (CDP Page.bringToFront) and retry before trusting this '
        'result.',
  };
}
