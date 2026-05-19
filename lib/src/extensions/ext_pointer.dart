import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import '../ref_registry.dart';
import '../utils/actionability_gate.dart';
import '../utils/dusk_exceptions.dart';
import '../utils/error_envelope.dart';
import 'ext_find.dart';
import 'ext_snapshot.dart' show duskSnapBuild;
import 'package:fluttersdk_artisan/artisan.dart';

/// Parses the optional `'true' | 'false'` flag [params] field [name],
/// returning [defaultValue] when missing or empty.
///
/// Used to thread Playwright-style opt-out flags
/// (`checkStable`, `checkReceivesEvents`, `includeSnapshot`) through the
/// VM Service param map (always `Map<String, String>`).
bool _parseBoolFlag(
  Map<String, String> params,
  String name, {
  required bool defaultValue,
}) {
  final String? raw = params[name];
  if (raw == null || raw.isEmpty) return defaultValue;
  return raw != 'false' && raw != '0';
}

/// Builds the post-action snapshot YAML and appends it under the
/// `snapshot` key of [payload], unless [params] sets
/// `includeSnapshot: 'false'`.
///
/// Mirrors Playwright MCP's `setIncludeSnapshot()` pattern: every mutating
/// action returns the fresh accessibility tree alongside its primary
/// confirmation so the agent can decide its next move without a second
/// round-trip. Caller already awaited any necessary `endOfFrame` ticks so
/// the snapshot reflects the post-action tree.
Future<void> _appendSnapshotIfRequested(
  Map<String, dynamic> payload,
  Map<String, String> params,
) async {
  if (!_parseBoolFlag(params, 'includeSnapshot', defaultValue: true)) {
    return;
  }
  final Map<String, dynamic> snap = await duskSnapBuild();
  payload['snapshot'] = snap['snapshot'];
}

/// Resolves a ref string to a live [RefEntry].
///
/// When [ref] begins with `q` it is treated as a Playwright-Locator-style
/// query handle: the stored [DuskQuery] is looked up in [RefRegistry] and
/// re-executed against the live Semantics + Element tree at this moment so
/// the returned entry reflects the freshest rect / element / node. When no
/// node matches the stored predicates, [DuskStaleHandleException] is
/// thrown so the action handler can surface a descriptive error and the
/// agent can decide to re-find or re-snap.
///
/// When [ref] begins with `e` it is a snapshot-frame token: a direct
/// [RefRegistry.lookup] returns the cached entry or `null` when the
/// snapshot group has been disposed.
///
/// All other prefixes (or empty ref) return `null` so the caller surfaces
/// the familiar "ref not found in registry" error.
RefEntry? resolveRefForAction(String ref) {
  if (ref.isEmpty) return null;
  if (ref.startsWith('q')) {
    final DuskQuery? query = RefRegistry.lookupQuery(ref);
    if (query == null) return null;
    // Hold a SemanticsHandle for the duration of the re-execution so the
    // semantics owner's rootSemanticsNode is non-null (the framework only
    // builds the Semantics subtree while at least one handle is alive).
    final SemanticsHandle handle = WidgetsBinding.instance.ensureSemantics();
    final RefEntry? entry;
    try {
      entry = resolveQuery(query);
    } finally {
      handle.dispose();
    }
    if (entry == null) {
      throw DuskStaleHandleException(ref: ref);
    }
    return entry;
  }
  return RefRegistry.lookup(ref);
}

/// Number of intermediate Move events emitted during a drag gesture.
///
/// Velocity recognizers need at least a few Move events to compute a
/// non-zero drag velocity; 5 steps with 16ms spacing is enough to satisfy
/// Flutter's gesture recognizer logic.
const int _kDragSteps = 5;

/// Pointer ID used for single-touch events (tap, hover).
///
/// The framework caches a hit-test result keyed by pointer ID for the
/// duration of a Down→Up sequence. Using different IDs across independent
/// gesture sequences avoids cache collisions from concurrent calls.
const int _kSinglePointer = 1;

/// Resolves a view ID from the platform dispatcher.
///
/// `PointerDownEvent` (and related events) require the view ID of the Flutter
/// view they target. The implicit view is correct for single-window Flutter Web
/// apps.
int _viewId() =>
    WidgetsBinding.instance.platformDispatcher.implicitView!.viewId;

/// Walks the element subtree rooted at [element] and returns the first
/// [EditableTextState] found, or `null` if none exists.
///
/// The spike (`wave-1-spike.md` finding #2) confirmed this descendant-walk
/// pattern because `EditableText` does not expose a static `of(context)`
/// factory; the state is reached by visiting child elements and checking their
/// runtime type.
EditableTextState? _findEditableTextState(Element element) {
  EditableTextState? found;

  void visit(Element child) {
    if (found != null) return;
    if (child is StatefulElement && child.state is EditableTextState) {
      found = child.state as EditableTextState;
      return;
    }
    child.visitChildren(visit);
  }

  // Check the element itself first, then its descendants.
  if (element is StatefulElement && element.state is EditableTextState) {
    return element.state as EditableTextState;
  }
  element.visitChildren(visit);
  return found;
}

/// Injects a tap at [center] in logical pixels.
///
/// Step sequence:
/// 1. PointerDownEvent at [center].
/// 2. 50ms delay (satisfies gesture recognizer debounce window).
/// 3. PointerUpEvent at [center].
/// 4. Two endOfFrame awaits (concurrent evaluate microtask interleave per
///    Oracle watch-out in `oracle-v3-architecture.md`).
///
/// [pointerId] must be unique relative to any concurrent in-flight Down/Up
/// sequence. Callers that issue sequential taps may reuse the same ID between
/// sequences because the Up event closes the hit-test cache entry.
Future<void> _injectTap(Offset center,
    {int pointerId = _kSinglePointer}) async {
  final viewId = _viewId();
  final ts = Duration.zero;

  // 1. Pointer down.
  WidgetsBinding.instance.handlePointerEvent(
    PointerDownEvent(
      pointer: pointerId,
      position: center,
      viewId: viewId,
      timeStamp: ts,
      kind: PointerDeviceKind.touch,
    ),
  );

  // 2. Hold for gesture recognizer debounce.
  await Future<void>.delayed(const Duration(milliseconds: 50));

  // 3. Pointer up — completes the tap gesture.
  WidgetsBinding.instance.handlePointerEvent(
    PointerUpEvent(
      pointer: pointerId,
      position: center,
      viewId: viewId,
      timeStamp: const Duration(milliseconds: 50),
    ),
  );

  // 4. Two frames: first settles the gesture recognizer arena, second
  //    completes any implicit animation triggered by the tap.
  await WidgetsBinding.instance.endOfFrame;
  await WidgetsBinding.instance.endOfFrame;
}

/// Handler for the `ext.dusk.tap` VM Service extension.
///
/// Resolves the `ref` parameter via [RefRegistry], injects a Down+50ms+Up
/// pointer sequence at the widget's logical-pixel center, and (for text-field
/// refs) calls `EditableText.of(element).requestKeyboard()` so the soft
/// keyboard / IME focus lands on the field.
///
/// Spike-confirmed (wave-1-spike.md finding #2 and #6):
/// - `handlePointerEvent(Down + 50ms + Up)` triggers `GestureDetector.onTap`.
/// - `requestKeyboard()` after the pointer events produces `hasPrimaryFocus == true`.
///
/// Parameters:
/// - `ref` (required): opaque ref string from a prior `ext.dusk.snapshot` call.
/// - `checkStable` (optional, default `'true'`): when `'false'`, skip the
///   Playwright stable-rect gate. Production callers leave the default;
///   tests that fabricate synthetic [RefEntry] rects opt out so the gate
///   does not trip on the geometry mismatch.
/// - `checkReceivesEvents` (optional, default `'true'`): when `'false'`,
///   skip the Playwright receives-events hit-test gate. Same rationale as
///   `checkStable`.
/// - `includeSnapshot` (optional, default `'true'`): when `'false'`, skip
///   embedding the post-action accessibility snapshot in the response.
///   Mirrors Playwright MCP's `setIncludeSnapshot()` opt-out.
///
/// Response JSON (default):
/// ```json
/// { "ref": "e3", "snapshot": "<yaml>" }
/// ```
///
/// With `includeSnapshot: 'false'`:
/// ```json
/// { "ref": "e3" }
/// ```
Future<developer.ServiceExtensionResponse> aiTestTapHandler(
  String method,
  Map<String, String> params,
) async {
  // PRE-DISPATCH: hard error gates. Failures here return .error because the
  // pointer was never sent. Two guard clauses before any await.

  final ref = params['ref'];
  if (ref == null || ref.isEmpty) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.tap: missing required param "ref"',
        DuskErrorEnvelope.missingParam('ref'),
      ),
    );
  }

  final RefEntry? entry;
  try {
    entry = resolveRefForAction(ref);
  } on DuskStaleHandleException catch (e) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.message, DuskErrorEnvelope.stale(ref)),
    );
  }
  if (entry == null) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.tap: ref "$ref" not found in registry',
        DuskErrorEnvelope.notFound(
          ref: ref,
          candidates: collectSnapshotCandidates(),
        ),
      ),
    );
  }

  // Actionability gate (Steps 15 + 3.1) — refuse to tap a disabled,
  // zero-rect, off-viewport, unstable, or obscured widget. Failures
  // surface the gate's canonical message verbatim so the MCP tool can
  // hand it to the agent without translation. Stable and receives-events
  // gates are opt-out via params for tests with synthetic geometry.
  final bool checkStable =
      _parseBoolFlag(params, 'checkStable', defaultValue: true);
  final bool checkReceivesEvents =
      _parseBoolFlag(params, 'checkReceivesEvents', defaultValue: true);
  try {
    await ensureActionable(
      entry,
      ref: ref,
      checkStable: checkStable,
      checkReceivesEvents: checkReceivesEvents,
    );
  } on DuskActionabilityException catch (e) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        e.message,
        DuskErrorEnvelope.fromActionabilityReason(e.ref, e.reason),
      ),
    );
  }

  // 1. Inject pointer events at the widget's logical-pixel center.
  //    `WidgetsBinding.instance.handlePointerEvent` (inside `_injectTap`)
  //    runs `hitTestInView` on the render tree, caches the hit-test path
  //    keyed by pointer id, and on PointerUp sweeps the gesture arena —
  //    firing whichever recognizer wins. This is the same dispatch
  //    `WidgetTester.tap` uses and reaches ancestor recognizers
  //    (GestureDetector, InkResponse, ButtonStyleButton) regardless of
  //    which descendant element the snapshot ref points at. No
  //    widget-tree fallback is needed; see D2 group in ext_pointer_test.dart.
  //
  //    Scope: this try/catch is the ONLY place that returns .error after the
  //    guard clauses above. A throw here means the pointer was NOT delivered.
  try {
    await _injectTap(entry.rect.center);
  } catch (e, st) {
    developer.log(
      '[ai-test-v3] ext.dusk.tap: _injectTap failed for ref "$ref": '
      '$e\n$st',
      name: 'ai-test',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.tap: injectTap failed: $e',
        DuskErrorEnvelope.unexpected(widgetPath: ref),
      ),
    );
  }

  // POST-DISPATCH: pointer already fired. Everything below is best-effort
  // enrichment. Any exception here is swallowed and logged — it must never
  // convert a successful tap into a Server error envelope (DEFECT-1).

  // 2. For text-field refs, grant keyboard focus so IME state is consistent.
  //    Walk descendants of the stored element to find the EditableTextState,
  //    then call requestKeyboard() on it (spike-confirmed: wave-1-spike.md
  //    finding #2). The element may be deactivated when navigation fires
  //    during the tap; that exception is swallowed here.
  if (entry.isTextField) {
    try {
      final editable = _findEditableTextState(entry.element);
      editable?.requestKeyboard();
      await WidgetsBinding.instance.endOfFrame;
    } catch (e) {
      developer.log(
        '[ai-test-v3] ext.dusk.tap: post-dispatch noise swallowed for '
        'ref "$ref" (keyboard focus): $e',
        name: 'ai-test',
      );
    }
  }

  // 3. Build the post-action snapshot (Playwright parity) and embed it
  //    under `snapshot`. Snapshot-build failures are post-dispatch noise
  //    and must NOT convert a successful tap into an error envelope.
  final Map<String, dynamic> payload = <String, dynamic>{'ref': ref};
  try {
    await _appendSnapshotIfRequested(payload, params);
  } catch (e) {
    developer.log(
      '[ai-test-v3] ext.dusk.tap: post-dispatch snapshot build swallowed '
      'for ref "$ref": $e',
      name: 'ai-test',
    );
  }

  return developer.ServiceExtensionResponse.result(jsonEncode(payload));
}

/// Handler for the `ext.dusk.hover` VM Service extension.
///
/// Injects a [PointerHoverEvent] with `kind: PointerDeviceKind.mouse` at the
/// center of the widget identified by `ref`. Mouse-region `onEnter` callbacks
/// fire in response to hover events; touch-kind events do not trigger them.
///
/// Parameters:
/// - `ref` (required): opaque ref string from `ext.dusk.snapshot`.
/// - `checkStable` / `checkReceivesEvents` (optional, default `'true'`):
///   Playwright actionability opt-outs. See [aiTestTapHandler] for details.
/// - `includeSnapshot` (optional, default `'true'`): when `'false'`, skip
///   embedding the post-action snapshot in the response.
///
/// Response JSON (default):
/// ```json
/// { "ref": "e5", "snapshot": "<yaml>" }
/// ```
Future<developer.ServiceExtensionResponse> aiTestHoverHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    final ref = params['ref'];
    if (ref == null || ref.isEmpty) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.hover: missing required param "ref"',
          DuskErrorEnvelope.missingParam('ref'),
        ),
      );
    }

    final RefEntry? entry;
    try {
      entry = resolveRefForAction(ref);
    } on DuskStaleHandleException catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(e.message, DuskErrorEnvelope.stale(ref)),
      );
    }
    if (entry == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.hover: ref "$ref" not found in registry',
          DuskErrorEnvelope.notFound(
            ref: ref,
            candidates: collectSnapshotCandidates(),
          ),
        ),
      );
    }

    // Actionability gate (Steps 15 + 3.1) — refuse to hover a disabled,
    // zero-rect, off-viewport, unstable, or obscured widget. Stable and
    // receives-events gates opt-out via params for synthetic test rects.
    final bool checkStable =
        _parseBoolFlag(params, 'checkStable', defaultValue: true);
    final bool checkReceivesEvents =
        _parseBoolFlag(params, 'checkReceivesEvents', defaultValue: true);
    try {
      await ensureActionable(
        entry,
        ref: ref,
        checkStable: checkStable,
        checkReceivesEvents: checkReceivesEvents,
      );
    } on DuskActionabilityException catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          e.message,
          DuskErrorEnvelope.fromActionabilityReason(e.ref, e.reason),
        ),
      );
    }

    // 1. Emit hover event at widget center.
    WidgetsBinding.instance.handlePointerEvent(
      PointerHoverEvent(
        pointer: _kSinglePointer,
        position: entry.rect.center,
        viewId: _viewId(),
        timeStamp: Duration.zero,
        kind: PointerDeviceKind.mouse,
      ),
    );

    // 2. Two frames to let MouseRegion and AnimatedContainer settle.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;

    // 3. Embed post-action snapshot (opt-out via includeSnapshot:'false').
    //    Snapshot build failures are best-effort; never convert success
    //    into error.
    final Map<String, dynamic> payload = <String, dynamic>{'ref': ref};
    try {
      await _appendSnapshotIfRequested(payload, params);
    } catch (e) {
      developer.log(
        '[ai-test-v3] ext.dusk.hover: post-dispatch snapshot build '
        'swallowed for ref "$ref": $e',
        name: 'ai-test',
      );
    }

    return developer.ServiceExtensionResponse.result(jsonEncode(payload));
  } catch (e, st) {
    developer.log(
      '[ai-test-v3] ext.dusk.hover: unexpected error: $e\n$st',
      name: 'ai-test',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.hover: $e',
        DuskErrorEnvelope.unexpected(),
      ),
    );
  }
}

/// Handler for the `ext.dusk.drag` VM Service extension.
///
/// Injects a Down→N×Move→Up pointer sequence that carries the pointer from
/// the center of `startRef` to the center of `endRef`. Five intermediate Move
/// events are spaced 16ms apart so velocity recognizers can compute a valid
/// drag velocity.
///
/// **Pointer ID uniqueness**: the drag uses pointer ID 2 to avoid colliding
/// with any concurrent single-touch event that uses ID 1. Sequential drags
/// may reuse ID 2 because the Up event closes the hit-test cache entry before
/// the next Down.
///
/// Parameters:
/// - `startRef` (required): ref for the drag source widget.
/// - `endRef` (required): ref for the drag destination widget.
/// - `checkStable` / `checkReceivesEvents` (optional, default `'true'`):
///   Playwright actionability opt-outs applied to BOTH endpoints. See
///   [aiTestTapHandler].
/// - `includeSnapshot` (optional, default `'true'`): when `'false'`, skip
///   embedding the post-action snapshot in the response.
///
/// Response JSON (default):
/// ```json
/// { "startRef": "e1", "endRef": "e2", "snapshot": "<yaml>" }
/// ```
Future<developer.ServiceExtensionResponse> aiTestDragHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    final startRef = params['startRef'];
    final endRef = params['endRef'];

    if (startRef == null || startRef.isEmpty) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.drag: missing required param "startRef"',
          DuskErrorEnvelope.missingParam('startRef'),
        ),
      );
    }
    if (endRef == null || endRef.isEmpty) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.drag: missing required param "endRef"',
          DuskErrorEnvelope.missingParam('endRef'),
        ),
      );
    }

    final RefEntry? startEntry;
    try {
      startEntry = resolveRefForAction(startRef);
    } on DuskStaleHandleException catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(e.message, DuskErrorEnvelope.stale(startRef)),
      );
    }
    if (startEntry == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.drag: startRef "$startRef" not found in registry',
          DuskErrorEnvelope.notFound(
            ref: startRef,
            candidates: collectSnapshotCandidates(),
          ),
        ),
      );
    }

    final RefEntry? endEntry;
    try {
      endEntry = resolveRefForAction(endRef);
    } on DuskStaleHandleException catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(e.message, DuskErrorEnvelope.stale(endRef)),
      );
    }
    if (endEntry == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.drag: endRef "$endRef" not found in registry',
          DuskErrorEnvelope.notFound(
            ref: endRef,
            candidates: collectSnapshotCandidates(),
          ),
        ),
      );
    }

    // Actionability gate (Steps 15 + 3.1) — both endpoints must clear the
    // gate before the pointer is committed. We gate startRef first so the
    // agent sees the upstream failure when both ends are bad, mirroring
    // the pre-existing "missing param" check ordering. Stable and
    // receives-events gates opt-out via params for synthetic test rects.
    final bool checkStable =
        _parseBoolFlag(params, 'checkStable', defaultValue: true);
    final bool checkReceivesEvents =
        _parseBoolFlag(params, 'checkReceivesEvents', defaultValue: true);
    try {
      await ensureActionable(
        startEntry,
        ref: startRef,
        checkStable: checkStable,
        checkReceivesEvents: checkReceivesEvents,
      );
    } on DuskActionabilityException catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          e.message,
          DuskErrorEnvelope.fromActionabilityReason(e.ref, e.reason),
        ),
      );
    }
    try {
      await ensureActionable(
        endEntry,
        ref: endRef,
        checkStable: checkStable,
        checkReceivesEvents: checkReceivesEvents,
      );
    } on DuskActionabilityException catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          e.message,
          DuskErrorEnvelope.fromActionabilityReason(e.ref, e.reason),
        ),
      );
    }

    // Drag uses pointer ID 2 to stay separate from single-touch events (ID 1).
    const int dragPointer = 2;
    final viewId = _viewId();
    final start = startEntry.rect.center;
    final end = endEntry.rect.center;

    // 1. Pointer down at the drag source.
    WidgetsBinding.instance.handlePointerEvent(
      PointerDownEvent(
        pointer: dragPointer,
        position: start,
        viewId: viewId,
        timeStamp: Duration.zero,
        kind: PointerDeviceKind.touch,
      ),
    );

    // 2. Intermediate Move events so velocity recognizers see actual motion.
    //    Five steps spaced 16ms apart (one frame per step).
    for (var step = 1; step <= _kDragSteps; step++) {
      final progress = step / _kDragSteps;
      final midpoint = Offset.lerp(start, end, progress)!;
      final elapsed = Duration(milliseconds: step * 16);

      await Future<void>.delayed(const Duration(milliseconds: 16));

      WidgetsBinding.instance.handlePointerEvent(
        PointerMoveEvent(
          pointer: dragPointer,
          position: midpoint,
          viewId: viewId,
          timeStamp: elapsed,
          kind: PointerDeviceKind.touch,
        ),
      );
    }

    // 3. Pointer up at the drag target.
    WidgetsBinding.instance.handlePointerEvent(
      PointerUpEvent(
        pointer: dragPointer,
        position: end,
        viewId: viewId,
        timeStamp: Duration(milliseconds: _kDragSteps * 16 + 16),
      ),
    );

    // 4. Two frames to settle drag-end callbacks and rebuild.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;

    // 5. Embed post-action snapshot (opt-out via includeSnapshot:'false').
    final Map<String, dynamic> payload = <String, dynamic>{
      'startRef': startRef,
      'endRef': endRef,
    };
    try {
      await _appendSnapshotIfRequested(payload, params);
    } catch (e) {
      developer.log(
        '[ai-test-v3] ext.dusk.drag: post-dispatch snapshot build '
        'swallowed: $e',
        name: 'ai-test',
      );
    }

    return developer.ServiceExtensionResponse.result(jsonEncode(payload));
  } catch (e, st) {
    developer.log(
      '[ai-test-v3] ext.dusk.drag: unexpected error: $e\n$st',
      name: 'ai-test',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.drag: $e',
        DuskErrorEnvelope.unexpected(),
      ),
    );
  }
}

/// Handler for the `ext.dusk.dblclick` VM Service extension.
///
/// Fires two tap sequences at the widget identified by `ref` with a ~100ms
/// delay between them, matching Playwright's double-click model. Both taps
/// share the same pointer ID ([_kSinglePointer]) since the Up event from
/// the first tap closes the hit-test cache entry before the second Down.
///
/// Passes through the same 4-gate actionability check as [aiTestTapHandler]
/// (enabled, zero-rect, off-viewport, stable/receives-events). The snapshot
/// is embedded ONCE, after both taps complete, so `includeSnapshot` fires
/// exactly once regardless of tap count. This matches the briefing's
/// requirement that dblclick is a single handler — latency is minimised and
/// the snapshot only captures the final post-dblclick tree.
///
/// Parameters: identical to [aiTestTapHandler] — `ref`, `checkStable`,
/// `checkReceivesEvents`, `includeSnapshot`.
///
/// Response JSON (default):
/// ```json
/// { "ref": "e3", "snapshot": "<yaml>" }
/// ```
Future<developer.ServiceExtensionResponse> aiTestDoubleClickHandler(
  String method,
  Map<String, String> params,
) async {
  // PRE-DISPATCH: hard error gates — same guard-clause shape as aiTestTapHandler.

  final ref = params['ref'];
  if (ref == null || ref.isEmpty) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.dblclick: missing required param "ref"',
        DuskErrorEnvelope.missingParam('ref'),
      ),
    );
  }

  final RefEntry? entry;
  try {
    entry = resolveRefForAction(ref);
  } on DuskStaleHandleException catch (e) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.message, DuskErrorEnvelope.stale(ref)),
    );
  }
  if (entry == null) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.dblclick: ref "$ref" not found in registry',
        DuskErrorEnvelope.notFound(
          ref: ref,
          candidates: collectSnapshotCandidates(),
        ),
      ),
    );
  }

  final bool checkStable =
      _parseBoolFlag(params, 'checkStable', defaultValue: true);
  final bool checkReceivesEvents =
      _parseBoolFlag(params, 'checkReceivesEvents', defaultValue: true);
  try {
    await ensureActionable(
      entry,
      ref: ref,
      checkStable: checkStable,
      checkReceivesEvents: checkReceivesEvents,
    );
  } on DuskActionabilityException catch (e) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        e.message,
        DuskErrorEnvelope.fromActionabilityReason(e.ref, e.reason),
      ),
    );
  }

  // 1. First tap — identical to aiTestTapHandler's _injectTap call.
  try {
    await _injectTap(entry.rect.center);
  } catch (e, st) {
    developer.log(
      '[ai-test-v3] ext.dusk.dblclick: first _injectTap failed for ref '
      '"$ref": $e\n$st',
      name: 'ai-test',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.dblclick: first injectTap failed: $e',
        DuskErrorEnvelope.unexpected(widgetPath: ref),
      ),
    );
  }

  // 2. Inter-tap delay (~100ms) to match Playwright's double-click timing.
  await Future<void>.delayed(const Duration(milliseconds: 100));

  // 3. Second tap — pointer ID reused safely because the first Up event
  //    closed the hit-test cache entry (sequential, non-concurrent).
  try {
    await _injectTap(entry.rect.center);
  } catch (e, st) {
    developer.log(
      '[ai-test-v3] ext.dusk.dblclick: second _injectTap failed for ref '
      '"$ref": $e\n$st',
      name: 'ai-test',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.dblclick: second injectTap failed: $e',
        DuskErrorEnvelope.unexpected(widgetPath: ref),
      ),
    );
  }

  // POST-DISPATCH: best-effort enrichment — snapshot fires once, after both
  // taps, so the agent sees the final post-dblclick accessibility tree.
  final Map<String, dynamic> payload = <String, dynamic>{'ref': ref};
  try {
    await _appendSnapshotIfRequested(payload, params);
  } catch (e) {
    developer.log(
      '[ai-test-v3] ext.dusk.dblclick: post-dispatch snapshot build '
      'swallowed for ref "$ref": $e',
      name: 'ai-test',
    );
  }

  return developer.ServiceExtensionResponse.result(jsonEncode(payload));
}

/// Registers all pointer-event VM Service extensions.
///
/// Called by the Wave 3 aggregator (`extensions.dart#registerAllAiTestExtensions`)
/// during [DuskPlugin.install]. This module uses [registerExtensionIdempotent]
/// for each registration so hot-restart is safe (the VM extension table persists
/// across hot-restart while Dart statics reset — try/catch on ArgumentError is
/// the only reliable idempotency primitive).
///
/// Extensions registered:
/// - `ext.dusk.tap` — pointer Down+50ms+Up at ref center; requestKeyboard for text fields.
/// - `ext.dusk.hover` — PointerHoverEvent (mouse kind) at ref center.
/// - `ext.dusk.drag` — Down+5×Move+Up from startRef to endRef.
/// - `ext.dusk.dblclick` — two tap sequences (~100ms apart) at ref center.
void registerPointerExtensions() {
  registerExtensionIdempotent('ext.dusk.tap', aiTestTapHandler);
  registerExtensionIdempotent('ext.dusk.hover', aiTestHoverHandler);
  registerExtensionIdempotent('ext.dusk.drag', aiTestDragHandler);
  registerExtensionIdempotent('ext.dusk.dblclick', aiTestDoubleClickHandler);
  registerExtensionIdempotent('ext.dusk.right_click', aiTestRightClickHandler);
  registerExtensionIdempotent(
      'ext.dusk.triple_click', aiTestTripleClickHandler);
}

/// Right-click (secondary mouse button) at the ref center. Playwright parity:
/// `locator.click({ button: 'right' })`. Useful for context menus.
Future<developer.ServiceExtensionResponse> aiTestRightClickHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    final String? ref = params['ref'];
    if (ref == null || ref.isEmpty) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.right_click: missing required param "ref"',
          DuskErrorEnvelope.missingParam('ref'),
        ),
      );
    }
    final RefEntry? entry;
    try {
      entry = resolveRefForAction(ref);
    } on DuskStaleHandleException catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(e.message, DuskErrorEnvelope.stale(ref)),
      );
    }
    if (entry == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.right_click: ref "$ref" not found in registry',
          DuskErrorEnvelope.notFound(
            ref: ref,
            candidates: collectSnapshotCandidates(),
          ),
        ),
      );
    }
    final bool checkStable =
        _parseBoolFlag(params, 'checkStable', defaultValue: true);
    final bool checkReceivesEvents =
        _parseBoolFlag(params, 'checkReceivesEvents', defaultValue: true);
    try {
      await ensureActionable(
        entry,
        ref: ref,
        checkStable: checkStable,
        checkReceivesEvents: checkReceivesEvents,
      );
    } on DuskActionabilityException catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          e.message,
          DuskErrorEnvelope.fromActionabilityReason(e.ref, e.reason),
        ),
      );
    }
    final viewId = _viewId();
    final ts = Duration.zero;
    WidgetsBinding.instance.handlePointerEvent(
      PointerDownEvent(
        pointer: _kSinglePointer,
        position: entry.rect.center,
        viewId: viewId,
        timeStamp: ts,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    WidgetsBinding.instance.handlePointerEvent(
      PointerUpEvent(
        pointer: _kSinglePointer,
        position: entry.rect.center,
        viewId: viewId,
        timeStamp: const Duration(milliseconds: 50),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    final Map<String, dynamic> payload = <String, dynamic>{
      'ref': ref,
      'button': 'right',
    };
    await _appendSnapshotIfRequested(payload, params);
    return developer.ServiceExtensionResponse.result(jsonEncode(payload));
  } catch (e, stackTrace) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.right_click error: $e\n$stackTrace',
      name: 'dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), DuskErrorEnvelope.unexpected()),
    );
  }
}

/// Three primary taps at ref center with ~100ms inter-tap delay. Playwright
/// parity: `locator.click({ clickCount: 3 })`. Selects an entire paragraph
/// in Material text fields.
Future<developer.ServiceExtensionResponse> aiTestTripleClickHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    final String? ref = params['ref'];
    if (ref == null || ref.isEmpty) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.triple_click: missing required param "ref"',
          DuskErrorEnvelope.missingParam('ref'),
        ),
      );
    }
    final RefEntry? entry;
    try {
      entry = resolveRefForAction(ref);
    } on DuskStaleHandleException catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(e.message, DuskErrorEnvelope.stale(ref)),
      );
    }
    if (entry == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.triple_click: ref "$ref" not found in registry',
          DuskErrorEnvelope.notFound(
            ref: ref,
            candidates: collectSnapshotCandidates(),
          ),
        ),
      );
    }
    final bool checkStable =
        _parseBoolFlag(params, 'checkStable', defaultValue: true);
    final bool checkReceivesEvents =
        _parseBoolFlag(params, 'checkReceivesEvents', defaultValue: true);
    try {
      await ensureActionable(
        entry,
        ref: ref,
        checkStable: checkStable,
        checkReceivesEvents: checkReceivesEvents,
      );
    } on DuskActionabilityException catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          e.message,
          DuskErrorEnvelope.fromActionabilityReason(e.ref, e.reason),
        ),
      );
    }
    await _injectTap(entry.rect.center);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _injectTap(entry.rect.center);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _injectTap(entry.rect.center);
    await WidgetsBinding.instance.endOfFrame;
    final Map<String, dynamic> payload = <String, dynamic>{
      'ref': ref,
      'clickCount': 3,
    };
    await _appendSnapshotIfRequested(payload, params);
    return developer.ServiceExtensionResponse.result(jsonEncode(payload));
  } catch (e, stackTrace) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.triple_click error: $e\n$stackTrace',
      name: 'dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), DuskErrorEnvelope.unexpected()),
    );
  }
}
