# CLI commands reference

Every `tapir:*` command `TapirDowelProvider.commands()` registers, run from a shell. Most mirror an MCP tool with the same parameter names as flags; `tapir:install`, `tapir:doctor` and `tapir:perf_campaign` are CLI only, and `tapir_evaluate` has no command. Reach for the CLI when the agent has a shell and no MCP client, when output goes to a file or a pipe, or when a script chains on exit codes.

## Contents

- [Entry points](#entry-points)
- [Output and exit codes](#output-and-exit-codes)
- [Shared flags](#shared-flags)
- [Commands by family](#commands-by-family)
- [Performance](#performance)
- [Setup and health: install, doctor](#setup-and-health-install-doctor)
- [Pipeline patterns](#pipeline-patterns)

## Entry points

| Form | When |
|---|---|
| `./bin/dowel <cmd>` | The default once `tapir:install` built it: an AOT binary that rebuilds itself when stale |
| `dart run tapir <cmd>` | Before `./bin/dowel` exists; loads the tapir commands itself, slower to start |

Start the app with dowel (`./bin/dowel start --device=<dev>`, add `--cdp-port=9222` on web) so the connected commands can find it.

## Output and exit codes

Default output depends on the verb:

- A one-line summary on the action verbs, and it names a no-op instead of ticking it: `Tapped e7 (no observable change)`, `Scrolled e3 (nothing moved: ...)`, `Nothing to pop: already at the root route`, `Navigation to /x not confirmed: <reason>`.
- The YAML tree for `tapir:snap`.
- JSON for `tapir:find`, `tapir:observe`, `tapir:get_routes`, `tapir:console`, `tapir:exceptions`, `tapir:reset_overlays` and `tapir:hot_reload_and_snap`.
- A file for `tapir:screenshot` (`-o` is required) and `tapir:perf_trace` (prints the path).

`--json` prints the raw envelope instead of the summary. It exists on `snap`, `tap`, `double_click`, `right_click`, `triple_click`, `hover`, `drag`, `fill`, `type`, `clear`, `press_key`, `focus`, `blur`, `scroll`, `set_checkbox`, `select_option`, `navigate`, `navigate_back`, `close_app`, `wait_for`, `wait_for_network_idle` and the perf verbs except `perf_trace`. Use it whenever output feeds a tool: `tapir:snap --json` is the way to read `grepLiteral`, `warnings`, `framesForced` and `renderErrors`.

Exit `0` is success and `1` is failure, including the verdicts a summary would hide:

| Command | Exits 1 when |
|---|---|
| `tapir:wait_for`, `tapir:wait_for_network_idle` | The condition never resolved |
| `tapir:fill`, `tapir:type` | `effect.verified` is false (the summary names what the field holds); `--json` and `--includeSnapshot` print the response and exit 0 |
| `tapir:set_checkbox` | `effect.verified` is false (the summary names the value read back); `--json` and `--includeSnapshot` print the response and exit 0 |
| `tapir:hot_reload_and_snap` | `reloaded` is false (the JSON is still printed): a compile error, or no reload line in the `flutter run` log within 10 seconds |
| `tapir:perf_end` | The report is `refused` (the engine drew nothing; no metrics) |
| `tapir:perf_compare` | An error-level regression |
| `tapir:perf_campaign` | Any scenario failed |
| `tapir:doctor` | The semantics row failed: the running app answered that its tree is off, or that it registers no `ext.tapir.*` at all (the other rows only warn or skip) |

stderr carries errors, including the gate's reason substring, the frame-production banner when tapir could not force frames, a warning when `fill` or `type` wrote the `nearest` field, and a warning on `tapPointOutsideOwner`.

On web with a `cdpPort` in the session, `snap`, `observe`, `tap`, `fill`, `type`, `navigate`, `scroll` and `press_key` bring a hidden tab to front over CDP once. `snap` and `observe` are then called again; an acting verb is not repeated, since its gesture may already have run, and a stderr notice asks for a `tapir:snap`.

## Shared flags

| Flag | Default | On |
|---|---|---|
| `--ref=<eN or qN>` | required | The ref-taking verbs |
| `--[no-]checkStable`, `--[no-]checkReceivesEvents` | on | `tap`, `double_click`, `right_click`, `triple_click`, `hover`, `drag`, `type`, `fill`, `set_checkbox` |
| `--includeSnapshot` | off (the MCP tools default it on) | The action verbs; prints the envelope with the post-action snapshot |
| `--snapshot=full\|diff\|none` | none | `tap`, `fill`, `type`, `navigate`, `scroll`; prints the snapshot after the summary and overrides `--includeSnapshot` |

Flag names match the MCP parameter names (`--timeoutMs`, not `--timeout`), except `tapir:drag`, which takes `--fromRef` and `--toRef` (`--startRef` and `--endRef` also work).

## Commands by family

### See and find

```bash
./bin/dowel tapir:snap                              # full tree
./bin/dowel tapir:snap --within=e12 --interactiveOnly
./bin/dowel tapir:snap --grep="Sign ?in" --depth=8
./bin/dowel tapir:snap --includeEnrichers           # Magic, Wind and custom enricher lines
./bin/dowel tapir:observe --roles=textbox,button --limit=20 --includeEnrichers=full
./bin/dowel tapir:screenshot -o page.jpg
./bin/dowel tapir:screenshot --ref=e7 --rect=0,0,200,80 -o widget.png
./bin/dowel tapir:find --text="Submit"
./bin/dowel tapir:find --contains="Sign" --within=e12
./bin/dowel tapir:find --semanticsLabel="Email field"
./bin/dowel tapir:find --key="login-submit"
```

`tapir:screenshot` takes `--format=jpeg|png` and `--quality`; without `--format` the format follows the `-o` extension, and a mismatch warns. On web with a `cdpPort` it falls back to CDP `Page.captureScreenshot`, clipped to `--ref` and `--rect`.

### Pointer

```bash
./bin/dowel tapir:tap --ref=e7
./bin/dowel tapir:tap --ref=q3 --no-checkStable         # an intentionally animated target
./bin/dowel tapir:tap --ref=e7 --snapshot=diff
./bin/dowel tapir:tap --ref=e7 --until="Saved"          # --untilTimeoutMs, default 3000
./bin/dowel tapir:tap --ref=e7 --no-retarget            # a merged boundary's centre
./bin/dowel tapir:double_click --ref=e12
./bin/dowel tapir:right_click --ref=e8
./bin/dowel tapir:triple_click --ref=e15
./bin/dowel tapir:hover --ref=e9
./bin/dowel tapir:drag --fromRef=e5 --toRef=e6
```

### Text and keys

```bash
./bin/dowel tapir:fill --ref=e4 --text="user@example.com"   # focus, clear, type, settle
./bin/dowel tapir:fill --ref=q3 --text=""                   # clear
./bin/dowel tapir:type --ref=e4 --text="user@example.com"
./bin/dowel tapir:clear --ref=e4
./bin/dowel tapir:press_key --key=Enter
./bin/dowel tapir:press_key --key=S --modifiers=control,shift
./bin/dowel tapir:focus --ref=e4
./bin/dowel tapir:blur
```

`fill`, `type` and `clear` refuse a ref that is a button, checkbox, radio, switch, slider or link (`ref eN is a <role>, not a text field`).

### Form controls and scroll

```bash
./bin/dowel tapir:set_checkbox --ref=e10 --value=true       # checkbox, switch or radio from any library; gated like a tap
./bin/dowel tapir:select_option --ref=e11 --value="GMT+3"   # DropdownButton with String values
./bin/dowel tapir:scroll --ref=e3 --dy=600
./bin/dowel tapir:scroll --ref=e3 --direction=up --pixels=200
./bin/dowel tapir:scroll --ref=e3 --dx=300
./bin/dowel tapir:scroll --ref=q5 --intoView
```

### Wait

```bash
./bin/dowel tapir:wait_for --text="Saved"
./bin/dowel tapir:wait_for --textGone="Loading" --timeoutMs=10000
./bin/dowel tapir:wait_for --expression="Order placed"      # matched as text, not evaluated
./bin/dowel tapir:wait_for_network_idle --idleMs=800 --timeoutMs=8000 --pollIntervalMs=200
```

`wait_for_network_idle` reads the in-flight count through `pendingHttpCountReader`, which an app wires to the separate `crumbs` package (`() => CrumbsStore.pendingHttpCount`) with an HTTP adapter that overrides `pendingCount`; until both are in place the count is always 0, so it succeeds after one idle window (about `idleMs`) or times out when `timeoutMs` is shorter than that; either way assume it always reports idle.

### Navigation and overlays

```bash
./bin/dowel tapir:navigate --route=/login
./bin/dowel tapir:navigate_back
./bin/dowel tapir:get_routes
./bin/dowel tapir:dismiss_modals                            # pop every PopupRoute
./bin/dowel tapir:reset_overlays                            # pop, Escape, then a Cancel-style tap
```

### Diagnostics and app control

```bash
./bin/dowel tapir:console --minLevel=WARNING --limit=20
./bin/dowel tapir:exceptions --limit=5
./bin/dowel tapir:exceptions --since=2026-11-07T10:00:00Z --clear
./bin/dowel tapir:close_app
./bin/dowel tinker --eval="WidgetsBinding.instance.lifecycleState.toString()"   # Dart evaluation is dowel's
```

### Batch and reload

```bash
./bin/dowel tapir:run "tap --ref=q3" "fill --ref=q1 --text=\"a b\"" "snap --grep Total"
./bin/dowel tapir:run --continue "press_key --key=Escape" "snap"
./bin/dowel tapir:hot_reload_and_snap
./bin/dowel tapir:hot_reload_and_snap --no-screenshot
```

`tapir:run` runs the steps in one process and one VM connection, prints one `[i/n] <step> ok: <first line>` per step and then the last step's output, and stops at the first failure with `step N failed (exit C): <step>` and that exit code; `--continue` runs every step and exits with the first non-zero code.

### Viewport and devices (web, needs `--cdp-port`)

```bash
./bin/dowel tapir:device_profile --list                     # no Chrome needed
./bin/dowel tapir:device_profile --preset=iphone-15-pro
./bin/dowel tapir:device_profile --reset
./bin/dowel tapir:resize_viewport --width=390 --height=844 --dpr=3.0 --mobile --touch --hold &
./bin/dowel tapir:resize_viewport --reset
```

An `Emulation.*` override lasts only as long as the CDP session that set it. Without `--hold` both commands close theirs on exit and the page returns to its own size (only `tapir:device_profile`'s window size stays); `tapir:resize_viewport --hold` in the background keeps it while you drive.

## Performance

```bash
./bin/dowel tapir:perf_begin                     # attribution mode
./bin/dowel tapir:perf_begin --mode=timing       # frame timings only
./bin/dowel tapir:perf_begin --phases            # also layout and paint
./bin/dowel tapir:tap --ref=e7                   # one interaction
./bin/dowel tapir:perf_end
./bin/dowel tapir:perf_insight --id=I1 --token=perf-1
./bin/dowel tapir:perf_trace --out=build/perf/trace.json

./bin/dowel tapir:perf_run --scenario=tool/perf/login.yaml --label=baseline --timing
./bin/dowel tapir:perf_compare build/perf/login-baseline.json build/perf/login-candidate.json
./bin/dowel tapir:perf_campaign tool/perf/campaign.yaml --platform=chrome --label=base
```

`perf_run` also takes `--variant`, `--out`, `--repeat`, `--platform`, `--against` and `--semantics-pass`; `perf_campaign` takes `--out`, `--only`, `--device`, `--cdp-port`, `--timing` and `--semantics-pass`, starts and stops the app itself, runs each scenario from a cold start, retries a failed one and prints `ok` or `FAILED` per scenario. Read `refused` in `perf_end`'s output first: a session the engine did not render through has no metrics, and the perf verbs do not wake a hidden app.

## Setup and health: install, doctor

```bash
dart run tapir tapir:install
./bin/dowel tapir:doctor
```

`tapir:install` is idempotent. It patches `lib/main.dart` (the `kReleaseMode` import, `WidgetsFlutterBinding.ensureInitialized()`, a `!kReleaseMode` block with `TapirPlugin.install()` before `runApp(`, or before `Magic.init(` on a Magic app), adds `MagicTapirIntegration.install()` after `Magic.init()` when `magic_devtools` is a dependency and its resolved release ships `tapir.dart`, then runs dowel's install and registers the plugin when they are missing. It first prints `Leftovers from fluttersdk_dusk found:` with one line per file an install of tapir's predecessor left (`bin/dispatcher.dart` that imports the old substrate, `bin/fsa`, a `lib/app/commands/_index.g.dart` that still imports the old package, an app command that uses `Artisan*` classes, a `"fluttersdk"` entry in `.mcp.json`) and the commands to run after deleting them; it deletes nothing.

`tapir:doctor` needs no session to run. With one recorded it asks the running app once (`ext.tapir.boot_id`) for three rows: whether `ext.tapir.*` is registered (the `TAPIR_DISABLE` row warns when it is not), the enricher count, and whether the Semantics tree is on. The semantics row is the only one that fails the command: it exits 1 when the app answers that its tree is off, or that it registers no tapir at all. With no session, or an app that does not answer within five seconds, those three rows print `Skipped (...)` and the exit is 0, so a skip proves nothing: confirm with `tapir:snap`. The other rows are hot-restart staleness, Magic wiring in `lib/main.dart`, session ownership (the recorded session belongs to this project), CDP session health (the port answers, serves this run's page, and that page is visible) and `fluttersdk_dusk leftovers` (the same list `tapir:install` prints, as a warning). Run it first whenever tapir behaves strangely: session ownership and CDP health catch failures that look like a broken app and are not.

## Pipeline patterns

```bash
set -e
./bin/dowel tapir:snap > /dev/null                         # baseline for the diff
./bin/dowel tapir:tap --ref=e7 --snapshot=diff
./bin/dowel tapir:wait_for --text="Saved" --timeoutMs=8000
./bin/dowel tapir:observe --roles=button | jq -r '.candidates[].label'
./bin/dowel tapir:tap --ref=e7 --json | jq '.effect.changed'
```
