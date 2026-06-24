# dusk:find

Mint a re-resolvable `q<N>` handle backed by one or more predicates (text, semanticsLabel, key). Mirrors Playwright's Locator semantics: every action call against a `qN` handle re-walks the live Semantics tree on each invocation, so the handle survives intermediate widget rebuilds without going stale.

`qN` and `eN` token spaces are disjoint. A handle minted by `dusk:find` is always `qN`; a handle harvested from `dusk:snap` is always `eN`. The dispatcher distinguishes by prefix, but action commands accept either shape via `--ref=`.

---

## Table of contents

- [Synopsis](#synopsis)
- [Arguments](#arguments)
- [Returns](#returns)
- [Re-resolution semantics](#re-resolution-semantics)
- [Examples](#examples)
- [See also](#see-also)

---

<a name="synopsis"></a>
## Synopsis

```
dart run fluttersdk_dusk dusk:find [--text=<value>]
                                    [--contains=<substring>]
                                    [--semanticsLabel=<value>]
                                    [--key=<value>]
```

`dusk:find` requires a running Flutter session (`CommandBoot.connected`). It dials the VM Service URI, calls `ext.dusk.find` with the supplied predicates, and prints the minted handle envelope as pretty-printed JSON.

At least one of the four options must be non-empty; an empty params map returns exit code `1` with a CLI-side error before the VM Service call.

---

<a name="arguments"></a>
## Arguments

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--text` | string | unset | Exact match against the widget's visible text label (the Semantics `value` or rendered `Text` content). Most common predicate; mirrors Playwright's `getByText` with exact-match semantics. |
| `--contains` | string | unset | Substring match against the visible text label or Semantics label (case-sensitive). Use when the label is dynamic (counters, timestamps, plurals) and exact `--text` is too brittle. |
| `--semanticsLabel` | string | unset | Exact match against the widget's accessibility label (the explicit `Semantics(label: ...)` value set by the widget tree). Use when the visible text and the a11y label diverge. |
| `--key` | string | unset | Match the widget's `ValueKey` identifier (the `Key('signin-button')` form). Most precise; survives label and copy changes. |

The predicates compose AND: a `dusk:find --text=Sign --key=signin-button` call returns the widget that matches both. Use a single predicate when the agent only needs one axis.

The CLI guards an empty params map (`Provide at least one of --text / --contains / --semanticsLabel / --key.`) so the VM Service handler never sees a zero-predicate call.

---

<a name="returns"></a>
## Returns

`dusk:find` returns an integer exit code via `Future<int>`:

| Exit code | Meaning |
|-----------|---------|
| `0` | Handle minted (or re-used; the registry is content-addressed). The handler emits the JSON envelope below. |
| `1` | No predicate supplied. The CLI guard fires before the VM Service call. |
| non-zero | VM Service handler returned `ServiceExtensionResponse.error`. Typical cause: the predicate matched zero widgets (no matches surfaces as a structured failure so the agent knows to broaden the predicate). |

**Success envelope (illustrative):**

Single match:

```json
{
  "ref": "q1",
  "matched": true,
  "matchCount": 1
}
```

Multi-match (ambiguous predicate):

```json
{
  "ref": "q1",
  "matched": true,
  "matchCount": 2,
  "diagnostic": "label 'Password' matched 2 nodes; refine with --text/--contains or use a q-handle"
}
```

`matchCount > 1` means the predicate is ambiguous: the handle still resolves to the FIRST match (backward-compatible), but the agent should narrow with an additional predicate before acting. Common disambiguation strategies:

- Add `--key=<widget-key>` when the widget carries a `ValueKey`.
- Add `--text=<visible-label>` when the accessibility label and the visible text differ.
- Use `--contains=<unique-substring>` when only part of the label is unique.

**Error envelope:**

The VM Service handler propagates errors as `ServiceExtensionResponse.error(extensionError, message)`. The CLI surfaces them via `ArtisanContext.callExtension` and exits non-zero. Common messages include `No widget matched predicates: {}`.

---

<a name="re-resolution-semantics"></a>
## Re-resolution semantics

A `qN` handle stores the predicate map, not the matched widget. Every action call (`dusk:tap --ref=q1`, `dusk:type --ref=q1`, etc.) re-executes the query against the live Semantics tree. Three consequences:

1. **Widget rebuilds don't invalidate the handle.** A `ListView` swap, a navigation transition, or a state-driven rebuild all leave the handle valid as long as the predicates still match something.
2. **The query is re-run on every action.** Cheap (a Semantics walk on each call), but emergent if the predicate is broad: prefer `--key` over `--text` for hot paths.
3. **`dusk:find` itself is idempotent in the registry.** Calling it twice with the same predicate map returns the same `qN`; the registry is content-addressed.

`eN` handles minted by `dusk:snap` work the opposite way: they freeze the matched widget at snap time and go stale on the next rebuild. Use `eN` for one-shot reads, `qN` for any sequence that spans more than one frame.

---

<a name="examples"></a>
## Examples

### 1. Mint a handle by visible text

```bash
dart run fluttersdk_dusk dusk:find --text="Sign in"
```

Expected output (illustrative):

```json
{
  "ref": "q1",
  "matchCount": 1,
  "rect": [120, 400, 240, 48],
  "role": "button",
  "label": "Sign in"
}
```

Reuse `q1` across subsequent action calls:

```bash
dart run fluttersdk_dusk dusk:tap --ref=q1
```

### 2. Mint a handle by accessibility label

```bash
dart run fluttersdk_dusk dusk:find --semanticsLabel="Submit form"
```

Use when the rendered button text is an icon and the only stable predicate is the a11y label.

### 3. Mint a handle by widget key (most precise)

```bash
dart run fluttersdk_dusk dusk:find --key="signin-submit"
```

Survives copy changes and a11y-label changes. Pair with a widget-side `Key('signin-submit')` declaration.

### 4. Mint a handle by substring (dynamic label)

```bash
dart run fluttersdk_dusk dusk:find --contains="pushed the button"
```

Useful when the visible label is dynamic, e.g. `"You have pushed the button 5 times:"` (counter changes per tap). `--text` would only match the exact string at the moment of capture; `--contains` survives the counter advancing.

### 5. Compose two predicates to disambiguate

```bash
dart run fluttersdk_dusk dusk:find --text="Save" --key="monitor-form-save"
```

The two predicates AND together; useful when the screen has multiple "Save" buttons but only one with the canonical key.

---

<a name="ref-staleness"></a>
## e-ref staleness and when to prefer q-handles

`e<N>` tokens minted by `dusk:snap` are frozen to the Semantics node that was
live at snap time. They become defunct the moment the node leaves the tree, which
happens on any route push, list rebuild, or conditional widget swap. The
`RefRegistry` that backs `e<N>` tokens does NOT re-resolve; calling an action
with a stale `e<N>` returns a `defunct (element no longer mounted)` failure.

`q<N>` handles minted by `dusk:find` store the predicate set instead of the
node, and re-walk the live tree on every action call. They survive navigations,
hot-reloads, and full widget rebuilds as long as the predicate still matches
something in the tree.

**When to reach for `dusk:find` / `q<N>` instead of using the `e<N>` from a
snap:**

- The page might rebuild between snap and action (e.g. Settings pages with
  dynamic sections, lists driven by async data).
- The agent will retry an action (gate failure, transient loading state).
- The flow spans more than one navigation hop; an `e<N>` from the previous
  screen is always stale after the route change.
- The agent holds a ref across a hot-reload.

The `RefRegistry` is intentionally frozen for `e<N>` (it is a FIFO token store,
not a live observer). There is no mechanism to refresh a stale `e<N>` in place;
the design intent is that `dusk:snap` re-mints the ref after every page change.
For rebuild-prone pages, prefer `dusk:find` / `dusk:observe` from the start.

---

<a name="semantics-label-over-match"></a>
## Avoiding `--semanticsLabel` over-match

`--semanticsLabel` performs an exact case-sensitive match against
`SemanticsNode.label` and returns the FIRST node in tree order. When two or
more nodes carry the same label (e.g. two `TextField` widgets both labelled
`Password` on a sign-up form, or a list of repeated row controls), the handle
resolves to the first node in tree order, which may not be the intended target.

The `matchCount` field in the response tells the agent how many nodes matched.
A `diagnostic` key appears when `matchCount > 1`, e.g.:

```
label 'Password' matched 2 nodes; refine with --text/--contains or use a q-handle
```

**Disambiguation strategies (most to least precise):**

1. Add `--key=<widget-key>` when the widget carries a `ValueKey`. This is the
   most precise predicate and survives label changes.
2. Combine `--semanticsLabel=Password --text=Confirm` when the second node has
   distinct visible text (some widgets expose both a label and a text value).
3. Use `--contains=<unique-substring>` when only part of the label is unique
   across the matching nodes.
4. Use `dusk:observe` with a narrow `intent` and inspect the returned candidate
   list; each candidate includes role, bounds, and enricher fields that let the
   agent identify the correct target before minting the handle.

---

<a name="see-also"></a>
## See also

- [dusk:snap](dusk-snap.md): produce `eN` refs for one-shot reads.
- [dusk:tap](dusk-tap.md): consume the `qN` ref to synthesise a tap.
- [dusk:observe](dusk-observe.md): structured candidate list of every interactive widget; useful when the agent doesn't know which predicate to query.
