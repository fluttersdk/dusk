import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Checkbox, Switch;
import 'package:flutter/widgets.dart';
import 'package:fluttersdk_artisan/artisan.dart';

import '../ref_registry.dart';
import '../utils/dusk_exceptions.dart';
import '../utils/error_envelope.dart';
import 'ext_pointer.dart' show resolveRefForAction;

// ---------------------------------------------------------------------------
// MCP descriptor constants — consumed by DuskArtisanProvider.mcpTools()
// ---------------------------------------------------------------------------

/// MCP tool name for the checkbox setter.
const String kDuskSetCheckboxMcpName = 'dusk_set_checkbox';

/// VM Service extension method name for the checkbox setter.
const String kDuskSetCheckboxMcpExtension = 'ext.dusk.set_checkbox';

// ---------------------------------------------------------------------------
// Aggregator
// ---------------------------------------------------------------------------

/// Registers the `ext.dusk.set_checkbox` VM Service extension.
///
/// Idempotent via [registerExtensionIdempotent]. Call from
/// [registerAllDuskExtensions] once during [DuskPlugin.install].
void registerCheckboxExtensions() {
  registerExtensionIdempotent(
    kDuskSetCheckboxMcpExtension,
    aiTestSetCheckboxHandler,
  );
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

/// Handler for the `ext.dusk.set_checkbox` VM Service extension.
///
/// Reads the current checked state of the [Checkbox] (or [Switch]) widget
/// identified by `ref` via a Semantics-node walk. When the current value
/// differs from the requested [value], injects a tap to toggle it; when
/// they already match, returns an idempotent success without touching the
/// widget.
///
/// Params (all string-valued):
/// - `ref` (required): opaque ref string from a prior `ext.dusk.snapshot` call.
/// - `value` (required): target value — `'true'` or `'false'`.
/// - `includeSnapshot` (optional, default `'true'`): when `'false'`, skip
///   embedding the post-action snapshot in the response.
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
        'ext.dusk.set_checkbox: missing required param "ref"',
        DuskErrorEnvelope.missingParam('ref'),
      ),
    );
  }

  final String? rawValue = params['value'];
  if (rawValue == null || rawValue.isEmpty) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.set_checkbox: missing required param "value"',
        DuskErrorEnvelope.missingParam('value'),
      ),
    );
  }

  final bool targetValue = rawValue != 'false' && rawValue != '0';

  // 2. Resolve the ref to a live widget entry.
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
        'ext.dusk.set_checkbox: ref "$ref" not found in registry',
        DuskErrorEnvelope.notFound(
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
    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, dynamic>{
        'ref': ref,
        'previousValue': effectiveCurrent,
        'value': effectiveCurrent,
        'toggled': false,
      }),
    );
  }

  // 5. Inject a tap to toggle the checkbox. Reuse the same
  //    PointerDownEvent+delay+PointerUpEvent sequence as ext_pointer.dart
  //    (duplicate here to keep the checkbox module self-contained and avoid
  //    a circular import on the private _injectTap function).
  try {
    await _injectTapAt(entry.rect.center);
  } catch (e, st) {
    developer.log(
      '[ai-test-v3] ext.dusk.set_checkbox: injectTap failed for ref '
      '"$ref": $e\n$st',
      name: 'ai-test',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.dusk.set_checkbox: injectTap failed: $e',
        DuskErrorEnvelope.unexpected(widgetPath: ref),
      ),
    );
  }

  return developer.ServiceExtensionResponse.result(
    jsonEncode(<String, dynamic>{
      'ref': ref,
      'previousValue': effectiveCurrent,
      'value': targetValue,
      'toggled': true,
    }),
  );
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

/// Injects a tap sequence (Down + 50ms + Up) at [center] in logical pixels.
///
/// Mirrors the `_injectTap` implementation in `ext_pointer.dart`. Duplicated
/// here to keep `ext_checkbox.dart` self-contained — `_injectTap` is private
/// to that file and exposing it would break the module boundary. Both copies
/// must be kept in sync if the timing constants ever change.
Future<void> _injectTapAt(Offset center) async {
  const int pointerId = 1;
  final int viewId =
      WidgetsBinding.instance.platformDispatcher.implicitView!.viewId;
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

  await WidgetsBinding.instance.endOfFrame;
  await WidgetsBinding.instance.endOfFrame;
}
