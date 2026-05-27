# CLI commands reference

Every `dusk_*` MCP tool has a matching `dusk:*` CLI command. Same params,
same return shape (JSON via stdout on success, JSON via stderr on error,
non-zero exit code on failure). Use the CLI from Bash when:

- The agent is wired to a shell, not an MCP client.
- The action's output should be redirected to a file (`> snapshot.yaml`).
- The action is part of a shell pipeline (`./bin/fsa dusk:snap | yq '.snapshot'`).
- A retry loop with `until` / `while` reads the exit code.

For interactive agent loops, MCP is faster (no process spawn per call).

## Entry points

| Form | Startup | When to use |
|---|---|---|
| `./bin/fsa <cmd>` | ~110ms warm AOT | Default; what `dusk:install` scaffolds |
| `dart run fluttersdk_dusk <cmd>` | ~3s cold | When `./bin/fsa` is missing |
| `dart run fluttersdk_artisan <cmd>` | ~3s cold | Substrate-level commands without dusk |

`./bin/fsa` auto-rebuilds when stale (4-condition check); manual force
rebuild: `rm -rf .artisan/cli-bundle .artisan/build.stamp && ./bin/fsa list`.

## Common flags across commands

| Flag | Default | Meaning |
|---|---|---|
| `--ref=<eN\|qN>` | (required) | Target widget for click / text / focus / checkbox |
| `--checkStable` / `--no-checkStable` | true | Skip the 2-frame stability check |
| `--checkReceivesEvents` / `--no-checkReceivesEvents` | true | Skip the hit-test check |
| `--includeSnapshot` / `--no-includeSnapshot` | true (actions), false (reads) | Append post-action snapshot |
| `--timeoutMs=<ms>` | 5000 | Hard timeout for waits |
| `--format=<jpeg\|png>` | jpeg | Screenshot encoding |

CLI option names match MCP `inputSchema` property names verbatim
(camelCase: `--checkStable`, `--includeSnapshot`, `--timeoutMs`,
`--startRef`, etc.). The CLI does no key translation between the two
surfaces.

## Output

stdout shape depends on the command:

- **JSON payload** on read / query verbs: `dusk:snap`, `dusk:observe`,
  `dusk:find`, `dusk:get_routes`, `dusk:console`, `dusk:exceptions`,
  `dusk:wait`, `dusk:wait_for_network_idle`, `dusk:hot_reload_and_snap`.
  These mirror the MCP response shape and are safe to pipe through `jq`.
- **One-line human summary** on side-effect verbs by default:
  `dusk:tap`, `dusk:hover`, `dusk:drag`, `dusk:type`, `dusk:clear`,
  `dusk:press_key`, `dusk:scroll`, `dusk:focus`, `dusk:blur`,
  `dusk:dblclick`, `dusk:right_click`, `dusk:triple_click`,
  `dusk:set_checkbox`, `dusk:select_option`, `dusk:navigate`,
  `dusk:navigate_back`, `dusk:modal`, `dusk:close_app`. Pass
  `--includeSnapshot` to receive JSON containing the post-action
  snapshot.
- **Bytes to disk** for `dusk:screenshot` (always requires `-o <path>`;
  prints `Wrote N bytes (K KB, format) to <path>`).
- **Categorised report** for `dusk:install` and `dusk:doctor`.

stderr carries error messages, including the actionability reason
substring on gate failures. Exit code: 0 on success, 1 on any failure.

For pipeline use, prefer the JSON-emitting verbs:

```bash
./bin/fsa dusk:snap | jq -r '.snapshot' > snap.yaml
./bin/fsa dusk:observe --roles=button --limit=10 | jq '.candidates[].label'
./bin/fsa dusk:tap --ref=e7 --includeSnapshot | jq '.snapshot'  # force JSON
```

## Commands by family

### See

```bash
./bin/fsa dusk:snap                           # full tree
./bin/fsa dusk:snap --depth=4                 # limit walk depth
./bin/fsa dusk:observe --roles=textbox,button --limit=20
./bin/fsa dusk:observe --intent="login fields" --includeEnrichers=full
./bin/fsa dusk:screenshot -o page.jpg
./bin/fsa dusk:screenshot --ref=e7 -o widget.png --format=png
```

`dusk:screenshot` requires `-o <path>` (the CLI writes the decoded
bytes to disk; the JSON `base64` is reserved for the MCP path).

### Find

```bash
./bin/fsa dusk:find --text="Submit"
./bin/fsa dusk:find --contains="Sign"
./bin/fsa dusk:find --semanticsLabel="Email field"
./bin/fsa dusk:find --key="ValueKey('login-submit')"
```

Returns `{ "ref": "q3", "matched": true }` or `{ "ref": null, "matched": false }`.

### Click family

```bash
./bin/fsa dusk:tap --ref=e7
./bin/fsa dusk:tap --ref=q3 --no-checkStable                  # for animated targets
./bin/fsa dusk:dblclick --ref=e12
./bin/fsa dusk:right_click --ref=e8
./bin/fsa dusk:triple_click --ref=e15
./bin/fsa dusk:hover --ref=e9                                 # mouse-only
./bin/fsa dusk:drag --startRef=e5 --endRef=e6
```

### Text input

```bash
./bin/fsa dusk:type --ref=e4 --text="user@example.com"
./bin/fsa dusk:clear --ref=e4
./bin/fsa dusk:press_key --key=Enter
./bin/fsa dusk:press_key --key=Tab --modifiers=shift
./bin/fsa dusk:focus --ref=e4
./bin/fsa dusk:blur
```

### Form controls

```bash
./bin/fsa dusk:set_checkbox --ref=e10 --value=true             # idempotent
./bin/fsa dusk:select_option --ref=e11 --value="GMT+3"
```

### Scroll

```bash
./bin/fsa dusk:scroll --dy=600                                  # scroll root down 600px
./bin/fsa dusk:scroll --ref=e3 --dy=-400                        # scroll a specific scrollable up
./bin/fsa dusk:scroll --ref=q5 --intoView                       # bring q5 into view
```

### Wait

```bash
./bin/fsa dusk:wait --text="Saved"
./bin/fsa dusk:wait --textGone="Loading" --timeoutMs=10000
./bin/fsa dusk:wait_for_network_idle
./bin/fsa dusk:wait_for_network_idle --idleMs=800 --timeoutMs=8000
```

`wait_for_network_idle` requires `fluttersdk_telescope` wired in the
running app; without it, it returns immediately as `matched: true`.

### Navigation

```bash
./bin/fsa dusk:navigate --route=/login
./bin/fsa dusk:navigate_back
./bin/fsa dusk:get_routes
./bin/fsa dusk:modal                                            # dismiss every PopupRoute
```

### Diagnostics

```bash
./bin/fsa dusk:console
./bin/fsa dusk:console --minLevel=WARNING --limit=20
./bin/fsa dusk:exceptions
./bin/fsa dusk:exceptions --limit=5
```

Empty arrays when telescope is not wired.

### App control

```bash
./bin/fsa dusk:close_app
```

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

./bin/fsa dusk:resize --width=1280 --height=800 --dpr=2.0
./bin/fsa dusk:resize --reset
```

Launch Chrome with the debug port first: `./bin/fsa start --device=chrome --cdp-port=9222`.

## Install + doctor (no app required)

```bash
dart run fluttersdk_dusk dusk:install                           # one-time setup
./bin/fsa dusk:doctor                                           # 5 preflight checks
```

`dusk:install` patches `lib/main.dart` (adds `kDebugMode` guard +
`DuskPlugin.install()`), scaffolds `./bin/fsa`, registers the provider in
`lib/app/_plugins.g.dart`, and (when magic is in pubspec) injects
`MagicDuskIntegration.install()` after `Magic.init()`. Idempotent.

`dusk:doctor` checks:

1. Hot-restart staleness (Chrome PID drift)
2. `DUSK_DISABLE` env-var
3. Enricher count (`DuskPlugin.enrichers.length`)
4. `semanticsEnabled` (the only check that exits non-zero on failure)
5. Magic-init detection in `lib/main.dart`

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
./bin/fsa dusk:snap | jq -r '.snapshot' > /tmp/snap-before.yaml
./bin/fsa dusk:tap --ref=e7
./bin/fsa dusk:snap | jq -r '.snapshot' > /tmp/snap-after.yaml
diff /tmp/snap-before.yaml /tmp/snap-after.yaml
```

## MCP-only: there is no CLI for evaluate

`dusk_evaluate` has no CLI mirror. From a shell, use `./bin/fsa tinker`
(the dusk-aware connected Dart REPL):

```bash
./bin/fsa tinker --eval="MyService.instance.state.toString()"
```

Or open the interactive REPL: `./bin/fsa tinker`.
