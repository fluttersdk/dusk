import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' show CheckedState;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:fluttersdk_artisan/artisan.dart';

import '../dusk_plugin.dart';
import '../ref_registry.dart';

/// `ext.dusk.snap` — Playwright-MCP-shaped accessibility snapshot.
///
/// Walks the live [SemanticsOwner] tree and emits a YAML snapshot. Each
/// interactive node receives an `[ref=eN]` token minted via [RefRegistry];
/// subsequent ref-based extensions (`ext.dusk.tap`, `ext.dusk.type`, ...)
/// call [RefRegistry.lookup] to resolve a token back to its hit point
/// or focus target.
///
/// After minting a token, every enricher registered on
/// [DuskPlugin.enrichers] is invoked with the element + ref registry.
/// Non-null returns are appended as indented child lines beneath the ref
/// entry. Magic and Wind ship their own enrichers via
/// `MagicDuskIntegration.install()` and `WindDuskIntegration.install()`.
///
/// ## YAML shape
///
/// ```yaml
/// - text "Hello"
/// - button "Click" [ref=e1]
/// - textbox "Email" [ref=e2]
///     magicFormField: email
///     wind:
///       breakpoint: lg
///       brightness: light
/// ```
///
/// ## Return envelope
///
/// ```json
/// { "snapshot": "<yaml>", "groupId": "snapshot-1700000000000" }
/// ```

void registerSnapExtension() {
  if (!kDebugMode) return;
  registerExtensionIdempotent('ext.dusk.snap', duskSnapHandler);
}

Future<developer.ServiceExtensionResponse> duskSnapHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    final int? depth =
        params['depth'] != null ? int.tryParse(params['depth']!) : null;
    final Map<String, dynamic> payload = await duskSnapBuild(maxDepth: depth);
    return developer.ServiceExtensionResponse.result(jsonEncode(payload));
  } catch (e, stackTrace) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      jsonEncode(<String, String>{
        'error': e.toString(),
        'stackTrace': stackTrace.toString(),
      }),
    );
  }
}

@visibleForTesting
Future<Map<String, dynamic>> duskSnapBuild({int? maxDepth}) async {
  final String groupId = 'snapshot-${DateTime.now().microsecondsSinceEpoch}';
  final SemanticsHandle handle = WidgetsBinding.instance.ensureSemantics();
  try {
    final Map<RenderObject, Element> elementByRenderObject =
        _buildElementByRenderObject();

    final SemanticsNode? root = RendererBinding
        .instance.rootPipelineOwner.semanticsOwner?.rootSemanticsNode;

    final StringBuffer buffer = StringBuffer();
    if (root != null) {
      _emitNode(
        node: root,
        depth: 0,
        maxDepth: maxDepth,
        buffer: buffer,
        groupId: groupId,
        elementByRenderObject: elementByRenderObject,
      );
    }

    return <String, dynamic>{
      'snapshot': buffer.toString(),
      'groupId': groupId,
    };
  } finally {
    handle.dispose();
  }
}

Map<RenderObject, Element> _buildElementByRenderObject() {
  final Map<RenderObject, Element> index = <RenderObject, Element>{};
  final Element? root = WidgetsBinding.instance.rootElement;
  if (root == null) return index;

  void visit(Element element) {
    final RenderObject? renderObject = element.renderObject;
    if (renderObject != null) {
      index.putIfAbsent(renderObject, () => element);
    }
    element.visitChildElements(visit);
  }

  root.visitChildElements(visit);
  return index;
}

void _emitNode({
  required SemanticsNode node,
  required int depth,
  required int? maxDepth,
  required StringBuffer buffer,
  required String groupId,
  required Map<RenderObject, Element> elementByRenderObject,
}) {
  if (maxDepth != null && depth > maxDepth) return;

  final SemanticsData data = node.getSemanticsData();
  final String label = data.label;
  final String value = data.value;
  final String? role = _roleFor(data);
  final bool interactive = _isInteractive(data);

  int childDepth = depth;
  if (interactive && role != null) {
    final RenderObject? renderObject = _renderObjectFor(node);
    final Element? element =
        renderObject == null ? null : elementByRenderObject[renderObject];

    if (renderObject != null && element != null) {
      final Rect rect = _globalRectFor(renderObject);
      final String token = RefRegistry.register(
        rect: rect,
        element: element,
        groupId: groupId,
        isTextField: data.flagsCollection.isTextField,
        node: node,
        renderObject: renderObject,
      );

      buffer.write('${_indent(depth)}- $role "${_escape(label)}"');
      if (value.isNotEmpty) {
        buffer.write(': "${_escape(value)}"');
      }
      buffer.writeln(' [ref=$token]');

      // Enricher loop. Each registered enricher may emit one or more YAML
      // lines indented under the ref entry. Magic + Wind register here.
      for (final enricher in DuskPlugin.enrichers) {
        final String? fragment = enricher(element, RefRegistry.instance);
        if (fragment == null || fragment.isEmpty) continue;
        for (final line in const LineSplitter().convert(fragment.trimRight())) {
          if (line.isEmpty) continue;
          buffer.writeln('${_indent(depth + 1)}$line');
        }
      }

      childDepth = depth + 1;
    }
  } else if (label.isNotEmpty || value.isNotEmpty) {
    final String textValue = value.isNotEmpty ? value : label;
    buffer.writeln('${_indent(depth)}- text "${_escape(textValue)}"');
    childDepth = depth + 1;
  }

  node.visitChildren((SemanticsNode child) {
    _emitNode(
      node: child,
      depth: childDepth,
      maxDepth: maxDepth,
      buffer: buffer,
      groupId: groupId,
      elementByRenderObject: elementByRenderObject,
    );
    return true;
  });
}

String? _roleFor(SemanticsData data) {
  final SemanticsFlags flags = data.flagsCollection;
  if (flags.isTextField) return 'textbox';
  if (flags.isChecked != CheckedState.none) return 'checkbox';
  if (flags.isLink) return 'link';
  if (flags.isHeader) return 'heading';
  if (flags.isImage) return 'image';
  if (flags.isButton || data.hasAction(SemanticsAction.tap)) {
    return 'button';
  }
  return null;
}

bool _isInteractive(SemanticsData data) {
  if (data.hasAction(SemanticsAction.tap)) return true;
  final SemanticsFlags flags = data.flagsCollection;
  return flags.isTextField ||
      flags.isChecked != CheckedState.none ||
      flags.isLink ||
      flags.isButton ||
      flags.isHeader ||
      flags.isImage;
}

RenderObject? _renderObjectFor(SemanticsNode node) {
  final Element? root = WidgetsBinding.instance.rootElement;
  if (root == null) return null;
  RenderObject? match;
  void visit(Element element) {
    if (match != null) return;
    final RenderObject? renderObject = element.renderObject;
    if (renderObject != null && identical(renderObject.debugSemantics, node)) {
      match = renderObject;
      return;
    }
    element.visitChildElements(visit);
  }

  root.visitChildElements(visit);
  return match;
}

Rect _globalRectFor(RenderObject renderObject) {
  if (renderObject is! RenderBox) return Rect.zero;
  if (!renderObject.hasSize) return Rect.zero;
  final Offset topLeft = renderObject.localToGlobal(Offset.zero);
  return topLeft & renderObject.size;
}

String _indent(int depth) => '  ' * depth;

String _escape(String input) =>
    input.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
