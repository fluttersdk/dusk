import 'dart:developer' as developer;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Checkbox, Switch;
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
/// Reads the current checked state of the [Checkbox] (or [Switch]) widget
/// identified by `ref` via a Semantics-node walk. When the current value
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

  // 3. Read the current checked state via the Semantics node associated with
  //    the ref's element. Walk up and down the element tree to find the
  //    nearest Checkbox or Switch widget and read its current value.
  final bool? currentValue = _readCheckboxValue(entry.element);
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
  final bool? settledValue = _readCheckboxValue(entry.element);

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

/// Reads the current boolean checked value from the element's associated
/// Semantics data.
///
/// Strategy (in order):
/// 1. Walk the element itself — if it IS a [Checkbox] or [Switch] stateful
///    widget, read the [CheckboxState] or [SwitchState] value directly.
/// 2. Walk descendants — find the nearest Checkbox/Switch descendant.
/// 3. Fall back to Semantics-node `isChecked` flag via the render pipeline.
///
/// Returns `null` when no checkable state is detectable.
bool? _readCheckboxValue(Element element) {
  // Try direct element and descendants.
  final bool? direct = _checkboxValueFromElement(element);
  if (direct != null) return direct;

  // Walk descendants.
  bool? found;
  void visit(Element child) {
    if (found != null) return;
    final bool? v = _checkboxValueFromElement(child);
    if (v != null) {
      found = v;
      return;
    }
    child.visitChildren(visit);
  }

  element.visitChildren(visit);
  return found;
}

/// Extracts the current boolean checked value from a single [element] if it
/// wraps a [Checkbox] or [Switch] widget.
///
/// Returns `null` when the element does not represent a checkable widget.
bool? _checkboxValueFromElement(Element element) {
  final Widget widget = element.widget;
  if (widget is Checkbox) {
    return widget.value ?? false;
  }
  if (widget is Switch) {
    return widget.value;
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
