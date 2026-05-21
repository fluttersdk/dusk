# dusk:observe

Return a structured candidate list of every interactive widget on screen. Mirrors the Stagehand observe-once-act-many pattern: the agent observes once, then issues many `dusk:tap` / `dusk:type` / `dusk:drag` calls against the minted `qN` refs without re-observing between actions.

No LLM is invoked server-side. The handler walks the live Semantics tree, mints a re-resolvable `qN` handle for each interactive widget, and returns the candidate list as JSON. The agent reads the list and decides which refs to act on. This is what differentiates `dusk:observe` from a model-side `dusk:snap`: it returns a flat, role-filterable list optimised for LLM consumption rather than the full tree.

The CLI surface is mostly for debugging; the MCP descriptor is the primary surface for agent integrations.

---

## Table of contents

- [Synopsis](#synopsis)
- [Arguments](#arguments)
- [Returns](#returns)
- [Observe-once-act-many](#observe-once-act-many)
- [Examples](#examples)
- [See also](#see-also)

---

<a name="synopsis"></a>
## Synopsis

```
dart run fluttersdk_dusk dusk:observe [--intent=<hint>]
                                       [--roles=<csv>]
                                       [--limit=<n>]
                                       [--includeEnrichers=<true|false|full>]
```

`dusk:observe` requires a running Flutter session (`CommandBoot.connected`). It dials the VM Service URI, calls `ext.dusk.observe`, and prints the JSON candidate list to stdout.

---

<a name="arguments"></a>
## Arguments

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `intent` | string | unset | Free-form caller hint describing what the agent is looking for. Echoed back in the response; NOT used server-side for ranking or filtering. Useful for logging and for telemetry that wants to correlate observes with the agent's downstream intent. |
| `roles` | csv string | unset (every role) | Comma-separated role filter (e.g. `button,textbox,checkbox`). Omit for every role. Useful when the agent already knows it only cares about, say, form fields. |
| `limit` | int (string) | `50` | Maximum number of candidates to return. The handler ranks by hit-test depth and returns the first N. |
| `includeEnrichers` | enum string | `true` | One of `true` (default; subset of enricher fields), `false` (no enricher fields), `full` (every enricher field). Use `full` when the agent needs the complete className tokens, route metadata, and form-field shape; use `false` for the smallest payload. |

All four options pass through to the VM Service handler as string values (no client-side parsing). Empty strings are dropped so the handler sees absent rather than empty when the caller omits an option.

---

<a name="returns"></a>
## Returns

The VM Service handler returns a JSON envelope; the CLI dumps it to stdout via `jsonEncode`.

**Success envelope (illustrative; `includeEnrichers=true`, single candidate shown):**

```json
{
  "intent": "find the sign in button",
  "candidates": [
    {
      "ref": "q1",
      "role": "button",
      "label": "Sign in",
      "rect": [120, 400, 240, 48],
      "actions": ["tap"],
      "enrichers": {
        "windClassName": "bg-primary-600 text-white",
        "magicRoute": "/login"
      }
    }
  ],
  "totalMatches": 1
}
```

Every candidate ships with:

- A re-resolvable `qN` handle (Playwright Locator semantics: every action call re-walks the tree).
- The Semantics `role` (button, textbox, checkbox, link, etc.).
- The Semantics `label` (visible text or explicit a11y label).
- The widget `rect` as `[left, top, width, height]`.
- The available `actions` list (typically a subset of `tap`, `focus`, `type`, `scroll`).
- The `enrichers` map when `includeEnrichers` is `true` or `full`.

**Error envelope:**

The VM Service handler propagates errors as `ServiceExtensionResponse.error(extensionError, message)`. Common causes: no running app at the recorded URI, `DuskPlugin.install()` not wired.

---

<a name="observe-once-act-many"></a>
## Observe-once-act-many

The Stagehand pattern that gives `dusk:observe` its name:

1. **Observe once.** A single `dusk:observe` call enumerates the interactive surface of the current screen, mints `qN` handles, and returns them in one JSON payload.
2. **Act many.** The agent issues a sequence of `dusk:tap --ref=qN`, `dusk:type --ref=qN`, `dusk:set_checkbox --ref=qN`, etc. against the minted refs WITHOUT re-observing between actions. Each action re-resolves the `qN` handle against the live tree, so the refs survive intermediate rebuilds.

The "no server-side LLM" property is the second half of the pattern: Stagehand-the-product runs an LLM server-side to rank candidates by intent. `dusk:observe` returns the raw candidate list and lets the agent's own LLM rank, so no model context is consumed on the server, and the response is deterministic.

Re-observe only when:

- The agent navigated to a new screen (the handles minted on the previous screen become stale matches).
- The candidate set itself changes (e.g. a modal opens, a list grows, a tab switches).

For incremental state changes on the same screen (clicking a button that disables another button, typing into a field that reveals a new form section), re-resolution on every action call is sufficient; no second `dusk:observe` is needed.

---

<a name="examples"></a>
## Examples

### 1. Enumerate every interactive widget on the current screen

```bash
dart run fluttersdk_dusk dusk:observe
```

Returns up to 50 candidates with a subset of enricher fields. Useful as the first call after a navigation to discover what is on screen.

### 2. Filter to a single role

```bash
dart run fluttersdk_dusk dusk:observe --roles=button --limit=10
```

Limits the response to up to 10 button candidates. Useful when the agent already knows the next action is a tap.

### 3. Observe followed by act-many

```bash
dart run fluttersdk_dusk dusk:observe --roles=textbox,button > /tmp/observe.json
# agent reads /tmp/observe.json, decides to type into q1 then tap q2
dart run fluttersdk_dusk dusk:type --ref=q1 --text="user@example.com"
dart run fluttersdk_dusk dusk:tap --ref=q2
```

No re-observe between the two actions; both `qN` handles re-resolve against the live tree on each call.

---

<a name="see-also"></a>
## See also

- [dusk:snap](dusk-snap.md): the raw Semantics-tree YAML; richer than `dusk:observe` but with `eN` refs that go stale on rebuild.
- [dusk:find](dusk-find.md): mint a single `qN` handle from a known predicate; pair with `dusk:observe` when the agent already knows what to look for.
- [dusk:tap](dusk-tap.md), `dusk:type`, `dusk:drag`: the action commands that consume the `qN` refs minted by `dusk:observe`.
