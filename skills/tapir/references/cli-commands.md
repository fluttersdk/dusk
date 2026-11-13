# CLI commands reference

Every `tapir_*` MCP tool has a matching `tapir:*` CLI command. Same params,
same return shape (JSON via stdout on success, JSON via stderr on error,
non-zero exit code on failure). Use the CLI from Bash when:

- The agent is wired to a shell, not an MCP client.
- The action's output should be redirected to a file (`> snapshot.yaml`).
- The action is part of a shell pipeline (`./bin/dowel tapir:snap | yq '.snapshot'`).
- A retry loop with `until` / `while` reads the exit code.

For interactive agent loops, MCP is faster (no process spawn per call).

## Contents

- [Entry points](#entry-points)
- [Common flags across commands](#common-flags-across-commands)
- [Output](#output)
- [Commands by family](#commands-by-family)
- [Performance](#performance)
- [Install + doctor (no app required)](#install--doctor-no-app-required)
- [Exit codes and pipeline patterns](#exit-codes-and-pipeline-patterns)
- [MCP-only: there is no CLI for evaluate](#mcp-only-there-is-no-cli-for-evaluate)

## Entry points

| Form | Startup | When to use |
|---|---|---|
| `./bin/dowel <cmd>` | ~110ms warm AOT | Default; what `tapir:install` scaffolds |
| `dart run tapir <cmd>` | ~3s cold | When `./bin/dowel` is missing; preloads `TapirDowelProvider` so `tapir:*` commands are available |
| `dart run dowel <cmd>` | ~3s cold | Substrate-level commands without tapir (bypasses the tapir wrapper) |

`./bin/dowel` auto-rebuilds when stale (4-condition check); manual force
rebuild: `rm -rf .dowel/cli-bundle .dowel/build.stamp && ./bin/dowel list`.

## Common flags across commands

| Flag | Default | Meaning |
|---|---|---|
| `--ref=<eN\|qN>` | (required) | Target widget for click / text / focus / checkbox |
| `--checkStable` / `--no-checkStable` | true | Skip the 2-frame stability check |
| `--checkReceivesEvents` / `--no-checkReceivesEvents` | true | Skip the hit-test check |
| `--includeSnapshot` / `--no-includeSnapshot` | false on the CLI (the MCP tools default to true) | Append the post-action snapshot; `--snapshot=full\|diff\|none` overrides it |
| `--timeoutMs=<ms>` | 5000 | Hard timeout for waits |
| `--format=<jpeg\|png>` | inferred from `--output`, else jpeg | Screenshot encoding |

CLI option names match MCP `inputSchema` property names (camelCase:
`--checkStable`, `--includeSnapshot`, `--timeoutMs`, etc.) except where a verb
documents an alias (`tapir:drag` takes `--fromRef` / `--toRef`; `--startRef` /
`--endRef` are legacy aliases, and the MCP tool uses `startRef` / `endRef`).

## Output

**`--json` on any verb prints the raw envelope.** Reach for it whenever the
output is going into a tool rather than a terminal; you no longer have to
know which verbs happen to emit JSON.

Without it, stdout shape depends on the command:

- **JSON payload** on read / query verbs: `tapir:observe`, `tapir:find`,
  `tapir:get_routes`, `tapir:console`, `tapir:exceptions`,
  `tapir:hot_reload_and_snap`. These mirror the MCP response shape and are
  safe to pipe through `jq`.
- **The tree as text** for `tapir:snap`. `tapir:snap --json` prints the whole
  envelope instead, which is the only way to read `grepLiteral`, `warnings`,
  `framesForced` and `renderErrors` from Bash.
- **One-line human summary** on the side-effect verbs and on `tapir:wait` /
  `tapir:wait_for_network_idle`. The summary is not lossy by accident: where
  the envelope carries a verdict, the line names it (`✓ Tapped e7 (no
  observable change)`).
- **Bytes to disk** for `tapir:screenshot` (always requires `-o <path>`;
  prints `Wrote N bytes (K KB, format) to <path>`).
- **Categorised report** for `tapir:install` and `tapir:doctor`.

The one-line summaries name a no-op instead of ticking it (`--json` and
`--includeSnapshot` print the raw envelope and are unchanged):

| Command | Line or exit |
|---|---|
| `tapir:fill`, `tapir:type` | `effect.verified == false` prints an error naming the value the field holds and exits `1` |
| `tapir:navigate` | `navigated == false` prints `No navigation: ...` |
| `tapir:navigate_back` | `popped == false` prints `Nothing to pop` |
| `tapir:scroll` | `effect.changed == false` prints `nothing moved` |
| `tapir:tap` | a tap on a merged boundary goes to its labelled control and the summary says so (`retargeted`); when it cannot, one stderr warning (`tapPointOutsideOwner`) |
| `tapir:fill`, `tapir:type` | when the field written was the `nearest` one (the ref overlapped no field) a warning names it |
| `tapir:hot_reload_and_snap` | exits `1` when `reloaded` is false (the JSON is still on stdout) |

stderr carries error messages, including the actionability reason
substring on gate failures, and the frame-production banner. The banner
now appears only when tapir could not force frames, and names the real
cause per platform (web: hidden tab and `Page.bringToFront`; desktop:
window hidden, minimised or occluded, or display asleep).

On web with a `cdpPort` in the session, `snap`, `observe`, `tap`, `fill`,
`type`, `navigate`, `scroll` and `press_key` send CDP `Page.bringToFront`
once when the answer carries a web `warnings` block (or the call fails and the
tab reports `hidden`). `snap` and `observe` are then called again; a verb that
acts is not repeated, since its gesture may already have fired, and a stderr
notice tells you to run `tapir:snap`. A CDP failure leaves the first result and
exit code.

**Exit code: 0 on success, 1 on any failure, and `tapir:wait` counts a
condition that never matched as a failure.** It used to print
`✓ Condition matched` and exit 0 on timeout, which made the one command
whose whole job is asserting a post-condition pass on exactly the case it
exists to catch. If a shell loop of yours worked around that, drop the
workaround.

```bash
./bin/dowel tapir:snap > snap.yaml
./bin/dowel tapir:snap --json | jq '.grepLiteral'
./bin/dowel tapir:observe --roles=button --limit=10 | jq '.candidates[].label'
./bin/dowel tapir:tap --ref=e7 --json | jq '.effect.changed'
./bin/dowel tapir:wait --text="Saved" || echo "never appeared"
```

## Commands by family

### See

```bash
./bin/dowel tapir:snap                           # full tree
./bin/dowel tapir:snap --depth=4                 # limit walk depth
./bin/dowel tapir:snap --within=e12              # one region only
./bin/dowel tapir:snap --interactiveOnly         # refs only, no prose
./bin/dowel tapir:snap --grep="Sign ?in"         # matches + the path to them
./bin/dowel tapir:snap --includeEnrichers        # add the Magic / Wind lines under each ref
./bin/dowel tapir:observe --roles=textbox,button --limit=20
./bin/dowel tapir:observe --intent="login fields" --includeEnrichers=full
./bin/dowel tapir:screenshot -o page.jpg
./bin/dowel tapir:screenshot --ref=e7 -o widget.png --format=png
```

`tapir:screenshot` requires `-o <path>` (the CLI writes the decoded
bytes to disk; the JSON `base64` is reserved for the MCP path). The format
follows the extension (`.png`, `.jpg`, `.jpeg`) when `--format` is not
given; an explicit `--format` wins and a mismatch warns on stderr.

### Find

```bash
./bin/dowel tapir:find --text="Submit"
./bin/dowel tapir:find --contains="Sign"
./bin/dowel tapir:find --semanticsLabel="Email field"
./bin/dowel tapir:find --text="Monitors" --within=e12   # scope to one region
./bin/dowel tapir:find --key="ValueKey('login-submit')"
```

Returns `{ "ref": "q3", "matched": true }` or `{ "ref": null, "matched": false }`.

### Click family

```bash
./bin/dowel tapir:tap --ref=e7
./bin/dowel tapir:tap --ref=q3 --no-checkStable                  # for animated targets
./bin/dowel tapir:tap --ref=e7 --snapshot=diff                   # print only the lines the tap changed
./bin/dowel tapir:dblclick --ref=e12
./bin/dowel tapir:right_click --ref=e8
./bin/dowel tapir:triple_click --ref=e15
./bin/dowel tapir:hover --ref=e9                                 # mouse-only
./bin/dowel tapir:drag --fromRef=e5 --toRef=e6
./bin/dowel tapir:tap --ref=e7 --no-retarget                     # tap a merged boundary's centre, not its labelled control
./bin/dowel tapir:tap --ref=e7 --until="Saved"                   # then poll for that text (--untilTimeoutMs, default 3000)
```

### Text input

```bash
./bin/dowel tapir:type --ref=e4 --text="user@example.com"
./bin/dowel tapir:clear --ref=e4
./bin/dowel tapir:press_key --key=Enter
./bin/dowel tapir:press_key --key=G                     # one letter or digit: a shortcut key
./bin/dowel tapir:press_key --key=S --modifiers=control # held before the key, released after it
./bin/dowel tapir:focus --ref=e4
./bin/dowel tapir:blur

./bin/dowel tapir:fill --ref=e4 --text="user@example.com"   # focus + clear + type + settle
./bin/dowel tapir:fill --ref=q3 --text=""                   # clear the field
./bin/dowel tapir:fill --ref=e4 --text="x" --includeSnapshot
```

`tapir:fill` replaces the focus + clear + type + wait sequence and retries
once when the ref goes stale mid-fill, so it is the default for entering
text. `--ref` and `--text` are both mandatory. `--includeSnapshot` defaults
to false on the CLI while the `tapir_fill` MCP tool defaults it to true;
pass it explicitly when you want the post-fill tree from Bash.
`--no-checkStable` and `--no-checkReceivesEvents` skip the matching
actionability steps, same as on the other gestures. `--snapshot=full|diff|none`
(also on `tap`, `type`, `navigate` and `scroll`) prints the post-action
snapshot after the summary and overrides `--includeSnapshot`; `diff` prints
only the changed lines since your last unfiltered snapshot.

A `fill`, `type` or `clear` on a ref that is a button, checkbox, radio,
switch, slider or link is refused (`ref eN is a <role>, not a text field`)
instead of writing the nearest field. `effect.target` says which field was
written; label and static-text refs still use the nearest one, with a warning.
`--modifiers` takes a comma list: `control` (or `ctrl`), `shift`, `alt`,
`meta`.

### Form controls

```bash
./bin/dowel tapir:set_checkbox --ref=e10 --value=true             # idempotent
./bin/dowel tapir:select_option --ref=e11 --value="GMT+3"
```

### Scroll

```bash
./bin/dowel tapir:scroll --ref=e3 --dy=600                         # scroll the list holding e3 down 600px
./bin/dowel tapir:scroll --ref=e3 --dy=-400                        # scroll a specific scrollable up
./bin/dowel tapir:scroll --ref=q5 --intoView                       # bring q5 into view
./bin/dowel tapir:scroll --ref=e3 --dx=300                         # horizontal
./bin/dowel tapir:scroll --ref=e3 --direction=up --pixels=200      # same delta as a signed pair; --dx / --dy win
```

### Wait

```bash
./bin/dowel tapir:wait --text="Saved"
./bin/dowel tapir:wait --textGone="Loading" --timeoutMs=10000
./bin/dowel tapir:wait --expression="Order placed"                 # text presence, not a Dart expression
./bin/dowel tapir:wait_for_network_idle
./bin/dowel tapir:wait_for_network_idle --idleMs=800 --timeoutMs=8000
```

`wait_for_network_idle` requires `crumbs` wired in the
running app; without it, it returns immediately as `matched: true`.

Both waits exit `1` when they never resolved, so `&&` chains stop where
they should. Read the exit code rather than the printed line.

### Navigation

```bash
./bin/dowel tapir:navigate --route=/login
./bin/dowel tapir:navigate_back
./bin/dowel tapir:get_routes
./bin/dowel tapir:modal                                            # dismiss every PopupRoute
./bin/dowel tapir:reset_overlays                                   # pop + Escape + Cancel-tap
```

`tapir:modal` only pops `PopupRoute` subclasses. `tapir:reset_overlays` runs
three escalating layers instead (pop every `PopupRoute`, press Escape, then
tap a Cancel / Dismiss / Close / OK / Done affordance), each a no-op once the
screen is clear, and returns `{popped, escaped, dismissTapped}` so you can
see which layer did the work. It is idempotent, so it is safe to call
speculatively between flows; reach for it when the overlay is not a
`PopupRoute` (a custom `OverlayEntry`, a dropdown menu, a barrier dialog).

### Diagnostics

```bash
./bin/dowel tapir:console
./bin/dowel tapir:console --minLevel=WARNING --limit=20
./bin/dowel tapir:exceptions
./bin/dowel tapir:exceptions --limit=5
./bin/dowel tapir:exceptions --since=2026-11-07T10:00:00Z --clear   # a delta; --clear empties the buffer after the read
```

`tapir:exceptions` works without crumbs (tapir keeps its own buffer);
`tapir:console` lists the app's `debugPrint` output and adds crumbs entries
when the adapter is wired.

### App control

```bash
./bin/dowel tapir:close_app
```

### Batch

```bash
./bin/dowel tapir:run "tap --ref=q3" "fill --ref=q1 --text=\"a b\"" "snap --grep Total"
./bin/dowel tapir:run --continue "press_key --key=Escape" "snap"
```

Runs several verbs in one process and one VM connection. Each step is a verb
line (a bare verb gets `tapir:`), tokenised like a shell and parsed by that
verb's own options. Output is one `[1/3] tap --ref=q3 ok: <first line>` per
step, then the last step's output. It stops at the first failing step with
`step N failed (exit C): <step>` and that exit code; `--continue` runs them
all and exits with the first non-zero code. Nested `tapir:run`, unknown verbs
and verbs that are not connected (`tapir:resize`, `tapir:device`, `tapir:install`,
`tapir:doctor`) fail as that step. Use `--text`, `--key` or `q<N>` handles
between steps, because `e<N>` refs belong to one snapshot.

### Composite

```bash
./bin/dowel tapir:hot_reload_and_snap
./bin/dowel tapir:hot_reload_and_snap --no-screenshot              # snap + exceptions only
```

### Device emulation (web only, requires `--cdp-port`)

```bash
./bin/dowel tapir:device --list                                    # print presets, no Chrome needed
./bin/dowel tapir:device --preset=iphone-15-pro
./bin/dowel tapir:device --preset=desktop-1440
./bin/dowel tapir:device --reset                                   # clear overrides

./bin/dowel tapir:resize --width=1280 --height=800 --dpr=2.0 --hold &   # keep it while you drive
./bin/dowel tapir:resize --width=390 --height=844 --mobile --touch  # emulate a phone (mobile flag, touch events)
./bin/dowel tapir:resize --reset
```

An `Emulation.*` override lasts only as long as the CDP session that sent
it: `tapir:device` and `tapir:resize` without `--hold` close theirs on exit,
so the page is back at its own size at once (only `tapir:device`'s window
bounds stay). The MCP `tapir_resize_viewport` and `tapir_device_profile`
cannot hold it; `tapir:resize --hold` in the background can.

Launch Chrome with the debug port first: `./bin/dowel start --device=chrome --cdp-port=9222`.

## Performance

```bash
./bin/dowel tapir:perf_begin                                      # attribution mode (default)
./bin/dowel tapir:perf_begin --mode=timing                        # frame timings only, no profiling flag
./bin/dowel tapir:perf_begin --phases                              # also profile layout and paint (attribution mode)
./bin/dowel tapir:tap --ref=e7                                     # drive exactly one interaction
./bin/dowel tapir:perf_end                                        # closes the session, reports insights
./bin/dowel tapir:perf_insight --id=I1                             # drill into one insight's rows

./bin/dowel tapir:perf_run --scenario=perf/login.yaml --label=baseline
#   more: --variant --out --repeat --platform --timing --against --semantics-pass
./bin/dowel tapir:perf_compare build/perf/login-baseline.json build/perf/login-candidate.json
./bin/dowel tapir:perf_trace --out=build/perf/trace.json           # last closed session as Chrome Trace JSON

rm -f .dowel/build.stamp                                      # rebuild a dispatcher a tapir change missed
./bin/dowel tapir:perf_campaign tool/perf/campaign.yaml --platform=chrome --label=base
#   more: --out --only --device --cdp-port --timing --semantics-pass
```

`tapir:perf_insight` and `tapir:perf_trace` take `--token` to name the closed
session they read.

Check `refused` in `tapir:perf_end`'s output first: a session the engine did
not render through (a backgrounded browser tab on web, a hidden window on
desktop; the perf verbs do not force frames) returns no metrics rather
than a report reading all zeros as "fast". `tapir:perf_run` repeats a
scenario from a clean start and writes medians to a file; `tapir:perf_compare`
gates on counts per painted frame, never on raw counts, and exits 1 on an
error-level regression. `tapir:perf_trace` writes to disk because a trace is
too large for a terminal or an agent's context. `tapir:perf_campaign` runs every
scenario of a campaign YAML on one platform, each from a cold start (its
hooks, Android preparation and `after_start` first), retries a failed one,
prints `ok` or `FAILED (see <.err>)` per scenario and exits 1 when any
failed; it starts and stops the app itself, so no app needs to be running.

## Install + doctor (no app required)

```bash
dart run tapir tapir:install                           # one-time setup
./bin/dowel tapir:doctor                                           # 7 preflight checks
```

`tapir:install` patches `lib/main.dart` (adds `!kReleaseMode` guard +
`TapirPlugin.install()`), scaffolds `./bin/dowel`, registers the provider in
`lib/app/_plugins.g.dart`, and (when `magic_devtools` is in pubspec AND
`lib/main.dart` contains an `await Magic.init(` anchor) injects
`import 'package:magic_devtools/tapir.dart';` and
`MagicTapirIntegration.install()` after `Magic.init()`. Idempotent.

`tapir:doctor` checks:

1. Hot-restart staleness (Chrome PID drift)
2. `TAPIR_DISABLE` env-var
3. Enricher count (`TapirPlugin.enrichers.length`)
4. `semanticsEnabled` (the only check that exits non-zero on failure)
5. Magic-init detection in `lib/main.dart`
6. Session ownership: does `state.json` describe THIS project? `~/.dowel/
   state.json` is one global slot, so a sibling project's `dowel start`
   takes it over and every `tapir:*` call from here drives that app instead,
   succeeding each time.
7. CDP session health: is the recorded `cdpPort` live, does it serve a page
   on this run's web port (an orphan browser from a killed run does not), and
   is that page visible (a hidden one stops frame production).

Reach for `tapir:doctor` FIRST whenever tapir behaves strangely. Checks 6 and 7
cover the two failures that look exactly like a broken driver or a broken app
and are neither.

## Exit codes and pipeline patterns

```bash
# Retry until idle
until ./bin/dowel tapir:wait_for_network_idle --timeoutMs=2000; do
  sleep 1
done

# Bail on first gate failure
set -e
./bin/dowel tapir:tap --ref=e7

# Capture both stdout and stderr for an agent log
./bin/dowel tapir:tap --ref=e7 >result.json 2>error.txt

# Snap as YAML to disk for diffing
./bin/dowel tapir:snap > /tmp/snap-before.yaml
./bin/dowel tapir:tap --ref=e7
./bin/dowel tapir:snap > /tmp/snap-after.yaml
diff /tmp/snap-before.yaml /tmp/snap-after.yaml

# Or let tapir diff for you: only the lines the tap changed since the last snap
./bin/dowel tapir:snap > /dev/null
./bin/dowel tapir:tap --ref=e7 --snapshot=diff
```

## MCP-only: there is no CLI for evaluate

`tapir_evaluate` has no CLI mirror. From a shell, use `./bin/dowel tinker`
(the tapir-aware connected Dart REPL):

```bash
./bin/dowel tinker --eval="MyService.instance.state.toString()"
```

Or open the interactive REPL: `./bin/dowel tinker`.
