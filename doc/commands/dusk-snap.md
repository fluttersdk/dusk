# dusk:snap

Capture the Semantics tree of the running Flutter app as YAML, tagging every interactive node with a `[ref=eN]` token. `dusk:snap` is the foundational read command: every action command (`dusk:tap`, `dusk:type`, `dusk:drag`, etc.) consumes one of its `eN` refs to locate the target widget.

The `eN` namespace is snapshot-frozen: every fresh `dusk:snap` clears the registry and mints new tokens. For long-lived handles that survive rebuilds, use `dusk:find` (which mints `qN` tokens) or `dusk:observe`.

---

## Table of contents

- [Synopsis](#synopsis)
- [Arguments](#arguments)
- [Returns](#returns)
- [Enricher fragments](#enricher-fragments)
- [Examples](#examples)
- [See also](#see-also)

---

<a name="synopsis"></a>
## Synopsis

```
dart run fluttersdk_dusk dusk:snap [--depth=<n>] [--includeEnrichers]
```

`dusk:snap` requires a running Flutter session (`CommandBoot.connected`). It dials the VM Service URI recorded in `~/.artisan/state.json`, calls `ext.dusk.snap`, and prints the snapshot YAML to stdout.

---

<a name="arguments"></a>
## Arguments

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--depth` | int (string-parsed) | unset (full tree) | Optional max tree depth. Caps the walk so very deep widget trees stay readable. Omit for the full tree. |
| `--includeEnrichers` | flag | `false` | Emit Magic and Wind enricher fragments under each ref entry. Default off matches the Playwright-style minimal snapshot; turn on when the agent needs the className tokens, route name, or form field metadata. |

The flag is parsed via `(ctx.input.option('includeEnrichers') as bool?) ?? false` and serialised as a string into the VM Service params map.

---

<a name="returns"></a>
## Returns

The VM Service handler returns a JSON envelope `{ "snapshot": "<yaml>" }`. The CLI unwraps the `snapshot` field and writes the raw YAML to stdout; when the field is missing the entire JSON object is dumped instead.

**Success envelope (illustrative):**

```yaml
[ref=e1] role=button label="Sign in" rect=(120,400,120,48) actions=[tap]
[ref=e2] role=textbox label="Email" rect=(20,200,335,56) actions=[tap, focus, type]
[ref=e3] role=text label="Welcome back" rect=(20,80,335,32)
```

When `--includeEnrichers` is set, each entry gains indented lines contributed by the registered enrichers (see [Enricher fragments](#enricher-fragments)).

**Error envelope:**

The VM Service handler propagates errors as `ServiceExtensionResponse.error(extensionError, message)`. The CLI surfaces the exception via `ArtisanContext.callExtension` and exits with a non-zero status. Typical failure modes:

- No running app at the recorded URI (the artisan dispatcher reports the dial failure before `dusk:snap` runs).
- `DuskPlugin.install()` not wired in `lib/main.dart` (run `dusk:install`).

---

<a name="enricher-fragments"></a>
## Enricher fragments

When `--includeEnrichers` is true, every `DuskSnapshotEnricher` registered via `DuskPlugin.registerEnricher` contributes indented lines under each ref. The two first-party enrichers:

- **MagicDuskIntegration** ships seven enrichers covering forms, routes, controllers, models, http, cache, and the policy gate.
- **WindDuskIntegration** ships the six-field `WindClassNameEnricher` (breakpoint, brightness, platform, states, bgColor, textColor).

Each enricher is synchronous and stateless; the `Element` reference is never retained across calls.

---

<a name="examples"></a>
## Examples

### 1. Minimal snapshot of the current screen

```bash
dart run fluttersdk_dusk dusk:snap
```

Expected output (illustrative; truncated):

```yaml
[ref=e1] role=text label="Monitors" rect=(20,80,200,32)
[ref=e2] role=button label="New monitor" rect=(20,140,335,48) actions=[tap]
[ref=e3] role=button label="Settings" rect=(355,140,40,48) actions=[tap]
```

### 2. Snapshot with depth cap

```bash
dart run fluttersdk_dusk dusk:snap --depth=4
```

Caps the walk at four levels of nesting. Useful for very dense screens (long lists, complex forms) where the full tree is noisy.

### 3. Snapshot with enrichers turned on

```bash
dart run fluttersdk_dusk dusk:snap --includeEnrichers
```

Expected output (illustrative):

```yaml
[ref=e2] role=button label="New monitor" rect=(20,140,335,48) actions=[tap]
  magicRoute: /monitors
  windClassName: bg-primary-600 dark:bg-primary-500 text-white
```

---

<a name="see-also"></a>
## See also

- [dusk:tap](dusk-tap.md): consume an `eN` token to synthesise a tap.
- [dusk:find](dusk-find.md): mint a long-lived `qN` handle that survives rebuilds.
- [dusk:observe](dusk-observe.md): structured candidate list when the agent needs more than the raw Semantics tree.
- [Plugins: Enricher authoring](../plugins/enricher-authoring.md): how to ship a custom enricher that contributes additional fragments.
