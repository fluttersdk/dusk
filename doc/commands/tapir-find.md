# tapir:find

Mint a re-resolvable `q<N>` handle backed by one or more predicates (text, semanticsLabel, key).

The command mirrors Playwright's Locator semantics: every action call against a `qN` handle re-walks the live Semantics tree on each invocation, so the handle survives intermediate widget rebuilds without going stale.

`qN` and `eN` token spaces are disjoint. A handle minted by `tapir:find` is always `qN`; a handle harvested from `tapir:snap` is always `eN`. The dispatcher distinguishes by prefix, but action commands accept either shape via `--ref=`.

- [Synopsis](#synopsis)
- [Arguments](#arguments)
- [Returns](#returns)
- [Re-resolution semantics](#re-resolution-semantics)
- [Examples](#examples)
- [e-ref staleness and when to prefer q-handles](#ref-staleness)
- [Avoiding `--semanticsLabel` over-match](#semantics-label-over-match)
- [Related Documentation](#related-documentation)

<a name="synopsis"></a>
## Synopsis

```
dart run tapir tapir:find [--text=<value>]
                                    [--contains=<substring>]
                                    [--semanticsLabel=<value>]
                                    [--key=<value>]
                                    [--within=<eN>]
```

`tapir:find` requires a running Flutter session (`CommandBoot.connected`). It dials the VM Service URI, calls `ext.tapir.find` with the supplied predicates, and prints the minted handle envelope as pretty-printed JSON.

At least one of the four predicate options must be non-empty (`--within` is a scope, not a predicate); an empty params map returns exit code `1` with a CLI-side error before the VM Service call.

---

<a name="arguments"></a>
## Arguments

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--text` | string | unset | Exact match against an accessibility label first, then against the `Text.data` of a rendered `Text` as a fallback. Most common predicate; mirrors Playwright's `getByText` with exact-match semantics. |
| `--contains` | string | unset | Substring match against the visible text label or Semantics label (case-sensitive). Use when the label is dynamic (counters, timestamps, plurals) and exact `--text` is too brittle. |
| `--semanticsLabel` | string | unset | Exact match against the widget's accessibility label (the explicit `Semantics(label: ...)` value set by the widget tree). Use when the visible text and the a11y label diverge. |
| `--key` | string | unset | Match the widget's `ValueKey` identifier (the `Key('signin-button')` form). Most precise; survives label and copy changes. |
| `--within` | string (`e<N>`) | unset (whole tree) | Evaluate the predicates inside one subtree. The scope becomes part of the minted `q<N>` handle, so it survives into every re-resolve; once the scope stops resolving the handle reports `matched: false` with a diagnostic naming it. Take the ref from a `tapir:snap` output: a ref minted by `tapir:wait` carries no semantics node, so it cannot bound a `--semanticsLabel` lookup and that combination is refused with a diagnostic rather than widened to the whole tree. |

The predicates compose AND: a `tapir:find --text=Sign --key=signin-button` call returns the widget that matches both. Use a single predicate when the agent only needs one axis.

The CLI guards an empty params map (`Provide at least one of --text / --contains / --semanticsLabel / --key.`) so the VM Service handler never sees a zero-predicate call.

---

<a name="returns"></a>
## Returns

`tapir:find` returns an integer exit code via `Future<int>`:

| Exit code | Meaning |
|-----------|---------|
| `0` | The call completed. A match mints a handle and emits the JSON envelope below; no match emits `{"ref": null, "matched": false}` (check `matched` before using `ref`). |
| `1` | No predicate supplied. The CLI guard fires before the VM Service call. |
| non-zero | VM Service handler returned `ServiceExtensionResponse.error`, or the call could not reach the app. |

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
  "diagnostic": "label 'Password' matched 2 nodes; refine with --key, --text, or --contains"
}
```

`matchCount > 1` means the predicate is ambiguous: the handle still resolves to the FIRST match (backward-compatible), but the agent should narrow with an additional predicate before acting. Common disambiguation strategies:

- Add `--key=<widget-key>` when the widget carries a `ValueKey`.
- Add `--text=<visible-label>` when the accessibility label and the visible text differ.
- Use `--contains=<unique-substring>` when only part of the label is unique.

**Error envelope:**

The VM Service handler propagates errors as `ServiceExtensionResponse.error(extensionError, message)`. The CLI surfaces them via `DowelContext.callExtension` and exits non-zero.

---

<a name="re-resolution-semantics"></a>
## Re-resolution semantics

A `qN` handle stores the predicate map, not the matched widget. Every action call (`tapir:tap --ref=q1`, `tapir:type --ref=q1`, etc.) re-executes the query against the live Semantics tree. Three consequences:

1. **Widget rebuilds don't invalidate the handle.** A `ListView` swap, a navigation transition, or a state-driven rebuild all leave the handle valid as long as the predicates still match something.
2. **The query is re-run on every action.** Cheap (a Semantics walk on each call), but emergent if the predicate is broad: prefer `--key` over `--text` for hot paths.
3. **`tapir:find` itself is idempotent in the registry.** Calling it twice with the same predicate map returns the same `qN`; the registry is content-addressed.

`eN` handles minted by `tapir:snap` work the opposite way: they freeze the matched widget at snap time and go stale on the next rebuild. Use `eN` for one-shot reads, `qN` for any sequence that spans more than one frame.

---

<a name="examples"></a>
## Examples

### 1. Mint a handle by visible text

```bash
dart run tapir tapir:find --text="Sign in"
```

Expected output (illustrative):

```json
{
  "ref": "q1",
  "matched": true,
  "matchCount": 1
}
```

Reuse `q1` across subsequent action calls:

```bash
dart run tapir tapir:tap --ref=q1
```

### 2. Mint a handle by accessibility label

```bash
dart run tapir tapir:find --semanticsLabel="Submit form"
```

Use when the rendered button text is an icon and the only stable predicate is the a11y label.

### 3. Mint a handle by widget key (most precise)

```bash
dart run tapir tapir:find --key="signin-submit"
```

Survives copy changes and a11y-label changes. Pair with a widget-side `Key('signin-submit')` declaration.

### 4. Mint a handle by substring (dynamic label)

```bash
dart run tapir tapir:find --contains="pushed the button"
```

Useful when the visible label is dynamic, e.g. `"You have pushed the button 5 times:"` (counter changes per tap). `--text` would only match the exact string at the moment of capture; `--contains` survives the counter advancing.

### 5. Compose two predicates to disambiguate

```bash
dart run tapir tapir:find --text="Save" --key="monitor-form-save"
```

The two predicates AND together; useful when the screen has multiple "Save" buttons but only one with the canonical key.

---

<a name="ref-staleness"></a>
## e-ref staleness and when to prefer q-handles

`e<N>` tokens minted by `tapir:snap` are frozen to the Semantics node that was
live at snap time. They become defunct the moment the node leaves the tree, which
happens on any route push, list rebuild, or conditional widget swap. The
`RefRegistry` that backs `e<N>` tokens does NOT re-resolve; calling an action
with a stale `e<N>` returns a `defunct (element no longer mounted)` failure.

`q<N>` handles minted by `tapir:find` store the predicate set instead of the
node, and re-walk the live tree on every action call. They survive navigations,
hot-reloads, and full widget rebuilds as long as the predicate still matches
something in the tree.

**When to reach for `tapir:find` / `q<N>` instead of using the `e<N>` from a
snap:**

- The page might rebuild between snap and action (e.g. Settings pages with
  dynamic sections, lists driven by async data).
- The agent will retry an action (gate failure, transient loading state).
- The flow spans more than one navigation hop; an `e<N>` from the previous
  screen is always stale after the route change.
- The agent holds a ref across a hot-reload.

The `RefRegistry` is intentionally frozen for `e<N>` (it is a FIFO token store,
not a live observer). There is no mechanism to refresh a stale `e<N>` in place;
the design intent is that `tapir:snap` re-mints the ref after every page change.
For rebuild-prone pages, prefer `tapir:find` / `tapir:observe` from the start.

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
label 'Password' matched 2 nodes; refine with --key, --text, or --contains
```

**Disambiguation strategies (most to least precise):**

1. Add `--key=<widget-key>` when the widget carries a `ValueKey`. This is the
   most precise predicate and survives label changes.
2. Combine `--semanticsLabel=Password --text=Confirm` when the second node has
   distinct visible text (some widgets expose both a label and a text value).
3. Use `--contains=<unique-substring>` when only part of the label is unique
   across the matching nodes.
4. Use `tapir:observe` with a narrow `intent` and inspect the returned candidate
   list; each candidate includes role, bounds, and enricher fields that let the
   agent identify the correct target before minting the handle.

**Interactive nodes win a mixed collision.** When a label spans one interactive
node (a button, switch, or text field exposing `SemanticsAction.tap`) and one or
more inert nodes (a `Text` heading or a settings label that repeats the control's
copy), the handle resolves to the first interactive node rather than the first
node in tree order. A visible label naming an adjacent control, or a heading
repeating a button's text, otherwise sits first in tree order and the tap would
land on the inert label. When every match is interactive or every match is inert,
the handle falls back to the first node in tree order. `matchCount` and
`diagnostic` still report the full collision either way, so an agent that needs a
specific one of several interactive matches should still refine the predicate.

Each `qN` gesture then dispatches at the resolved node's own on-screen rect (the
`RenderBox` bounds of the widget that contributes the node), so off-centre
controls (a sidebar item, a submit button below the fold) receive the tap at
their real position rather than the viewport centre.

---

<a name="related-documentation"></a>
## Related Documentation

- [tapir:snap](tapir-snap.md): produce `eN` refs for one-shot reads.
- [tapir:tap](tapir-tap.md): consume the `qN` ref to synthesise a tap.
- [tapir:observe](tapir-observe.md): structured candidate list of every interactive widget; useful when the agent doesn't know which predicate to query.
