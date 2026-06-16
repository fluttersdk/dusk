# dusk:fill

Focus, clear, type, and settle a text field in a single call. `dusk:fill` promotes the manual focus + clear + type + settle + stale-retry dance into one first-class command, so an agent no longer re-discovers the sequence (and its frame-await + retry subtleties) on every form.

Internally `dusk:fill` composes the existing gated `ext.dusk.focus`, `ext.dusk.clear`, and `ext.dusk.type` handlers verbatim, so it inherits the full 6-step actionability gate, IME focus, `onChanged` / form-validator firing (via `userUpdateTextEditingValue`), and post-action snapshot semantics. It re-resolves the ref before each attempt and retries the whole sequence once if the ref goes stale mid-fill.

---

## Table of contents

- [Synopsis](#synopsis)
- [Arguments](#arguments)
- [Returns](#returns)
- [Stale-retry](#stale-retry)
- [Examples](#examples)
- [See also](#see-also)

---

<a name="synopsis"></a>
## Synopsis

```
dart run fluttersdk_dusk dusk:fill --ref=<eN|qN> --text=<value>
                                    [--includeSnapshot]
                                    [--[no-]checkStable]
                                    [--[no-]checkReceivesEvents]
```

`dusk:fill` requires a running Flutter session (`CommandBoot.connected`). It dials the VM Service URI, calls `ext.dusk.fill`, and prints either a one-line success (`Filled <ref>`) or the full JSON envelope when `--includeSnapshot` is set.

---

<a name="arguments"></a>
## Arguments

| Option | Type | Default | Required | Description |
|--------|------|---------|----------|-------------|
| `--ref` | string | (none) | yes (`mandatory: true`) | Text-field ref token (`e1` from a prior `dusk:snap`, or `q1` from a prior `dusk:find`). Empty values trigger a CLI-side error with exit code `1` before the VM Service call. |
| `--text` | string | (none) | yes (`mandatory: true`) | Value to set. Replaces existing content. Pass an empty string to clear the field. |
| `--includeSnapshot` | flag | `false` | no | Embed the post-fill snapshot YAML in the response. |
| `--checkStable` | flag | `true` | no | Run the Stable (2-frame rect-unchanged) actionability gate during the type step. |
| `--checkReceivesEvents` | flag | `true` | no | Run the Receives-Events (front-most hit-test) actionability gate during the type step. |

---

<a name="returns"></a>
## Returns

| Exit code | Meaning |
|-----------|---------|
| `0` | Field filled. Emits `Filled <ref>` (default) or the full JSON envelope when `--includeSnapshot` is set. |
| `1` | `--ref` or `--text` was missing (CLI-side guard fires before the VM Service call). |
| non-zero | VM Service handler returned an error: ref not found, actionability gate failure, no editable under the ref, or a stale handle that did not recover on retry. |

**Success envelope (`--includeSnapshot` on):**

```json
{
  "ref": "e7",
  "text": "alice@example.com",
  "filled": true,
  "snapshot": "[ref=e7] role=textbox typeable:true ..."
}
```

---

<a name="stale-retry"></a>
## Stale-retry

`dusk:fill` re-resolves the ref via the registry before each attempt. When a `q<N>` handle's stored predicates transiently miss (the field is rebuilding mid-fill), the resolver reports a stale handle; `dusk:fill` re-runs the whole resolve + focus + clear + type sequence once so the second pass walks the now-settled tree. A second stale outcome surfaces a typed `stale` error envelope so the agent re-snaps or re-finds rather than looping. Prefer a `q<N>` handle (from `dusk:find`) for fields that may rebuild between snapshot and fill; the retry then re-resolves cleanly.

---

<a name="examples"></a>
## Examples

### 1. Fill an email field in one call

```bash
dart run fluttersdk_dusk dusk:snap > /tmp/snap.yaml
# locate the email field's eN in /tmp/snap.yaml
dart run fluttersdk_dusk dusk:fill --ref=e7 --text="alice@example.com"
```

```
[ok]      Filled e7
```

### 2. Clear a field

```bash
dart run fluttersdk_dusk dusk:fill --ref=e7 --text=""
```

### 3. Fill a re-resolvable handle that survives rebuilds

```bash
dart run fluttersdk_dusk dusk:find --key="email-input"   # -> q1
dart run fluttersdk_dusk dusk:fill --ref=q1 --text="alice@example.com" --includeSnapshot
```

---

<a name="see-also"></a>
## See also

- [dusk:snap](dusk-snap.md): produce the `eN` refs that `dusk:fill` consumes; text fields collapse to a single `typeable: true` node.
- [dusk:find](dusk-find.md): mint a re-resolvable `qN` handle that survives rebuilds; pass it as `--ref=q1`.
- [dusk:tap](dusk-tap.md): focus a field by tapping; `dusk:fill` does the focus for you.
- [Reference: Actionability gate](../reference/actionability-gate.md): the gate the composed type step runs.
