# tapir:fill

Focus, clear, type, and settle a text field in a single call.

`tapir:fill` promotes the manual focus + clear + type + settle + stale-retry dance into one first-class command, so an agent no longer re-discovers the sequence (and its frame-await + retry subtleties) on every form.

Internally `tapir:fill` composes the existing gated `ext.tapir.focus`, `ext.tapir.clear`, and `ext.tapir.type` handlers verbatim, so it inherits the full 6-step actionability gate, IME focus, `onChanged` / form-validator firing (via `userUpdateTextEditingValue`), and post-action snapshot semantics. It re-resolves the ref before each attempt and retries the whole sequence once if the ref goes stale mid-fill.

- [Synopsis](#synopsis)
- [Arguments](#arguments)
- [Returns](#returns)
- [Which field was written](#which-field-was-written)
- [Stale-retry](#stale-retry)
- [Examples](#examples)
- [Related Documentation](#related-documentation)

<a name="synopsis"></a>
## Synopsis

```
dart run tapir tapir:fill --ref=<eN|qN> --text=<value>
                                    [--includeSnapshot]
                                    [--snapshot=full|diff|none]
                                    [--[no-]checkStable]
                                    [--[no-]checkReceivesEvents]
```

`tapir:fill` requires a running Flutter session (`CommandBoot.connected`). It dials the VM Service URI, calls `ext.tapir.fill`, and prints either a one-line success (`Filled <ref>`) or the full JSON envelope when `--includeSnapshot` is set.

---

<a name="arguments"></a>
## Arguments

| Option | Type | Default | Required | Description |
|--------|------|---------|----------|-------------|
| `--ref` | string | (none) | yes (`mandatory: true`) | Text-field ref token (`e1` from a prior `tapir:snap`, or `q1` from a prior `tapir:find`). Empty values trigger a CLI-side error with exit code `1` before the VM Service call. |
| `--text` | string | (none) | yes (`mandatory: true`) | Value to set. Replaces existing content. Pass an empty string to clear the field. |
| `--includeSnapshot` | flag | `false` | no | Embed the post-fill snapshot YAML in the response. |
| `--snapshot` | `full`, `diff` or `none` | (none) | no | Print the post-fill snapshot after the one-line summary and override `--includeSnapshot`. `diff` prints only the lines the fill changed since your last unfiltered snapshot (a `tapir:snap` or an earlier action), as `- old` then `+ new` per changed row, with a `(K of N lines changed)` footer; with no baseline yet it prints the full text. Over MCP this is the `snapshot` enum on `tapir_fill`. |
| `--checkStable` | flag | `true` | no | Run the Stable (2-frame rect-unchanged) actionability gate during the type step. |
| `--checkReceivesEvents` | flag | `true` | no | Run the Receives-Events (front-most hit-test) actionability gate during the type step. |

---

<a name="returns"></a>
## Returns

| Exit code | Meaning |
|-----------|---------|
| `0` | Field filled. Emits `Filled <ref>` (default) or the full JSON envelope when `--includeSnapshot` or `--json` is set. |
| `1` | `--ref` or `--text` was missing (CLI-side guard fires before the VM Service call); OR, in the one-line mode, `effect.verified` came back `false`. |
| non-zero | VM Service handler returned an error: ref not found, actionability gate failure, no editable under the ref, or a stale handle that did not recover on retry. |

**A fill that did not stick.** The response carries `effect.verified`, read back from the live controller after the two-frame settle, so a formatter or echo that reverts the write a frame later reports `verified: false` too. A green tick only means the text was dispatched: an input formatter that trimmed or rejected it leaves the field holding something else. In the one-line mode that case prints an error naming what the field holds and exits `1`:

```
Fill not verified: e7 holds "12", not the text that was typed ("12abc")
```

With `--includeSnapshot` or `--json` the JSON envelope is printed and the exit code stays `0`; read `effect.verified` and `effect.value` yourself.

**A gate that could not confirm.** The gate runs in the type step, and the response carries that step's `checks` block whenever the receives-events check was `indeterminate` or `skipped` (see [Actionability gate](../reference/actionability-gate.md#what-the-gate-could-not-prove)). A clean response has no `checks` key, so its presence is the signal; read it together with `effect`. The default CLI summary omits `checks`: pass `--json` to print the full response, or `--includeSnapshot` (without `--snapshot`, which disables that flag) to print the envelope.

**Success envelope (`--includeSnapshot` on):**

```json
{
  "ref": "e7",
  "text": "alice@example.com",
  "filled": true,
  "snapshot": "- textbox \"Email\" [ref=e7]\n  typeable: true\n..."
}
```

---

<a name="which-field-was-written"></a>
## Which field was written

`tapir:fill` resolves the target field once and uses it for focus, clear and type, so the three steps cannot land in different fields. The response says which one in `effect.target`:

```json
"effect": {
  "kind": "text", "verified": true, "value": "alice@example.com",
  "target": { "matchKind": "overlap", "label": "Email", "rect": { "x": 20, "y": 200, "width": 335, "height": 56 } }
}
```

`matchKind` is `overlap` (the field overlapping the ref's rect the most: the ref is the field), `nearest` (nothing overlaps, so the field nearest the ref's centre was written) or `element` (the ref had no rect, so the first editable under its element was used). Label and static-text handles keep the `nearest` fallback, since a label above its field is how you address that field. On `nearest` the CLI prints a warning naming the field and its rect, so a fill into a neighbouring field is visible.

A ref whose node is an interactive control other than a text field is refused instead of falling back to the nearest field (a dropdown, checkbox or button ref used to wipe and rewrite whichever field sat closest). The error reads `ref e9 is a button, not a text field`, with the role being `button`, `checkbox`, `radio`, `switch`, `slider` or `link`. Target the field itself, or use `tapir:tap`, `tapir:select_option` or `tapir:set_checkbox`. The same rules apply to `tapir:type` and `tapir:clear`.

---

<a name="stale-retry"></a>
## Stale-retry

`tapir:fill` re-resolves the ref via the registry before each attempt. When a `q<N>` handle's stored predicates transiently miss (the field is rebuilding mid-fill), the resolver reports a stale handle; `tapir:fill` re-runs the whole resolve + focus + clear + type sequence once so the second pass walks the now-settled tree. A second stale outcome surfaces a typed `stale` error envelope so the agent re-snaps or re-finds rather than looping. Prefer a `q<N>` handle (from `tapir:find`) for fields that may rebuild between snapshot and fill; the retry then re-resolves cleanly.

---

<a name="examples"></a>
## Examples

### 1. Fill an email field in one call

```bash
dart run tapir tapir:snap > /tmp/snap.yaml
# locate the email field's eN in /tmp/snap.yaml
dart run tapir tapir:fill --ref=e7 --text="alice@example.com"
```

```
✓ Filled e7
```

### 2. Clear a field

```bash
dart run tapir tapir:fill --ref=e7 --text=""
```

### 3. Fill a re-resolvable handle that survives rebuilds

```bash
dart run tapir tapir:find --key="email-input"   # -> q1
dart run tapir tapir:fill --ref=q1 --text="alice@example.com" --includeSnapshot
```

---

<a name="related-documentation"></a>
## Related Documentation

- [tapir:snap](tapir-snap.md): produce the `eN` refs that `tapir:fill` consumes; text fields collapse to a single `typeable: true` node.
- [tapir:find](tapir-find.md): mint a re-resolvable `qN` handle that survives rebuilds; pass it as `--ref=q1`.
- [tapir:tap](tapir-tap.md): focus a field by tapping; `tapir:fill` does the focus for you.
- [Reference: Actionability gate](../reference/actionability-gate.md): the gate the composed type step runs.
