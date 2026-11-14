<p align="center">
  <img src="https://raw.githubusercontent.com/anilcancakir/tapir/master/.github/tapir-logo.svg" width="120" alt="Tapir logo" />
</p>

<h1 align="center">Tapir</h1>

<p align="center">
  <strong>Give your AI agent eyes and hands on a running Flutter app.</strong><br/>
  Snapshot the Semantics tree, tap, type, scroll, screenshot and profile the live app from one CLI and one MCP server, with no flutter_test harness and no test file between actions.
</p>

<p align="center">
  <a href="https://pub.dev/packages/tapir"><img src="https://img.shields.io/pub/v/tapir.svg" alt="pub package"></a>
  <a href="https://github.com/anilcancakir/tapir/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/anilcancakir/tapir/ci.yml?branch=master&label=CI" alt="CI"></a>
  <a href="https://codecov.io/gh/anilcancakir/tapir"><img src="https://codecov.io/gh/anilcancakir/tapir/graph/badge.svg" alt="codecov"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://pub.dev/packages/tapir/score"><img src="https://img.shields.io/pub/points/tapir" alt="pub points"></a>
</p>

<p align="center">
  <a href="https://anilcancakir.com/tapir">Documentation</a> ·
  <a href="https://pub.dev/packages/tapir">pub.dev</a> ·
  <a href="https://github.com/anilcancakir/tapir/issues">Issues</a>
</p>

## At a glance

| Fact | Value |
|---|---|
| Package | [`tapir`](https://pub.dev/packages/tapir) |
| Install | `dart pub add tapir`, then `dart run tapir tapir:install` |
| Import | `package:tapir/tapir.dart` (`TapirPlugin.install()`, behind `if (!kReleaseMode)`) |
| Entry points | `dart run tapir <command>`, `./bin/dowel <command>`, `TapirPlugin.install()`, `TapirPlugin.enrichers`, `TapirDowelProvider` (`package:tapir/cli.dart`), `dart run tapir mcp:serve` |
| Platforms | Any Flutter target that exposes a VM Service in a debug or profile build: Android, iOS, web, macOS, Windows, Linux; viewport and device emulation need Chrome with a CDP port |
| Requires | Dart 3.13, Flutter 3.47; a plugin of [`dowel`](https://pub.dev/packages/dowel) (`^0.0.21`) |
| Dependencies | `dowel`, `image`, `meta`, `wind_kit_diagnostics_contracts`, `yaml`, the Flutter SDK |
| License | MIT |

## Install

```bash
dart pub add tapir
dart run tapir tapir:install
dart run tapir start --device=macos   # dowel records the session every tapir:* command dials
dart run tapir tapir:snap
```

`tapir:install` patches `lib/main.dart` (the import, `WidgetsFlutterBinding.ensureInitialized()` when missing, and `TapirPlugin.install()` inside a `!kReleaseMode` guard), then scaffolds the fast `./bin/dowel` wrapper and registers tapir as a dowel plugin. Re-running it changes nothing. The [installation guide](https://anilcancakir.com/tapir/docs/getting-started/installation) also adds `dowel` as a direct dependency (`dart pub add dowel`). Wired by hand, `main.dart` looks like this:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tapir/tapir.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode) {
    TapirPlugin.install();
  }
  runApp(const MyApp()); // MyApp is the host app's root widget.
}
```

The guard is `!kReleaseMode`, not `kDebugMode`: debug and profile builds carry tapir (`tapir:perf_run` measures a profile build) and a release build tree-shakes it. Without the guard tapir ships in release, and anyone who reaches that app's VM Service can drive it. `--dart-define=TAPIR_DISABLE=1` skips registration in a build that must not expose the extensions. The [`example/`](example/) app gives each verb a live target widget.

## Snapshot and refs

```bash
dart run tapir tapir:snap --interactiveOnly
# - textbox "Email" [ref=e1]
#   typeable: true
# - button "Sign in" [ref=e2]
```

| Token | Minted by | Lifetime |
|---|---|---|
| `e<N>` | `tapir:snap` | The same Semantics node keeps its token across snapshots, and a token outlives its widget. A ref whose element left the tree is relocated by label (`reresolved` on the response) only when the snapshot recorded a binding for it, the live tree has the same number of nodes with that label and the match sits on the route the ref was minted on; otherwise it fails as `defunct` and you re-snap |
| `q<N>` | `tapir:find`, `tapir:observe` | Re-resolved against the live tree on every action, like a Playwright Locator; survives rebuilds |

Narrow a read with `--within=<eN>`, `--interactiveOnly` and `--grep=<regex>`; they compose. `--includeEnrichers` adds Wind state (the host calls `Wind.installDebugResolver()` from `wind_kit`, read through `wind_kit_diagnostics_contracts`) and Magic state (`MagicTapirIntegration.install()` from `magic_devtools`, after `Magic.init()`; see [Magic integration](https://anilcancakir.com/tapir/docs/plugins/magic-integration)). A ref line ending in `[offscreen]` or `[occluded]` names why an action would fail before you try it.

## Actions and the actionability gate

```bash
dart run tapir tapir:tap --ref=e2 --snapshot=diff
dart run tapir tapir:fill --ref=e1 --text="ada@example.com" --json
```

Gestures (`tap`, `hover`, `drag`, `scroll`, `dblclick`, `right_click`, `triple_click`) and text verbs (`type`, `clear`, `fill`, `press_key`) dispatch real pointer and key events into the widget tree. `tap`, `hover`, `drag`, the click variants, `type`, `clear` and `fill` first pass the gate, in a fixed order, and a refusal names the reason an agent can branch on:

| Check | Refusal substring | Recovery |
|---|---|---|
| Defunct (preflight) | `defunct (...)` | Re-snap |
| Enabled | `not enabled` | Re-snap; the widget may enable later |
| Zero rect | `zero rect` | Re-snap or re-find |
| Off-viewport (scrolls into view first) | `off-viewport` | `tapir:scroll` into view, then retry |
| Stable across two frames | `not stable` | Wait for the animation; `--no-checkStable` |
| Receives events (hit test) | `obscured by` | Dismiss the overlay (`tapir:reset_overlays`); `--no-checkReceivesEvents` |

A green tick is dispatch, not effect. Add `--json` to print the whole response and read the `effect` block: `effect.changed` for `tap` and `scroll`, `effect.verified` and `effect.value` for `type`, `fill` and `clear`. When the hit test could not answer (routine on a web debug build) the response of a gated verb such as `tap` or `type` carries a `checks` block with `receivesEvents: indeterminate` instead of a silent pass; `fill` reports only its `effect`. `tapir:run "tap --ref=e5" "snap --grep Counter"` batches verbs into one round trip.

## Waiting and observing

```bash
dart run tapir tapir:observe --roles=button,textbox   # q<N> handles, re-resolved per action
dart run tapir tapir:wait --text="Welcome back" --timeoutMs=5000
```

| Verb | Returns |
|---|---|
| `tapir:wait` | Waits for `--text`, `--textGone` or `--expression` |
| `tapir:wait_for_network_idle` | Waits until in-flight HTTP requests stay at zero for `--idleMs` |
| `tapir:observe` | A flat candidate list of interactive widgets with `q<N>` handles: observe once, act many times (Stagehand's pattern, no model call inside tapir) |
| `tapir:console`, `tapir:exceptions` | In-app `debugPrint` output and `FlutterError`s, overflow included; `--since=<iso8601>` scopes errors to one action |
| `tapir:get_routes` | The router's location and the top page (`tapir:navigate` and `tapir:navigate_back` change it) |

When the app is not producing frames (a hidden window or a backgrounded tab) tapir forces frames outside the web and reports `framesForced: true`; where it cannot, every response carries a `warnings` block rather than a stale answer that looks fresh. See [frame production](https://anilcancakir.com/tapir/docs/reference/frame-production).

## Screenshots and web

```bash
dart run tapir tapir:screenshot --output=shot.jpg
dart run tapir start --device=chrome --cdp-port=9333
dart run tapir tapir:device --preset=pixel-8
```

| Surface | Behaviour |
|---|---|
| `tapir:screenshot` | JPEG (default) or PNG of the viewport, or of one widget with `--ref` (and a sub-rect of it with `--rect`) |
| Web screenshot | With `--cdp-port`, the CLI captures through CDP `Page.captureScreenshot`; the `tapir_screenshot` MCP tool stays in-isolate and can time out under CanvasKit, so prefer the CLI on web |
| `tapir:device` | Presets `iphone-x`, `iphone-13`, `iphone-15-pro`, `pixel-5`, `pixel-8`, `ipad-pro-12.9`, `desktop-1440`, `desktop-1920` (viewport, DPR, touch, user agent); the emulation ends with the command, the window size stays. `tapir:resize --width --height` overrides the viewport until exit, or longer with `--hold` |
| `tapir:hot_reload_and_snap` | Hot reload, then snapshot, screenshot and recent exceptions in one round trip |

## Performance tracing

```bash
dart run tapir tapir:perf_begin --mode=attribution
dart run tapir tapir:tap --ref=e7
dart run tapir tapir:perf_end
```

| Verb | Does |
|---|---|
| `tapir:perf_begin`, `tapir:perf_end` | Bracket one interaction; `attribution` ranks the widget builds that cost time next to Wind and Magic counters, `timing` reports frame timings you can quote. A session in which the engine rendered nothing is refused (`refused: true`, exit `1`), never reported as zeros that read as fast |
| `tapir:perf_insight` | The rows behind one insight of the last report |
| `tapir:perf_run`, `tapir:perf_compare`, `tapir:perf_campaign` | Repeat a scenario from a clean start and write medians, judge one run against another, run a campaign of scenarios from cold starts |
| `tapir:perf_trace --out=trace.json` | The last session as a Chrome Trace JSON for `ui.perfetto.dev` |

## MCP server and clients

The `tapir_*` tools ride on the `dowel` MCP server, so the client config key is `dowel`. `dart run tapir mcp:install` writes the entry into `.mcp.json`: `./bin/dowel mcp:serve` when the fast wrapper exists and `dart run tapir mcp:serve` otherwise. Standard config for any client that reads `.mcp.json`:

```json
{ "mcpServers": { "dowel": { "command": "./bin/dowel", "args": ["mcp:serve"], "cwd": "." } } }
```

| Client | Install |
|---|---|
| Claude Code | `claude mcp add dowel -- ./bin/dowel mcp:serve`, then `/mcp reconnect dowel` after a change |
| VS Code | `code --add-mcp '{"name":"dowel","type":"stdio","command":"dart","args":["run","tapir","mcp:serve"]}'` |
| Cursor | `.cursor/mcp.json` (project) or `~/.cursor/mcp.json` (user) |
| Windsurf | `~/.codeium/windsurf/mcp_config.json` |
| Goose, Warp | Paste the standard config into Goose (Advanced settings, Extensions, Add custom extension) or Warp (Settings, AI, Manage MCP Servers) |
| Claude Desktop | `claude_desktop_config.json` (macOS: `~/Library/Application Support/Claude/`, Windows: `%APPDATA%\Claude\`) |
| Codex | `codex mcp add dowel ./bin/dowel mcp:serve` |

| Without tapir | With tapir |
|---|---|
| You hot reload, screenshot, drag the PNG into the chat, paste widget source and ask why the button does nothing. | The agent calls `tapir_snap`, then `tapir_tap` on `e7`; the gate checks the button, the tap lands, a fresh snap confirms it. |
| You add `Future.delayed` and re-run to tell a timing issue from a bug. | The gate refuses with a reason (`not stable`, `obscured by`, `off-viewport`) that names the cause. |

## For AI coding agents

| Do | Because |
|---|---|
| Install tapir only behind `if (!kReleaseMode)` | Anyone who reaches the VM Service of a build that carries tapir can drive the app |
| Start the app with `dart run tapir start`, not `flutter run` | Every `tapir:*` command dials the session dowel records |
| Snap again after a navigation or rebuild, or use a `q<N>` handle from `tapir:find` | `e<N>` refs are frozen to the snapshot that minted them |
| Narrow a snapshot with `--within`, `--interactiveOnly` or `--grep` | A full tree costs context, and a sidebar that repeats page labels misleads an exact-label lookup |
| Read `effect` (and `checks` when present) before trusting a green tick | A tick says the event left tapir, not that the widget took it |
| Branch on the leading refusal substring, never on the trailing detail | The substrings and the gate order are a frozen contract; the detail is not |
| Read `framesForced` and `warnings` on a response that looks empty | A hidden window or tab stops frames, and the tree then reads as a broken screen |
| Check `refused` first on a `tapir:perf_end` report | A refused session carries no metrics |
| Point the MCP client at the `dowel` key and reconnect after `mcp:install` | The tools ride on the dowel server, and clients do not reload an entry on their own |

## Dependencies

`dowel` for the CLI, the MCP server and the VM Service connection; `wind_kit_diagnostics_contracts` to read Wind state without depending on Wind; `image` for screenshot encoding; `yaml` and `meta`. The rest is the Flutter SDK.

## Links

- [Documentation](https://anilcancakir.com/tapir/docs/getting-started/installation): installation, quickstart, every command, MCP setup, the actionability gate, Magic and Wind integration, and the [MCP tool reference](https://anilcancakir.com/tapir/docs/mcp/tool-reference)
- [API reference](https://pub.dev/documentation/tapir/latest/)
- [llms.txt](llms.txt) and the [agent skill](skills/tapir/SKILL.md) for AI coding agents: `npx skills add anilcancakir/tapir`
- [Changelog](CHANGELOG.md), [report an issue](https://github.com/anilcancakir/tapir/issues), [security policy](https://github.com/anilcancakir/tapir/security/policy)

## License

MIT, see [LICENSE](LICENSE). Built by [Anılcan Çakır](https://anilcancakir.com).
