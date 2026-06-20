import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' show CheckedState;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:fluttersdk_artisan/artisan.dart';
import 'package:fluttersdk_wind_diagnostics_contracts/fluttersdk_wind_diagnostics_contracts.dart';

import '../dusk_error_capture.dart';
import '../dusk_plugin.dart';
import '../ref_registry.dart';
import '../utils/error_envelope.dart';

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
/// entry. Magic ships its enrichers via `MagicDuskIntegration.install()`.
/// Wind diagnostics flow through `fluttersdk_wind_diagnostics_contracts.WindDebugRegistry`
/// (registered by `Wind.installDebugResolver()`) and are emitted as a
/// `wind:` sub-block above the enricher loop.
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
///
/// When non-fatal render/build FlutterErrors have been captured (ParentDataWidget
/// misuse, overflow, etc.), a `renderErrors` block is added so a silently-broken
/// widget is visible without a separate `ext.dusk.exceptions` call. Omitted when
/// clean:
///
/// ```json
/// { "snapshot": "<yaml>", "groupId": "...",
///   "renderErrors": { "count": 1,
///     "recent": [ { "type": "FlutterError", "message": "Incorrect use of ..." } ],
///     "hint": "Run dusk:exceptions for full messages + stack traces." } }
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
    // Playwright parity: snapshots are MINIMAL by default — just structural
    // YAML (role/label/value/[ref=eN]). Pass includeEnrichers=true to opt in
    // to Magic + Wind enricher fragments (magicRoute, magicAuthUser,
    // magicRecentHttp, wind.*, etc.). Most agent loops only need refs to
    // act; enricher payload triples snapshot size on rich app pages.
    final bool includeEnrichers =
        (params['includeEnrichers'] ?? 'false') == 'true';
    final Map<String, dynamic> payload = await duskSnapBuild(
      maxDepth: depth,
      includeEnrichers: includeEnrichers,
    );
    return developer.ServiceExtensionResponse.result(jsonEncode(payload));
  } catch (e, stackTrace) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.snap error: $e\n$stackTrace',
      name: 'dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), DuskErrorEnvelope.unexpected()),
    );
  }
}

/// Builds the same `{snapshot, groupId}` payload that `ext.dusk.snap` emits.
///
/// Production callers in this package (action handlers in Step 3.2) reuse
/// this to embed a fresh accessibility snapshot in their action responses
/// (Playwright `setIncludeSnapshot()` parity). Behaves identically to a
/// direct call to [duskSnapHandler]: walks the live Semantics tree, mints
/// `eN` ref tokens via [RefRegistry], invokes every enricher registered on
/// [DuskPlugin.enrichers], and serialises to YAML.
Future<Map<String, dynamic>> duskSnapBuild({
  int? maxDepth,
  bool includeEnrichers = false,
}) async {
  final String groupId = 'snapshot-${DateTime.now().microsecondsSinceEpoch}';
  final SemanticsHandle handle = WidgetsBinding.instance.ensureSemantics();
  try {
    final Map<RenderObject, Element> elementByRenderObject =
        _buildElementByRenderObject();

    // Walk rootPipelineOwner AND descend into every child pipeline owner.
    // The Flutter test harness, Flutter web, and modern engine configs
    // host the actual widget tree under a CHILD pipeline owner; the root
    // owner's semanticsOwner is typically null in those contexts, so a
    // root-only walk emits an empty buffer. Mirrors the child-walk fix
    // already in place at ext_find.dart for the q-handle re-resolver.
    final StringBuffer buffer = StringBuffer();
    void walkOwner(PipelineOwner owner) {
      final SemanticsNode? root = owner.semanticsOwner?.rootSemanticsNode;
      if (root != null) {
        _emitNode(
          node: root,
          depth: 0,
          maxDepth: maxDepth,
          buffer: buffer,
          groupId: groupId,
          elementByRenderObject: elementByRenderObject,
          includeEnrichers: includeEnrichers,
        );
      }
      owner.visitChildren(walkOwner);
    }

    walkOwner(RendererBinding.instance.rootPipelineOwner);

    // Surface captured non-fatal render/build FlutterErrors (ParentDataWidget
    // misuse, overflow, etc.) directly in the snapshot. A widget that throws at
    // build time can render partially and stay invisible in the semantics tree,
    // so an action against it silently no-ops. Including a renderErrors summary
    // here means a broken screen is impossible to miss without remembering to
    // call ext.dusk.exceptions separately. Omitted entirely when there are none.
    final List<Map<String, dynamic>> captured =
        recentCapturedExceptions(limit: 50);

    return <String, dynamic>{
      'snapshot': buffer.toString(),
      'groupId': groupId,
      if (captured.isNotEmpty)
        'renderErrors': <String, dynamic>{
          'count': captured.length,
          'recent': captured
              .take(3)
              .map((Map<String, dynamic> e) => <String, dynamic>{
                    'type': e['type'],
                    'message':
                        (e['message'] as String? ?? '').split('\n').first,
                  })
              .toList(),
          'hint': 'Run dusk:exceptions for full messages + stack traces.',
        },
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
  required bool includeEnrichers,
  RenderObject? enclosingTextboxRenderObject,
}) {
  if (maxDepth != null && depth > maxDepth) return;

  final SemanticsData data = node.getSemanticsData();
  final String label = data.label;
  final String value = data.value;
  final String? role = _roleFor(data);
  final bool interactive = _isInteractive(data);

  // The render object threaded into the children walk for the next textbox
  // containment check. Defaults to the value received from the parent; an
  // emitted (non-collapsed) textbox replaces it with its own render object.
  RenderObject? childEnclosingTextbox = enclosingTextboxRenderObject;

  int childDepth = depth;
  if (interactive && role != null) {
    final RenderObject? renderObject = _renderObjectFor(node);
    final Element? element =
        renderObject == null ? null : elementByRenderObject[renderObject];

    // D2 collapse: a `textbox` node whose render object is a DESCENDANT of an
    // ancestor textbox's render object is a duplicate (e.g. wind's
    // `Semantics(textField:true) > MergeSemantics > TextField`, where
    // RenderEditable owns its own textField node that MergeSemantics cannot
    // absorb). Suppress the inner ref so existing scripts keep resolving the
    // single outer typeable node; descend into children without emitting a
    // line. Containment, never label/value equality (that false-collapses
    // shared-label siblings whose render objects are unrelated).
    if (role == 'textbox' &&
        renderObject != null &&
        enclosingTextboxRenderObject != null &&
        _isRenderDescendantOf(renderObject, enclosingTextboxRenderObject)) {
      node.visitChildren((SemanticsNode child) {
        _emitNode(
          node: child,
          depth: depth,
          maxDepth: maxDepth,
          buffer: buffer,
          groupId: groupId,
          elementByRenderObject: elementByRenderObject,
          includeEnrichers: includeEnrichers,
          enclosingTextboxRenderObject: enclosingTextboxRenderObject,
        );
        return true;
      });
      return;
    }

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

      // D2: the surviving textbox is the one `dusk:type` resolves. Annotate it
      // so agents target the typeable node directly. Additive sub-line; no
      // change to the node-line format. This node's render object becomes the
      // containment anchor for any nested (duplicate) textbox below it.
      if (role == 'textbox') {
        buffer.writeln('${_indent(depth + 1)}typeable: true');
        childEnclosingTextbox = renderObject;
      }

      // Live overflow check: walk the render-object parent chain to find the
      // nearest ancestor (or self) that is currently overflowing.
      // RenderFlex and shifted-box render objects append ' OVERFLOWING' to
      // toStringShort() only while _hasOverflow is true and only in
      // !kReleaseMode. Checking ancestors catches the common case where the
      // interactive widget (button/link) lives inside an overflowing flex row.
      // No retained state; graceful for render types that do not expose the
      // suffix (they are simply not flagged).
      if (_isInsideOverflowingAncestor(renderObject)) {
        buffer.writeln('${_indent(depth + 1)}overflow: true');
      }

      // Enricher loop. Each registered enricher may emit one or more YAML
      // lines indented under the ref entry. Magic + Wind register here.
      // Default off (Playwright parity): callers opt in via
      // includeEnrichers=true on dusk:snap or the includeEnrichers flag on
      // action handlers that embed a post-action snapshot.
      if (includeEnrichers) {
        // Wind diagnostics via fluttersdk_wind_diagnostics_contracts neutral bridge.
        // Wind registers a WindDebugResolver at app boot (Wind.installDebugResolver);
        // dusk reads it here without ever importing wind types. Returns const {}
        // for non-Wind widgets, a graceful no-op.
        final WindDebugResolver? resolver = WindDebugRegistry.current;
        if (resolver != null) {
          final Map<String, Object?> windData = resolver.resolve(element);
          if (windData.isNotEmpty) {
            buffer.writeln('${_indent(depth + 1)}wind:');
            windData.forEach((key, value) {
              if (value is List) {
                buffer.writeln(
                    '${_indent(depth + 2)}$key: [${value.join(', ')}]');
              } else {
                buffer.writeln('${_indent(depth + 2)}$key: $value');
              }
            });
          }
        }
        // Existing enricher loop UNCHANGED (Magic still uses this path).
        for (final enricher in DuskPlugin.enrichers) {
          final String? fragment = enricher(element, RefRegistry.instance);
          if (fragment == null || fragment.isEmpty) continue;
          for (final line
              in const LineSplitter().convert(fragment.trimRight())) {
            if (line.isEmpty) continue;
            buffer.writeln('${_indent(depth + 1)}$line');
          }
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
      includeEnrichers: includeEnrichers,
      enclosingTextboxRenderObject: childEnclosingTextbox,
    );
    return true;
  });
}

/// Returns true if [renderObject] is a strict render-tree descendant of
/// [ancestor].
///
/// Walks the render-object parent chain from [renderObject] upward (the same
/// `current.parent` shape used by [_isInsideOverflowingAncestor]) and reports
/// containment. Used by the D2 textbox collapse: an inner textbox node whose
/// render object lives beneath an outer textbox's render object is a duplicate
/// (e.g. RenderEditable under a `Semantics(textField:true)` wrapper) and is
/// suppressed in favour of the single outer typeable node. Containment is
/// strict (a node is never its own ancestor) so two sibling fields sharing a
/// label never collapse: neither render object is beneath the other.
bool _isRenderDescendantOf(RenderObject renderObject, RenderObject ancestor) {
  RenderObject? current = renderObject.parent;
  while (current != null) {
    if (identical(current, ancestor)) return true;
    current = current.parent;
  }
  return false;
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

/// Returns true if [renderObject] or any of its render-parent ancestors is
/// currently overflowing.
///
/// RenderFlex and shifted-box objects append ' OVERFLOWING' to
/// [RenderObject.toStringShort] in debug / profile mode only while
/// `_hasOverflow` is true. Walking ancestors is necessary because the
/// interactive widget (e.g. a button) is typically a child of the
/// overflowing flex container, not the flex itself.
bool _isInsideOverflowingAncestor(RenderObject renderObject) {
  RenderObject? current = renderObject;
  while (current != null) {
    if (current.toStringShort().contains(' OVERFLOWING')) return true;
    current = current.parent;
  }
  return false;
}
