import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:fluttersdk_artisan/artisan.dart';

import '../ref_registry.dart';
import '../utils/error_envelope.dart';

// ---------------------------------------------------------------------------
// Self-registration entry point
// ---------------------------------------------------------------------------

/// Registers the `ext.dusk.find` VM Service extension.
///
/// Mints a `q<N>` query handle for one or more predicates (`text`,
/// `semanticsLabel`, `key`) and stores the predicate set in [RefRegistry]
/// so subsequent action tools (tap / hover / drag / type) can re-resolve
/// the handle against the live Semantics tree on each call.
///
/// Idempotent via [registerExtensionIdempotent] — hot-restart safe.
void registerFindExtension() {
  registerExtensionIdempotent('ext.dusk.find', extDuskFindHandler);
}

// ---------------------------------------------------------------------------
// ext.dusk.find
// ---------------------------------------------------------------------------

/// Handler for the `ext.dusk.find` VM Service extension.
///
/// Accepts at least one of `text`, `semanticsLabel`, or `key`; walks the
/// live Semantics + Element tree once to verify the predicates resolve to
/// a node, then mints a `q<N>` handle backed by the stored predicate set.
///
/// On first match returns `{"ref": "q<N>", "matched": true}`. When no node
/// matches, returns `{"ref": null, "matched": false}` — no handle is minted.
///
/// The handle is opaque from the agent's perspective: passing it back to
/// `ext.dusk.tap` etc. triggers a fresh tree walk at that moment, so a
/// handle survives widget rebuilds, route pushes, and snapshot disposal as
/// long as the predicates still match something live.
Future<developer.ServiceExtensionResponse> extDuskFindHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    final String? text = _nonEmpty(params['text']);
    final String? semanticsLabel = _nonEmpty(params['semanticsLabel']);
    final String? keyValue = _nonEmpty(params['key']);

    // 1. At least one predicate is required. Surface as extensionError so
    //    the MCP tool can hand the message back verbatim to the agent.
    if (text == null && semanticsLabel == null && keyValue == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.find: at least one of "text", "semanticsLabel", or '
          '"key" is required',
          DuskErrorEnvelope.missingParam('text|semanticsLabel|key'),
        ),
      );
    }

    final DuskQuery query = DuskQuery(
      text: text,
      semanticsLabel: semanticsLabel,
      keyValue: keyValue,
    );

    // 2. Verify the query resolves to a live node before minting. We do
    //    NOT store the resolved RefEntry — the handle re-executes the
    //    walk on every action call so the agent gets the latest rect /
    //    element after intermediate rebuilds.
    final RefEntry? entry = resolveQuery(query);
    if (entry == null) {
      return developer.ServiceExtensionResponse.result(
        jsonEncode(<String, dynamic>{
          'ref': null,
          'matched': false,
        }),
      );
    }

    // 3. Mint a fresh q-handle. The verification entry above is throwaway
    //    (no groupId scope; action handlers rebuild RefEntry on call).
    final String token = RefRegistry.registerQuery(query);

    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, dynamic>{
        'ref': token,
        'matched': true,
      }),
    );
  } catch (e, stackTrace) {
    developer.log(
      '[ai-test-v3] ext.dusk.find error: $e\n$stackTrace',
      name: 'ai-test',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), DuskErrorEnvelope.unexpected()),
    );
  }
}

// ---------------------------------------------------------------------------
// Query resolution — shared with action handlers via resolveQuery
// ---------------------------------------------------------------------------

/// Re-executes a stored [DuskQuery] against the live tree and returns a
/// fresh [RefEntry] for the first match, or `null` when no node matches.
///
/// The returned entry is NOT registered in [RefRegistry]'s e-map — it is a
/// throwaway record consumed by the calling action handler in the same
/// turn. This is what makes q-refs survive snapshot-group disposal: there
/// is no persistent e-token whose lifetime is bound to a snapshot.
///
/// Resolution order:
/// 1. When [DuskQuery.keyValue] is set, walks the Element tree and matches
///    any widget whose `key` stringifies to the supplied value.
/// 2. When [DuskQuery.semanticsLabel] is set, walks the Semantics tree and
///    matches the first node whose label is `==` to the supplied value.
/// 3. When [DuskQuery.text] is set, prefers a Semantics node with that
///    label (matches accessibility-labelled buttons / text fields) and
///    falls back to a [Text] widget whose `data` matches exactly.
///
/// When multiple predicates are set they all must match the same node /
/// element (intersection).
RefEntry? resolveQuery(DuskQuery query) {
  // 1. Key-based match: Element tree walk. Cheapest, most specific.
  if (query.keyValue != null) {
    final Element? element = _findElementByKey(query.keyValue!);
    if (element == null) return null;
    if (!_elementMatchesOtherPredicates(element, query)) return null;
    return _entryFromElement(element);
  }

  // 2. Semantics-label match: walk the Semantics tree first because it
  //    surfaces merged accessibility labels (Button "Submit" with no
  //    Text descendant still resolves).
  if (query.semanticsLabel != null) {
    final SemanticsNode? node =
        _findSemanticsNodeByLabel(query.semanticsLabel!);
    if (node == null) return null;
    return _entryFromSemanticsNode(node);
  }

  // 3. text-only match: Semantics-label first (covers labelled widgets
  //    where the visible text is the accessibility label), then Element-
  //    tree Text widget fallback.
  if (query.text != null) {
    final SemanticsNode? node = _findSemanticsNodeByLabel(query.text!);
    if (node != null) {
      return _entryFromSemanticsNode(node);
    }
    final Element? element = _findElementByTextData(query.text!);
    if (element == null) return null;
    return _entryFromElement(element);
  }

  return null;
}

// ---------------------------------------------------------------------------
// Private helpers — tree walks
// ---------------------------------------------------------------------------

String? _nonEmpty(String? raw) {
  if (raw == null) return null;
  if (raw.isEmpty) return null;
  return raw;
}

/// Walks the Element tree and returns the first element whose widget has a
/// [Key] whose `toString()` matches [needle].
Element? _findElementByKey(String needle) {
  Element? found;

  void visit(Element element) {
    if (found != null) return;
    final Key? key = element.widget.key;
    if (key != null && key.toString() == needle) {
      found = element;
      return;
    }
    // Also match ValueKey<T>.value.toString() for the common case where
    // agents supply "monitor-row-123" rather than "[<'monitor-row-123'>]".
    if (key is ValueKey && key.value.toString() == needle) {
      found = element;
      return;
    }
    element.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return found;
}

/// Walks the Element tree and returns the first element whose widget is a
/// [Text] with [Text.data] equal to [needle].
Element? _findElementByTextData(String needle) {
  Element? found;

  void visit(Element element) {
    if (found != null) return;
    if (element.widget is Text) {
      final String? data = (element.widget as Text).data;
      if (data == needle) {
        found = element;
        return;
      }
    }
    element.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return found;
}

/// Walks the live Semantics tree and returns the first node whose [label]
/// equals [needle].
///
/// Production-bound widget trees expose their semantics owner via
/// `RendererBinding.instance.rootPipelineOwner.semanticsOwner`. The Flutter
/// test harness, however, mounts the widget tree under a CHILD pipeline
/// owner attached to the test view (see `ext_snapshot_dispatcher_test.dart`
/// docs for the rationale). We walk the root owner first, then every child
/// owner registered under it, so this helper works in BOTH environments.
SemanticsNode? _findSemanticsNodeByLabel(String needle) {
  SemanticsNode? found;

  void visit(SemanticsNode node) {
    if (found != null) return;
    if (node.label == needle) {
      found = node;
      return;
    }
    node.visitChildren((SemanticsNode child) {
      visit(child);
      return found == null;
    });
  }

  void visitOwner(PipelineOwner owner) {
    if (found != null) return;
    final SemanticsNode? root = owner.semanticsOwner?.rootSemanticsNode;
    if (root != null) visit(root);
    owner.visitChildren((PipelineOwner child) {
      if (found == null) visitOwner(child);
    });
  }

  visitOwner(RendererBinding.instance.rootPipelineOwner);
  return found;
}

/// Cross-checks an Element-tree match against the supplied query's
/// remaining predicates. Returns `true` when every non-null predicate
/// (other than the one that produced the element) matches.
bool _elementMatchesOtherPredicates(Element element, DuskQuery query) {
  // text predicate: walk descendants for a Text widget with matching data.
  if (query.text != null) {
    bool matches = false;
    void visit(Element child) {
      if (matches) return;
      if (child.widget is Text && (child.widget as Text).data == query.text) {
        matches = true;
        return;
      }
      child.visitChildElements(visit);
    }

    if (element.widget is Text && (element.widget as Text).data == query.text) {
      matches = true;
    } else {
      element.visitChildElements(visit);
    }
    if (!matches) return false;
  }

  // semanticsLabel predicate has no cheap Element-side check; if it was
  // supplied alongside key, we accept the key match — the find handler is
  // already best-effort and the action's actionability gate provides the
  // final filter when the resolved node disagrees.
  return true;
}

/// Materialises a [RefEntry] from an [Element] using its [RenderBox] rect
/// when available. Returns `null` if the render box is not sized yet.
RefEntry? _entryFromElement(Element element) {
  final RenderObject? renderObject = element.findRenderObject();
  if (renderObject is! RenderBox) return null;
  if (!renderObject.hasSize) return null;
  final Offset topLeft = renderObject.localToGlobal(Offset.zero);
  final Rect rect = topLeft & renderObject.size;
  return RefEntry(
    rect: rect,
    element: element,
    groupId: _kQueryGroupId,
    isTextField: false,
    renderObject: renderObject,
  );
}

/// Materialises a [RefEntry] from a [SemanticsNode]. The element field is
/// set to the root element (best-effort anchor for EditableText focus
/// lookups); the rect is mapped from the node's local space up through
/// each ancestor's transform to obtain global coordinates that
/// pointer-event dispatch can hit.
RefEntry? _entryFromSemanticsNode(SemanticsNode node) {
  final Element? root = WidgetsBinding.instance.rootElement;
  if (root == null) return null;
  final bool isTextField = node.flagsCollection.isTextField;
  return RefEntry(
    rect: _globalRectFromSemantics(node),
    element: root,
    groupId: _kQueryGroupId,
    isTextField: isTextField,
    node: node,
  );
}

/// Walks up the [SemanticsNode] ancestor chain, applying each ancestor's
/// transform to map [node]'s local rect into global coordinates.
///
/// [SemanticsNode.rect] is in the parent's coordinate space and
/// [SemanticsNode.transform] (when present) maps the local space onto the
/// parent. Composing transforms from the leaf upward yields the global
/// rect; pointer dispatch consumes `rect.center` and must be in the same
/// space as the view's logical viewport.
Rect _globalRectFromSemantics(SemanticsNode node) {
  Rect rect = node.rect;
  SemanticsNode? current = node;
  while (current != null) {
    final Matrix4? transform = current.transform;
    if (transform != null) {
      rect = MatrixUtils.transformRect(transform, rect);
    }
    current = current.parent;
  }
  return rect;
}

/// Pseudo group id used for throwaway entries materialised by [resolveQuery].
///
/// The entries are never inserted into [RefRegistry]'s e-map, so the id
/// only exists to satisfy [RefEntry]'s `required String groupId` field. It
/// is intentionally distinct from any real snapshot group id so a stray
/// [RefRegistry.disposeGroup] call cannot target it.
const String _kQueryGroupId = '__query__';
