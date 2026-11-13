# tapir:tap

Synthesise a tap at the widget identified by a snapshot ref token. `tapir:tap` is the primary action command: every interactive flow in an agent-driven test starts with a `tapir:snap` (to obtain `eN` refs) followed by one or more `tapir:tap --ref=<eN>` calls.

The handler routes through the actionability gate (enabled, zero-rect, off-viewport) before the pointer event leaves the VM. A gate failure throws `TapirActionabilityException` and surfaces as a structured error; the agent re-snaps or re-finds rather than silently retrying.

- [Synopsis](#synopsis)
- [Arguments](#arguments)
- [Returns](#returns)
- [Actionability gate](#actionability-gate)
- [Examples](#examples)
- [Related Documentation](#related-documentation)

<a name="synopsis"></a>
## Synopsis

```
dart run tapir tapir:tap --ref=<eN|qN>
                                   [--includeSnapshot]
                                   [--snapshot=full|diff|none]
                                   [--[no-]checkStable]
                                   [--[no-]checkReceivesEvents]
                                   [--[no-]retarget]
                                   [--until=<text>]
                                   [--untilTimeoutMs=<n>]
```

`tapir:tap` requires a running Flutter session (`CommandBoot.connected`). It dials the VM Service URI, calls `ext.tapir.tap`, and prints either a one-line success or the post-tap JSON depending on `--includeSnapshot` / `--until`.

The pointer is dispatched at the target's LIVE center: the handler re-resolves the element's current bounding rect immediately after the actionability gate passes (falling back to the cached snapshot rect only for slivers / detached render objects), so a tap still lands on a button whose host rebuilt it into a shifted slot between `tapir:snap` and `tapir:tap`.

---

<a name="arguments"></a>
## Arguments

| Option | Type | Default | Required | Description |
|--------|------|---------|----------|-------------|
| `--ref` | string | (none) | yes (`mandatory: true`) | Snapshot ref token (e.g. `e1` from a prior `tapir:snap`, or `q1` from a prior `tapir:find`). Empty values trigger a CLI-side error with exit code `1` before the VM Service call is made. |
| `--includeSnapshot` | flag | `false` | no | Embed the post-tap snapshot YAML in the response. Useful when the tap is expected to trigger a navigation or modal and the next agent step needs the fresh tree. |
| `--snapshot` | `full`, `diff` or `none` | (none) | no | Print the post-tap snapshot after the one-line summary and override `--includeSnapshot`. `full` is the whole tree; `diff` is only the lines the tap changed since your last unfiltered snapshot (a `tapir:snap` or an earlier action), as `- old` then `+ new` per changed row, `+ ` for an added row, `- ` for a removed one, and a `(K of N lines changed)` footer; `none` prints nothing. With no baseline yet, `diff` returns the full text. Over MCP this is the `snapshot` enum on `tapir_tap`. |
| `--checkStable` | flag | `true` | no | Run the Stable (2-frame rect-unchanged) actionability gate. Disable when targeting an animating widget that intentionally rebuilds across frames. |
| `--checkReceivesEvents` | flag | `true` | no | Run the Receives-Events (front-most hit-test) actionability gate. Disable when targeting a widget that is intentionally occluded by an overlay you also want to interact with. |
| `--retarget` | flag | `true` | no | Send a tap on a merged boundary to its one labelled control. `--no-retarget` taps the boundary centre (see below). |
| `--until` | string | (none) | no | After the tap settles, poll the live element tree (same loop as `tapir:wait`) for a `Text` whose data equals this value, up to the `--untilTimeoutMs` timeout (default 3000ms), and add an `untilMatched` boolean to the response reporting whether it appeared. Use to confirm a navigation / state change in one call instead of a separate `tapir:wait`. Off by default, which keeps the response shape unchanged. Setting `--until` always prints the JSON envelope (so `untilMatched` is visible) regardless of `--includeSnapshot`. |
| `--untilTimeoutMs` | int | `3000` | no | Timeout in milliseconds for the `--until` poll. Ignored when `--until` is not set. |

The two `check*` flags default to `true`. Disable them with the inverted form (`--no-checkStable`, `--no-checkReceivesEvents`) when the target genuinely should not be subject to that precondition.

---

<a name="returns"></a>
## Returns

`tapir:tap` returns an integer exit code via `Future<int>`:

| Exit code | Meaning |
|-----------|---------|
| `0` | Tap synthesised. The handler emits either `Tapped <ref>` (default) or the full JSON envelope when `--includeSnapshot` is set. |
| `1` | `--ref` was missing or empty (CLI-side guard fires before the VM Service call). |
| non-zero | VM Service handler returned `ServiceExtensionResponse.error`. Common causes: ref not found in the registry, actionability gate failure, no running app at the recorded URI. |

**Success envelope (default, `--includeSnapshot` off):**

```
[ok]      Tapped e2
```

When the `effect` block reports no change, the one-line form says so rather than
claiming a plain success:

```
[ok]      Tapped e2 (no observable change)
```

**Success envelope (`--includeSnapshot` on):**

```json
{
  "snapshot": "[ref=e1] role=text label=\"Welcome\" ...",
  "ref": "e2"
}
```

**The `effect` block, on every response:**

```json
{
  "ref": "e2",
  "effect": { "kind": "treeChanged", "changed": true }
}
```

`changed` is `true` when the target's route or its own semantics subtree differed after the tap, `false` when nothing observable changed. The signal is deliberately scoped to the TARGET rather than the whole tree, so unrelated background churn does not read as "something happened", and a counter button whose own label increments does.

`changed: false` is the classic false success: a button the gate accepted, whose `onTap` never fired. It was an opt-in `--verify` flag until it became clear that the agents who most needed it were the ones who did not know to ask for it.

**Stale `eN` refs.** When the widget behind an `eN` ref was rebuilt since the snapshot, the tap relocates it by the label and index the snapshot bound to the ref, provided the live tree has the same number of nodes with that label. The response then lists the ref: `"reresolved": ["e2"]`. With a different count the ref fails as `defunct (element no longer mounted)` and the agent re-snaps. The bound query has no role, so a node of another role with the same label in the same position could be matched.

**A merge boundary taps its own control (#60).** A `MergeSemantics` boundary (a player, a row or a card that merges a label and a button) taps at its own centre, which can belong to another handler (a full-frame stage that pauses on any tap) while the gate still reports `confirmed`. When exactly one labelled control owns the merged label (a `Semantics` whose label is part of it, with an `onTap` or `button`) and a hit test at its centre reaches it, the pointer goes there and the response carries `"retargeted": {"from": {"x", "y"}, "to": {"x", "y"}, "ownerRect": {"left", "top", "width", "height"}}`; the summary says `Tapped e7 on its control at (x, y), not the merged centre (x, y)`. When the centre had a tap handler of its own (a stage or a row that opens) the response adds `"centreHandled": true` inside `retargeted` and the summary names `--no-retarget`: pass `--no-retarget` to tap that handler instead of the control.

When that is not safe (several labelled candidates, or the control is covered by something else or lies outside the viewport) the tap stays at the centre and the response carries `"tapPointOutsideOwner": {"ownerRect": {...}, "point": {"x", "y"}}`, with one warning line on stderr naming both. Treat it as "this tap may have hit something else": check the result with `tapir:snap`, or target the control's own ref. The gate is unchanged. `tapir:snap` and `tapir:observe` show the control's rect before any tap (`tapOwner`). Only `tap` retargets; `hover`, `dblclick`, `right_click`, `triple_click` and `drag` still use the centre.

**Hidden window.** A hidden or minimised desktop app is woken before the tap and the response carries `"framesForced": true`; a tap against a window that cannot be woken carries a `warnings` block instead. On a web session started with `--cdp-port`, the CLI sends CDP `Page.bringToFront` once when the answer carries a web `warnings` block (or the call fails and the tab reports `hidden`). A tap is never repeated, because its gesture may already have fired: a stderr notice tells you to run `tapir:snap` to see what it did. See [Frame production](../reference/frame-production.md).

**Error envelope (actionability gate failure):**

The message format is `Widget ref=<ref> is not actionable: <reason>` where `<reason>` is one of `defunct (...)`, `not enabled`, `zero rect`, `off-viewport (rect=..., viewport=...)`, `not stable (rect changed by Xpx)`, or `obscured by other widget (top=...)`. The agent branches by substring-matching on `<reason>`; the full vocabulary is documented under [Reference: Actionability gate](../reference/actionability-gate.md#failure-reason-substrings).

---

<a name="actionability-gate"></a>
## Actionability gate

The actionability gate runs six preconditions in order: defunct (Step 0, preflight: render-object still attached), enabled (Tristate.isFalse fails), zero-rect (zero width or height), off-viewport (auto-`showOnScreen` first when a Scrollable ancestor exists), stable (2-frame rect drift ≤ 0.5px; opt out via `--no-checkStable`), and receives-events (hit-test path includes the target or descendant; opt out via `--no-checkReceivesEvents`). The full reference lives at [Reference: Actionability gate](../reference/actionability-gate.md).

Two further checks layer on top when their CLI flags are enabled:

- `checkStable` ; the rect is unchanged across two consecutive frames.
- `checkReceivesEvents` ; the hit-test at the rect center resolves to the target widget (i.e. no overlay is intercepting the tap).

See [Reference: Actionability gate](../reference/actionability-gate.md) for the full ordering rationale and how new preconditions can be appended without breaking pinned agent prompts.

---

<a name="examples"></a>
## Examples

### 1. Tap a button by its snapshot ref

```bash
dart run tapir tapir:snap > /tmp/snap.yaml
# locate the button's eN in /tmp/snap.yaml
dart run tapir tapir:tap --ref=e2
```

Expected output (illustrative):

```
[ok]      Tapped e2
```

### 2. Tap and capture the post-tap tree in one round trip

```bash
dart run tapir tapir:tap --ref=e2 --includeSnapshot
```

Expected output (illustrative; abbreviated):

```json
{"snapshot":"[ref=e1] role=text label=\"Detail page\" ...","ref":"e2"}
```

### 3. Tap an intentionally-animating widget

```bash
dart run tapir tapir:tap --ref=e5 --no-checkStable
```

Skips the 2-frame stable check for an animating loader / shimmer / spinner that the agent legitimately wants to interact with.

### 4. Read whether the tap had an observable effect

```bash
dart run tapir tapir:tap --ref=e2 --includeSnapshot
```

Expected output (illustrative):

```json
{"ref":"e2","effect":{"kind":"treeChanged","changed":true},"snapshot":"..."}
```

No flag is needed: the block is on every response. Use it as a post-condition assertion in agent-driven flows, and read it before concluding the app is broken.

### 5. Tap and wait for the expected text to appear

```bash
dart run tapir tapir:tap --ref=e2 --until="Welcome back"
```

Expected output (illustrative):

```json
{"ref":"e2","untilMatched":true}
```

After the tap, the handler polls the element tree for a `Text("Welcome back")` up to 3000ms. `untilMatched:false` means the text never appeared within the window (the tap did not produce the expected navigation / state change). This folds a `tapir:wait --text=...` into the tap call so the agent confirms the outcome in one round trip.

---

<a name="related-documentation"></a>
## Related Documentation

- [tapir:snap](tapir-snap.md): produce the `eN` refs that `tapir:tap` consumes.
- [tapir:find](tapir-find.md): mint a re-resolvable `qN` handle that survives rebuilds; pass it as `--ref=q1`.
- [tapir:observe](tapir-observe.md): structured candidate list when the agent needs more than the raw Semantics tree.
- [Reference: Actionability gate](../reference/actionability-gate.md): full ordering and message format the agent branches on.
