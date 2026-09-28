/// The interaction a dusk gesture opens inside a perf session, carried in the
/// zone the gesture dispatches in and published through a slot for work the
/// zone cannot reach.
///
/// Two routes, because Dart zones reach some of an interaction's consequences
/// and not others. Gesture callbacks run synchronously inside
/// `handlePointerEvent`, and Timers, microtasks and stream subscriptions
/// created there keep the zone they were created in (dart-sdk
/// `lib/async/timer.dart:48-50`, `lib/async/stream_impl.dart:125`), so an
/// `onTap` that starts a request hands it the interaction for free. Frames,
/// builds, `initState` and post-frame callbacks run in the binding's frame
/// zone instead (sky_engine `platform_dispatcher.dart:427,432`), so a refetch
/// fired from `initState` after a tap navigates never sees it. That work joins
/// through [activeInteraction] by time, and the host marks the join
/// `linkedBy: 'frame'`.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../extensions/ext_perf.dart' show perfSessionOpen;

/// One dusk gesture inside a perf session, from dispatch to settle.
///
/// Read it off the zone with `Zone.current[#fluttersdk_interaction]`, the
/// public symbol [zoneKey] names; a public symbol is equal across libraries
/// (dart-sdk `lib/core/symbol.dart:38-39`), so a host reads it without
/// importing dusk. A handle whose [closedAtUs] is set is ABSENT: Timers and
/// stream subscriptions created in the zone keep it forever (a Reverb socket
/// opened during a login tap), and without the close every later message on
/// that socket would be attributed to the tap.
final class PerfInteraction {
  PerfInteraction._({
    required this.id,
    required this.verb,
    required this.target,
    required this.startUs,
  });

  /// The zone value key, `#fluttersdk_interaction`.
  static const Symbol zoneKey = #fluttersdk_interaction;

  /// `i<N>`, unique for the isolate's lifetime.
  final String id;

  /// The `ext.dusk.*` verb without its prefix (`tap`, `fill`, `scroll`).
  final String verb;

  /// The ref, route or key the verb acted on; null for a verb without one
  /// (`blur`, `dismiss_modals`).
  final String? target;

  /// `FlutterTimeline.now` at dispatch, in microseconds.
  final int startUs;

  /// `FlutterTimeline.now` when the interaction settled, or null while it is
  /// still open.
  int? get closedAtUs => _closedAtUs;
  int? _closedAtUs;

  bool get isOpen => _closedAtUs == null;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'verb': verb,
        'target': target,
        'startUs': startUs,
        'closedAtUs': _closedAtUs,
      };
}

/// Poll cadence of the settle watch.
const Duration _kSettlePoll = Duration(milliseconds: 50);

/// Consecutive frame-free polls that settle an interaction: 300 ms.
const int _kQuietPolls = 6;

/// Polls after which an interaction closes whatever the app does: 5 s. An
/// infinite animation never goes quiet.
const int _kCapPolls = 100;

/// The same cap on the real clock, for a watch whose timer was starved.
const int _kCapMicros = 5000000;

/// Interactions kept for `ext.dusk.perf_trace`. Only a driving agent opens
/// them, so this is hours of driving, not a memory concern.
const int _kLogLimit = 512;

int _counter = 0;

/// Open interactions, oldest first.
final List<PerfInteraction> _open = <PerfInteraction>[];

/// Every interaction opened, oldest first, capped at [_kLogLimit].
final List<PerfInteraction> _log = <PerfInteraction>[];

/// The most recently opened interaction that has not settled, or null when
/// none is open or no perf session is.
///
/// For work that runs in the frame zone and so cannot read the interaction
/// off its own zone: a build, an `initState` refetch, a post-frame callback.
/// Interactions may overlap (an agent can tap again before the last tap
/// settles); the newest is the one a frame just produced most plausibly
/// belongs to.
PerfInteraction? activeInteraction() {
  if (!perfSessionOpen || _open.isEmpty) return null;
  return _open.last;
}

/// Runs a gesture verb's [dispatch] inside the interaction it opens.
///
/// Outside a perf session this is `dispatch()` and nothing else: no handle,
/// no zone, no timer. Inside one, it opens a [PerfInteraction] for [verb] on
/// [target], runs [dispatch] with the handle as the zone value
/// [PerfInteraction.zoneKey], and once [dispatch] completes (or throws)
/// watches for the settle that closes it. A verb dispatched inside another
/// (`fill` runs `focus`, `clear` and `type`) joins the open interaction it
/// runs in rather than opening its own: to the app it is one gesture.
///
/// Gesture semantics are untouched: the zone adds a value and no error
/// handler, so a throw propagates exactly as before.
Future<T> runPerfInteraction<T>(
  String verb,
  String? target,
  Future<T> Function() dispatch,
) {
  if (!perfSessionOpen || _zoneInteraction() != null) return dispatch();
  return _runOpened(_openInteraction(verb, target), dispatch);
}

/// Interactions opened between [startUs] and [endUs] inclusive, oldest first.
List<PerfInteraction> perfInteractionsBetween(int startUs, int endUs) => _log
    .where(
      (PerfInteraction i) => i.startUs >= startUs && i.startUs <= endUs,
    )
    .toList();

/// Forgets every interaction and restarts the id sequence. A watch still
/// running closes its handle into nothing.
@visibleForTesting
void resetPerfInteractionsForTesting() {
  _open.clear();
  _log.clear();
  _counter = 0;
}

Future<T> _runOpened<T>(
  PerfInteraction handle,
  Future<T> Function() dispatch,
) async {
  try {
    return await runZoned(
      dispatch,
      zoneValues: <Object?, Object?>{PerfInteraction.zoneKey: handle},
    );
  } finally {
    // After the await, so the watch's own Timer is created in the caller's
    // zone and does not carry the handle it is about to close.
    _watchSettle(handle);
  }
}

PerfInteraction? _zoneInteraction() {
  final Object? value = Zone.current[PerfInteraction.zoneKey];
  return value is PerfInteraction && value.isOpen ? value : null;
}

PerfInteraction _openInteraction(String verb, String? target) {
  final PerfInteraction handle = PerfInteraction._(
    id: 'i${++_counter}',
    verb: verb,
    target: target,
    startUs: FlutterTimeline.now,
  );
  _open.add(handle);
  _log.add(handle);
  if (_log.length > _kLogLimit) _log.removeRange(0, _log.length - _kLogLimit);
  return handle;
}

/// Closes [handle] once nothing has been scheduled for 300 ms, after 5 s
/// whatever happens, or as soon as the session closes.
///
/// Quiet is counted in polls rather than read off a clock, so a fake-async
/// test settles on the time it pumps. A frame drawn between two polls counts
/// too: a post-frame callback marks it, since `hasScheduledFrame` alone reads
/// false again by the time the next poll looks.
void _watchSettle(PerfInteraction handle) {
  final SchedulerBinding scheduler = SchedulerBinding.instance;
  bool framed = false;
  void onFrame(Duration _) {
    if (!handle.isOpen) return;
    framed = true;
    scheduler.addPostFrameCallback(onFrame);
  }

  scheduler.addPostFrameCallback(onFrame);

  int polls = 0;
  int quiet = 0;
  Timer.periodic(_kSettlePoll, (Timer timer) {
    polls++;
    final bool busy = framed ||
        scheduler.hasScheduledFrame ||
        scheduler.schedulerPhase != SchedulerPhase.idle;
    framed = false;
    quiet = busy ? 0 : quiet + 1;
    final bool capped = polls >= _kCapPolls ||
        FlutterTimeline.now - handle.startUs >= _kCapMicros;
    if (quiet < _kQuietPolls && !capped && perfSessionOpen) return;

    timer.cancel();
    handle._closedAtUs = FlutterTimeline.now;
    _open.remove(handle);
  });
}
