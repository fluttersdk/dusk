# dusk:tap

Synthesise a tap at the widget identified by a snapshot ref token. `dusk:tap` is the primary action command: every interactive flow in an agent-driven test starts with a `dusk:snap` (to obtain `eN` refs) followed by one or more `dusk:tap --ref=<eN>` calls.

The handler routes through the actionability gate (enabled, zero-rect, off-viewport) before the pointer event leaves the VM. A gate failure throws `DuskActionabilityException` and surfaces as a structured error; the agent re-snaps or re-finds rather than silently retrying.

---

## Table of contents

- [Synopsis](#synopsis)
- [Arguments](#arguments)
- [Returns](#returns)
- [Actionability gate](#actionability-gate)
- [Examples](#examples)
- [See also](#see-also)

---

<a name="synopsis"></a>
## Synopsis

```
dart run fluttersdk_dusk dusk:tap --ref=<eN|qN>
                                   [--includeSnapshot]
                                   [--[no-]checkStable]
                                   [--[no-]checkReceivesEvents]
                                   [--verify]
                                   [--until=<text>]
```

`dusk:tap` requires a running Flutter session (`CommandBoot.connected`). It dials the VM Service URI, calls `ext.dusk.tap`, and prints either a one-line success or the post-tap JSON depending on `--includeSnapshot` / `--verify`.

The pointer is dispatched at the target's LIVE center: the handler re-resolves the element's current bounding rect immediately after the actionability gate passes (falling back to the cached snapshot rect only for slivers / detached render objects), so a tap still lands on a button whose host rebuilt it into a shifted slot between `dusk:snap` and `dusk:tap`.

---

<a name="arguments"></a>
## Arguments

| Option | Type | Default | Required | Description |
|--------|------|---------|----------|-------------|
| `--ref` | string | (none) | yes (`mandatory: true`) | Snapshot ref token (e.g. `e1` from a prior `dusk:snap`, or `q1` from a prior `dusk:find`). Empty values trigger a CLI-side error with exit code `1` before the VM Service call is made. |
| `--includeSnapshot` | flag | `false` | no | Embed the post-tap snapshot YAML in the response. Useful when the tap is expected to trigger a navigation or modal and the next agent step needs the fresh tree. |
| `--checkStable` | flag | `true` | no | Run the Stable (2-frame rect-unchanged) actionability gate. Disable when targeting an animating widget that intentionally rebuilds across frames. |
| `--checkReceivesEvents` | flag | `true` | no | Run the Receives-Events (front-most hit-test) actionability gate. Disable when targeting a widget that is intentionally occluded by an overlay you also want to interact with. |
| `--verify` | flag | `false` | no | Capture a target-scoped before/after signal (the nearest enclosing route name plus a hash of the target element's own semantics subtree) and add a `changed` boolean to the response reporting whether the tap produced an observable effect on the target. Off by default, which keeps the response shape unchanged. Enabling `--verify` always prints the JSON envelope (so the `changed` field is visible) regardless of `--includeSnapshot`. |
| `--until` | string | (none) | no | After the tap settles, poll the live element tree (same loop as `dusk:wait`) for a `Text` whose data equals this value, up to the `until` timeout (default 3000ms), and add an `untilMatched` boolean to the response reporting whether it appeared. Use to confirm a navigation / state change in one call instead of a separate `dusk:wait`. Off by default, which keeps the response shape unchanged. |

The two `check*` flags default to `true`. Disable them with the inverted form (`--no-checkStable`, `--no-checkReceivesEvents`) when the target genuinely should not be subject to that precondition.

---

<a name="returns"></a>
## Returns

`dusk:tap` returns an integer exit code via `Future<int>`:

| Exit code | Meaning |
|-----------|---------|
| `0` | Tap synthesised. The handler emits either `Tapped <ref>` (default) or the full JSON envelope when `--includeSnapshot` is set. |
| `1` | `--ref` was missing or empty (CLI-side guard fires before the VM Service call). |
| non-zero | VM Service handler returned `ServiceExtensionResponse.error`. Common causes: ref not found in the registry, actionability gate failure, no running app at the recorded URI. |

**Success envelope (default, `--includeSnapshot` off):**

```
[ok]      Tapped e2
```

**Success envelope (`--includeSnapshot` on):**

```json
{
  "snapshot": "[ref=e1] role=text label=\"Welcome\" ...",
  "ref": "e2"
}
```

**Success envelope (`--verify` on):**

```json
{
  "ref": "e2",
  "changed": true
}
```

`changed` is `true` when the target's route or semantics subtree differed after the tap, `false` when nothing observable changed (a false-success signal the agent can branch on). The `changed` field is omitted entirely when `--verify` is off.

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
dart run fluttersdk_dusk dusk:snap > /tmp/snap.yaml
# locate the button's eN in /tmp/snap.yaml
dart run fluttersdk_dusk dusk:tap --ref=e2
```

Expected output (illustrative):

```
[ok]      Tapped e2
```

### 2. Tap and capture the post-tap tree in one round trip

```bash
dart run fluttersdk_dusk dusk:tap --ref=e2 --includeSnapshot
```

Expected output (illustrative; abbreviated):

```json
{"snapshot":"[ref=e1] role=text label=\"Detail page\" ...","ref":"e2"}
```

### 3. Tap an intentionally-animating widget

```bash
dart run fluttersdk_dusk dusk:tap --ref=e5 --no-checkStable
```

Skips the 2-frame stable check for an animating loader / shimmer / spinner that the agent legitimately wants to interact with.

### 4. Tap and verify the tap had an observable effect

```bash
dart run fluttersdk_dusk dusk:tap --ref=e2 --verify
```

Expected output (illustrative):

```json
{"ref":"e2","changed":true}
```

`changed:false` flags a tap that the gate accepted but that produced no observable effect on the target (the classic false-success: a button that looks tappable but whose `onTap` never fired). Use it as a post-condition assertion in agent-driven flows.

### 5. Tap and wait for the expected text to appear

```bash
dart run fluttersdk_dusk dusk:tap --ref=e2 --until="Welcome back"
```

Expected output (illustrative):

```json
{"ref":"e2","untilMatched":true}
```

After the tap, the handler polls the element tree for a `Text("Welcome back")` up to 3000ms. `untilMatched:false` means the text never appeared within the window (the tap did not produce the expected navigation / state change). This folds a `dusk:wait --text=...` into the tap call so the agent confirms the outcome in one round trip.

---

<a name="see-also"></a>
## See also

- [dusk:snap](dusk-snap.md): produce the `eN` refs that `dusk:tap` consumes.
- [dusk:find](dusk-find.md): mint a re-resolvable `qN` handle that survives rebuilds; pass it as `--ref=q1`.
- [dusk:observe](dusk-observe.md): structured candidate list when the agent needs more than the raw Semantics tree.
- [Reference: Actionability gate](../reference/actionability-gate.md): full ordering and message format the agent branches on.
