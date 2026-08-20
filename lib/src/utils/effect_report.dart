/// The `effect` block the five verbs that can observe a result return.
///
/// A dusk action reports that it DISPATCHED, not that the widget received.
/// That distinction has cost real debugging time more than once: a fill
/// printed a green tick four times onto a field covered by a pinned footer,
/// and a fill against an `InputType.number` field reported the text it had
/// been handed while the widget kept nothing, which produced a defect-shaped
/// story that survived two rewrites of the widget.
///
/// Every builder here answers the same question in the verb's own terms:
/// what does the widget hold NOW, and is that what the caller asked for. The
/// block is always present on a successful action of those five, so an
/// agent never has to remember to opt in, and the diagnostic it would
/// otherwise hand-assemble (act, re-snap, read the value back, compare)
/// collapses into the response it already has.
///
/// The verbs without one have nothing cheap to read back: a hover, a
/// keypress or a modal dismissal leaves no single value that says whether
/// it landed. `select_option` is the exception worth fixing, and it still
/// echoes its own `value` parameter.
///
/// Shape: `{"kind": "<kind>", ...kind-specific fields}`. Every kind that can
/// express intent carries `verified`; the ones that only observe a change
/// carry `changed`.
library;

/// Effect of a text write: what the field holds after it, and whether that
/// matches what was requested.
///
/// [actual] is read back from the live `TextEditingController`, never echoed
/// from the request. `verified: false` with an [actual] shorter than
/// [expected] is the signature of an input formatter or a keyboard type
/// filtering the write.
Map<String, dynamic> textEffect({
  required String expected,
  required String? actual,
}) {
  return <String, dynamic>{
    'kind': 'text',
    'verified': actual == expected,
    'value': actual,
  };
}

/// Effect of a gesture: whether the target's own semantics subtree changed.
///
/// [before] and [after] are opaque tokens compared by equality. Scoped to
/// the target rather than the whole tree, so unrelated background churn does
/// not read as "something happened".
Map<String, dynamic> treeChangedEffect({
  required String before,
  required String after,
}) {
  return <String, dynamic>{
    'kind': 'treeChanged',
    'changed': before != after,
  };
}

/// Effect of a scroll: the scrollable's pixel offset on both sides of it.
///
/// `changed: false` with equal offsets is the tell that the ref was not a
/// scrollable, or that the list was already at the end. Both report success
/// today and neither moves anything.
Map<String, dynamic> scrollOffsetEffect({
  required double? before,
  required double? after,
}) {
  return <String, dynamic>{
    'kind': 'scrollOffset',
    'changed': before != after,
    'before': before,
    'after': after,
  };
}

/// Effect of a checkbox or switch write: the checked state on both sides,
/// and whether it landed on the requested value.
Map<String, dynamic> checkedEffect({
  required bool expected,
  required bool? before,
  required bool? after,
}) {
  return <String, dynamic>{
    'kind': 'checked',
    'verified': after == expected,
    'before': before,
    'after': after,
  };
}
