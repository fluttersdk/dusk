# Actionability gate + ref tokens

The two parts of dusk that matter most for agent recovery: the gate that
guards every gesture, and the ref token system that lets the agent
target widgets across UI mutations.

## The 6-step gate, in detail

Every `dusk_tap`, `dusk_hover`, `dusk_drag`, `dusk_dblclick`,
`dusk_right_click`, `dusk_triple_click`, and `dusk_type` runs this gate
before dispatching the pointer / keyboard event. Steps run in order; the
first failure aborts the call and returns an error envelope.

### Step 0: defunct preflight

The gate probes `element.findRenderObject()`. If it returns null or
throws a `FlutterError` containing `"inactive element"` or
`"_ElementLifecycle.defunct"`, the gate raises
`DuskActionabilityException` with reason `"defunct (element no longer
mounted)"`.

**Why it fails.** The ref was minted under an earlier snap; the widget
has since unmounted (route change, list rebuild, conditional render).

**Recovery.** Call `dusk_snap` and pick a fresh `e<N>`. If the ref came
from `dusk_find` / `dusk_observe` (`q<N>`), it should re-resolve; if
even the `q<N>` is defunct, the widget is genuinely gone from the tree.

### Step 1: enabled

The gate reads `node.flagsCollection.isEnabled`. Fails only on
`Tristate.isFalse`; widgets that never set the flag pass (`Tristate.none`).

**Why it fails.** The widget rendered an explicit "disabled" semantic
(`AbsorbPointer`, `IgnorePointer`, `MaterialButton(onPressed: null)`,
disabled `TextField`).

**Recovery.** Do NOT retry. Find what makes the widget disabled
(usually upstream state: form validation, role-based gating, a loading
flag). Use `dusk_observe { includeEnrichers: "full" }` to inspect
enricher fields like `magicGateResult` or `magicControllerFlags` that
reveal why; then call the action that flips the state.

### Step 2: zero rect

The gate fails when `rect.width == 0 || rect.height == 0`.

**Why it fails.** Layout has not run yet. Common after a route push
before the new screen finishes building, or for widgets that depend on
async-loaded data.

**Recovery.** Call `dusk_wait_for` on the expected post-layout content
(label of a sibling widget, "Loading" text disappearance) and re-try.

### Step 3: off-viewport (with auto-scroll retry)

The gate computes the logical viewport from `view.physicalSize /
view.devicePixelRatio`. If `rect` does not overlap, the gate looks for
a `Scrollable` ancestor; when one exists, it calls
`renderObject.showOnScreen(duration: Duration.zero)`, awaits one frame
(200ms timeout), re-reads the rect, and re-checks. If still off-viewport
the gate fails with `"off-viewport (rect=Rect.fromLTRB(...), viewport=
Rect.fromLTRB(...))"`.

**Why it fails.** The widget is genuinely off-screen and no
`Scrollable` ancestor can bring it in (top-level widget in a non-scrollable
column, or the scrollable is nested and the gate's single
`showOnScreen` did not propagate).

**Recovery.** Call `dusk_scroll` toward the rect explicitly:

```
dusk_scroll { ref: "<scrollable-ref>", dy: 400 }   # or -400 for up
dusk_tap    { ref: "<target>" }
```

For horizontal scrollables: `dusk_scroll { ref: ..., dx: 300 }`.

### Step 4: not stable (2-frame rect drift)

Skipped when `checkStable: false`. Otherwise the gate waits one frame
(200ms timeout), re-reads the rect, and compares against the original.
Fails when the max side delta exceeds 0.5 logical pixels with reason
`"not stable (rect changed by Xpx)"` (X formatted to one decimal).

**Why it fails.** The widget is animating: route transition, hero
animation, AnimatedContainer, list scroll inertia, ripple effect.

**Recovery.** Two paths:

1. Wait for the animation to settle. The action that triggered the
   animation finished some time ago; one of these usually works:
   - `dusk_wait_for { textGone: "Loading" }` if a spinner is the cause
   - A small explicit wait of 300-500ms (no built-in tool; loop your
     own retry, or fall through to path 2)
2. Pass `checkStable: false` when the animation is intentional and the
   action is safe to fire mid-frame (e.g. a ripple from a previous tap
   while you tap a different button). Use sparingly.

### Step 5: receives events (hit-test path)

Skipped when `checkReceivesEvents: false`. Otherwise the gate hit-tests
at `rect.center` via `RendererBinding.instance.hitTestInView`. The
target element (or any descendant) must appear in the hit path. Fails
with `"obscured by other widget (top=<runtimeType>)"` where
`<runtimeType>` is the unqualified class name of the topmost hit-test
target.

**Why it fails.** Another widget is in front of the target:

- A modal dialog or bottom sheet is open (`top=_ModalScope`, `top=ModalBarrier`)
- A snackbar is overlapping (`top=SnackBar`)
- A drawer or overlay is half-visible (`top=DrawerController`)
- A custom widget intercepted the pointer (`top=GestureDetector`)

**Recovery.**

- For modals: `dusk_dismiss_modals` then retry.
- For snackbars: wait for it to auto-dismiss (`dusk_wait_for { textGone:
  "<snackbar text>" }`), or accept the obscure and tap through with
  `checkReceivesEvents: false`.
- For genuine overlay-on-purpose: target the overlay widget itself,
  not the one underneath. Snap + observe to find the right ref.

## The error envelope shape

Every gate failure (and most extension errors) returns this JSON object
as the MCP tool's error response:

```json
{
  "message": "Widget ref=e7 is not actionable: not stable (rect changed by 1.2px)",
  "ref": "e7",
  "reason": "not stable (rect changed by 1.2px)",
  "method": "ext.dusk.tap"
}
```

Branch on `reason` (or substring of `message`). The MCP client surfaces
the full message in the tool result; the agent should parse for the
substring vocabulary above and apply the matching recovery.

Stale `q<N>` handles return a different envelope:

```json
{
  "message": "Query handle ref=q3 is stale: no live match for stored predicates",
  "ref": "q3",
  "method": "ext.dusk.tap"
}
```

Recovery: re-call `dusk_find` or `dusk_observe` with broader / different
predicates.

## Ref token lifecycles

### `e<N>` (snapshot refs)

- Minted by `dusk_snap`. One token per interactive Semantics node
  (button, textbox, checkbox, link, heading, image).
- Deduped by `SemanticsNode.id`: the same widget across consecutive
  snaps returns the same `e<N>`. The dedup refreshes the ref's
  internal `groupId` to the latest snap, so old `e<N>` tokens that
  appear in newer snaps stay valid.
- Become defunct when the node unmounts (the widget leaves the tree).
  After hot-reload, navigation, or a list rebuild, expect every
  not-refreshed `e<N>` to fail with `"defunct"`.

When to use them: immediately after the snap that minted them, when
the UI is static, when the action is one-shot.

### `q<N>` (query handles)

- Minted by `dusk_find` and `dusk_observe`. Store a predicate set
  (`text`, `contains`, `semanticsLabel`, `key`).
- Re-resolve on every action: walk the live Semantics tree, find the
  first match, dispatch against it. Survive snap disposal, navigation,
  hot-reload (as long as something still matches).
- Throw `DuskStaleHandleException` when predicates match nothing live.

When to use them: across multi-step flows, retry loops, animated UI,
async-loading content. Default to `q<N>` whenever the agent will hold a
ref across more than one action.

### Disjoint spaces

`e<N>` and `q<N>` never share a token. Never invent a ref by guessing
the next number; always mint via the appropriate tool. The action
handlers prefix-sniff (`q...` is a query, anything else is a snapshot
ref), so passing `e<N>` to an action that re-resolves would still
lookup the snapshot entry.

## Choosing between snap and observe

Both walk the Semantics tree. Snap returns a YAML document with `e<N>`
tokens; observe returns a JSON candidate array with `q<N>` handles.

Use snap when:

- The agent will reason against the YAML structure (parent-child, role
  layout, full enricher context).
- The next action is single-shot.
- The agent wants to see uninteractive widgets too (text labels,
  headings used for context).

Use observe when:

- The agent will loop over candidates (form fill, "tap every visible
  link", "find the row whose text contains X").
- The action is retry-prone or the UI animates.
- The agent only cares about interactive widgets.

Common pattern: `dusk_snap` once to orient, then `dusk_observe` (or
`dusk_find`) to mint stable handles for the actual loop.

## When the gate is wrong

The gate is conservative. There are real cases where the agent knows
the action is safe but the gate fails:

- A button enters a ripple animation immediately when tapped, but the
  agent wants to fire a second action against a different button while
  the ripple plays: pass `checkStable: false` on that second action.
- An expected overlay is in front of the target on purpose (a
  permanently-pinned snackbar that does not block touches): pass
  `checkReceivesEvents: false`.

Both flags are per-call. There is no global way to disable the gate;
that is intentional. Disable per call, not per session.
