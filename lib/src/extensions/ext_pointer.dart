import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../ref_registry.dart';
import '../utils/actionability_gate.dart';
import '../utils/dusk_exceptions.dart';
import 'package:fluttersdk_artisan/artisan.dart';

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
///
/// Response JSON:
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
      'ext.dusk.tap: missing required param "ref"',
    );
  }

  final entry = RefRegistry.lookup(ref);
  if (entry == null) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      'ext.dusk.tap: ref "$ref" not found in registry',
    );
  }

  // Actionability gate (Step 15) — refuse to tap a disabled, zero-rect, or
  // off-viewport widget. Failures surface the gate's canonical message
  // verbatim so the MCP tool can hand it to the agent without translation.
  try {
    ensureActionable(entry, ref: ref);
  } on DuskActionabilityException catch (e) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      e.message,
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
      'ext.dusk.tap: injectTap failed: $e',
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

  return developer.ServiceExtensionResponse.result(
    jsonEncode(<String, dynamic>{'ref': ref}),
  );
}

/// Handler for the `ext.dusk.hover` VM Service extension.
///
/// Injects a [PointerHoverEvent] with `kind: PointerDeviceKind.mouse` at the
/// center of the widget identified by `ref`. Mouse-region `onEnter` callbacks
/// fire in response to hover events; touch-kind events do not trigger them.
///
/// Parameters:
/// - `ref` (required): opaque ref string from `ext.dusk.snapshot`.
///
/// Response JSON:
/// ```json
/// { "ref": "e5" }
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
        'ext.dusk.hover: missing required param "ref"',
      );
    }

    final entry = RefRegistry.lookup(ref);
    if (entry == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        'ext.dusk.hover: ref "$ref" not found in registry',
      );
    }

    // Actionability gate (Step 15) — refuse to hover a disabled, zero-rect,
    // or off-viewport widget. The gate is inside the existing try/catch so
    // unrelated runtime errors keep their generic surface; the explicit
    // `on DuskActionabilityException` branch forwards the canonical message.
    try {
      ensureActionable(entry, ref: ref);
    } on DuskActionabilityException catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        e.message,
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

    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, dynamic>{'ref': ref}),
    );
  } catch (e, st) {
    developer.log(
      '[ai-test-v3] ext.dusk.hover: unexpected error: $e\n$st',
      name: 'ai-test',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      'ext.dusk.hover: $e',
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
///
/// Response JSON:
/// ```json
/// { "startRef": "e1", "endRef": "e2" }
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
        'ext.dusk.drag: missing required param "startRef"',
      );
    }
    if (endRef == null || endRef.isEmpty) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        'ext.dusk.drag: missing required param "endRef"',
      );
    }

    final startEntry = RefRegistry.lookup(startRef);
    if (startEntry == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        'ext.dusk.drag: startRef "$startRef" not found in registry',
      );
    }

    final endEntry = RefRegistry.lookup(endRef);
    if (endEntry == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        'ext.dusk.drag: endRef "$endRef" not found in registry',
      );
    }

    // Actionability gate (Step 15) — both endpoints must clear the gate
    // before the pointer is committed. We gate startRef first so the agent
    // sees the upstream failure when both ends are bad, mirroring the
    // pre-existing "missing param" check ordering.
    try {
      ensureActionable(startEntry, ref: startRef);
    } on DuskActionabilityException catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        e.message,
      );
    }
    try {
      ensureActionable(endEntry, ref: endRef);
    } on DuskActionabilityException catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        e.message,
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

    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, dynamic>{
        'startRef': startRef,
        'endRef': endRef,
      }),
    );
  } catch (e, st) {
    developer.log(
      '[ai-test-v3] ext.dusk.drag: unexpected error: $e\n$st',
      name: 'ai-test',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      'ext.dusk.drag: $e',
    );
  }
}

/// Registers all three pointer-event VM Service extensions.
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
void registerPointerExtensions() {
  registerExtensionIdempotent('ext.dusk.tap', aiTestTapHandler);
  registerExtensionIdempotent('ext.dusk.hover', aiTestHoverHandler);
  registerExtensionIdempotent('ext.dusk.drag', aiTestDragHandler);
}
