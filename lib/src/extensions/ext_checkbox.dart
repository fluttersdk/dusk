import 'dart:developer' as developer;
import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:dowel/dowel.dart';

import '../ref_registry.dart';
import '../utils/actionability_gate.dart' show resolveViewFor;
import '../utils/tapir_exceptions.dart';
import '../utils/tapir_register.dart';
import '../utils/tapir_response.dart';
import '../utils/effect_report.dart';
import '../utils/error_envelope.dart';
import '../utils/frame_sync.dart';
import '../utils/perf_interaction.dart';
import 'ext_pointer.dart' show resolveRefForAction;

// ---------------------------------------------------------------------------
// MCP descriptor constants — consumed by TapirDowelProvider.mcpTools()
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
    aiTestSetCheckboxHandler,
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
/// differs from the requested [value], injects a tap to toggle it; when
/// they already match, returns an idempotent success without touching the
/// widget.
///
/// Params (all string-valued):
/// - `ref` (required): opaque ref string from a prior `ext.tapir.snapshot` call.
/// - `value` (required): target value — `'true'` or `'false'`.
/// - `includeSnapshot`: accepted and ignored. The response never embeds a
///   snapshot; run `ext.tapir.snap` afterwards to see the post-toggle tree.
///
/// Response JSON (default):
/// ```json
/// {
///   "ref": "e3",
///   "previousValue": false,
///   "value": true,
///   "toggled": true
/// }
/// ```
Future<developer.ServiceExtensionResponse> aiTestSetCheckboxHandler(
  String method,
  Map<String, String> params,
) async {
  // 1. Validate required params before any widget-tree access.
  final String? ref = params['ref'];
  if (ref == null || ref.isEmpty) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.tapir.set_checkbox: missing required param "ref"',
        TapirErrorEnvelope.missingParam('ref'),
      ),
    );
  }

  final String? rawValue = params['value'];
  if (rawValue == null || rawValue.isEmpty) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.tapir.set_checkbox: missing required param "value"',
        TapirErrorEnvelope.missingParam('value'),
      ),
    );
  }

  final bool targetValue = rawValue != 'false' && rawValue != '0';

  // 2. Resolve the ref to a live widget entry.
  final RefEntry? entry;
  try {
    entry = resolveRefForAction(ref);
  } on TapirStaleHandleException catch (e) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.message, TapirErrorEnvelope.stale(ref)),
    );
  }
  if (entry == null) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.tapir.set_checkbox: ref "$ref" not found in registry',
        TapirErrorEnvelope.notFound(
          ref: ref,
          candidates: collectSnapshotCandidates(),
        ),
      ),
    );
  }

  // 3. Read the current checked state from the ref's Semantics node.
  final bool? currentValue = _readCheckedState(entry);
  if (currentValue == null) {
    // Fall back to false when no checkbox state is detectable so the handler
    // stays non-crashing; the tap below will then toggle the widget.
  }
  final bool effectiveCurrent = currentValue ?? false;

  // 4. Idempotent: no-op when the current value already matches the target.
  if (effectiveCurrent == targetValue) {
    return tapirResult(<String, dynamic>{
      'ref': ref,
      'previousValue': effectiveCurrent,
      'value': effectiveCurrent,
      'toggled': false,
      'effect': checkedEffect(
        expected: targetValue,
        before: effectiveCurrent,
        after: effectiveCurrent,
      ),
    });
  }

  // 5. Inject a tap to toggle the checkbox. Reuse the same
  //    PointerDownEvent+delay+PointerUpEvent sequence as ext_pointer.dart
  //    (duplicate here to keep the checkbox module self-contained and avoid
  //    a circular import on the private _injectTap function).
  final Offset center = entry.rect.center;
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
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.tapir.set_checkbox: injectTap failed: $e',
        TapirErrorEnvelope.unexpected(widgetPath: ref),
      ),
    );
  }

  // 6. Re-read the widget rather than reporting the value we asked for. A
  //    control whose parent rejects the change, or one whose tap landed on
  //    an overlay, keeps its old state, and `value: targetValue` would call
  //    that a success.
  final bool? settledValue = _readCheckedState(entry);

  return tapirResult(<String, dynamic>{
    'ref': ref,
    'previousValue': effectiveCurrent,
    'value': targetValue,
    'toggled': true,
    'effect': checkedEffect(
      expected: targetValue,
      before: effectiveCurrent,
      after: settledValue,
    ),
  });
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Reads the checked (checkbox) or toggled (switch) state of the control that
/// [entry] names, from its Semantics node.
///
/// The Semantics flags are the one place every checkable widget reports its
/// state, whichever library built it (`flutter/material`, `material_ui`,
/// `wind_kit`, a hand-built `Semantics`). The node is the one the ref was
/// minted from; an entry without one (the Element-tree walk behind
/// `find_by_text`) falls back to the nearest node at or above its render
/// object. A mixed checkbox reads as unchecked.
///
/// Returns `null` when the node carries neither flag, or when Semantics is off.
bool? _readCheckedState(RefEntry entry) {
  // 1. Find the node: the one the ref was minted from, else the closest
  //    ancestor render object that owns one.
  SemanticsNode? node = entry.node;
  RenderObject? render = entry.renderObject ?? entry.element.renderObject;
  while (node == null && render != null) {
    node = render.debugSemantics;
    render = render.parent;
  }
  if (node == null) return null;

  // 2. The merged data carries the flags of every descendant folded into the
  //    node, which is how a labelled tile reports its inner checkbox.
  final SemanticsFlags flags = node.getSemanticsData().flagsCollection;
  if (flags.isChecked != CheckedState.none) {
    return flags.isChecked == CheckedState.isTrue;
  }
  if (flags.isToggled != Tristate.none) {
    return flags.isToggled == Tristate.isTrue;
  }
  return null;
}

/// Injects a tap sequence (Down + 50ms + Up) at [center] in logical pixels,
/// into the view [element] belongs to.
///
/// Mirrors the `_injectTap` implementation in `ext_pointer.dart`. Duplicated
/// here to keep `ext_checkbox.dart` self-contained — `_injectTap` is private
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
