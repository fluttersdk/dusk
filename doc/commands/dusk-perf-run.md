# dusk:perf_run

Run a perf scenario several times from a clean start and write one file per scenario: medians of counts per painted frame, a spread block, the insights of the median repeat, and every repeat's full report. The file is what `dusk:perf_compare` reads.

---

## Table of contents

- [Synopsis](#synopsis)
- [The scenario file](#the-scenario-file)
- [What one run does](#what-one-run-does)
- [The run file](#the-run-file)
- [Refusals and exit codes](#refusals-and-exit-codes)
- [The semantics pass](#the-semantics-pass)
- [See also](#see-also)

---

<a name="synopsis"></a>
## Synopsis

```
dart run fluttersdk_dusk dusk:perf_run <scenario.yaml> [--label=<name>] [--out=<dir>]
    [--repeat=<n>] [--platform=chrome|android|ios] [--timing]
    [--against=<baseline.yaml>] [--semantics-pass] [--json]
```

`dusk:perf_run` requires a running session (`CommandBoot.connected`). On Chrome it also needs the CDP port `artisan start --cdp-port` records: every session is brought to front first, and viewport, resize and wheel go through DevTools.

| Flag | Default | Meaning |
|------|---------|---------|
| `<scenario.yaml>` / `--scenario` | required | The scenario file. |
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

<a name="what-one-run-does"></a>
## What one run does

Each repeat is one unit: the scenario's setup, `Page.bringToFront` on Chrome, the targets that can be resolved early, `perf_begin`, the steps, a 300 ms settle (Flutter delivers frame timings in batches of about 100 ms), then `perf_end` with `full=true`. Setup runs before every repeat so each starts from the same state: the controllers are singletons, and a search term left by one repeat would filter every later one.

A setup `navigate` has to land and stay. An answer of `navigated: false` (the router dropped or redirected the route) fails the run at once with the payload. Otherwise the runner reads `ext.dusk.get_routes`, waits for network idle, and reads it again; a route that moved in between (a first fetch answering 401 redirects to the login screen) fails the run naming both. `get_routes` answers the page's name, not its path, so the two reads are compared with each other rather than with the requested route.

Every setup failure other than a restart's ends with a `Diagnostics:` line: the route `ext.dusk.get_routes` answers, the last setup navigate's payload, and the three newest `ext.dusk.exceptions` entries. A diagnostic call that fails is named in its place.

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
2. Each semantics repeat runs the setup, opens the session, calls `ext.dusk.semantics_hold action=release`, replays the steps by those coordinates (`ext.dusk.tap {x, y}`, `ext.dusk.drag {x, y, toX, toY}`, CDP for the wheel), calls `action=acquire`, and only then `perf_end`. The handle is never released outside that window, and the acquire runs even when a step fails.

The file gains `semanticsPass: "measured"` and `semanticsOff: {summary, repeats}`. `fill`, `type` and `scroll` act through a resolved widget, so a scenario with one of them records `semanticsPass: "unsupported"` with a `semanticsPassReason` instead of failing the run; so does a replay that fails. The acquire's own frame, which rebuilds the whole tree, falls inside the window: read the series as an upper bound on what the tree costs, not an exact figure. See [the semantics hold](../reference/semantics-hold.md).

---

<a name="see-also"></a>
## See also

- [dusk:perf_compare](dusk-perf-compare.md): judge one run file against another.
- [dusk:perf_end](dusk-perf-end.md): the report each repeat is.
- [dusk:perf_trace](dusk-perf-trace.md): export a session's timeline.
