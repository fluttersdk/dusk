import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
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

/// Whether [ensureFramesProduced] may wake a hidden engine.
///
/// On by default; `--dart-define=DUSK_FORCE_FRAMES=false` leaves a hidden
/// app frameless, so every response carries the `warnings` block instead.
const bool kDuskForceFrames = bool.fromEnvironment(
  'DUSK_FORCE_FRAMES',
  defaultValue: true,
);

/// Wakes an engine that stopped producing frames because its window or tab
/// is hidden, and reports whether it had to.
///
/// A hidden, minimised or occluded desktop window moves the lifecycle to
/// `hidden`, which turns
/// `SchedulerBinding.framesEnabled` off: a tap is dispatched and never
/// applied, and a snapshot reads a stale semantics tree. Delivering
/// `AppLifecycleState.resumed` on `flutter/lifecycle`, the message the engine
/// itself sends, turns frames back on. `scheduleForcedFrame` alone is not
/// enough, because a route transition needs a run of frames, not one.
///
/// Only `hidden` and `paused` are forced. `detached` means the engine is
/// going away, and a null lifecycle is a first frame the engine has not
/// reported yet. `inactive` already produces frames. The OS moves the app
/// back to `hidden` on its next occlusion event, so callers apply this per
/// call, not once.
///
/// A lifecycle message alone proves nothing: a sleeping display can leave
/// `framesEnabled` true with no frame ever running. The wake therefore counts
/// only when a frame actually follows it; otherwise the previous lifecycle is
/// put back and the response keeps its `warnings` block. The put-back is
/// skipped when the engine sent a lifecycle of its own during the wait.
///
/// Never attempted on web: Chrome withholds `requestAnimationFrame` from a
/// hidden tab, so no message can make a frame run, and trying would cost every
/// verb a 200 ms wait and four lifecycle callbacks in the app. Web recovers
/// with `Page.bringToFront`.
///
/// Returns true only when this call forced and a frame ran.
Future<bool> ensureFramesProduced() async {
  if (kIsWeb || !kDuskForceFrames) return false;

  final SchedulerBinding scheduler = SchedulerBinding.instance;
  if (scheduler.framesEnabled) return false;

  final AppLifecycleState? state = scheduler.lifecycleState;
  if (state != AppLifecycleState.hidden && state != AppLifecycleState.paused) {
    return false;
  }

  bool delivering = false;
  bool engineSpoke = false;
  void deliver(AppLifecycleState next) {
    delivering = true;
    try {
      _deliverLifecycle(next);
    } finally {
      delivering = false;
    }
  }

  final AppLifecycleListener engineWatch = AppLifecycleListener(
    onStateChange: (_) {
      if (!delivering) engineSpoke = true;
    },
  );

  try {
    // 1. Wake the engine with `inactive`, not `resumed`: Flutter drops a
    // message equal to the current state, so an engine `resumed` arriving
    // during the wait would be invisible to the watch if dusk had already
    // moved the lifecycle there.
    deliver(AppLifecycleState.inactive);
    scheduler.scheduleForcedFrame();

    // 2. Require proof that a frame ran.
    bool frameRan = true;
    await WidgetsBinding.instance.endOfFrame.timeout(
      kFrameSyncTimeout,
      onTimeout: () => frameRan = false,
    );

    if (frameRan) {
      deliver(AppLifecycleState.resumed);
      return true;
    }

    // 3. Undo a wake that produced nothing, so the response does not claim
    // it, unless the engine reported a lifecycle itself meanwhile: putting
    // the old one back would overwrite what the engine just said.
    if (!engineSpoke) deliver(state!);

    return false;
  } finally {
    engineWatch.dispose();
  }
}

/// Delivers [state] on `flutter/lifecycle`, the message the engine sends.
///
/// `channelBuffers.push` reaches the lifecycle handler synchronously, so the
/// state has flipped by the time it returns.
void _deliverLifecycle(AppLifecycleState state) {
  ServicesBinding.instance.channelBuffers.push(
    SystemChannels.lifecycle.name,
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
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

  const String starved = 'The engine is not producing frames, so the '
      'semantics tree is not being rebuilt and dispatched gestures cannot '
      'take effect.';

  return <String, dynamic>{
    'framesEnabled': false,
    'lifecycleState': SchedulerBinding.instance.lifecycleState?.name,
    'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
    'hint': kIsWeb
        ? '$starved A backgrounded browser tab is the usual cause. Bring the '
            'page to front (CDP Page.bringToFront) and retry before trusting '
            'this result.'
        : '$starved The window is hidden, minimised or occluded, or the '
            'display is asleep, and dusk could not force frames. Bring the '
            'window to front (for example '
            '`osascript -e \'tell application "<App>" to activate\'`) and '
            'retry before trusting this result.',
  };
}
