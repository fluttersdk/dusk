import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A single addressable entry stored in [RefRegistry].
///
/// Each entry pairs an `[ref=eN]` token (minted by [RefRegistry.register])
/// with the live tree references the V3 action tools (Steps 7–14) need to
/// resolve the ref back to a hit point or focus target.
///
/// Two field groups:
///
/// **Hot-path fields** (every action tool reads these):
///
/// * [rect] — bounding rect in logical pixels (global coordinates), captured
///   at registration. Pointer-event extensions hit at `rect.center`.
/// * [element] — the [Element] backing the registered tree node. The text-
///   input extension walks descendants for `EditableText.of(...)`; the scroll
///   extension passes the element to `Scrollable.maybeOf(...)`.
/// * [isTextField] — `true` when the registered node has the
///   `SemanticsFlag.isTextField` flag. The tap extension uses this signal
///   to call `requestKeyboard()` after the pointer events (Step 1 spike
///   verified the chain produces `hasPrimaryFocus == true`).
/// * [groupId] — identifies the snapshot (or `find_by_*` call) that minted
///   the token. Disposing the group via [RefRegistry.disposeGroup] removes
///   every entry under it atomically.
///
/// **Inspection fields** (snapshot enrichment / debugging):
///
/// * [node] — the [SemanticsNode] the entry was minted from, when the entry
///   came from a Semantics-tree walk. `null` for synthetic entries (e.g.
///   `find_by_text`, which walks the Element tree directly).
/// * [renderObject] — the [RenderObject] backing the node, captured at
///   registration. Useful for tools that want to recompute the rect under
///   a different transform without re-walking the tree.
class RefEntry {
  /// Creates a [RefEntry] from its component parts. All non-nullable fields
  /// must be provided; the registry never mutates an entry after registration.
  const RefEntry({
    required this.rect,
    required this.element,
    required this.groupId,
    required this.isTextField,
    this.node,
    this.renderObject,
  });

  /// Bounding rect in logical pixels (global coordinates).
  final Rect rect;

  /// The [Element] backing the registered tree node.
  final Element element;

  /// Snapshot group that owns this entry. Disposing the group removes the
  /// entry.
  final String groupId;

  /// Whether this ref points to a text-input widget.
  final bool isTextField;

  /// The [SemanticsNode] the entry was minted from, when the entry came from
  /// a Semantics-tree walk. `null` for synthetic entries (e.g. `find_by_text`).
  final SemanticsNode? node;

  /// The [RenderObject] backing the registered tree node.
  final RenderObject? renderObject;
}

/// Immutable predicate set stored alongside a `qN` query handle.
///
/// Mirrors the Playwright Locator pattern: a handle is opaque from the
/// agent's perspective, and the predicates re-execute on every action so the
/// handle is resilient to re-renders that would invalidate a snapshot-frame
/// `eN` ref.
///
/// The class deliberately stores NO [Element] or [SemanticsNode] handles;
/// the query walks the live Semantics tree from scratch on each resolution.
/// This is what makes `qN` refs survive widget rebuild, route push, and
/// snapshot-group disposal.
///
/// At least one of [text], [semanticsLabel], or [keyValue] must be non-null
/// at construction time; the [extDuskFindHandler] gate enforces this.
@immutable
class DuskQuery {
  /// Creates a [DuskQuery] from the supplied predicates. Callers must pass
  /// at least one non-null field.
  const DuskQuery({
    this.text,
    this.semanticsLabel,
    this.keyValue,
  });

  /// Exact match against [SemanticsNode.label] (preferred for accessibility-
  /// labelled widgets) or against a [Text.data] descendant when no semantic
  /// label is set.
  final String? text;

  /// Exact match against [SemanticsNode.label]. Distinct from [text] so
  /// agents can opt into label-only matching without [Text.data] fallback.
  final String? semanticsLabel;

  /// Stringified [Key] value (matches [ValueKey.value.toString()]).
  final String? keyValue;
}

/// Static registry mapping `[ref=eN]` tokens to [RefEntry] records.
///
/// V3 mints a fresh `e<N>` token every time [register] is called UNLESS a
/// [SemanticsNode] is supplied AND a token has already been issued for the
/// same `node.id` — in which case the previously-issued token is returned
/// and its payload is refreshed in place. This is what makes repeated
/// `flutter_snapshot` calls on an unchanged tree return identical refs
/// (Step 6 acceptance test (b)).
///
/// The dedupe key is `node.id` ALONE (not `groupId + node.id`): every
/// snapshot mints a fresh `groupId`, but the agent should observe stable
/// tokens for stable widgets across snapshots. On a cache hit the entry's
/// stored `groupId` is updated to the latest snapshot's id so disposal of
/// older snapshot groups never invalidates a token still referenced by a
/// newer snapshot.
///
/// Tokens are scoped to a `groupId` (e.g. `snapshot-1700000000000`). The
/// owning extension calls [disposeGroup] when the group is superseded
/// (next snapshot, or page navigation) — every entry **whose current
/// `groupId` matches** is removed atomically.
///
/// All state is static. Tests must call [resetForTesting] (or the legacy
/// [disposeAll]) in `setUp` to avoid bleed-through between test cases.
///
/// ## Thread safety
///
/// All VM Service extension calls arrive on the root isolate. No cross-
/// isolate mutation occurs; no synchronization primitives are needed.
class RefRegistry {
  RefRegistry._();

  /// Sentinel instance for enricher contracts.
  ///
  /// [DuskSnapshotEnricher] takes a `RefRegistry` parameter for forward
  /// compatibility, but all current registry operations are static. Snap
  /// passes this singleton so enrichers conform to the typedef without
  /// constructing throw-away instances per call.
  static final RefRegistry instance = RefRegistry._();

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  /// Monotonic counter used to mint `e<N>` tokens.
  static int _counter = 0;

  /// Token → entry. Lookup table for action tools.
  static final Map<String, RefEntry> _entries = <String, RefEntry>{};

  /// SemanticsNode.id → token. Powers the cache-hit semantics of
  /// [register]: the same node always maps to the same token regardless
  /// of which snapshot's `groupId` minted it. Cleared by [disposeAll];
  /// individual entries are removed by [disposeGroup] when the entry's
  /// current `groupId` matches.
  static final Map<int, String> _byNodeId = <int, String>{};

  /// Monotonic counter used to mint `q<N>` query handle tokens.
  ///
  /// Separate from [_counter] so query handles (`q1`, `q2`, …) and
  /// snapshot-frame refs (`e1`, `e2`, …) never collide and the agent can
  /// tell at a glance which shape it is dealing with.
  static int _queryCounter = 0;

  /// Token → query predicates. Lookup table for action tools that detect
  /// the `q` prefix and re-execute the Semantics tree walk on every call.
  static final Map<String, DuskQuery> _queries = <String, DuskQuery>{};

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Mints (or returns the cached) token for the supplied tree references.
  ///
  /// When [node] is supplied AND a token has already been issued for the
  /// same `node.id`, the same token is returned and its underlying entry
  /// is refreshed in place (so action tools always see the latest
  /// [element] / [rect] for that node, AND the entry's current `groupId`
  /// becomes the supplied [groupId] — the latest snapshot owns the
  /// disposal lifecycle).
  ///
  /// When [node] is `null` (e.g. the `find_by_text` walk does not have a
  /// SemanticsNode handle), a fresh token is always minted.
  ///
  /// Tokens look like `e1`, `e2`, … to mirror Playwright MCP's
  /// `[ref=e<N>]` shape.
  static String register({
    required Rect rect,
    required Element element,
    required String groupId,
    required bool isTextField,
    SemanticsNode? node,
    RenderObject? renderObject,
  }) {
    // 1. Cache hit — only when a SemanticsNode is supplied. Find an
    //    existing token for node.id and refresh its payload so downstream
    //    action tools see the latest element/rect/renderObject. The
    //    entry's groupId is updated to the LATEST caller's groupId so
    //    older snapshots' disposeGroup calls never strand a still-live
    //    token.
    if (node != null) {
      final String? existing = _byNodeId[node.id];
      if (existing != null) {
        _entries[existing] = RefEntry(
          rect: rect,
          element: element,
          groupId: groupId,
          isTextField: isTextField,
          node: node,
          renderObject: renderObject,
        );
        return existing;
      }

      // 2. Mint a new token, store the entry, and remember the node.id
      //    mapping for future cache hits.
      _counter += 1;
      final String token = 'e$_counter';
      _entries[token] = RefEntry(
        rect: rect,
        element: element,
        groupId: groupId,
        isTextField: isTextField,
        node: node,
        renderObject: renderObject,
      );
      _byNodeId[node.id] = token;
      return token;
    }

    // 3. No SemanticsNode → mint fresh every call. The entry still
    //    carries the supplied groupId so disposeGroup cleans it up.
    _counter += 1;
    final String token = 'e$_counter';
    _entries[token] = RefEntry(
      rect: rect,
      element: element,
      groupId: groupId,
      isTextField: isTextField,
      node: null,
      renderObject: renderObject,
    );
    return token;
  }

  /// Looks up [RefEntry] by token. Returns `null` if the token is unknown
  /// or its owning group has been disposed.
  static RefEntry? lookup(String ref) => _entries[ref];

  /// Mints a fresh `q<N>` query handle for the supplied predicate set and
  /// stores it for subsequent action-tool re-resolution.
  ///
  /// Unlike [register], query handles are NEVER deduped: each call mints a
  /// fresh token. The caller (the `ext.dusk.find` handler) verifies that at
  /// least one predicate is non-null before invoking this method.
  ///
  /// Query handles are NOT scoped to a `groupId`: they survive snapshot
  /// disposal because the predicates are re-executed against the live
  /// Semantics tree on every action call. Use [disposeAll] /
  /// [resetForTesting] to clear them in tests.
  static String registerQuery(DuskQuery query) {
    _queryCounter += 1;
    final String token = 'q$_queryCounter';
    _queries[token] = query;
    return token;
  }

  /// Looks up the stored [DuskQuery] for a `q<N>` token. Returns `null`
  /// when the token is unknown (e.g. after [disposeAll], or for `e<N>`
  /// tokens which live in the [_entries] map instead).
  static DuskQuery? lookupQuery(String ref) => _queries[ref];

  /// Removes every entry whose current `groupId` equals [groupId].
  /// Subsequent [lookup] calls for those tokens return `null`.
  ///
  /// Entries that were registered under [groupId] but later refreshed
  /// (cache hit) by a newer snapshot now carry the newer snapshot's
  /// groupId — those are NOT removed by this call. This is what lets
  /// older snapshot ids be disposed without invalidating refs the agent
  /// is still using.
  ///
  /// No-op when no entry currently carries [groupId].
  static void disposeGroup(String groupId) {
    // 1. Collect tokens to remove. Iterate before mutation to avoid
    //    concurrent-modification on the entries map.
    final List<String> toRemove = <String>[];
    final List<int> nodeIdsToRemove = <int>[];
    for (final MapEntry<String, RefEntry> entry in _entries.entries) {
      if (entry.value.groupId == groupId) {
        toRemove.add(entry.key);
      }
    }
    // 2. Drop entries.
    for (final String token in toRemove) {
      _entries.remove(token);
    }
    // 3. Drop dedupe-cache mappings whose token is gone. Iterate the
    //    node-id map separately because entries[X] just disappeared.
    for (final MapEntry<int, String> entry in _byNodeId.entries) {
      if (toRemove.contains(entry.value)) {
        nodeIdsToRemove.add(entry.key);
      }
    }
    for (final int nodeId in nodeIdsToRemove) {
      _byNodeId.remove(nodeId);
    }
  }

  /// Removes every entry in the registry and resets the counter.
  ///
  /// Used by tests to reset global state between test cases. Production
  /// code must call [disposeGroup] for ordinary lifecycle management.
  static void disposeAll() {
    _entries.clear();
    _byNodeId.clear();
    _queries.clear();
    _counter = 0;
    _queryCounter = 0;
  }

  /// Returns every token whose current `groupId` equals [groupId].
  ///
  /// Used by tests to verify [disposeGroup] semantics; production code
  /// should look up by token, not iterate.
  static List<String> refsForGroup(String groupId) {
    final List<String> out = <String>[];
    for (final MapEntry<String, RefEntry> entry in _entries.entries) {
      if (entry.value.groupId == groupId) {
        out.add(entry.key);
      }
    }
    return List<String>.unmodifiable(out);
  }

  // ---------------------------------------------------------------------------
  // Test support
  // ---------------------------------------------------------------------------

  /// Alias of [disposeAll] with a clearer name for `setUp` blocks.
  ///
  /// `setUp(RefRegistry.resetForTesting)` reads more naturally than
  /// `setUp(RefRegistry.disposeAll)`. Both clear every static.
  @visibleForTesting
  static void resetForTesting() => disposeAll();

  /// Registers an entry directly, bypassing the Semantics walk.
  ///
  /// **Test-only.** Provides the same hot-path fields as [register] so
  /// widget tests for action extensions (tap, type, scroll, …) can
  /// construct entries without running the snapshot extension.
  ///
  /// The returned ref string is identical in format to production refs (`eN`).
  static String registerForTesting({
    required Rect rect,
    required Element element,
    required String groupId,
    required bool isTextField,
  }) =>
      register(
        rect: rect,
        element: element,
        groupId: groupId,
        isTextField: isTextField,
      );
}
