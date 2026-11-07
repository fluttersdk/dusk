import 'dart:async';
import 'dart:developer' as developer;

import 'package:fluttersdk_artisan/artisan.dart';

import 'frame_sync.dart';

/// The shape every `ext.dusk.*` handler has.
typedef DuskExtensionHandler = Future<developer.ServiceExtensionResponse>
    Function(String method, Map<String, String> params);

/// Zone key under which [wrapDuskHandler] records that it forced frames.
///
/// A zone value rather than a field: two extension calls can be in flight at
/// once, and only the one that actually woke the engine may report it.
final Object _framesForcedKey = Object();

/// Zone key under which [wrapDuskHandler] keeps the refs the call relocated.
/// Per call for the same reason as [_framesForcedKey].
final Object _reresolvedKey = Object();

/// Wraps [handler] so it runs against an engine that produces frames.
///
/// With [ensureFrames] the wrapper calls [ensureFramesProduced] before the
/// handler and runs the handler in a zone that remembers whether it forced,
/// which `duskResult` turns into a `framesForced: true` key. It is re-applied
/// on every call because the OS flips a hidden window back to `hidden` on
/// its next occlusion event.
///
/// Verbs that must observe the engine as it is (perf, boot, console,
/// exceptions, evaluate, close) pass `ensureFrames: false` and get [handler]
/// back unchanged.
DuskExtensionHandler wrapDuskHandler(
  DuskExtensionHandler handler, {
  bool ensureFrames = true,
}) {
  if (!ensureFrames) return handler;

  return (String method, Map<String, String> params) async {
    final bool forced = await ensureFramesProduced();

    return Zone.current.fork(
      zoneValues: <Object, Object>{
        _framesForcedKey: forced,
        _reresolvedKey: <String>[],
      },
    ).run(() => handler(method, params));
  };
}

/// Whether the extension call running in the current zone forced frames.
bool framesForcedInCurrentCall() => Zone.current[_framesForcedKey] == true;

/// Records that the current extension call relocated the stale `e<N>` [ref]
/// to a live control, so `duskResult` can say so.
///
/// Recorded once per ref per call. A no-op outside a call wrapped with
/// `ensureFrames: true`, which is every verb that resolves a ref.
void markRefReresolved(String ref) {
  final Object? refs = Zone.current[_reresolvedKey];
  if (refs is! List<String> || refs.contains(ref)) return;
  refs.add(ref);
}

/// The refs the extension call running in the current zone re-resolved, in
/// the order it relocated them. Empty outside a wrapped call.
List<String> reresolvedRefsInCurrentCall() {
  final Object? refs = Zone.current[_reresolvedKey];
  return refs is List<String> ? List<String>.unmodifiable(refs) : <String>[];
}

/// Registers [handler] as the `ext.dusk.*` extension [method], wrapped by
/// [wrapDuskHandler], idempotently across hot restarts.
void registerDuskExtension(
  String method,
  DuskExtensionHandler handler, {
  bool ensureFrames = true,
}) {
  registerExtensionIdempotent(
    method,
    wrapDuskHandler(handler, ensureFrames: ensureFrames),
  );
}
