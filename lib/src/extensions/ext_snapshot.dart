import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' show CheckedState, FlutterView;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:fluttersdk_wind_diagnostics_contracts/fluttersdk_wind_diagnostics_contracts.dart';

import '../dusk_error_capture.dart';
import '../dusk_plugin.dart';
import '../ref_registry.dart';
import '../utils/dusk_register.dart';
import '../utils/dusk_response.dart';
import '../utils/error_envelope.dart';
import '../utils/snapshot_diff.dart';
import '../utils/viewport_visibility.dart';

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
/// A `grep` that is not a valid regex matches as a literal substring and the
/// envelope gains `"grepLiteral": true`; the key is absent otherwise.
///
/// A ref-bearing line outside the viewport ends with ` [offscreen]`, and one
/// whose centre another widget covers ends with ` [occluded]`; a healthy
/// screen carries neither.
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
///     "hint": "Run dusk:exceptions (CLI) or dusk_exceptions (MCP) for full messages + stack traces." } }
/// ```

void registerSnapExtension() {
  // Profile builds carry it so a profile-mode perf session can still be
  // driven; release tree-shakes it.
  if (kReleaseMode) return;
  registerDuskExtension('ext.dusk.snap', duskSnapHandler);
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
    // Narrowing. Unset by default: an unfiltered walk stays byte-identical
    // to what it was.
    final String? within = params['within'];
    final bool interactiveOnly = params['interactiveOnly'] == 'true';
    final String? grep = params['grep'];

    final Map<String, dynamic> payload = await duskSnapBuild(
      maxDepth: depth,
      includeEnrichers: includeEnrichers,
      within: (within != null && within.isNotEmpty) ? within : null,
      interactiveOnly: interactiveOnly,
      grep: (grep != null && grep.isEmpty) ? null : grep,
    );
    return duskResult(payload);
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
  String? within,
  bool interactiveOnly = false,
  String? grep,
}) async {
  final String groupId = 'snapshot-${DateTime.now().microsecondsSinceEpoch}';
  final (RegExp? pattern, bool grepLiteral) = _compileGrep(grep);
  final _SnapFilter filter = _SnapFilter(
    interactiveOnly: interactiveOnly,
    grep: pattern,
  );
  final SemanticsHandle handle = WidgetsBinding.instance.ensureSemantics();
  try {
    final Map<RenderObject, Element> elementByRenderObject =
        _buildElementByRenderObject();
    final Map<String, List<SemanticsNode>> nodesByLabel = _nodesByOwnLabel();

    // Walk rootPipelineOwner AND descend into every child pipeline owner.
    // The Flutter test harness, Flutter web, and modern engine configs
    // host the actual widget tree under a CHILD pipeline owner; the root
    // owner's semanticsOwner is typically null in those contexts, so a
    // root-only walk emits an empty buffer. Mirrors the child-walk fix
    // already in place at ext_find.dart for the q-handle re-resolver.
    final StringBuffer buffer = StringBuffer();

    // `within` replaces the root walk outright rather than filtering it: the
    // caller has already named the subtree, so there is nothing to search.
    if (within != null && within.isNotEmpty) {
      _emitNode(
        node: _resolveWithinNode(within),
        depth: 0,
        maxDepth: maxDepth,
        buffer: buffer,
        groupId: groupId,
        elementByRenderObject: elementByRenderObject,
        nodesByLabel: nodesByLabel,
        includeEnrichers: includeEnrichers,
        filter: filter,
      );
    } else {
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
            nodesByLabel: nodesByLabel,
            includeEnrichers: includeEnrichers,
            filter: filter,
          );
        }
        owner.visitChildren(walkOwner);
      }

      walkOwner(RendererBinding.instance.rootPipelineOwner);
    }

    // Surface captured non-fatal render/build FlutterErrors (ParentDataWidget
    // misuse, overflow, etc.) directly in the snapshot. A widget that throws at
    // build time can render partially and stay invisible in the semantics tree,
    // so an action against it silently no-ops. Including a renderErrors summary
    // here means a broken screen is impossible to miss without remembering to
    // call ext.dusk.exceptions separately. Omitted entirely when there are none.
    final List<Map<String, dynamic>> captured =
        recentCapturedExceptions(limit: 50);

    final String snapshot = buffer.toString();
    // Only the full, default-shaped tree is a fair thing to diff against: a
    // narrowed walk or one carrying enricher lines would read as a wall of
    // added and removed rows next to it.
    final bool unfiltered = maxDepth == null &&
        (within == null || within.isEmpty) &&
        pattern == null &&
        !interactiveOnly &&
        !includeEnrichers;
    if (unfiltered) recordSnapshotBaseline(snapshot);

    return <String, dynamic>{
      'snapshot': snapshot,
      'groupId': groupId,
      if (grepLiteral) 'grepLiteral': true,
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
          'hint': 'Run dusk:exceptions (CLI) or dusk_exceptions (MCP) for '
              'full messages + stack traces.',
        },
    };
  } finally {
    handle.dispose();
  }
}

String? _snapshotBaseline;

/// The text of the last unfiltered snapshot, or `null` before the first one
/// (and after a hot restart, which clears module state).
///
/// Held here rather than in [RefRegistry], whose surface is frozen. It is the
/// reference a later snapshot is diffed against.
String? get snapshotBaseline => _snapshotBaseline;

/// Stores [snapshot] as the new baseline, replacing the previous one.
void recordSnapshotBaseline(String snapshot) {
  _snapshotBaseline = snapshot;
}

@visibleForTesting
void resetSnapshotBaselineForTesting() {
  _snapshotBaseline = null;
}

/// The snapshot entries an action verb adds to its response payload.
///
/// The `snapshot` param (`full`, `diff`, `none`) wins over `includeSnapshot`
/// when present. Without it, `includeSnapshot` decides as it always has
/// (default on): the full text under `snapshot`, or nothing.
///
/// `diff` answers the lines that changed since the last unfiltered snapshot
/// (a `dusk:snap` or an earlier action), with `snapshotMode: "diff"` beside
/// it; with no baseline yet the full text comes back. The baseline is read
/// before the post-action build because that build replaces it.
///
/// The mode is read case-insensitively. An unknown `snapshot` value does not
/// throw, because this runs after the action has already taken effect and
/// every embed site would swallow the error and return no snapshot at all;
/// the payload carries `snapshotError` instead, so the caller sees why.
Future<Map<String, dynamic>> snapshotForAction(
  Map<String, String> params,
) async {
  final String mode =
      params['snapshot']?.trim().toLowerCase() ?? _legacySnapshotMode(params);
  switch (mode) {
    case 'none':
      return <String, dynamic>{};
    case 'full':
      final Map<String, dynamic> snap = await duskSnapBuild();
      return <String, dynamic>{'snapshot': snap['snapshot']};
    case 'diff':
      final String? previous = snapshotBaseline;
      final Map<String, dynamic> snap = await duskSnapBuild();
      return <String, dynamic>{
        'snapshot': diffSnapshots(previous, snap['snapshot'] as String),
        'snapshotMode': 'diff',
      };
    default:
      return <String, dynamic>{
        'snapshotError':
            'unknown snapshot mode "${params['snapshot']}": use full, diff or none',
      };
  }
}

/// The mode `includeSnapshot` asks for: `none` only for an explicit
/// `'false'` or `'0'`.
String _legacySnapshotMode(Map<String, String> params) {
  final String raw = params['includeSnapshot'] ?? '';
  return raw == 'false' || raw == '0' ? 'none' : 'full';
}

/// The three ways a snapshot walk can be narrowed.
///
/// A full tree is the wrong default answer to most questions. It costs
/// context on a large screen, and on a shell whose sidebar repeats the
/// labels of the pages it opens it actively misleads: an unscoped lookup
/// resolves the nav item and the caller concludes two pages differ.
@immutable
final class _SnapFilter {
  const _SnapFilter({required this.interactiveOnly, required this.grep});

  /// Emit only nodes that carry a ref (button, textbox, link, header,
  /// image, anything with a tap action). Plain `- text` lines are dropped.
  final bool interactiveOnly;

  /// Emit only nodes whose own label or value matches, plus every ancestor
  /// on the path to one. Ancestors are kept because they carry the refs an
  /// agent acts on: a matching `- text` line has none of its own.
  final RegExp? grep;
}

/// Compiles the `grep` param, falling back to a literal substring match when
/// it is not a valid regex.
///
/// Agents pass label text, and a label such as `Container Sample (MP4, H.264`
/// is an unterminated group. The fallback is reported through the second
/// element so the response can say the pattern was read literally; a valid
/// regex keeps its regex meaning and reports `false`.
(RegExp?, bool) _compileGrep(String? grep) {
  if (grep == null || grep.isEmpty) return (null, false);
  try {
    return (RegExp(grep), false);
  } on FormatException {
    return (RegExp(RegExp.escape(grep)), true);
  }
}

/// True when [node] or any node beneath it matches [pattern].
bool _subtreeMatches(SemanticsNode node, RegExp pattern) {
  final SemanticsData data = node.getSemanticsData();
  if (pattern.hasMatch(data.label) || pattern.hasMatch(data.value)) {
    return true;
  }
  bool found = false;
  node.visitChildren((SemanticsNode child) {
    if (found) return false;
    found = _subtreeMatches(child, pattern);
    return !found;
  });
  return found;
}

/// Resolves the `within` ref to the semantics node its subtree starts at.
///
/// Throws [StateError] when the ref is unknown or carries no node: falling
/// back to the whole tree would answer a different question than the one
/// asked, silently.
SemanticsNode _resolveWithinNode(String ref) {
  final RefEntry? entry = RefRegistry.lookup(ref);
  if (entry == null) {
    throw StateError(
      'duskSnapBuild: within ref "$ref" not found. Take it from the ref '
      'tokens of a prior snapshot; q<N> query handles are not addressable '
      'here (they re-resolve per action and have no fixed subtree).',
    );
  }
  final SemanticsNode? node = entry.node;
  if (node == null) {
    throw StateError(
      'duskSnapBuild: within ref "$ref" carries no semantics node, so it '
      'has no subtree to scope to. Re-snapshot and use a ref from that '
      'output.',
    );
  }
  // Membership in the registry is not liveness. Nothing calls disposeGroup
  // in production, so a token outlives the widget it was minted from, and a
  // detached SemanticsNode still answers visitChildren: scoping to one
  // walked a subtree that is no longer on screen and returned an EMPTY tree
  // with no error, which an agent reads as "this region is empty" rather
  // than "your ref is stale".
  if (!node.attached || !entry.element.mounted) {
    throw StateError(
      'duskSnapBuild: within ref "$ref" no longer resolves; the widget it '
      'named has left the tree. Re-snapshot and scope to a ref from that '
      'output.',
    );
  }
  return node;
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

/// Every labelled node in the live tree, grouped by its own label in the walk
/// order `resolveQuery` counts in (each pipeline owner's root, then its child
/// owners).
///
/// A full walk of its own rather than counts gathered while emitting: `within`
/// and `depth` cut the emit walk short, and an index or count taken from a cut
/// walk would disagree with the resolver's, which always counts the whole
/// tree. Keyed on [SemanticsNode.label], the string the resolver compares,
/// for the reason `ext_observe.dart` gives at its `seenByLabel` counter.
Map<String, List<SemanticsNode>> _nodesByOwnLabel() {
  final Map<String, List<SemanticsNode>> byLabel =
      <String, List<SemanticsNode>>{};

  void visit(SemanticsNode node) {
    if (node.label.isNotEmpty) {
      byLabel.putIfAbsent(node.label, () => <SemanticsNode>[]).add(node);
    }
    node.visitChildren((SemanticsNode child) {
      visit(child);
      return true;
    });
  }

  void visitOwner(PipelineOwner owner) {
    final SemanticsNode? root = owner.semanticsOwner?.rootSemanticsNode;
    if (root != null) visit(root);
    owner.visitChildren(visitOwner);
  }

  visitOwner(RendererBinding.instance.rootPipelineOwner);
  return byLabel;
}

/// How [node]'s ref re-finds it after a rebuild, or `null` when it cannot.
///
/// A node with no label of its own is unreachable through the resolver's
/// label walk, so it gets no binding. Neither does one whose reported label
/// differs from its own (a merging boundary): the index was counted under one
/// string and would be searched under another, the mismatch `ext_observe.dart`
/// refuses to index for the same reason.
///
/// [element] is the node's mounted element, read for the route the binding
/// pins relocation to.
RefBinding? _bindingFor(
  SemanticsNode node,
  SemanticsData data,
  Map<String, List<SemanticsNode>> nodesByLabel,
  Element element,
) {
  final String label = node.label;
  if (label.isEmpty || data.label != label) return null;
  // A node under a pipeline owner the root walk does not reach has no index
  // the resolver could reproduce.
  final List<SemanticsNode> namesakes =
      nodesByLabel[label] ?? const <SemanticsNode>[];
  final int index = namesakes.indexOf(node);
  if (index < 0) return null;

  final Route<dynamic>? route = ModalRoute.of(element);
  return RefBinding(
    query: DuskQuery(
      semanticsLabel: label,
      matchIndex: index,
    ),
    matchCount: namesakes.length,
    route: route == null ? null : WeakReference<Route<dynamic>>(route),
  );
}

void _emitNode({
  required SemanticsNode node,
  required int depth,
  required int? maxDepth,
  required StringBuffer buffer,
  required String groupId,
  required Map<RenderObject, Element> elementByRenderObject,
  required Map<String, List<SemanticsNode>> nodesByLabel,
  required bool includeEnrichers,
  _SnapFilter filter = const _SnapFilter(interactiveOnly: false, grep: null),
  RenderObject? enclosingTextboxRenderObject,
}) {
  if (maxDepth != null && depth > maxDepth) return;

  // MergeSemantics keeps each absorbed descendant in the tree as its own node,
  // flagged here, while the platform sees only the boundary that already
  // carries its label, flags and actions. Printing it too lists one control
  // twice. It is skipped without taking a depth step, so anything beneath it
  // that is not itself merged still lines up under the boundary's line.
  if (node.isMergedIntoParent) {
    node.visitChildren((SemanticsNode child) {
      _emitNode(
        node: child,
        depth: depth,
        maxDepth: maxDepth,
        buffer: buffer,
        groupId: groupId,
        elementByRenderObject: elementByRenderObject,
        nodesByLabel: nodesByLabel,
        includeEnrichers: includeEnrichers,
        filter: filter,
        enclosingTextboxRenderObject: enclosingTextboxRenderObject,
      );
      return true;
    });
    return;
  }

  final SemanticsData data = node.getSemanticsData();
  final String label = data.label;
  final String value = data.value;
  final String? role = _roleFor(data);
  final bool interactive = _isInteractive(data);

  // A filtered-out node still descends: a match can live below it, and the
  // depth it passes down is its own, so the surviving lines close up rather
  // than sitting at the indentation of a parent that is no longer printed.
  final bool onGrepPath =
      filter.grep == null || _subtreeMatches(node, filter.grep!);

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
          nodesByLabel: nodesByLabel,
          includeEnrichers: includeEnrichers,
          filter: filter,
          enclosingTextboxRenderObject: enclosingTextboxRenderObject,
        );
        return true;
      });
      return;
    }

    if (renderObject != null && element != null && onGrepPath) {
      final Rect rect = _globalRectFor(renderObject);
      final String token = RefRegistry.register(
        rect: rect,
        element: element,
        groupId: groupId,
        isTextField: data.flagsCollection.isTextField,
        node: node,
        renderObject: renderObject,
      );
      RefRegistry.bind(token, _bindingFor(node, data, nodesByLabel, element));

      buffer.write('${_indent(depth)}- $role "${_escape(label)}"');
      if (value.isNotEmpty) {
        buffer.write(': "${_escape(value)}"');
      }
      buffer.write(' [ref=$token]');
      buffer.writeln(_visibilityMarker(renderObject, rect));

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
  } else if ((label.isNotEmpty || value.isNotEmpty) &&
      !filter.interactiveOnly &&
      onGrepPath) {
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
      nodesByLabel: nodesByLabel,
      includeEnrichers: includeEnrichers,
      filter: filter,
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

/// The trailing marker for a ref-bearing line: ` [offscreen]` when [rect] is
/// outside the view, ` [occluded]` when something above it claims its centre,
/// and an empty string on a healthy screen so its output does not change.
///
/// An off-screen node is never probed for occlusion: a hit test at a point
/// outside the view finds nothing, which would read as a cover. Nor is one
/// with no area (a sliver reports [Rect.zero]): its centre is not its own.
String _visibilityMarker(RenderObject renderObject, Rect rect) {
  if (rect.isEmpty) return '';
  final FlutterView? view =
      WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view == null) return '';
  if (isRectOutsideViewport(rect, view.physicalSize / view.devicePixelRatio)) {
    return ' [offscreen]';
  }
  final HitProbe probe = probeHitAt(
    target: renderObject,
    point: rect.center,
    viewId: view.viewId,
  );
  return probe.verdict == HitVerdict.covered ? ' [occluded]' : '';
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
