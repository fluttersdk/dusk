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
/// action because the underlying widget is disabled, has a zero-area rect,
/// or sits outside the current root view.
///
/// [ref] is the `eN` token that triggered the check; [reason] is one of
/// `"not enabled"`, `"zero rect"`, or `"off-viewport (rect=..., viewport=...)"`.
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

  /// Short, machine-readable cause: one of `"not enabled"`, `"zero rect"`,
  /// or `"off-viewport (rect=..., viewport=...)"`.
  final String reason;
}
