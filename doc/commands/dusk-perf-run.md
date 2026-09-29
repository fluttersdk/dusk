# dusk:perf_run

Run a perf scenario several times from a clean start and write one file per scenario: medians of counts per painted frame, a spread block, the insights of the median repeat, and every repeat's full report. The file is what `dusk:perf_compare` reads.

---

## Table of contents

- [Synopsis](#synopsis)
- [The scenario file](#the-scenario-file)
- [Fragments, parameters and variants](#fragments-parameters-and-variants)
- [What one run does](#what-one-run-does)
- [The run file](#the-run-file)
- [Refusals and exit codes](#refusals-and-exit-codes)
- [The semantics pass](#the-semantics-pass)
- [See also](#see-also)

---

<a name="synopsis"></a>
## Synopsis

```
dart run fluttersdk_dusk dusk:perf_run <scenario.yaml> [--variant=<key>] [--label=<name>]
    [--out=<dir>] [--repeat=<n>] [--platform=chrome|android|ios] [--timing]
    [--against=<baseline.yaml>] [--semantics-pass] [--json]
```

`dusk:perf_run` requires a running session (`CommandBoot.connected`). On Chrome it also needs the CDP port `artisan start --cdp-port` records: every session is brought to front first, and viewport, resize and wheel go through DevTools.

| Flag | Default | Meaning |
|------|---------|---------|
| `<scenario.yaml>` / `--scenario` | required | The scenario file. |
| `--variant` | none | The [variant](#variants) to run. Required when the file declares `variants` (the error lists the keys), refused when it does not. It applies to `--against` too, so both files have to declare it. |
| `--label` | `run` | Names the run in the file name. `[a-z0-9_-]` only; anything else is rejected. |
| `--out` | `build/perf` | Directory the run files go to. |
| `--repeat` | the scenario's `repeat` | Repeats per series. |
| `--platform` | read from the session | `chrome`, `android` or `ios`. Read from the state file's device when omitted (`chrome`/`web-server`, `emulator-*`, a simulator UDID). |
| `--timing` | `false` | Also run timing-mode repeats, interleaved with the attribution ones. Their medians are the only milliseconds `dusk:perf_compare` gates on. |
| `--against` | none | A baseline scenario run inside the same rounds, the order alternating, written to its own file. Both files carry `interleavedWith`. |
| `--semantics-pass` | `false` | Also measure with dusk's semantics handle released. See [the semantics pass](#the-semantics-pass). |
| `--json` | `false` | Print the run file minus every `repeats[]` (insights cut to six), plus `path`. |

---

<a name="the-scenario-file"></a>
## The scenario file

```yaml
name: monitors-list-scroll-1440   # [a-z0-9_-]: becomes the file name
viewport: {width: 1440, height: 900}   # Chrome only; the device's own elsewhere
platforms: [chrome, android]      # default: chrome, android, ios
setup:                            # runs before EVERY repeat
  - hot_restart
  - navigate: /monitors
  - wait_for_text: Monitors       # or {text: Monitors, timeout_ms: 20000}
  - wait_for_network_idle
  - tap: {target: {text: perf-monitor-0000}}   # a gesture, unmeasured
steps:                            # the timed window
  - wheel: {target: {key: monitor-list}, dy: 1200}
    only: [chrome]
  - drag: {target: {text: Monitors}, dy: -600}
    only: [android, ios]
  - tap: {target: {role: button, name: Add monitor}}
  - wait: 400
repeat: 3
thresholds: {warn: 10, error: 25}  # percent, per metric
```

Steps: `tap`, `fill` (`text`), `type` (`text`), `press_key` (`key`), `scroll` (`dx`/`dy`), `wheel` (`dx`/`dy`, and `ticks`: how many events of that size to send one frame apart at the one resolved point, 1 to 200, default 1; a real wheel is many small ticks, and one large event jumps a list in a single frame), `drag` (`dx`/`dy` from the target's center), `navigate` (a route), `resize` (`width`/`height`) and `wait` (ms). A step may carry `only: [...]`.

Setup takes `hot_restart`, `navigate`, `wait_for_text` and `wait_for_network_idle`, and also the gestures `tap`, `fill`, `type`, `press_key`, `wheel`, `drag` and `wait`, written and validated exactly as steps are (targets, `only`, the Chrome-only rule). They run before `perf_begin`, so the path to the measured screen is not measured: navigate to `/monitors`, tap the row `perf-monitor-0000`, then time only the tab switches, rather than baking a seeded id into `navigate: /monitors/<uuid>`. `only` is refused on the four setup verbs, which run everywhere.

A target is resolved on the live screen in every repeat, never written as a ref: an `e12` from one run is stale after the next navigate, and the file is rejected if it names one. A target only `wait` steps precede (on the platform the run is on) is resolved before `perf_begin`, a `wheel`'s hover point with it, so the lookup costs the window nothing. Every other target could be created or moved by an earlier step (the `English` option in the overlay a tap opens), so it is resolved inside the window, right before its step, and the run file records that cost. A target not there yet is looked up again every 100 ms for up to 3 s before the run fails with "matched nothing". Exactly one of:

| Target | Resolves through |
|---|---|
| `{text: ...}` | `ext.dusk.find --text`; with `index > 0`, the `index`-th of `ext.dusk.find_by_text` |
| `{label: ...}` | `ext.dusk.find --semanticsLabel`; no `index` (nothing can serve one: name the control as `{role, name, index}` instead) |
| `{role: ..., name: ...}` | the `index`-th `ext.dusk.observe` candidate with that role whose label is `name`: what `dusk:snap` prints as `- button "Add monitor"`. Roles are snap's: `button`, `textbox`, `checkbox`, `link`, `heading`, `image` |
| `{key: ...}` | `ext.dusk.find --key`; a key names one widget, so no `index` |

`wheel` is a CDP mouseWheel, because `dusk:scroll` moves the parent scrollable programmatically and some screens only respond to the wheel. `wheel` and `resize` are Chrome only, and the file is rejected when one could run elsewhere: on android and ios scroll with a `drag`. Every problem in the file is reported at once.

---

<a name="fragments-parameters-and-variants"></a>
## Fragments, parameters and variants

A scenario file is loaded through `loadPerfScenarios` (`lib/src/perf/scenario_loader.dart`), which adds three things to the grammar above: setup fragments, `${...}` interpolation with secrets, and variants. `PerfScenario.parse` reads the same grammar from a string, except that it refuses an `include` (a string has no directory to resolve one against) and `variants` (they yield several scenarios).

### Fragments

A setup entry `- include: <path>` flattens a fragment file into `setup` in place. The path is relative to the file that holds the entry.

```yaml
# scenarios/monitors-list.yaml
setup:
  - hot_restart
  - include: fragments/login.yaml
    with: {email: "${env.PERF_EMAIL}", password: "${env.PERF_PASSWORD}"}
    when: {text: Sign in, unless_text: Monitors, timeout_ms: 60000}
  - navigate: /monitors
```

```yaml
# scenarios/fragments/login.yaml
params:
  email: {}                         # required: no default
  password: {secret: true}
  submit: {default: Sign in}
when: {text: Sign in}               # used when the include names no `when`
steps:                              # the setup grammar, nested includes too
  - fill: {target: {label: Email}, text: "${email}"}
  - fill: {target: {label: Password}, text: "${password}"}
  - tap: {target: {role: button, name: "${submit}"}}
```

A fragment takes `params`, `when` and `steps` and nothing else. Every param is required unless it has a `default`; a `with:` key the fragment does not declare, a missing required param, an include cycle (a includes b includes a) and includes nested deeper than 8 are each a problem. An include is a setup entry only: the measured `steps` are written out, so the file shows everything the window times. A problem inside a fragment names it and the entry, `fragments/login.yaml steps[1].fill.text`, and so does every flattened entry at run time.

`when: {text, unless_text, timeout_ms}` guards the whole fragment; the include's own `when` replaces the fragment's. The runner polls the screen for up to `timeout_ms` (default 60000): `text` on screen runs the fragment, `unless_text` on screen skips it (and wins when both are there). On timeout the fragment is skipped when there is no `unless_text`, and the run fails when there is one, since the screen showed neither state.

At run time the guard is a poll of `ext.dusk.find --text` every 250 ms, `unless_text` first, then `text`, up to `timeout_ms`. Each guard is decided once per pass over the setup (so once per repeat in `dusk:perf_run`), at the first of its steps that runs on the platform, and the decision covers every step the include flattened. A guard nested in another is decided only after the outer one decided to run, so a skipped outer fragment never polls for its inner one. The timeout failure names both texts and the include (`list-scroll setup[1] (when): neither "Sign in" nor "Monitors" showed within 60000 ms, ...`) and ends with the same `Diagnostics:` line as any setup failure.

### Interpolation

Every scalar value in a scenario or fragment file (never a key) is interpolated once, in its own file:

| Written | Reads |
|---|---|
| `${name}` | the fragment's param `name` |
| `${env.NAME}` | the environment variable `NAME` |
| `$$` | one literal `$` |

A `with:` value is resolved in the including file and passed on as it is, never scanned again: `Pa$$w0rd` arrives as `Pa$w0rd` however many includes it goes through, and an environment value `a${b}` arrives as `a${b}`. A `default` reads the environment only. An undefined name is a problem that names the file and the path.

### Secrets

A value any part of which came from `${env.*}` or from a param declared `secret: true` is a secret, and stays one through every `with:`. It may only be the `text` of a `fill` or `type`; anywhere else (a route, a `wait_for_text`, a target, a `when`) the file is refused with "a secret may only be typed". The run file writes the text of a secret step as `***`, and a problem never prints a secret, raw or JSON-encoded. Once the files have loaded, `dusk:perf_run` masks every secret, raw or JSON-encoded, in everything it prints (errors, diagnostics, the success lines and the `--json` envelope) and in every string of the run files it writes, such as a `semanticsPassReason` that quotes a failed fill.

### Variants

`variants` turns one file into one scenario per key, named `<name>-<key>`, so twin files that differ in the viewport become one:

```yaml
name: monitors-list-scroll
platforms: [chrome]
viewport: {width: 1440, height: 900}
steps:
  - wheel: {target: {key: monitor-list}, dy: 1200}
variants:
  1440: {}
  390:
    viewport: {width: 390, height: 844}
    platforms: [chrome, android, ios]
    steps:
      - drag: {target: {text: Monitors}, dy: -600}
```

A variant may replace `viewport`, `platforms`, `repeat` and `steps`; each key it names replaces the base's whole value (a variant's `steps` replaces the whole list). A key is read as text (YAML reads `1440` as a number) and must use `[a-z0-9_-]`. Each resulting scenario is validated on its own, so a step's `only:` is checked against that variant's `platforms`, and a problem in one names it (`monitors-list-scroll-390: variants.390.steps[0]...`).

`dusk:perf_run` runs one variant per call: `--variant=390` runs `monitors-list-scroll-390` and writes `<out>/monitors-list-scroll-390-<label>.json`, whose top-level `variant` says which key it was. A file with variants run without `--variant`, a key it does not declare, and `--variant` on a file without variants each exit 1 before the app is touched.

---

<a name="what-one-run-does"></a>
## What one run does

Each repeat is one unit: the scenario's setup, `Page.bringToFront` on Chrome, the targets that can be resolved early, `perf_begin`, the steps, a 300 ms settle (Flutter delivers frame timings in batches of about 100 ms), then `perf_end` with `full=true`. Setup runs before every repeat so each starts from the same state: the controllers are singletons, and a search term left by one repeat would filter every later one.

A setup `navigate` has to land and stay. First the app has to be routable: the runner reads `ext.dusk.get_routes` every 100 ms, for up to 10 s, until its `uri` names a mounted Router. `ext.dusk.boot_id` answers as soon as `DuskPlugin.install()` has run, and a host that installs dusk before its own boot (magic_devtools' documented order) is still booting or showing a loading screen then; a navigate sent before the Router exists answers `navigated: false` even when the route lands a moment later. No Router within 10 s fails the run, and so does a `get_routes` with no `uri` at all, which means the app runs an older dusk than the CLI: relaunch it.

An answer of `navigated: false` is then held against the Router for up to 3 s: `ext.dusk.navigate` reads the Router two frames after dispatching, and a Router that has only just mounted is still applying its first location then (measured after a web hot restart: `false` as the Router mounted, `true` 300 ms later). A route whose path is reached exactly in that time counts (query ignored; a page under it does not, since a web hot restart keeps the URL and an app still on `/monitors/7` would otherwise pass for a dropped navigate to `/monitors`), the payload the diagnostics quote carries `landedLate: true`, and the unit's entry in `repeats[]` carries `setupLandedLate: true`. A route that never lands (the router dropped it) or lands elsewhere (a redirect) fails the run with the payload. The route is never dispatched twice: a second push would stack it.

Once it has landed, the runner reads `get_routes`'s `uri`, waits for network idle, and reads it again; a route whose path moved in between (a first fetch answering 401 redirects to the login screen) fails the run naming both. The two reads compare paths, so a page that normalises its query after the first fetch (`/monitors` to `/monitors?page=1`) has not moved.

Every setup failure other than a restart's ends with a `Diagnostics:` line: the Router's `uri` as `ext.dusk.get_routes` answers it (`route none (no Router mounted)` when there is none, plus the page name when the Navigator's top page has one), the last setup navigate's payload, and the three newest `ext.dusk.exceptions` entries. A diagnostic call that fails is named in its place.

`hot_restart` is a hot restart on a debug build. A profile build cannot hot restart, so there it is a full relaunch through `artisan restart`, carrying the session's flags; `env.restartMode` says which (`none` when the setup has no restart). Either way the runner reads `ext.dusk.boot_id` first and waits, up to 90 s after a hot restart, until it answers with a different id, which `DuskPlugin.install()` mints on every run of `main()` and registers last. Not a new isolate: on Flutter web DWDS keeps isolate `"1"` across a hot restart, and on the VM the old isolate answers until the new one replaces it. The errors the app answers while it restarts (DWDS's -32603 for an extension not registered yet) are waited out, and the last one is named if the 90 s run out. An app that does not answer `ext.dusk.boot_id` at all runs an older dusk: relaunch it.

With `--timing`, `--against` or both, each round runs every unit once and the next round reverses the order, so drift in the app (a warming cache, a growing heap) lands on both sides alike.

Actions are called with `includeSnapshot: false`: a snapshot per step would build the semantics tree inside the window and cost frames the scenario did not ask for.

---

<a name="the-run-file"></a>
## The run file

`<out>/<scenario>-<label>.json`:

```json
{
  "scenario": {"name": "monitors-list-scroll-1440", "...": "the parsed scenario"},
  "label": "before",
  "variant": "1440",
  "env": {"platform": "macOS", "isWeb": true, "buildMode": "debug",
          "semanticsEnabled": true, "target": "chrome", "device": "chrome",
          "emulator": false, "restartMode": "hot_restart",
          "host": {"os": "macos", "uname": "Darwin 25.0.0 arm64",
                   "cpu": "Apple M3 Pro", "cores": 12},
          "renderer": "unknown"},
  "summary": {
    "repeats": 3, "refused": 0,
    "frames": {"count": 42, "painted": 42, "dropped": 0, "overBudget": 1},
    "perFrame": {"blocks.MonitorRow": 2.2, "wind.wDivBuilds": 31.4},
    "ms": {"buildMs.p50": 4.1, "buildMs.p90": 8.3, "rasterMs.p50": 3.0},
    "spread": {"perFrame": {"blocks.MonitorRow": {"min": 2.0, "max": 3.0, "rangePct": 45.5}},
               "ms": {"...": {}}},
    "timing": {"repeats": 3, "refused": 0, "ms": {"...": 0}, "spread": {}}
  },
  "insights": [{"id": "I1", "severity": "warn", "title": "...", "...": "..."}],
  "repeats": [{"series": "attribution", "index": 0, "...": "the full perf_end report",
               "resolves": [{"step": 0, "verb": "tap", "phase": "beforeBegin", "resolveMs": 12.4},
                            {"step": 2, "verb": "tap", "phase": "inWindow", "resolveMs": 38.1}]}]
}
```

- `perFrame` flattens every count to a name: `blocks.<widget>`, `<wind|magic>.<counter>`, `<wind|magic>.<counter>.<row>`. Gauges such as `wind.cacheSize` are left out. A metric a repeat lacks counts as zero there.
- `ms` (attribution) is indicative: build profiling inflates every duration. Compare `summary.timing.ms` instead.
- `insights` come from the repeat whose total per-frame count is the median.
- `variant` is the `--variant` the run used, present only when it used one.
- `repeats[].resolves` lists each targeted step's lookup: `beforeBegin` outside the window, `inWindow` inside it, where `resolveMs` (retries included) is time the session measured. The semantics pass resolves nothing, so its repeats carry an empty list.
- `env.host` comes from the host: `uname` and the CPU. `env.renderer` is the app's own answer (`canvaskit` or `skwasm` on web, through `rendererReader`); only when the app answers `unknown` does the runner fall back to the Impeller backend line of the artisan run log (`impeller-vulkan`), else `unknown`.

---

<a name="refusals-and-exit-codes"></a>
## Refusals and exit codes

A refused repeat (the engine drew one frame or none, see `dusk:perf_end`) is kept in `repeats[]` with `refused: true` and left out of every median; `summary.refused` counts them.

| Exit code | Meaning |
|-----------|---------|
| `0` | At least one attribution repeat was measured. |
| `1` | A bad input (scenario, label, repeat, platform), a setup or step that could not run (the session is still closed, so the profiling flags are restored), or every attribution repeat refused. The file is still written in the last case. |

---

<a name="the-semantics-pass"></a>
## The semantics pass

dusk keeps a semantics handle for the whole process, so every dusk-driven frame also builds the semantics tree. `--semantics-pass` measures the app without it, as a separate `semanticsOff` series:

1. The first attribution round records where each `tap`, `drag` and `wheel` dispatched (`reportPoint`).
2. Each semantics repeat runs the setup, opens the session, calls `ext.dusk.semantics_hold action=release`, replays the steps by those coordinates (`ext.dusk.tap {x, y}`, `ext.dusk.drag {x, y, toX, toY}`, CDP for the wheel), closes the session with `perf_end`, and only then calls `action=acquire`. The acquire's frame rebuilds the whole tree, so it stays out of the window, and the report's `env.semanticsEnabled` describes the window rather than the re-acquired handle. The handle is never released outside that window, and the acquire runs even when a step or `perf_end` fails.

The file gains `semanticsPass: "measured"` and `semanticsOff: {summary, repeats}`. `fill`, `type` and `scroll` act through a resolved widget, so a scenario with one of them records `semanticsPass: "unsupported"` with a `semanticsPassReason` instead of failing the run; so does a replay that fails. See [the semantics hold](../reference/semantics-hold.md).

A release does not always turn the tree off. The framework builds it while any handle is held, and the platform holds its own while `platformDispatcher.semanticsEnabled` is true. When the release answers `semanticsEnabled: true` the pass stops there: it closes that window, re-acquires, records `semanticsPass: "unsupported"` and writes no `semanticsOff` series, since what it would measure is the attribution series again. The `semanticsPassReason` names the platform and what holds semantics on:

| Where | What holds it | `semanticsPassReason` |
|---|---|---|
| chrome | The web engine turns semantics on at the first semantics tree a real app sends (dusk's first snapshot sends one) and never turns it off. | `on chrome, releasing dusk's semantics handle left semantics on: the platform holds it: Flutter web's engine ...` |
| android, ios | An accessibility service (TalkBack, VoiceOver, another assistive service). | `on android, ... an accessibility service ... is on; turn it off and rerun.` |
| any | A `SemanticsHandle` the app or a package took with `ensureSemantics`. | `on <platform>, ... another semantics handle in the app holds it ...` |

On chrome, then, the pass reports `unsupported` for any app dusk has snapshotted; measure the semantics-off figure on a native target.

---

<a name="see-also"></a>
## See also

- [dusk:perf_compare](dusk-perf-compare.md): judge one run file against another.
- [dusk:perf_end](dusk-perf-end.md): the report each repeat is.
- [dusk:perf_trace](dusk-perf-trace.md): export a session's timeline.
