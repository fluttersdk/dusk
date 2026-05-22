<p align="center">
  <img src="https://raw.githubusercontent.com/fluttersdk/magic/master/.github/magic-logo.svg" width="120" alt="Dusk Logo" />
</p>

<h1 align="center">Dusk</h1>

<p align="center">
  <strong>End-to-end driver for Flutter apps. Read by humans, driven by AI agents.</strong><br/>
  Snapshot the Semantics tree, drive any gesture, capture screenshots, observe live state, all from one CLI and one stdio MCP server.
</p>

<p align="center">
  <a href="https://github.com/fluttersdk/dusk/actions"><img src="https://img.shields.io/github/actions/workflow/status/fluttersdk/dusk/ci.yml?branch=develop&label=CI" alt="CI"></a>
  <a href="https://pub.dev/packages/fluttersdk_dusk"><img src="https://img.shields.io/pub/v/fluttersdk_dusk.svg" alt="pub package"></a>
  <a href="https://pub.dev/packages/fluttersdk_dusk/score"><img src="https://img.shields.io/pub/points/fluttersdk_dusk" alt="pub points"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://github.com/fluttersdk/dusk/stargazers"><img src="https://img.shields.io/github/stars/fluttersdk/dusk?style=flat" alt="GitHub stars"></a>
</p>

<p align="center">
  <a href="https://fluttersdk.com/dusk">Documentation</a> ·
  <a href="https://pub.dev/packages/fluttersdk_dusk">pub.dev</a> ·
  <a href="https://github.com/fluttersdk/dusk/issues">Issues</a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/fluttersdk/dusk/main/screenshots/demo.gif" width="640" alt="Dusk demo: snap, tap, screenshot in one round-trip" />
</p>

<!-- TODO(v0.0.2-followup): record screenshots/demo.gif (320px wide, 8s, ~2MB). Sequence: dusk:snap (YAML appears) -> dusk:tap --ref=e7 (counter increments) -> dusk:screenshot (PNG saves). Capture tool: Kap (macOS) / ScreenToGif (Windows). Per dart.dev/tools/pub/pubspec#screenshots GIFs are supported in pubspec screenshots: too (since the 2023 fix); add there once the asset exists. -->

---

> [!NOTE]
> Requires Dart SDK >= 3.4.0 and Flutter >= 3.22.0. dusk is debug-only: production builds tree-shake the entire driver across web, desktop, and mobile.

## Pick your path

Choose the entry point that matches your workflow. The same `ext.dusk.*` extensions back every column.

| | Best for | Install |
|---|---|---|
| **Dusk in your app** | Hot-reload integration tests + agent-driven walkthroughs | `flutter pub add fluttersdk_dusk` then `dart run fluttersdk_dusk dusk:install` (the CLI patches `lib/main.dart` automatically, gated by `kDebugMode`; idempotent). |
| **Dusk CLI** | Drive a running app from the terminal (CI + local QA) | `dart run fluttersdk_dusk dusk:snap` |
| **Dusk MCP** | Claude Code, Cursor, Windsurf, Codex, Goose, VS Code Copilot, Warp, Claude Desktop | `dart run fluttersdk_artisan mcp:install` (writes `.mcp.json`) |
| **Dusk via IDE** | One-click MCP install in VS Code, Cursor, Goose | See [§ MCP install: 8 clients](#mcp-install-8-clients) for badges |

Manual wiring, Magic-stack integration, and the full per-command flag reference live in the [Getting Started guide](https://fluttersdk.com/dusk/getting-started).

> [!TIP]
> **fastcli** is the AOT-compiled artisan dispatcher (~110ms warm) shipped as `./bin/fsa`. It is auto-scaffolded the first time you run `dart run fluttersdk_artisan install`. After that, every `./bin/fsa <cmd>` is the fast path. Skipping fastcli is fine: every command also runs as `dart run fluttersdk_dusk <cmd>` with the same surface, ~3s slower per call.

## Why Dusk?

End-to-end testing on Flutter has always been a stitched-together ritual. `flutter_driver` ships a one-off socket protocol that does not survive hot restart. `integration_test` runs in-process against a simulated `WidgetTester`, but you write a test file, build, run, and wait. AI coding agents that want to drive the running app reach for ad hoc `flutter test` invocations, copy stack traces back into the prompt, and paste screenshots back, calling it a workflow.

**Dusk closes that loop.** A single VM Service extension family (`ext.dusk.*`), a single CLI namespace (`dusk:*`), and a single stdio MCP server back **32 CLI commands** and **31 MCP tools** (28 `ext.dusk.*` + 3 `artisan:dusk:*` substrate-routed). The same contracts power human-driven terminal calls and agent-driven MCP tool calls: `dusk:tap --ref=e7` (CLI) and `dusk_tap` (MCP) reach the exact same code path. No test harness, no test file, no build step. Attach to the live app and the agent has eyes (`dusk_snap`, `dusk_screenshot`, `dusk_observe`) and hands (`dusk_tap`, `dusk_type`, `dusk_scroll`, `dusk_drag`).

| Tool | What it does | Where Dusk fits |
|---|---|---|
| **[integration_test](https://pub.dev/packages/integration_test)** (Flutter SDK) | In-process `WidgetTester` wrapper; runs tests via `flutter drive` | Different niche: integration_test owns the *authored test file*; Dusk owns the *unscripted running app*. Use both. |
| **[patrol](https://pub.dev/packages/patrol)** (Leancode, 694 likes) | Native UI permissions + dialogs layered on `integration_test` | Orthogonal: patrol owns *authored tests with native dialogs*; Dusk owns *unscripted automation by humans and AI agents*. |
| **[flutter_driver](https://pub.dev/packages/flutter_driver)** (Flutter SDK, legacy) | One-off socket protocol; being phased out | Dusk is hot-restart safe via `registerExtensionIdempotent` (16 aggregator register functions), one contract for CLI and MCP, no test harness, no separate isolate. |
| **[maestro](https://github.com/mobile-dev-inc/maestro)** (13.7K stars) | YAML DSL over OS accessibility layer | Dusk drives the Flutter widget tree directly (Semantics nodes + RenderObjects); no Flutter Desktop limitation; zero YAML to author. |
| **[mcp_flutter](https://github.com/Arenukvern/mcp_flutter)** (298 stars) | Flutter MCP toolkit with `fmt_*` tools | Dusk is on pub.dev with verified publisher, framework-native Artisan plugin, `e<N>` and `q<N>` ref system, 6-step actionability gate. |
| **[playwright-mcp](https://github.com/microsoft/playwright-mcp)** (33K stars) | Browser MCP via accessibility tree + `[ref=eN]` tokens | The Flutter-native equivalent. Dusk's `q<N>` handles mirror Playwright's `getByRole()`; `dusk_observe` borrows Stagehand's observe-once-act-many pattern, ported to Flutter Semantics. |

## Features

| | Feature | Description |
|:--|:--------|:------------|
| 🌳 | **Semantics Snapshot** | `dusk_snap` emits a YAML tree with stable `[ref=eN]` tokens; every action targets a ref, no brittle XPath or coordinate guessing |
| 🛠️ | **32 CLI Commands** | snap, tap, type, drag, scroll, hover, dblclick, right_click, triple_click, focus, blur, clear, set_checkbox, select_option, press_key, wait, find, observe, navigate, modal, screenshot, hot_reload_and_snap, CDP resize + device, close_app, install, doctor |
| 🤖 | **31 MCP Tools** | The full CLI surface plus `dusk_evaluate`, exposed as stdio JSON-RPC tools to Claude Code, Cursor, Windsurf, VS Code Copilot, and any MCP-compatible agent |
| 🚪 | **6-Step Actionability Gate** | Every gesture passes defunct (preflight) → enabled → zero-rect → off-viewport (auto-scrolls) → stable (2-frame rect drift) → receives-events (hit-test path); no flaky taps |
| 🔖 | **Playwright-style Locators** | `q<N>` re-resolvable handles via `dusk_find` walk the live Semantics tree on every action. Stale handles throw, never silently act on the wrong widget |
| 🔄 | **Hot Reload + Snap Round-trip** | `dusk_hot_reload_and_snap` returns `{reloaded, durationMs, snapshot, screenshot, exceptions}` in one call |
| 🖥️ | **CDP Device Emulation** | `dusk_resize_viewport` and `dusk_device_profile` (iphone-x, pixel-5, desktop-1440, plus 5 more) drive Chrome DevTools Protocol |
| 🎨 | **Snapshot Enricher Plug-in** | `DuskPlugin.enrichers.add()` lets `magic` and `wind` add framework-specific YAML fragments via a frozen `String? Function(Element, RefRegistry)` contract |
| 🔒 | **Debug-Only Tree-Shake** | Consumer wraps `DuskPlugin.install()` in `kDebugMode`; release builds tree-shake the entire driver across web, desktop, and mobile |

> [!IMPORTANT]
> `DuskPlugin.install()` must be wrapped in `if (kDebugMode) { ... }` at the call site in `lib/main.dart`. Release builds tree-shake the entire driver across web (dart2js), desktop (dart2native), and mobile (AOT), but only when the guard exists. Without the guard, dusk ships into release binaries.

## MCP install: 8 clients

Dusk is the first Flutter MCP server focused on **UI automation** (tap, snap, screenshot, observe) rather than runtime telemetry. The 31 `dusk_*` tools surface to any MCP-compatible agent.

> [!NOTE]
> Configs below use `./bin/fsa` (the fastcli wrapper, see top of README). If fastcli is not scaffolded yet, swap `./bin/fsa mcp:serve` for `dart run fluttersdk_dusk mcp:serve` in every client row.

**Standard config** (any client that reads `.mcp.json` in the project root):

```jsonc
{
  "mcpServers": {
    "fluttersdk": {
      "command": "./bin/fsa",
      "args": ["mcp:serve"],
      "cwd": "."
    }
  }
}
```

| Client | Install |
|---|---|
| **Claude Code** | `claude mcp add fluttersdk -- ./bin/fsa mcp:serve` |
| **VS Code** | `code --add-mcp '{"name":"fluttersdk","command":"./bin/fsa","args":["mcp:serve"]}'`, or drop the standard config into `.vscode/mcp.json` |
| **Cursor** | Settings > MCP > Add new MCP Server, or drop the standard config into `~/.cursor/mcp.json` |
| **Windsurf** | Drop the standard config into `~/.codeium/windsurf/mcp_config.json` |
| **Goose** | Advanced settings > Extensions > Add custom extension; paste the standard config |
| **Warp** | Settings > AI > Manage MCP Servers, or `/add-mcp` slash command with the standard config |
| **Claude Desktop** | Edit `claude_desktop_config.json` (macOS: `~/Library/Application Support/Claude/`, Windows: `%APPDATA%\Claude\`) and add the standard config under `mcpServers` |
| **Codex** | `codex mcp add fluttersdk ./bin/fsa mcp:serve` |

### Before / after

| Without Dusk | With Dusk |
|---|---|
| You hot-reload, screenshot the result, drag the PNG into Claude, type "the counter button should be tappable but isn't, what's wrong?", scroll, copy the relevant widget source, paste back. | Claude calls `dusk_snap` and reads the YAML tree with `[ref=eN]` tokens. Claude calls `dusk_tap --ref=e7`, the gate fires, the counter increments, Claude verifies via a fresh snap. Loop closes without you in the middle. |
| You wonder if the failing test is a timing issue or a real bug. You add `Future.delayed(Duration(seconds: 2))` and re-run. | The 6-step actionability gate fires before every gesture: defunct, not enabled, zero rect, off-viewport, not stable, obscured by another widget. Errors carry agent-parseable reason strings. |

### Typical agent session

```
[agent] artisan_start { device: macos }            # launch the app
[agent] dusk_snap {}                                # semantic tree with stable refs
[agent] dusk_observe {}                             # structured candidate list (Stagehand-style)
[agent] dusk_tap { ref: "e7" }                      # tap a button by ref
[agent] dusk_screenshot { format: "jpeg" }          # verify visually
[agent] dusk_hot_reload_and_snap {}                 # reload + snap in one round-trip
[agent] artisan_stop                                # tear down
```

Full per-tool input schemas + example calls in the [MCP tool reference](https://fluttersdk.com/dusk/mcp/tool-reference). For agents that read structured project context at attach time, the canonical entry point is [`llms.txt`](https://fluttersdk.com/dusk/llms.txt); it lists the 31 MCP tool names inline, plus the command surface, ref token grammar, and 6-step actionability vocabulary. The site serves the bare URLs to humans and the same paths with a `.md` suffix to LLM agents (e.g. `https://fluttersdk.com/dusk/getting-started.md`).

## Examples

The [`example/`](example/) directory ships a vanilla Flutter showroom that gives every CLI command a live target widget on one route: TextField, Dropdown, Checkbox, Switch, counter button, Draggable + DragTarget, dialog, bottom sheet, 30 ListTile rows for scrolling, and navigation buttons across three named routes.

```bash
cd example && flutter pub get
dart run fluttersdk_dusk start --device=macos
```

## Documentation

Full docs with live examples at **[fluttersdk.com/dusk](https://fluttersdk.com/dusk)**: commands catalog, MCP tool reference, the 6-step actionability reference, Magic and Wind integration guides, and the snapshot enricher authoring guide. The internal architecture lives in [`ARCHITECTURE.md`](ARCHITECTURE.md) for contributors.

## Contributing

```bash
git clone https://github.com/fluttersdk/dusk.git
cd dusk && flutter pub get
flutter test && dart analyze
```

CI enforces 80%+ line coverage on `lib/` on every push to develop, main, and master, with zero analyze issues and zero format drift on `lib/`, `test/`, and `bin/`. New behavior ships with a failing test first (red, green, refactor).

Before opening a pull request, run the same checks CI runs:

```bash
dart format --output=none --set-exit-if-changed lib/ test/ bin/
dart analyze lib/ test/ bin/
flutter test --exclude-tags=integration --coverage --timeout=30s
dart pub publish --dry-run
```

[Report a bug](https://github.com/fluttersdk/dusk/issues/new?template=bug_report.yml) · [Request a feature](https://github.com/fluttersdk/dusk/issues/new?template=feature_request.yml)

## License

MIT, see [LICENSE](LICENSE) for details.

---

<p align="center">
  <sub>Built with care by <a href="https://github.com/fluttersdk">FlutterSDK</a></sub><br/>
  <sub>If Dusk saves you debugging time, <a href="https://github.com/fluttersdk/dusk">give it a star</a>, it helps others discover it.</sub>
</p>
