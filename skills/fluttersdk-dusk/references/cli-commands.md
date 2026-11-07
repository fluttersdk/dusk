# CLI commands reference

Every `dusk_*` MCP tool has a matching `dusk:*` CLI command. Same params,
same return shape (JSON via stdout on success, JSON via stderr on error,
non-zero exit code on failure). Use the CLI from Bash when:

- The agent is wired to a shell, not an MCP client.
- The action's output should be redirected to a file (`> snapshot.yaml`).
- The action is part of a shell pipeline (`./bin/fsa dusk:snap | yq '.snapshot'`).
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
| `./bin/fsa <cmd>` | ~110ms warm AOT | Default; what `dusk:install` scaffolds |
| `dart run fluttersdk_dusk <cmd>` | ~3s cold | When `./bin/fsa` is missing; preloads `DuskArtisanProvider` so `dusk:*` commands are available |
| `dart run fluttersdk_artisan <cmd>` | ~3s cold | Substrate-level commands without dusk (bypasses the dusk wrapper) |

`./bin/fsa` auto-rebuilds when stale (4-condition check); manual force
rebuild: `rm -rf .artisan/cli-bundle .artisan/build.stamp && ./bin/fsa list`.

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
documents an alias (`dusk:drag` takes `--fromRef` / `--toRef`; `--startRef` /
`--endRef` are legacy aliases, and the MCP tool uses `startRef` / `endRef`).

## Output

**`--json` on any verb prints the raw envelope.** Reach for it whenever the
output is going into a tool rather than a terminal; you no longer have to
know which verbs happen to emit JSON.

Without it, stdout shape depends on the command:

- **JSON payload** on read / query verbs: `dusk:observe`, `dusk:find`,
  `dusk:get_routes`, `dusk:console`, `dusk:exceptions`,
  `dusk:hot_reload_and_snap`. These mirror the MCP response shape and are
  safe to pipe through `jq`.
- **The tree as text** for `dusk:snap`. `dusk:snap --json` prints the whole
  envelope instead, which is the only way to read `grepLiteral`, `warnings`,
  `framesForced` and `renderErrors` from Bash.
- **One-line human summary** on the side-effect verbs and on `dusk:wait` /
  `dusk:wait_for_network_idle`. The summary is not lossy by accident: where
  the envelope carries a verdict, the line names it (`✓ Tapped e7 (no
  observable change)`).
- **Bytes to disk** for `dusk:screenshot` (always requires `-o <path>`;
  prints `Wrote N bytes (K KB, format) to <path>`).
- **Categorised report** for `dusk:install` and `dusk:doctor`.

The one-line summaries name a no-op instead of ticking it (`--json` and
`--includeSnapshot` print the raw envelope and are unchanged):

| Command | Line or exit |
|---|---|
| `dusk:fill`, `dusk:type` | `effect.verified == false` prints an error naming the value the field holds and exits `1` |
| `dusk:navigate` | `navigated == false` prints `No navigation: ...` |
| `dusk:navigate_back` | `popped == false` prints `Nothing to pop` |
| `dusk:scroll` | `effect.changed == false` prints `nothing moved` |
| `dusk:tap` | a tap on a merged boundary goes to its labelled control and the summary says so (`retargeted`); when it cannot, one stderr warning (`tapPointOutsideOwner`) |
| `dusk:fill`, `dusk:type` | when the field written was the `nearest` one (the ref overlapped no field) a warning names it |
| `dusk:hot_reload_and_snap` | exits `1` when `reloaded` is false (the JSON is still on stdout) |

stderr carries error messages, including the actionability reason
substring on gate failures, and the frame-production banner. The banner
now appears only when dusk could not force frames, and names the real
cause per platform (web: hidden tab and `Page.bringToFront`; desktop:
window hidden, minimised or occluded, or display asleep).

On web with a `cdpPort` in the session, `snap`, `observe`, `tap`, `fill`,
`type`, `navigate`, `scroll` and `press_key` send CDP `Page.bringToFront`
once when the answer carries a web `warnings` block (or the call fails and the
tab reports `hidden`). `snap` and `observe` are then called again; a verb that
acts is not repeated, since its gesture may already have fired, and a stderr
notice tells you to run `dusk:snap`. A CDP failure leaves the first result and
exit code.

**Exit code: 0 on success, 1 on any failure, and `dusk:wait` counts a
condition that never matched as a failure.** It used to print
`✓ Condition matched` and exit 0 on timeout, which made the one command
whose whole job is asserting a post-condition pass on exactly the case it
exists to catch. If a shell loop of yours worked around that, drop the
workaround.

```bash
./bin/fsa dusk:snap > snap.yaml
./bin/fsa dusk:snap --json | jq '.grepLiteral'
./bin/fsa dusk:observe --roles=button --limit=10 | jq '.candidates[].label'
./bin/fsa dusk:tap --ref=e7 --json | jq '.effect.changed'
./bin/fsa dusk:wait --text="Saved" || echo "never appeared"
```

## Commands by family

### See

```bash
./bin/fsa dusk:snap                           # full tree
./bin/fsa dusk:snap --depth=4                 # limit walk depth
./bin/fsa dusk:snap --within=e12              # one region only
./bin/fsa dusk:snap --interactiveOnly         # refs only, no prose
./bin/fsa dusk:snap --grep="Sign ?in"         # matches + the path to them
./bin/fsa dusk:snap --includeEnrichers        # add the Magic / Wind lines under each ref
./bin/fsa dusk:observe --roles=textbox,button --limit=20
./bin/fsa dusk:observe --intent="login fields" --includeEnrichers=full
./bin/fsa dusk:screenshot -o page.jpg
./bin/fsa dusk:screenshot --ref=e7 -o widget.png --format=png
```

`dusk:screenshot` requires `-o <path>` (the CLI writes the decoded
bytes to disk; the JSON `base64` is reserved for the MCP path). The format
follows the extension (`.png`, `.jpg`, `.jpeg`) when `--format` is not
given; an explicit `--format` wins and a mismatch warns on stderr.

### Find

```bash
./bin/fsa dusk:find --text="Submit"
./bin/fsa dusk:find --contains="Sign"
./bin/fsa dusk:find --semanticsLabel="Email field"
./bin/fsa dusk:find --text="Monitors" --within=e12   # scope to one region
./bin/fsa dusk:find --key="ValueKey('login-submit')"
```

Returns `{ "ref": "q3", "matched": true }` or `{ "ref": null, "matched": false }`.

### Click family

```bash
./bin/fsa dusk:tap --ref=e7
./bin/fsa dusk:tap --ref=q3 --no-checkStable                  # for animated targets
./bin/fsa dusk:tap --ref=e7 --snapshot=diff                   # print only the lines the tap changed
./bin/fsa dusk:dblclick --ref=e12
./bin/fsa dusk:right_click --ref=e8
./bin/fsa dusk:triple_click --ref=e15
./bin/fsa dusk:hover --ref=e9                                 # mouse-only
./bin/fsa dusk:drag --fromRef=e5 --toRef=e6
./bin/fsa dusk:tap --ref=e7 --no-retarget                     # tap a merged boundary's centre, not its labelled control
./bin/fsa dusk:tap --ref=e7 --until="Saved"                   # then poll for that text (--untilTimeoutMs, default 3000)
```

### Text input

```bash
./bin/fsa dusk:type --ref=e4 --text="user@example.com"
./bin/fsa dusk:clear --ref=e4
./bin/fsa dusk:press_key --key=Enter
./bin/fsa dusk:press_key --key=G                     # one letter or digit: a shortcut key
./bin/fsa dusk:press_key --key=S --modifiers=control # held before the key, released after it
./bin/fsa dusk:focus --ref=e4
./bin/fsa dusk:blur

./bin/fsa dusk:fill --ref=e4 --text="user@example.com"   # focus + clear + type + settle
./bin/fsa dusk:fill --ref=q3 --text=""                   # clear the field
./bin/fsa dusk:fill --ref=e4 --text="x" --includeSnapshot
```

`dusk:fill` replaces the focus + clear + type + wait sequence and retries
once when the ref goes stale mid-fill, so it is the default for entering
text. `--ref` and `--text` are both mandatory. `--includeSnapshot` defaults
to false on the CLI while the `dusk_fill` MCP tool defaults it to true;
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
./bin/fsa dusk:set_checkbox --ref=e10 --value=true             # idempotent
./bin/fsa dusk:select_option --ref=e11 --value="GMT+3"
```

### Scroll

```bash
./bin/fsa dusk:scroll --ref=e3 --dy=600                         # scroll the list holding e3 down 600px
./bin/fsa dusk:scroll --ref=e3 --dy=-400                        # scroll a specific scrollable up
./bin/fsa dusk:scroll --ref=q5 --intoView                       # bring q5 into view
./bin/fsa dusk:scroll --ref=e3 --dx=300                         # horizontal
./bin/fsa dusk:scroll --ref=e3 --direction=up --pixels=200      # same delta as a signed pair; --dx / --dy win
```

### Wait

```bash
./bin/fsa dusk:wait --text="Saved"
./bin/fsa dusk:wait --textGone="Loading" --timeoutMs=10000
./bin/fsa dusk:wait --expression="Order placed"                 # text presence, not a Dart expression
./bin/fsa dusk:wait_for_network_idle
./bin/fsa dusk:wait_for_network_idle --idleMs=800 --timeoutMs=8000
```

`wait_for_network_idle` requires `fluttersdk_telescope` wired in the
running app; without it, it returns immediately as `matched: true`.

Both waits exit `1` when they never resolved, so `&&` chains stop where
they should. Read the exit code rather than the printed line.

### Navigation

```bash
./bin/fsa dusk:navigate --route=/login
./bin/fsa dusk:navigate_back
./bin/fsa dusk:get_routes
./bin/fsa dusk:modal                                            # dismiss every PopupRoute
./bin/fsa dusk:reset_overlays                                   # pop + Escape + Cancel-tap
```

`dusk:modal` only pops `PopupRoute` subclasses. `dusk:reset_overlays` runs
three escalating layers instead (pop every `PopupRoute`, press Escape, then
tap a Cancel / Dismiss / Close / OK / Done affordance), each a no-op once the
screen is clear, and returns `{popped, escaped, dismissTapped}` so you can
see which layer did the work. It is idempotent, so it is safe to call
speculatively between flows; reach for it when the overlay is not a
`PopupRoute` (a custom `OverlayEntry`, a dropdown menu, a barrier dialog).

### Diagnostics

```bash
./bin/fsa dusk:console
./bin/fsa dusk:console --minLevel=WARNING --limit=20
./bin/fsa dusk:exceptions
./bin/fsa dusk:exceptions --limit=5
./bin/fsa dusk:exceptions --since=2026-11-07T10:00:00Z --clear   # a delta; --clear empties the buffer after the read
```

`dusk:exceptions` works without telescope (dusk keeps its own buffer);
`dusk:console` lists the app's `debugPrint` output and adds telescope entries
when the adapter is wired.

### App control

```bash
./bin/fsa dusk:close_app
```

### Batch

```bash
./bin/fsa dusk:run "tap --ref=q3" "fill --ref=q1 --text=\"a b\"" "snap --grep Total"
./bin/fsa dusk:run --continue "press_key --key=Escape" "snap"
```

Runs several verbs in one process and one VM connection. Each step is a verb
line (a bare verb gets `dusk:`), tokenised like a shell and parsed by that
verb's own options. Output is one `[1/3] tap --ref=q3 ok: <first line>` per
step, then the last step's output. It stops at the first failing step with
`step N failed (exit C): <step>` and that exit code; `--continue` runs them
all and exits with the first non-zero code. Nested `dusk:run`, unknown verbs
and verbs that are not connected (`dusk:resize`, `dusk:device`, `dusk:install`,
`dusk:doctor`) fail as that step. Use `--text`, `--key` or `q<N>` handles
between steps, because `e<N>` refs belong to one snapshot.

### Composite

```bash
./bin/fsa dusk:hot_reload_and_snap
./bin/fsa dusk:hot_reload_and_snap --no-screenshot              # snap + exceptions only
```

### Device emulation (web only, requires `--cdp-port`)

```bash
./bin/fsa dusk:device --list                                    # print presets, no Chrome needed
./bin/fsa dusk:device --preset=iphone-15-pro
./bin/fsa dusk:device --preset=desktop-1440
./bin/fsa dusk:device --reset                                   # clear overrides

./bin/fsa dusk:resize --width=1280 --height=800 --dpr=2.0 --hold &   # keep it while you drive
./bin/fsa dusk:resize --width=390 --height=844 --mobile --touch  # emulate a phone (mobile flag, touch events)
./bin/fsa dusk:resize --reset
```

An `Emulation.*` override lasts only as long as the CDP session that sent
it: `dusk:device` and `dusk:resize` without `--hold` close theirs on exit,
so the page is back at its own size at once (only `dusk:device`'s window
bounds stay). The MCP `dusk_resize_viewport` and `dusk_device_profile`
cannot hold it; `dusk:resize --hold` in the background can.

Launch Chrome with the debug port first: `./bin/fsa start --device=chrome --cdp-port=9222`.

## Performance

```bash
./bin/fsa dusk:perf_begin                                      # attribution mode (default)
./bin/fsa dusk:perf_begin --mode=timing                        # frame timings only, no profiling flag
./bin/fsa dusk:perf_begin --phases                              # also profile layout and paint (attribution mode)
./bin/fsa dusk:tap --ref=e7                                     # drive exactly one interaction
./bin/fsa dusk:perf_end                                        # closes the session, reports insights
./bin/fsa dusk:perf_insight --id=I1                             # drill into one insight's rows

./bin/fsa dusk:perf_run --scenario=perf/login.yaml --label=baseline
#   more: --variant --out --repeat --platform --timing --against --semantics-pass
./bin/fsa dusk:perf_compare build/perf/login-baseline.json build/perf/login-candidate.json
./bin/fsa dusk:perf_trace --out=build/perf/trace.json           # last closed session as Chrome Trace JSON

rm -f .artisan/build.stamp                                      # rebuild a dispatcher a dusk change missed
./bin/fsa dusk:perf_campaign tool/perf/campaign.yaml --platform=chrome --label=base
#   more: --out --only --device --cdp-port --timing --semantics-pass
```

`dusk:perf_insight` and `dusk:perf_trace` take `--token` to name the closed
session they read.

Check `refused` in `dusk:perf_end`'s output first: a session the engine did
not render through (a backgrounded browser tab on web, a hidden window on
desktop; the perf verbs do not force frames) returns no metrics rather
than a report reading all zeros as "fast". `dusk:perf_run` repeats a
scenario from a clean start and writes medians to a file; `dusk:perf_compare`
gates on counts per painted frame, never on raw counts, and exits 1 on an
error-level regression. `dusk:perf_trace` writes to disk because a trace is
too large for a terminal or an agent's context. `dusk:perf_campaign` runs every
scenario of a campaign YAML on one platform, each from a cold start (its
hooks, Android preparation and `after_start` first), retries a failed one,
prints `ok` or `FAILED (see <.err>)` per scenario and exits 1 when any
failed; it starts and stops the app itself, so no app needs to be running.

## Install + doctor (no app required)

```bash
dart run fluttersdk_dusk dusk:install                           # one-time setup
./bin/fsa dusk:doctor                                           # 7 preflight checks
```

`dusk:install` patches `lib/main.dart` (adds `!kReleaseMode` guard +
`DuskPlugin.install()`), scaffolds `./bin/fsa`, registers the provider in
`lib/app/_plugins.g.dart`, and (when `magic_devtools` is in pubspec AND
`lib/main.dart` contains an `await Magic.init(` anchor) injects
`import 'package:magic_devtools/dusk.dart';` and
`MagicDuskIntegration.install()` after `Magic.init()`. Idempotent.

`dusk:doctor` checks:

1. Hot-restart staleness (Chrome PID drift)
2. `DUSK_DISABLE` env-var
3. Enricher count (`DuskPlugin.enrichers.length`)
4. `semanticsEnabled` (the only check that exits non-zero on failure)
5. Magic-init detection in `lib/main.dart`
6. Session ownership: does `state.json` describe THIS project? `~/.artisan/
   state.json` is one global slot, so a sibling project's `artisan start`
   takes it over and every `dusk:*` call from here drives that app instead,
   succeeding each time.
7. CDP session health: is the recorded `cdpPort` live, does it serve a page
   on this run's web port (an orphan browser from a killed run does not), and
   is that page visible (a hidden one stops frame production).

Reach for `dusk:doctor` FIRST whenever dusk behaves strangely. Checks 6 and 7
cover the two failures that look exactly like a broken driver or a broken app
and are neither.

## Exit codes and pipeline patterns

```bash
# Retry until idle
until ./bin/fsa dusk:wait_for_network_idle --timeoutMs=2000; do
  sleep 1
done

# Bail on first gate failure
set -e
./bin/fsa dusk:tap --ref=e7

# Capture both stdout and stderr for an agent log
./bin/fsa dusk:tap --ref=e7 >result.json 2>error.txt

# Snap as YAML to disk for diffing
./bin/fsa dusk:snap > /tmp/snap-before.yaml
./bin/fsa dusk:tap --ref=e7
./bin/fsa dusk:snap > /tmp/snap-after.yaml
diff /tmp/snap-before.yaml /tmp/snap-after.yaml

# Or let dusk diff for you: only the lines the tap changed since the last snap
./bin/fsa dusk:snap > /dev/null
./bin/fsa dusk:tap --ref=e7 --snapshot=diff
```

## MCP-only: there is no CLI for evaluate

`dusk_evaluate` has no CLI mirror. From a shell, use `./bin/fsa tinker`
(the dusk-aware connected Dart REPL):

```bash
./bin/fsa tinker --eval="MyService.instance.state.toString()"
```

Or open the interactive REPL: `./bin/fsa tinker`.
