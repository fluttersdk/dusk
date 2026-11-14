# Actionability gate and refs

How to recover when an action is refused or a ref goes stale: the gate step by step, the error shape, and the life of `e<N>` and `q<N>` tokens.

## Contents

- [The gate, step by step](#the-gate-step-by-step)
- [The error shape](#the-error-shape)
- [Ref lifecycles](#ref-lifecycles)
- [Snap or observe](#snap-or-observe)
- [When to switch a check off](#when-to-switch-a-check-off)
- [semanticsLabel exact match and over-match](#semanticslabel-exact-match-and-over-match)

## The gate, step by step

`tap`, `dblclick`, `right_click`, `triple_click`, `hover`, `drag`, `type` and `fill` run this gate before they dispatch anything. The steps run in order and the first failure ends the call. The order and the reason substrings are a frozen contract; new checks are appended.

### 0. Defunct preflight

The element behind the ref has no render object, or Flutter reports it inactive. Reason `defunct (element no longer mounted)`; an element that is still mounted but detached gives `defunct (element no longer attached to a render object)`, so branch on `defunct`.

The node left the tree (navigation, list rebuild, conditional render). A labelled `e<N>` has already been tried for relocation by then (see below), so `defunct` means the namesake count or the route changed, or the ref had no label. Re-snap and pick a fresh ref. A `q<N>` that matches nothing fails as a stale handle instead.

### 1. Enabled

Fails only when the Semantics `isEnabled` flag is explicitly false; a node that never sets it passes. Reason `not enabled`.

The control is disabled on purpose: a form not yet valid, a loading flag, a permission. Retrying gives the same answer. Find what disables it (`tapir_observe { includeEnrichers: "full" }` shows `magicGateResult` and the other Magic lines on a Magic app) and change that state.

### 2. Zero rect

Width or height is 0. Reason `zero rect`. Layout has not run yet: right after a route push, or content waiting on data. `tapir_wait_for` on content of the new screen, then retry.

### 3. Off-viewport

The rect does not overlap the view. Under a `Scrollable` the gate calls `showOnScreen` once, waits a frame and checks again. Reason `off-viewport (rect=..., viewport=...)`. No scrollable ancestor, or a nested one the single call did not move: scroll explicitly, then retry.

```text
tapir_scroll { ref: "<a widget in the list>", dy: 400 }
tapir_tap { ref: "<target>" }
```

### 4. Stable

Skipped with `checkStable: false`. The rect is read again a frame later; a side that moved more than 0.5 logical pixels fails with `not stable (rect changed by Xpx)`. Something is animating: a route transition, a hero, an implicit animation, scroll inertia. Wait for the animation to finish (`tapir_wait_for { textGone: "Loading" }` when a spinner drives it), or switch the check off when the animation is intentional and endless.

### 5. Receives events

Skipped with `checkReceivesEvents: false`. A hit test at the centre has to reach the target or a descendant; otherwise `obscured by other widget (top=...)`, naming the type of the topmost hit. Typical covers: a dialog or sheet (`tapir_reset_overlays`), a snackbar (wait for its text to go), a drawer, an overlay entry.

The hit test can also fail to answer. On Flutter Web's debug build that is routine: the path comes back with only the root render view. Refusing every tap on that would be worse, so the gate proceeds and the response says so:

```json
"checks": {
  "receivesEvents": "indeterminate",
  "why": "hit-test returned only the root render view",
  "overlapCandidates": ["RenderPhysicalShape@0,712,390x88"],
  "hint": "..."
}
```

| `checks` | Meaning |
|---|---|
| absent | Confirmed: the hit test reached the target |
| `receivesEvents: "indeterminate"` | Could not answer; the action ran anyway |
| `receivesEvents: "skipped"` | You passed `checkReceivesEvents: false` |

`overlapCandidates` lists up to five render objects that overlap the target and paint after it, only on the indeterminate path. An overlap is not proof of a cover; judge the action by its `effect`.

## The error shape

A refused action returns an error whose detail is a JSON string:

```json
{
  "message": "Widget ref=e7 is not actionable: not stable (rect changed by 1.2px)",
  "envelope": { "type": "not_stable", "widget_path": "e7", "suggestions": [] }
}
```

Branch on the substring in `message`, or on `envelope.type`: `disabled`, `zero_rect`, `off_viewport`, `not_stable`, `obscured`, `stale` (a defunct `e<N>` or a stale `q<N>`), `not_found` (an unknown ref; `suggestions` holds up to three near matches), `missing_param`, `timeout`, `unexpected`.

A stale query handle reads:

```json
{
  "message": "Query handle ref=q3 is stale: no live match for stored predicates",
  "envelope": { "type": "stale", "widget_path": "q3", "suggestions": [] }
}
```

Call `tapir_find` or `tapir_observe` again with broader or different predicates; retrying the same handle fails the same way.

## Ref lifecycles

### `e<N>`, snapshot refs

- Minted by `tapir_snap`, one per interactive Semantics node (button, textbox, checkbox, link, heading, image). The same node in consecutive snaps keeps its token.
- Resolved against the element captured at snap time, so it goes stale when that node unmounts.
- A labelled ref carries a binding: a label query, its index, and the number of nodes with that label at snap time. When the element is gone the action re-runs the query and trusts the hit only if the live tree has the same number of namesakes on the same route; the ref then points at the new control and the response lists it in `reresolved`. A different count (a list that grew or shrank) or another route fails as `defunct`. The query has no role, so a node of another role with the same label in the same slot could match.
- Use one right after the snap that minted it, on a static screen, for a one-off action.

### `q<N>`, query handles

- Minted by `tapir_find` (`text`, `contains`, `semanticsLabel`, `key`, `within`) and `tapir_observe`.
- Walk the live tree again on every action, so they survive rebuilds, navigation and hot reload while the predicates still match; with no match they fail as stale.
- A `tapir_find` handle names the first match and reports `matchCount`. A `tapir_observe` handle for a labelled candidate also stores its position among same-label nodes, so a list of rows offering one action can be worked row by row while the list is unchanged. An unlabelled candidate stores no position: its handle matches the candidate's value text, so it can resolve to another control showing the same text, and one with no value has no predicate and is stale at once; use a snapshot ref or a unique `key` for those. For a labelled one, the position is not an identity: a row inserted or removed above a held handle moves a neighbour into its position, and the handle then resolves to that neighbour without any error. It goes stale only when fewer same-label nodes remain than its position. Observe again after any insertion or removal that changes positions.
- Use one whenever a ref is held across more than one action, a retry, or a changing screen.

### Disjoint spaces

`e<N>` and `q<N>` never share a token, and a token is never guessed: the next number is not a valid ref until a tool mints it. A handler treats a `q`-prefixed token as a query and anything else as a snapshot ref.

## Snap or observe

| Use `tapir_snap` when | Use `tapir_observe` when |
|---|---|
| You reason about structure (parents, headings, prose) | You loop over candidates (form fields, rows, links) |
| The next action is one-shot | The action may retry or the UI animates |
| You need the text around the controls | Only interactive widgets matter |

A common shape: one narrow `tapir_snap` to orient, then `tapir_observe` or `tapir_find` for the handles the loop uses.

## When to switch a check off

Both switches are per call; there is no session-wide way to skip the gate, so a skipped check is always visible in the call that skipped it.

- `checkStable: false`: the target animates on purpose (a pulsing indicator, a ripple still running from an earlier tap) and its handler is safe mid-animation.
- `checkReceivesEvents: false`: a cover lets touches through by design (a pinned banner that does not absorb pointers).

## semanticsLabel exact match and over-match

`tapir_find { semanticsLabel: "Password" }` matches `SemanticsNode.label` exactly and case-sensitively. When several nodes share the label it resolves to the first interactive one (a button, text field or anything with a tap action) so a tap lands on the control and not on a caption that repeats its text; only when none is interactive does it take the first in tree order. Every success carries `matchCount`; above 1 it adds a `diagnostic`:

```json
{
  "ref": "q3",
  "matched": true,
  "matchCount": 2,
  "diagnostic": "label 'Password' matched 2 nodes; refine with --key, --text, or --contains"
}
```

The handle still resolves, to that one match. Predicates are not intersected: the resolver uses the first one set in the order `key`, `semanticsLabel`, `text`, `contains` and ignores the rest, except that a `text` beside a `key` must also appear in a `Text` below that widget. So narrowing means swapping the predicate, not adding a second one to `semanticsLabel`:

| Use | When |
|---|---|
| `key` | The widget carries a `Key`; the most precise, survives label changes, and wins over every other predicate |
| `text` | The visible text differs from the label (instead of `semanticsLabel`) |
| `contains` | Only part of the label is unique (`"Confirm"` for "Confirm password"); instead of `text` and `semanticsLabel` |
| `within` | Added to any of them when the duplicates live in different regions (a sidebar and the page) |
| `tapir_observe` | No predicate is unique; pick from the candidates' bounds and fields |
