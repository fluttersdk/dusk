# tapir:snap

Capture the Semantics tree of the running Flutter app as YAML, tagging every interactive node with a `[ref=eN]` token.

`tapir:snap` is the foundational read command: every action command (`tapir:tap`, `tapir:type`, `tapir:drag`, etc.) consumes one of its `eN` refs to locate the target widget.

The `eN` namespace is snapshot-frozen: every fresh `tapir:snap` clears the registry and mints new tokens. For long-lived handles that survive rebuilds, use `tapir:find` (which mints `qN` tokens) or `tapir:observe`.

An `eN` ref also recovers from a rebuild on its own, within limits. Each snapshot binds a label-and-index query, plus the number of nodes carrying that label, to every labelled ref. When the element behind the ref has left the tree, the action relocates the control by that query, but only if the live tree still has the same number of nodes with that label; the response then lists the ref under `reresolved` (for example `"reresolved": ["e5"]`). With a different count the ref fails as `defunct (element no longer mounted)` and you re-snap. The query has no role, so a node of another role with the same label in the same position could be matched.

Interactive nodes inside a currently-overflowing render ancestor carry an additive `overflow: true` sub-line in the YAML output. This is a live current-state check (`RenderFlex.toStringShort()` appends ` OVERFLOWING` while the constraint is violated); it is not a historical record. For the full non-fatal error history including overflow details, use `tapir:exceptions`.

Text fields collapse to a single typeable ref. A field such as a wind `WInput` produces two nested `textbox` Semantics nodes (the outer wrapper plus the `RenderEditable` leaf that always owns its own node). `tapir:snap` suppresses the inner duplicate when its render object is a render-tree descendant of the outer `textbox` node's render object, emitting one ref for the surviving node and tagging it with an additive `typeable: true` sub-line. Collapse is by render-object containment only, so two sibling fields sharing the same label stay two distinct refs. Target the node carrying `typeable: true` when typing: `tapir:type` resolves the inner `EditableText` from it.

- [Synopsis](#synopsis)
- [Arguments](#arguments)
- [Narrowing, and why the full tree is usually the wrong answer](#narrowing)
- [Returns](#returns)
- [Enricher fragments](#enricher-fragments)
- [Examples](#examples)
- [Related Documentation](#related-documentation)

<a name="synopsis"></a>
## Synopsis

```
dart run tapir tapir:snap [--depth=<n>]
                                   [--within=<eN>]
                                   [--interactiveOnly]
                                   [--grep=<regex>]
                                   [--includeEnrichers]
                                   [--json]
```

`tapir:snap` requires a running Flutter session (`CommandBoot.connected`). It dials the VM Service URI recorded for this project's dowel session, calls `ext.tapir.snap`, and prints the snapshot YAML to stdout.

---

<a name="arguments"></a>
## Arguments

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--depth` | int (string-parsed) | unset (full tree) | Optional max tree depth. Caps the walk so very deep widget trees stay readable. Omit for the full tree. |
| `--includeEnrichers` | flag | `false` | Emit Magic and Wind enricher fragments under each ref entry. Default off matches the Playwright-style minimal snapshot; turn on when the agent needs the className tokens, route name, or form field metadata. |
| `--within` | string (`e<N>`) | unset (whole tree) | Scope the walk to one subtree. Takes an `e<N>` ref from a prior snapshot; `q<N>` query handles are not addressable here, since they re-resolve per action and have no fixed subtree. An unknown or node-less ref is an error rather than a silent widening. |
| `--interactiveOnly` | flag | `false` | Emit only nodes that carry a ref (buttons, text fields, links, headers, anything with a tap action) and drop the plain `- text` lines. |
| `--grep` | string (regex) | unset | Emit only nodes whose label or value matches, plus the ancestors that lead to them. Ancestors survive because they carry the refs you act on: a matching `- text` line has none of its own. A pattern that is not a valid regex (a label such as `Container Sample (MP4, H.264` is an unterminated group) is matched as a literal substring instead, and the envelope carries `"grepLiteral": true`. |
| `--json` | flag | `false` | Print the whole envelope as JSON instead of the tree alone, so `grepLiteral`, `warnings`, `framesForced` and `renderErrors` are readable. Text mode is unchanged. |

Every flag is serialised as a string into the VM Service params map; the command does no key translation. `tapir:snap` has no `--snapshot` option: it is the snapshot. The `--snapshot=full|diff|none` option belongs to the action verbs ([tapir:tap](tapir-tap.md), `tapir:fill`, `tapir:type`, `tapir:navigate`, `tapir:scroll`).

---

<a name="narrowing"></a>
## Narrowing, and why the full tree is usually the wrong answer

A full tree costs context on any real screen, and on a shell whose sidebar repeats the labels of the pages it opens it is also the misleading answer: an exact-label lookup resolves the nav item, so the caller measures the sidebar and concludes two pages differ. That has produced confident wrong readings more than once.

```bash
# Read one region. Take its ref from a prior snapshot.
dart run tapir tapir:snap --within=e12

# Only the things you can act on.
dart run tapir tapir:snap --interactiveOnly

# Only what matches, plus the path to it.
dart run tapir tapir:snap --grep="Sign ?in"
```

The three compose. `--within=e12 --interactiveOnly` is the usual shape before an action: one region, refs only.

An unfiltered call is unchanged, byte for byte.

---

<a name="returns"></a>
## Returns

The VM Service handler returns a JSON envelope `{ "snapshot": "<yaml>", "groupId": "<id>" }`. The CLI unwraps the `snapshot` field and writes the raw YAML to stdout; when the field is missing the entire JSON object is dumped instead.

**Success envelope (illustrative):**

```yaml
- text "Welcome back"
- textbox "Email" [ref=e1]
  typeable: true
- button "Sign in" [ref=e2]
```

Each line is `- <role> "<label>"`, with `: "<value>"` after the label when the node has a value and the `[ref=eN]` token on interactive nodes; plain text nodes print as `- text "..."` and carry no ref. Children are indented two spaces under their parent. The `typeable: true` sub-line marks the single surviving `textbox` node after the nested-field collapse described above; it is the node `tapir:type` resolves.

A ref line may end with ` [offscreen]` and/or ` [occluded]` after `[ref=eN]`:

```yaml
- button "Archive" [ref=e9] [offscreen]
- button "Save" [ref=e4] [occluded]
```

`[offscreen]` means the widget lies outside the viewport (scroll it into view with `tapir:scroll --intoView`). `[occluded]` means a hit test at its centre reaches a widget painted above it, such as a dialog or an overlay (dismiss that first). A healthy screen prints neither, so the output is unchanged. An offscreen node is never probed for occlusion, and a node with no area carries neither marker.

A merged node (a `MergeSemantics` boundary) whose centre is not on its own control gets one more indented sub-line, `tapOwner: {"x":656.0,"y":536.0,"w":120.0,"h":40.0}`: the control's rect in logical pixels. A tap on that ref goes to that control (see [`tapir:tap`](tapir-tap.md)) unless the object says `"retargets":false` (several candidates, or the control is covered or off screen), and `"centreHandled":true` means the centre has a tap handler of its own that `--no-retarget` would tap. The line is absent on every other node (#60).

When `--includeEnrichers` is set, each entry gains indented lines contributed by the registered enrichers (see [Enricher fragments](#enricher-fragments)).

### The diff baseline

An unfiltered `tapir:snap` records its text as the baseline that `--snapshot=diff` on an action verb compares against: the action then returns only the lines it changed. A snap with `--grep`, `--within`, `--depth`, `--interactiveOnly` or `--includeEnrichers` is a partial view and never replaces the baseline, and a hot restart clears it (the next diff then returns the full text). Take a plain `tapir:snap` first when you plan to use `diff`.

### Render errors

When the `FlutterError.onError` capture buffer holds non-fatal render or build errors (for example a `ParentDataWidget` misuse such as `Expanded` placed outside a `Flex`, or a layout overflow), the response includes a `renderErrors` block:

```json
{
  "snapshot": "<yaml>",
  "groupId": "snapshot-1700000000000",
  "renderErrors": {
    "count": 2,
    "recent": [
      { "type": "FlutterError", "message": "Incorrect use of ParentDataWidget." },
      { "type": "FlutterError", "message": "A RenderFlex overflowed by 32 pixels." }
    ],
    "hint": "Run tapir:exceptions (CLI) or tapir_exceptions (MCP) for full messages + stack traces."
  }
}
```

Fields:

| Field | Type | Description |
|-------|------|-------------|
| `count` | int | Total number of captured render/build errors. May exceed `recent.length`. |
| `recent` | array (max 3) | Most recent entries; each has `type` (string) and `message` (first line only). |
| `hint` | string | Fixed advisory pointing to `tapir:exceptions` (CLI) / `tapir_exceptions` (MCP) for full detail. |

The `renderErrors` block is **omitted entirely** when no errors are in the buffer. A clean screen produces the standard two-key envelope (`snapshot` + `groupId`).

**CLI banner:** when `renderErrors` is present, `tapir:snap` prints a render-error banner to **stderr** (stdout stays the pure snapshot text, so tooling that captures only stdout is unaffected):

```
⚠ 2 render error(s) captured on this screen (run tapir:exceptions for full detail):
  - FlutterError: Incorrect use of ParentDataWidget.
  - FlutterError: A RenderFlex overflowed by 32 pixels.
```

### Frame production

When the app is not producing frames, semantics labels are never rebuilt: the snapshot comes back with its buttons and none of its `- text` nodes, and a screen that renders perfectly reads as completely empty. Tapir first tries to wake a hidden or minimised app, and a snapshot taken after waking carries `"framesForced": true`. When it cannot (the `TAPIR_FORCE_FRAMES=false` opt-out, a `detached` lifecycle, a wake that produced no frame, or any hidden web tab) the response carries a `warnings` block and `tapir:snap` prints a banner to stderr. On web:

```
⚠ The app is not producing frames (lifecycle: hidden), so this result may be stale. A
  backgrounded browser tab is the usual cause: bring the page to front and retry.
```

On desktop the banner names a hidden, minimised or occluded window or an asleep display instead.

On a web session started with `--cdp-port`, the CLI acts on the web warning itself: it sends CDP `Page.bringToFront` once and calls `ext.tapir.snap` again, so a snapshot of a backgrounded tab usually comes back healthy. A CDP failure leaves the first result and its exit code. Without a `cdpPort` nothing changes.

Do not read an empty tree as an empty screen without checking for this block first. See [Frame production](../reference/frame-production.md).

**Error envelope:**

The VM Service handler propagates errors as `ServiceExtensionResponse.error(extensionError, message)`. The CLI surfaces the exception via `DowelContext.callExtension` and exits with a non-zero status. Typical failure modes:

- No running app at the recorded URI (the dowel dispatcher reports the dial failure before `tapir:snap` runs).
- `TapirPlugin.install()` missing from `lib/main.dart` (run `tapir:install`).

---

<a name="enricher-fragments"></a>
## Enricher fragments

When `--includeEnrichers` is true, every `TapirSnapshotEnricher` appended to the `TapirPlugin.enrichers` live list contributes indented lines under each ref. The two first-party enrichers:

- **MagicTapirIntegration** ships the Magic enrichers (see [Plugins: Magic integration](../plugins/magic-integration.md) for the fields).
- **`wind_kit`** surfaces a six-field `wind:` block (breakpoint, brightness, platform, states, bgColor, textColor) through the neutral `wind_kit_diagnostics_contracts.WindDebugRegistry` bridge rather than via an enricher, once the app calls `Wind.installDebugResolver()`, so the data appears under each W-prefixed widget ref without any enricher registration.

Each enricher is synchronous and stateless; the `Element` reference is never retained across calls.

### Overflow annotation

The `overflow: true` sub-line is emitted by the snapshot dispatcher itself (not via an enricher) when the resolved `RenderObject.toStringShort()` contains the Flutter debug suffix ` OVERFLOWING`. It appears for any interactive node whose nearest render ancestor is currently violating its constraints, regardless of whether enrichers are enabled. Example output:

```yaml
- button "Submit" [ref=e5]
  overflow: true
```

### Typeable annotation and textbox collapse

A text field commonly produces two nested `textbox` Semantics nodes: an outer wrapper (e.g. a wind `WInput`'s `Semantics(textField:true)`) and the `RenderEditable` leaf, which always owns its own `textField` node and which `MergeSemantics` cannot absorb. Both nodes used to mint a ref; typing on the inner leaf threw `-32000`. The snapshot walk now suppresses the inner node when its render object is a render-tree descendant of the outer `textbox` node's render object, leaving one ref for the surviving node and appending `typeable: true` beneath it:

```yaml
- textbox "Email" [ref=e2]
  typeable: true
```

The collapse is by render-object containment only, never label/value equality, so two sibling fields sharing a label remain two distinct refs. The `typeable: true` node is the one `tapir:type` resolves to the inner `EditableText`.

### Merged controls

A control wrapped in `MergeSemantics` (a magic_starter `MSSwitch` row, a wind `WAnchor` around a hover `WDiv`) is listed once. Flutter keeps each absorbed descendant in the tree as its own node flagged `isMergedIntoParent`, so the walk used to print a `button "X"` line followed by a nested duplicate. A merged node now prints no line and mints no ref; the walk still descends through it, and the boundary line already carries the merged label, flags and actions, which is what the platform exposes. Refs after a removed duplicate shift down by one each, so a script that hard-coded ref numbers re-snaps.

---

<a name="examples"></a>
## Examples

### 1. Minimal snapshot of the current screen

```bash
dart run tapir tapir:snap
```

Expected output (illustrative; truncated):

```yaml
- text "Monitors"
- button "New monitor" [ref=e1]
- button "Settings" [ref=e2]
```

### 2. Snapshot with depth cap

```bash
dart run tapir tapir:snap --depth=4
```

Caps the walk at four levels of nesting. Useful for very dense screens (long lists, complex forms) where the full tree is noisy.

### 3. Snapshot with enrichers turned on

```bash
dart run tapir tapir:snap --includeEnrichers
```

Expected output (illustrative):

```yaml
- button "New monitor" [ref=e1]
  wind:
    breakpoint: lg
    brightness: light
  magicRoute: /monitors
```

---

<a name="related-documentation"></a>
## Related Documentation

- [tapir:tap](tapir-tap.md): consume an `eN` token to synthesise a tap.
- [tapir:find](tapir-find.md): mint a long-lived `qN` handle that survives rebuilds.
- [tapir:observe](tapir-observe.md): structured candidate list when the agent needs more than the raw Semantics tree.
- [Plugins: Enricher authoring](../plugins/enricher-authoring.md): how to ship a custom enricher that contributes additional fragments.
