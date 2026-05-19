/// Typed exception hierarchy for Dusk runtime errors.
///
/// Action tools (tap, type, scroll, ...) throw [DuskException] subclasses
/// when they detect a precondition violation that the agent should know
/// about. Catching [DuskException] in the VM Service extension boundary lets
/// each tool translate the failure into its tool-specific error payload
/// without leaking generic `Exception` / `StateError` instances to the wire.
library;

/// Marker base class for every exception raised by the Dusk runtime.
///
/// Implementations carry a human-readable [message] suitable for surfacing
/// directly to the agent. Subclasses MAY expose additional structured
/// fields (e.g. `ref`, `reason`) when the agent benefits from machine-
/// readable context.
abstract class DuskException implements Exception {
  /// Creates a [DuskException] with the supplied [message].
  const DuskException(this.message);

  /// Human-readable description of the failure.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown by [ensureActionable] when a registered ref cannot accept an
/// action because the underlying widget fails one of the 5 Playwright-parity
/// gates: not enabled, zero-area rect, off-viewport, unstable bounding box,
/// or obscured by another widget.
///
/// [ref] is the `eN` token that triggered the check; [reason] is one of:
///
/// * `"not enabled"` — semantics flag `isEnabled` is `Tristate.isFalse`.
/// * `"zero rect"` — rect width or height is 0.
/// * `"off-viewport (rect=..., viewport=...)"` — rect does not overlap the
///   logical viewport.
/// * `"not stable (rect changed by Xpx)"` — bounding box drifted more than
///   0.5 logical pixels between two consecutive frames (animated widget).
/// * `"obscured by other widget (top=<runtimeType>)"` — hit-test at
///   `rect.center` resolved a non-descendant target (overlay, modal scrim,
///   stacked widget).
///
/// Agents branch on substring of [reason] (`"not enabled"`, `"zero rect"`,
/// `"off-viewport"`, `"not stable"`, `"obscured by"`); the substrings are a
/// load-bearing public contract — see `lib/src/utils/actionability_gate.dart`
/// off-limits notes.
///
/// [message] is the pre-formatted string action handlers can surface
/// verbatim back to the agent.
class DuskActionabilityException extends DuskException {
  /// Creates a [DuskActionabilityException] for the supplied [ref] and
  /// [reason]; the [message] is composed in the canonical
  /// `"Widget ref=$ref is not actionable: $reason"` shape.
  const DuskActionabilityException({
    required this.ref,
    required this.reason,
  }) : super('Widget ref=$ref is not actionable: $reason');

  /// The `eN` token whose underlying widget failed the actionability check.
  final String ref;

  /// Short, machine-readable cause. Substring is the agent-parseable
  /// contract: one of `"not enabled"`, `"zero rect"`, `"off-viewport"`,
  /// `"not stable"`, or `"obscured by"`.
  final String reason;
}

/// Thrown when an action handler resolves a `q<N>` query handle whose stored
/// predicates no longer match any node in the live Semantics tree.
///
/// Unlike `eN` snapshot refs (which fail with a generic
/// `"ref not found in registry"` when the snapshot group is disposed),
/// `qN` refs survive snapshot disposal but lose their target when the UI
/// changes such that the original predicates no longer match. The agent
/// should re-snap or re-find rather than retrying with the same handle.
///
/// [ref] is the `qN` token that resolved to zero live matches.
class DuskStaleHandleException extends DuskException {
  /// Creates a [DuskStaleHandleException] for the supplied [ref]; the
  /// [message] is composed in the canonical
  /// `"Query handle ref=$ref is stale: no live match for stored predicates"`
  /// shape.
  const DuskStaleHandleException({required this.ref})
      : super(
          'Query handle ref=$ref is stale: no live match for stored predicates',
        );

  /// The `qN` token whose stored predicates no longer match any live node.
  final String ref;
}
