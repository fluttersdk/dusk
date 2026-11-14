import 'dart:developer' as developer;
import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:dowel/dowel.dart';

import '../ref_registry.dart';
import '../utils/actionability_gate.dart'
    show
        ActionabilityReport,
        dispatchRectOf,
        ensureActionable,
        resolveViewFor,
        stampChecks;
import '../utils/tapir_exceptions.dart';
import '../utils/tapir_register.dart';
import '../utils/tapir_response.dart';
import '../utils/effect_report.dart';
import '../utils/error_envelope.dart';
import '../utils/frame_sync.dart';
import '../utils/perf_interaction.dart';
import 'ext_pointer.dart' show resolveRefForAction;

// ---------------------------------------------------------------------------
// MCP descriptor constants, consumed by TapirDowelProvider.mcpTools()
// ---------------------------------------------------------------------------

/// MCP tool name for the checkbox setter.
const String kTapirSetCheckboxMcpName = 'tapir_set_checkbox';

/// VM Service extension method name for the checkbox setter.
const String kTapirSetCheckboxMcpExtension = 'ext.tapir.set_checkbox';

// ---------------------------------------------------------------------------
// Aggregator
// ---------------------------------------------------------------------------

/// Registers the `ext.tapir.set_checkbox` VM Service extension.
///
/// Idempotent via [registerExtensionIdempotent]. Call from
/// [registerAllTapirExtensions] once during [TapirPlugin.install].
void registerCheckboxExtensions() {
  registerTapirExtension(
    kTapirSetCheckboxMcpExtension,
    tapirSetCheckboxHandler,
  );
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

/// Handler for the `ext.tapir.set_checkbox` VM Service extension.
///
/// Reads the current checked (or toggled) state of the control identified by
/// `ref` from its Semantics node, so a material, material_ui, wind_kit or
/// hand-built checkbox or switch answers the same way. When the current value
/// differs from the requested `value`, runs the actionability gate on the
/// control (scrolling it into view, refusing one that is disabled, covered or
/// moving with the gate's reason) and injects a tap to toggle it; when they
/// already match, returns an idempotent success without touching the widget.
///
/// Params (all string-valued):
/// - `ref` (required): opaque ref string from a prior `ext.tapir.snap` call.
/// - `value` (required): target value, `'true'` or `'false'` (`'1'` and
///   `'0'` too); anything else is refused as `invalid_param`.
/// - `checkStable` / `checkReceivesEvents` (optional, default `'true'`): the
///   gate opt-outs the other gated verbs take.
/// - `includeSnapshot`: accepted and ignored. The response never embeds a
///   snapshot; run `ext.tapir.snap` afterwards to see the post-toggle tree.
///
/// Response JSON (default); `value` is the state read back after the tap,
/// not the request, so it equals `effect.after`:
/// ```json
/// {
///   "ref": "e3",
///   "previousValue": false,
///   "value": true,
///   "toggled": true
/// }
/// ```
Future<developer.ServiceExtensionResponse> tapirSetCheckboxHandler(
  String method,
  Map<String, String> params,
) async {
  // 1. Validate required params before any widget-tree access.
  final String? ref = params['ref'];
  if (ref == null || ref.isEmpty) {
    return tapirError(
      'ext.tapir.set_checkbox: missing required param "ref"',
      TapirErrorEnvelope.missingParam('ref'),
    );
  }

  final String? rawValue = params['value'];
  if (rawValue == null || rawValue.isEmpty) {
    return tapirError(
      'ext.tapir.set_checkbox: missing required param "value"',
      TapirErrorEnvelope.missingParam('value'),
    );
  }

  // Only a boolean the CLI or MCP can send counts: anything else ("flase")
  // used to read as true and tick the box.
  final bool targetValue;
  switch (rawValue) {
    case 'true' || '1':
      targetValue = true;
    case 'false' || '0':
      targetValue = false;
    default:
      return tapirError(
        'ext.tapir.set_checkbox: value "$rawValue" is not a boolean; pass '
        'true or false',
        TapirErrorEnvelope.invalidParam('value'),
      );
  }

  // 2. Resolve the ref to a live widget entry.
  final RefEntry? entry;
  try {
    entry = resolveRefForAction(ref);
  } on TapirStaleHandleException catch (e) {
    return tapirError(e.message, TapirErrorEnvelope.stale(ref));
  }
  if (entry == null) {
    return tapirError(
      'ext.tapir.set_checkbox: ref "$ref" not found in registry',
      TapirErrorEnvelope.notFound(
        ref: ref,
        candidates: collectSnapshotCandidates(),
      ),
    );
  }

  // 3. Read the current checked state from the ref's Semantics node. A ref
  //    with no checkable state is refused: tapping it on a guess toggles
  //    whatever sits under the rect and reports a state nobody read. So is a
  //    container holding several controls: no single tap target names them.
  final _CheckedRead current = _readCheckedState(entry);
  if (current.ambiguous) {
    return tapirError(
      'ext.tapir.set_checkbox: ref "$ref" holds more than one checkbox, '
      'switch or radio; pass the ref of one of them',
      TapirErrorEnvelope.refused(widgetPath: ref),
    );
  }
  if (!current.found) {
    return tapirError(
      'ext.tapir.set_checkbox: ref "$ref" has no checked or toggled state '
      'in its Semantics node; pass the ref of a checkbox, switch or radio',
      TapirErrorEnvelope.refused(widgetPath: ref),
    );
  }
  final bool? currentValue = current.value;

  // 4. Idempotent: no-op when the current value already matches the target.
  //    A mixed control (null) matches neither target, so it is always tapped.
  if (currentValue == targetValue) {
    return tapirResult(<String, dynamic>{
      'ref': ref,
      'previousValue': currentValue,
      'value': currentValue,
      'toggled': false,
      'effect': checkedEffect(
        expected: targetValue,
        before: currentValue,
        after: currentValue,
      ),
    });
  }

  // 5. The gate the other tapping verbs run, on the control the tap is for:
  //    one below the fold is scrolled into view, and one that is disabled,
  //    covered or moving is refused with the gate's reason rather than
  //    tapped where it is not.
  final RefEntry target = _controlEntry(entry, current.control);
  final ActionabilityReport gate;
  try {
    gate = await ensureActionable(
      target,
      ref: ref,
      checkStable: !_offValues.contains(params['checkStable']),
      checkReceivesEvents: !_offValues.contains(params['checkReceivesEvents']),
    );
  } on TapirActionabilityException catch (e) {
    return tapirError(
      e.message,
      TapirErrorEnvelope.fromActionabilityReason(e.ref, e.reason),
    );
  }

  // 6. Inject a tap to toggle the checkbox. Reuse the same
  //    PointerDownEvent+delay+PointerUpEvent sequence as ext_pointer.dart
  //    (duplicate here to keep the checkbox module self-contained and avoid
  //    a circular import on the private _injectTap function). The point is
  //    read live because the gate may have scrolled: a state read off a
  //    control is tapped at that control, since the ref's own centre can sit
  //    on a sibling control or on nothing at all.
  final Rect? live = identical(target, entry)
      ? _readCheckedState(entry).rect ?? dispatchRectOf(entry)
      : dispatchRectOf(target);
  final Offset center = (live ?? target.rect).center;
  final Element element = entry.element;
  try {
    await runPerfInteraction<void>(
      'set_checkbox',
      ref,
      () => _injectTapAt(center, element),
    );
  } catch (e, st) {
    developer.log(
      '[tapir] ext.tapir.set_checkbox: injectTap failed for ref '
      '"$ref": $e\n$st',
      name: 'tapir',
    );
    return tapirError(
      'ext.tapir.set_checkbox: injectTap failed: $e',
      TapirErrorEnvelope.unexpected(widgetPath: ref),
    );
  }

  // 7. Re-read the widget rather than reporting the value we asked for. A
  //    control whose parent rejects the change, or one whose tap landed on
  //    an overlay, keeps its old state, and `value: targetValue` would call
  //    that a success.
  final bool? settledValue = _readCheckedState(entry).value;

  final Map<String, dynamic> payload = <String, dynamic>{
    'ref': ref,
    'previousValue': currentValue,
    'value': settledValue,
    'toggled': true,
    'effect': checkedEffect(
      expected: targetValue,
      before: currentValue,
      after: settledValue,
    ),
  };
  stampChecks(payload, gate);
  return tapirResult(payload);
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// The values that switch a gate check off, as the other gated verbs read
/// them.
const Set<String> _offValues = <String>{'false', '0'};

/// A checked-state read: [found] is false when no checkable state was
/// detectable, and [ambiguous] is true when the ref holds several controls
/// that each have one; [value] is null with [found] true for a mixed
/// checkbox, which is neither checked nor unchecked. [rect] is the global
/// logical rect of the control the state came from, and [control] the render
/// object that draws it; both are null when the ref's own rect is the tap
/// target (a state read off an ancestor, or no single control to name).
typedef _CheckedRead = ({
  bool found,
  bool ambiguous,
  bool? value,
  Rect? rect,
  RenderBox? control,
});

const _CheckedRead _notFound = (
  found: false,
  ambiguous: false,
  value: null,
  rect: null,
  control: null,
);

const _CheckedRead _ambiguous = (
  found: false,
  ambiguous: true,
  value: null,
  rect: null,
  control: null,
);

/// The entry the gate and the tap address: the element that builds [control]
/// under [entry], or [entry] itself when there is no control to name or its
/// element is not under the ref.
///
/// Gating the ref instead measures its centre, which for a labelled container
/// is often empty space the hit test passes through, and passing a covered
/// ref would let the tap land on a control the gate never looked at.
RefEntry _controlEntry(RefEntry entry, RenderBox? control) {
  if (control == null || !control.attached || !control.hasSize) return entry;
  Element? owner;
  void visit(Element element) {
    if (owner != null) return;
    if (element is RenderObjectElement &&
        identical(element.renderObject, control)) {
      owner = element;
      return;
    }
    element.visitChildElements(visit);
  }

  visit(entry.element);
  final Element? found = owner;
  if (found == null) return entry;
  return RefEntry(
    rect: control.localToGlobal(Offset.zero) & control.size,
    element: found,
    groupId: entry.groupId,
    isTextField: false,
    node: control.debugSemantics ?? entry.node,
    renderObject: control,
  );
}

/// Reads the checked (checkbox, radio) or toggled (switch) state of the
/// control that [entry] names, from its Semantics node.
///
/// The Semantics flags are the one place every checkable widget reports its
/// state, whichever library built it (`flutter/material`, `material_ui`,
/// `wind_kit`, a hand-built `Semantics`). The node is the one the ref was
/// minted from; an entry without one (the Element-tree walk behind
/// `find_by_text`) falls back to the nearest node at or above its render
/// object.
///
/// Returns [_notFound] when no flag is reachable, or when Semantics is off,
/// and [_ambiguous] when the ref's own node holds more than one control.
_CheckedRead _readCheckedState(RefEntry entry) {
  // 1. Find the node: the one the ref was minted from, else the closest
  //    ancestor render object that owns one. `owned` records whether the
  //    node belongs to the ref itself rather than to a container above it.
  final RenderObject? start = entry.renderObject ?? entry.element.renderObject;
  SemanticsNode? node = entry.node;
  bool owned = node != null;
  RenderObject? render = start;
  while (node == null && render != null) {
    node = render.debugSemantics;
    owned = node != null && identical(render, start);
    render = render.parent;
  }
  if (node == null) return _notFound;

  // 2. The merged data carries the flags of every descendant folded into the
  //    node, which is how a merging tile reports its inner checkbox, and how
  //    a bare switch in a labelled container reports its state: a switch is
  //    no semantics boundary, so its flag lands on the container's node. On
  //    the ref's own node, the tap goes to the render object that set the
  //    flag; the container's centre can sit beside the control.
  final _CheckedRead? own = _flagsOf(node);
  if (own != null) {
    final RenderBox? annotated = owned && start != null
        ? _annotatedControl(start)
        : null;
    if (annotated == null) return own;
    return (
      found: true,
      ambiguous: false,
      value: own.value,
      rect: annotated.localToGlobal(Offset.zero) & annotated.size,
      control: annotated,
    );
  }

  // 3. A labelled container that does not merge keeps the control in a
  //    child node. Only the ref's own node is searched: an ancestor's
  //    subtree holds siblings, and borrowing their state is a guess.
  if (!owned) return _notFound;
  final List<SemanticsNode> controls = _checkableDescendants(node);
  if (controls.isEmpty) return _notFound;
  if (controls.length > 1) return _ambiguous;

  // 4. The tap has to land on the control that was read, so the read
  //    carries that node's own rect, and the render object that owns the
  //    node so the gate can measure the control rather than the container.
  final SemanticsNode control = controls.single;
  return (
    found: true,
    ambiguous: false,
    value: _flagsOf(control)!.value,
    rect: _globalRectOf(control, resolveViewFor(entry.element)),
    control: start == null ? null : _nodeOwner(start, control),
  );
}

/// The render box at or under [root] that owns [node], or null when none
/// does (a node owned outside the ref's render subtree).
RenderBox? _nodeOwner(RenderObject root, SemanticsNode node) {
  RenderBox? owner;
  void visit(RenderObject render) {
    if (owner != null) return;
    if (render is RenderBox && identical(render.debugSemantics, node)) {
      owner = render;
      return;
    }
    render.visitChildren(visit);
  }

  visit(root);
  return owner;
}

/// The checked or toggled state [node] itself reports, or null when it has
/// neither flag.
_CheckedRead? _flagsOf(SemanticsNode node) {
  final SemanticsFlags flags = node.getSemanticsData().flagsCollection;
  if (flags.isChecked != CheckedState.none) {
    return (
      found: true,
      ambiguous: false,
      value: switch (flags.isChecked) {
        CheckedState.mixed => null,
        CheckedState.isTrue => true,
        _ => false,
      },
      rect: null,
      control: null,
    );
  }
  if (flags.isToggled != Tristate.none) {
    return (
      found: true,
      ambiguous: false,
      value: flags.isToggled == Tristate.isTrue,
      rect: null,
      control: null,
    );
  }
  return null;
}

/// The descendants of [node] that carry a checked or toggled flag, without
/// looking inside one that does. Stops at two: the caller only tells none,
/// one and several apart.
List<SemanticsNode> _checkableDescendants(SemanticsNode node) {
  final List<SemanticsNode> controls = <SemanticsNode>[];
  void visit(SemanticsNode parent) {
    parent.visitChildren((SemanticsNode child) {
      if (_flagsOf(child) != null) {
        controls.add(child);
      } else {
        visit(child);
      }
      return controls.length < 2;
    });
  }

  visit(node);
  return controls;
}

/// The one laid-out render box at or under [root] whose semantics
/// annotations set a checked, mixed or toggled state, or null when none or
/// several do: with several, no single tap names the state that was read,
/// and the ref's own rect is the honest fallback.
RenderBox? _annotatedControl(RenderObject root) {
  final List<RenderBox> found = <RenderBox>[];
  void visit(RenderObject node) {
    if (found.length > 1) return;
    if (node is SemanticsAnnotationsMixin &&
        node is RenderBox &&
        (node.properties.checked != null ||
            node.properties.mixed != null ||
            node.properties.toggled != null)) {
      found.add(node as RenderBox);
      return;
    }
    node.visitChildren(visit);
  }

  visit(root);
  if (found.length != 1) return null;
  final RenderBox box = found.single;
  return box.attached && box.hasSize ? box : null;
}

/// [node]'s rect in global logical pixels, the space pointer events use.
///
/// A [SemanticsNode.rect] is local to the node; each transform up to the
/// root maps it onto the parent, the way `globalRectFromSemantics` in
/// `ext_find.dart` composes them. The root's transform folds in [view]'s
/// device pixel ratio, so the composed rect is physical and is divided back.
Rect _globalRectOf(SemanticsNode node, FlutterView view) {
  Rect rect = node.rect;
  for (
    SemanticsNode? current = node;
    current != null;
    current = current.parent
  ) {
    final Matrix4? transform = current.transform;
    if (transform != null) {
      rect = MatrixUtils.transformRect(transform, rect);
    }
  }
  final double dpr = view.devicePixelRatio;
  return Rect.fromLTRB(
    rect.left / dpr,
    rect.top / dpr,
    rect.right / dpr,
    rect.bottom / dpr,
  );
}

/// Injects a tap sequence (Down + 50ms + Up) at [center] in logical pixels,
/// into the view [element] belongs to.
///
/// Mirrors the `_injectTap` implementation in `ext_pointer.dart`. Duplicated
/// here to keep `ext_checkbox.dart` self-contained: `_injectTap` is private
/// to that file and exposing it would break the module boundary. Both copies
/// must be kept in sync if the timing constants ever change.
Future<void> _injectTapAt(Offset center, Element element) async {
  const int pointerId = 1;
  final int viewId = resolveViewFor(element).viewId;
  const Duration ts = Duration.zero;

  WidgetsBinding.instance.handlePointerEvent(
    PointerDownEvent(
      pointer: pointerId,
      position: center,
      viewId: viewId,
      timeStamp: ts,
      kind: PointerDeviceKind.touch,
    ),
  );

  await Future<void>.delayed(const Duration(milliseconds: 50));

  WidgetsBinding.instance.handlePointerEvent(
    PointerUpEvent(
      pointer: pointerId,
      position: center,
      viewId: viewId,
      timeStamp: const Duration(milliseconds: 50),
    ),
  );

  await awaitFramesOrTimeout(2);
}
