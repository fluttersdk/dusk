<p align="center">
  <img src="https://raw.githubusercontent.com/anilcancakir/tapir/master/.github/tapir-logo.svg" width="120" alt="Tapir Logo" />
</p>

<h1 align="center">Tapir</h1>

<p align="center">
  <strong>End-to-end driver for Flutter apps. Read by humans, driven by AI agents.</strong><br/>
  Snapshot the Semantics tree, drive any gesture, capture screenshots, observe live state, all from one CLI and one stdio MCP server.
</p>

<p align="center">
  <a href="https://github.com/anilcancakir/tapir/actions"><img src="https://img.shields.io/github/actions/workflow/status/anilcancakir/tapir/ci.yml?branch=master&label=CI" alt="CI"></a>
  <a href="https://pub.dev/packages/tapir"><img src="https://img.shields.io/pub/v/tapir.svg" alt="pub package"></a>
  <a href="https://pub.dev/packages/tapir/score"><img src="https://img.shields.io/pub/points/tapir" alt="pub points"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://github.com/anilcancakir/tapir/stargazers"><img src="https://img.shields.io/github/stars/anilcancakir/tapir?style=flat" alt="GitHub stars"></a>
</p>

<p align="center">
  <a href="https://anilcancakir.com/tapir">Documentation</a> ·
  <a href="https://pub.dev/packages/tapir">pub.dev</a> ·
  <a href="https://github.com/anilcancakir/tapir/issues">Issues</a>
</p>

---

> [!NOTE]
> Requires Dart SDK >= 3.4.0 and Flutter >= 3.22.0. tapir is debug-only: production builds tree-shake the entire driver across web, desktop, and mobile.

## Installation

```bash
flutter pub add tapir
dart run tapir tapir:install      # patches lib/main.dart + scaffolds ./bin/dowel + registers tapir plugin
```

That's it. After the second command, all 42 `tapir:*` commands surface through `./bin/dowel <cmd>` (~110ms warm) or `dart run tapir <cmd>` (works the same, ~3s startup), and the MCP server is one `dart run tapir mcp:install` away. When fastcli (`./bin/dowel`) is absent, `mcp:install` writes `dart run tapir mcp:serve` into `.mcp.json` automatically; no manual edit required. See [MCP install: 8 clients](#mcp-install-8-clients) for the per-client wiring. Manual wiring, Magic-stack integration, and the full per-command flag reference live in the [Getting Started guide](https://anilcancakir.com/tapir/docs/getting-started).

> [!TIP]
> **fastcli** is the AOT-compiled dowel dispatcher (~110ms warm) shipped as `./bin/dowel`. `tapir:install` scaffolds it for you automatically (best-effort; falls through to a warning when `dart` is not on PATH). After that, every `./bin/dowel <cmd>` is the fast path. The CLI also runs as `dart run tapir <cmd>` with the same surface, ~3s slower per call.

## Why Tapir?

End-to-end testing on Flutter has always been a stitched-together ritual. `flutter_driver` ships a one-off socket protocol that does not survive hot restart. `integration_test` runs in-process against a simulated `WidgetTester`, but you write a test file, build, run, and wait. AI coding agents that want to drive the running app reach for ad hoc `flutter test` invocations, copy stack traces back into the prompt, and paste screenshots back, calling it a workflow.

**Tapir closes that loop.** A single VM Service extension family (`ext.tapir.*`), a single CLI namespace (`tapir:*`), and a single stdio MCP server back **42 CLI commands** and **40 MCP tools** (33 `ext.tapir.*` + 7 `dowel:tapir:*` substrate-routed). The same contracts power human-driven terminal calls and agent-driven MCP tool calls: `tapir:tap --ref=e7` (CLI) and `tapir_tap` (MCP) reach the exact same code path. No test harness, no test file, no build step. Attach to the live app and the agent has eyes (`tapir_snap`, `tapir_screenshot`, `tapir_observe`) and hands (`tapir_tap`, `tapir_type`, `tapir_scroll`, `tapir_drag`). On Flutter web, the `tapir:screenshot` CLI command falls back to CDP `Page.captureScreenshot` when dowel was started with `--cdp-port`, bypassing the in-isolate extension that hangs under CanvasKit; the `tapir_screenshot` MCP tool still dispatches in-isolate, so web agents should use the CLI for screenshots. `tapir_exceptions` captures non-fatal `FlutterError`s (including overflow) in-package so diagnostics work even without crumbs.

| Tool | What it does | Where Tapir fits |
|---|---|---|
| **[integration_test](https://pub.dev/packages/integration_test)** (Flutter SDK) | In-process `WidgetTester` wrapper; runs tests via `flutter drive` | Different niche: integration_test owns the *authored test file*; Tapir owns the *unscripted running app*. Use both. |
| **[patrol](https://pub.dev/packages/patrol)** (Leancode, 694 likes) | Native UI permissions + dialogs layered on `integration_test` | Orthogonal: patrol owns *authored tests with native dialogs*; Tapir owns *unscripted automation by humans and AI agents*. |
| **[flutter_driver](https://pub.dev/packages/flutter_driver)** (Flutter SDK, legacy) | One-off socket protocol; being phased out | Tapir is hot-restart safe via `registerExtensionIdempotent` (21 aggregator register functions), one contract for CLI and MCP, no test harness, no separate isolate. |
| **[maestro](https://github.com/mobile-dev-inc/maestro)** (13.7K stars) | YAML DSL over OS accessibility layer | Tapir drives the Flutter widget tree directly (Semantics nodes + RenderObjects); no Flutter Desktop limitation; zero YAML to author. |
| **[mcp_flutter](https://github.com/Arenukvern/mcp_flutter)** (298 stars) | Flutter MCP toolkit with `fmt_*` tools | Tapir is on pub.dev with verified publisher, framework-native Dowel plugin, `e<N>` and `q<N>` ref system, 6-step actionability gate. |
| **[playwright-mcp](https://github.com/microsoft/playwright-mcp)** (33K stars) | Browser MCP via accessibility tree + `[ref=eN]` tokens | The Flutter-native equivalent. Tapir's `q<N>` handles mirror Playwright's `getByRole()`; `tapir_observe` borrows Stagehand's observe-once-act-many pattern, ported to Flutter Semantics. |

## Features

| | Feature | Description |
|:--|:--------|:------------|
| 🌳 | **Semantics Snapshot** | `tapir_snap` emits a YAML tree with stable `[ref=eN]` tokens; every action targets a ref, no brittle XPath or coordinate guessing |
| 🛠️ | **42 CLI Commands** | run (a batch of verbs in one call), snap, tap, type, fill, drag, scroll, hover, dblclick, right_click, triple_click, focus, blur, clear, set_checkbox, select_option, press_key, wait, find, observe, navigate, navigate_back, get_routes, modal, reset_overlays, screenshot, hot_reload_and_snap, CDP resize + device, close_app, install, doctor, wait_for_network_idle, console, exceptions, perf_begin + perf_end + perf_insight + perf_run + perf_compare + perf_trace + perf_campaign |
| 🤖 | **40 MCP Tools** | The full CLI surface plus `tapir_evaluate`, exposed as stdio JSON-RPC tools to Claude Code, Cursor, Windsurf, VS Code Copilot, and any MCP-compatible agent |
| 🚪 | **6-Step Actionability Gate** | Every gesture passes defunct (preflight) → enabled → zero-rect → off-viewport (auto-scrolls) → stable (2-frame rect drift) → receives-events (hit-test path); no flaky taps, and a `checks` block when the last one could not be proven rather than a silent pass |
| 🔖 | **Playwright-style Locators** | `q<N>` re-resolvable handles via `tapir_find` walk the live Semantics tree on every action. Stale handles throw, never silently act on the wrong widget |
| 🔄 | **Hot Reload + Snap Round-trip** | `tapir_hot_reload_and_snap` returns `{reloaded, durationMs, snapshot, screenshot, exceptions}` in one call |
| 🖥️ | **CDP Device Emulation** | `tapir_resize_viewport` and `tapir_device_profile` (iphone-x, pixel-5, desktop-1440, plus 5 more) drive Chrome DevTools Protocol |
| 📈 | **Frame Attribution Session** | `tapir_perf_begin` / `tapir_perf_end` bracket a driven interaction and report which widget types built, how often and for how long, next to wind's cache hit/miss/bypass counters and magic's controller notifies. A session the engine did not render through is REFUSED rather than reported, because a table of zeros reads as "fast" |
| 🎨 | **Snapshot Enricher Plug-in** | `TapirPlugin.enrichers.add()` lets `magic` and `wind` add framework-specific YAML fragments via a frozen `String? Function(Element, RefRegistry)` contract |
| 🔒 | **Release Tree-Shake** | Consumer wraps `TapirPlugin.install()` in `!kReleaseMode`, so debug and profile builds carry the driver; release builds tree-shake it across web, desktop, and mobile |
| 📡 | **AI-first Distribution** | Canonical `tapir` skill at [`skills/tapir/`](skills/tapir/) and hosted docs MCP at `mcp.anilcancakir.com`, distributed to 8+ agents (Claude Code, Cursor, OpenCode, Gemini CLI, VS Code Copilot, Codex CLI, Cline, Roo Code) via [anilcancakir/ai](https://github.com/anilcancakir/ai). First end-to-end driver in the Flutter ecosystem to ship its own LLM-agent skill bundle + docs MCP. |

> [!IMPORTANT]
> `TapirPlugin.install()` must be wrapped in `if (!kReleaseMode) { ... }` at the call site in `lib/main.dart`, so debug and profile builds carry it (`tapir:perf_run` measures a profile build). An app wired under `kDebugMode` before this still works in debug, but registers no `ext.tapir.*` in a profile build. Release builds tree-shake the entire driver across web (dart2js), desktop (dart2native), and mobile (AOT), but only when the guard exists. Without the guard, tapir ships into release binaries.

## AI Coding Assistants

Tapir ships AI-first. The skill at [`skills/tapir/SKILL.md`](skills/tapir/SKILL.md) teaches your agent the 6 core laws, the `e<N>` / `q<N>` ref grammar, the 6-step actionability vocabulary, the 40 MCP tool surface, and the agent-workflow playbooks. The same skill is distributed through [**anilcancakir/ai**](https://github.com/anilcancakir/ai) for Claude Code, Cursor, OpenCode, Gemini CLI, VS Code Copilot, Codex CLI, Cline, and Roo Code, one command:

```bash
npx skills add anilcancakir/ai --skill tapir
```

The hosted MCP server at `mcp.anilcancakir.com` exposes a `search-docs` tool over Streamable HTTP (no auth) for agents that need to query the tapir docs corpus directly. The LLM-readable inventory lives at [`llms.txt`](llms.txt). Full multi-client wire-up and the OpenCode registry URL live in the [anilcancakir/ai README](https://github.com/anilcancakir/ai).

This is independent of tapir's own runtime MCP server (`./bin/dowel mcp:serve`, covered in the next section): the docs MCP teaches the agent ABOUT tapir; the runtime MCP gives the agent eyes and hands on a running Flutter app.

## MCP install: 8 clients

Tapir is the first Flutter MCP server focused on **UI automation** (tap, snap, screenshot, observe) rather than runtime telemetry. The 40 `tapir_*` tools surface to any MCP-compatible agent.

> [!NOTE]
> Configs below use `./bin/dowel` (the fastcli wrapper, see top of README). If fastcli is not scaffolded yet, swap `./bin/dowel mcp:serve` for `dart run tapir mcp:serve` in every client row.

**Standard config** (any client that reads `.mcp.json` in the project root):

```jsonc
{
  "mcpServers": {
    "dowel": {
      "command": "./bin/dowel",
      "args": ["mcp:serve"],
      "cwd": "."
    }
  }
}
```

| Client | Install |
|---|---|
| **Claude Code** | `claude mcp add dowel -- ./bin/dowel mcp:serve` |
| **VS Code** | `code --add-mcp '{"name":"dowel","command":"./bin/dowel","args":["mcp:serve"]}'`, or drop the standard config into `.vscode/mcp.json` |
| **Cursor** | Settings > MCP > Add new MCP Server, or drop the standard config into `~/.cursor/mcp.json` |
| **Windsurf** | Drop the standard config into `~/.codeium/windsurf/mcp_config.json` |
| **Goose** | Advanced settings > Extensions > Add custom extension; paste the standard config |
| **Warp** | Settings > AI > Manage MCP Servers, or `/add-mcp` slash command with the standard config |
| **Claude Desktop** | Edit `claude_desktop_config.json` (macOS: `~/Library/Application Support/Claude/`, Windows: `%APPDATA%\Claude\`) and add the standard config under `mcpServers` |
| **Codex** | `codex mcp add dowel ./bin/dowel mcp:serve` |

### Before / after

| Without Tapir | With Tapir |
|---|---|
| You hot-reload, screenshot the result, drag the PNG into Claude, type "the counter button should be tappable but isn't, what's wrong?", scroll, copy the relevant widget source, paste back. | Claude calls `tapir_snap` and reads the YAML tree with `[ref=eN]` tokens. Claude calls `tapir_tap --ref=e7`, the gate fires, the counter increments, Claude verifies via a fresh snap. Loop closes without you in the middle. |
| You wonder if the failing test is a timing issue or a real bug. You add `Future.delayed(Duration(seconds: 2))` and re-run. | The 6-step actionability gate fires before every gesture: defunct, not enabled, zero rect, off-viewport, not stable, obscured by another widget. Errors carry agent-parseable reason strings. |

### Typical agent session

```
[agent] dowel_start { device: macos }            # launch the app
[agent] tapir_snap {}                                # semantic tree with stable refs
[agent] tapir_observe {}                             # structured candidate list (Stagehand-style)
[agent] tapir_tap { ref: "e7" }                      # tap a button by ref
[agent] tapir_screenshot { format: "jpeg" }          # verify visually
[agent] tapir_hot_reload_and_snap {}                 # reload + snap in one round-trip
[agent] dowel_stop                                # tear down
```

Full per-tool input schemas + example calls in the [MCP tool reference](https://anilcancakir.com/tapir/docs/mcp/tool-reference). For agents that read structured project context at attach time, the canonical entry point is [`llms.txt`](https://anilcancakir.com/tapir/docs/llms.txt); it lists the 40 MCP tool names inline, plus the command surface, ref token grammar, and 6-step actionability vocabulary. The site serves the bare URLs to humans and the same paths with a `.md` suffix to LLM agents (e.g. `https://anilcancakir.com/tapir/docs/getting-started.md`).

## Examples

The [`example/`](example/) directory ships a vanilla Flutter showroom that gives every CLI command a live target widget on one route: TextField, Dropdown, Checkbox, Switch, counter button, Draggable + DragTarget, dialog, bottom sheet, 30 ListTile rows for scrolling, and navigation buttons across three named routes.

```bash
cd example && flutter pub get
dart run tapir start --device=macos
```

## Documentation

Full docs with live examples at **[anilcancakir.com/tapir](https://anilcancakir.com/tapir)**: commands catalog, MCP tool reference, the 6-step actionability reference, Magic and Wind integration guides, and the snapshot enricher authoring guide. The internal architecture lives in [`ARCHITECTURE.md`](ARCHITECTURE.md) for contributors.

## Contributing

```bash
git clone https://github.com/anilcancakir/tapir.git
cd tapir && flutter pub get
flutter test && dart analyze
```

CI enforces 80%+ line coverage on `lib/` on every push to `master` and every PR back into it, with zero analyze issues and zero format drift on `lib/`, `test/`, and `bin/`. New behavior ships with a failing test first (red, green, refactor).

Before opening a pull request, run the same checks CI runs:

```bash
dart format --output=none --set-exit-if-changed lib/ test/ bin/
dart analyze lib/ test/ bin/
flutter test --exclude-tags=integration --coverage --timeout=30s
dart pub publish --dry-run
```

[Report a bug](https://github.com/anilcancakir/tapir/issues/new?template=bug_report.yml) · [Request a feature](https://github.com/anilcancakir/tapir/issues/new?template=feature_request.yml)

## License

MIT, see [LICENSE](LICENSE) for details.

---

<p align="center">
  <sub>Built by <a href="https://github.com/anilcancakir">Anılcan Çakır</a></sub><br/>
  <sub>If Tapir saves you debugging time, <a href="https://github.com/anilcancakir/tapir">give it a star</a>, it helps others discover it.</sub>
</p>
