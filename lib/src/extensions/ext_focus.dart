import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:fluttersdk_artisan/artisan.dart';

import '../utils/error_envelope.dart';
import 'ext_pointer.dart' show resolveRefForAction;
import 'ext_snapshot.dart' show duskSnapBuild;

const String kDuskFocusMcpName = 'dusk_focus';
const String kDuskFocusMcpExtension = 'ext.dusk.focus';
const String kDuskBlurMcpName = 'dusk_blur';
const String kDuskBlurMcpExtension = 'ext.dusk.blur';

bool _parseBoolFlag(
  Map<String, String> params,
  String name, {
  required bool defaultValue,
}) {
  final String? raw = params[name];
  if (raw == null || raw.isEmpty) return defaultValue;
  return raw != 'false' && raw != '0';
}

Future<void> _appendSnapshotIfRequested(
  Map<String, dynamic> payload,
  Map<String, String> params,
) async {
  if (!_parseBoolFlag(params, 'includeSnapshot', defaultValue: false)) {
    return;
  }
  final Map<String, dynamic> snap = await duskSnapBuild();
  payload['snapshot'] = snap['snapshot'];
}

/// Handler for `ext.dusk.focus` — requests keyboard focus on the widget
/// resolved by [params]['ref'].
///
/// Walks the resolved element to find the nearest `Focus` widget (or
/// `EditableText` for text fields) and calls `FocusNode.requestFocus()`.
/// Playwright parity: `locator.focus()` sets the keyboard focus to the
/// element without triggering a click.
Future<developer.ServiceExtensionResponse> aiTestFocusHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    final String? ref = params['ref'];
    if (ref == null || ref.isEmpty) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.focus: missing required param "ref"',
          DuskErrorEnvelope.missingParam('ref'),
        ),
      );
    }
    final entry = resolveRefForAction(ref);
    if (entry == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.focus: ref "$ref" not found in registry',
          DuskErrorEnvelope.notFound(ref: ref),
        ),
      );
    }
    // Resolve the FocusNode in 3 stages so TextField (whose internal Focus
    // lives BELOW the captured Semantics element) is reachable:
    // 1. Ancestor Focus — Focus.maybeOf walks UP from entry.element.
    // 2. Descendant EditableText — TextField wraps an EditableText whose
    //    focusNode is the actual editing-focus target; common case.
    // 3. Descendant Focus widget — generic fall-back for non-text focus
    //    targets whose Focus sits below the snap-captured element.
    FocusNode? node = Focus.maybeOf(entry.element);
    node ??= _findDescendantFocusNode(entry.element);
    if (node == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.focus: no Focus ancestor or descendant for ref "$ref"',
          DuskErrorEnvelope.unexpected(),
        ),
      );
    }
    node.requestFocus();
    await WidgetsBinding.instance.endOfFrame;
    final Map<String, dynamic> payload = <String, dynamic>{
      'ref': ref,
      'focused': true,
    };
    await _appendSnapshotIfRequested(payload, params);
    return developer.ServiceExtensionResponse.result(jsonEncode(payload));
  } catch (e, stackTrace) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.focus error: $e\n$stackTrace',
      name: 'dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), DuskErrorEnvelope.unexpected()),
    );
  }
}

/// Handler for `ext.dusk.blur` — clears keyboard focus.
///
/// Playwright parity: `locator.blur()` removes focus from the element.
/// When `ref` is provided we blur ONLY when the resolved element is the
/// primary focused node. When `ref` is omitted we clear whatever has
/// primary focus (Playwright `page.evaluate(() => document.activeElement.blur())`
/// equivalent).
Future<developer.ServiceExtensionResponse> aiTestBlurHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    final FocusManager fm = FocusManager.instance;
    final FocusNode? primary = fm.primaryFocus;
    primary?.unfocus();
    await WidgetsBinding.instance.endOfFrame;
    final Map<String, dynamic> payload = <String, dynamic>{
      'blurred': true,
      'hadFocus': primary != null,
    };
    await _appendSnapshotIfRequested(payload, params);
    return developer.ServiceExtensionResponse.result(jsonEncode(payload));
  } catch (e, stackTrace) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.blur error: $e\n$stackTrace',
      name: 'dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), DuskErrorEnvelope.unexpected()),
    );
  }
}

/// Walks descendants of [element] looking for a focus target. Returns the
/// first `EditableText.focusNode` (TextField / text-input case) or the first
/// `Focus.focusNode` encountered, whichever comes first in depth-first order.
/// Returns null when no candidate is found.
FocusNode? _findDescendantFocusNode(Element element) {
  FocusNode? found;
  void visitor(Element child) {
    if (found != null) return;
    final Widget widget = child.widget;
    if (widget is EditableText) {
      found = widget.focusNode;
      return;
    }
    if (widget is Focus) {
      // Prefer the widget's own focusNode; fall back to the inherited
      // Focus.of for cases where Focus delegates to a parent FocusScope.
      found = widget.focusNode ?? Focus.maybeOf(child);
      if (found != null) return;
    }
    child.visitChildElements(visitor);
  }

  element.visitChildElements(visitor);
  return found;
}

void registerFocusExtensions() {
  registerExtensionIdempotent(kDuskFocusMcpExtension, aiTestFocusHandler);
  registerExtensionIdempotent(kDuskBlurMcpExtension, aiTestBlurHandler);
}
