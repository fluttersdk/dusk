<p align="center">
  <img src="https://raw.githubusercontent.com/fluttersdk/magic/master/.github/magic-logo.svg" width="120" alt="Dusk Logo" />
</p>

<h1 align="center">Dusk</h1>

<p align="center">
  <strong>End-to-end driver for Flutter apps. Read by humans, driven by AI agents.</strong><br/>
  Snapshot the Semantics tree, tap any widget by ref token, type into TextFields, capture screenshots, scroll, drag, wait, navigate, and observe live state, all from one CLI and one stdio MCP server.
</p>

<p align="center">
  <a href="https://pub.dev/packages/fluttersdk_dusk"><img src="https://img.shields.io/pub/v/fluttersdk_dusk.svg" alt="pub package"></a>
  <a href="https://github.com/fluttersdk/dusk/actions"><img src="https://img.shields.io/github/actions/workflow/status/fluttersdk/dusk/ci.yml?branch=develop&label=CI" alt="CI"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://pub.dev/packages/fluttersdk_dusk/score"><img src="https://img.shields.io/pub/points/fluttersdk_dusk" alt="pub points"></a>
  <a href="https://github.com/fluttersdk/dusk/stargazers"><img src="https://img.shields.io/github/stars/fluttersdk/dusk?style=flat" alt="GitHub stars"></a>
</p>

<p align="center">
  <a href="https://fluttersdk.com/dusk">Documentation</a> ·
  <a href="https://pub.dev/packages/fluttersdk_dusk">pub.dev</a> ·
  <a href="https://github.com/fluttersdk/dusk/issues">Issues</a>
</p>

---

## Why Dusk?

**Stop screenshotting your Flutter app into Claude. Let your agent see the widget tree itself.**

End-to-end testing on Flutter has always been a stitched-together ritual. `flutter_driver` ships a one-off socket protocol that does not survive hot restart. `integration_test` runs in-process against a simulated WidgetTester, but you write a test file, build, run, and wait. `patrol` adds native dialog support but still asks you to author tests up front. AI coding agents that want to *drive the running app* reach for ad hoc `flutter test` invocations, copy stack traces back into the prompt, paste back screenshots, and call it a workflow.

**Dusk closes that loop.** A single VM Service extension family (`ext.dusk.*`), a single CLI namespace (`dusk:*`), and a single stdio MCP server back **32 CLI commands** and **31 MCP tools**. The same contracts power human-driven terminal calls and agent-driven MCP tool calls, so a developer typing `dusk:tap --ref=e7` and Claude Code calling `dusk_tap` reach the exact same code path. No test harness, no test file, no build step. You attach to the live app and the agent has eyes (`dusk_snap`, `dusk_screenshot`, `dusk_observe`) and hands (`dusk_tap`, `dusk_type`, `dusk_scroll`, `dusk_drag`).

```bash
# Before, the hand-rolled integration_test ritual
edit integration_test/app_test.dart       # write per-screen WidgetTester finders
edit integration_test/driver.dart         # spawn the driver isolate
flutter test integration_test/            # build, run, wait, hope it didn't time out
edit golden_test/*.dart                   # add a parallel pixel-diff suite for screenshots
```

```bash
# After, the Dusk way
flutter pub add fluttersdk_dusk
dart run fluttersdk_dusk dusk:install      # injects DuskPlugin.install() into lib/main.dart
dart run fluttersdk_dusk start             # boots the app, records the VM Service URI
dart run fluttersdk_dusk dusk:snap         # YAML tree with [ref=eN] tokens
dart run fluttersdk_dusk dusk:tap --ref=e7 # drive any gesture by ref
```

Framework-agnostic. Pure-Dart CLI (no `dart:ui` import), Magic and Wind integrations ship inside *those* packages via the `DuskSnapshotEnricher` plug-in point, so a vanilla Flutter app gets every command without any framework lock-in. Debug-only by design; release builds tree-shake the entire driver.

## Features

| | Feature | Description |
|:--|:--------|:------------|
| 🌳 | **Semantics Snapshot** | `dusk_snap` emits a YAML tree with stable `[ref=eN]` tokens; every action tool targets a ref, no brittle XPath or coordinate guessing |
| 🛠️ | **32 CLI Commands** | snap, tap, type, drag, scroll, hover, dblclick, right_click, triple_click, focus, blur, clear, set_checkbox, select_option, press_key, wait, find, observe, navigate, modal, screenshot, hot_reload_and_snap, CDP resize + device, close_app, install, doctor |
| 🤖 | **31 MCP Tools** | The full CLI surface plus `dusk_evaluate`, exposed as stdio JSON-RPC tools to Claude Code, Cursor, Windsurf, VS Code Copilot, and any MCP-capable agent |
| 🚪 | **5-Gate Actionability** | Every gesture passes through enabled → zero-rect → off-viewport (auto-scrolls via `showOnScreen`) → stable (2-frame rect drift) → receives-events (hit-test path); no flaky taps |
| 🔖 | **Playwright-style Locators** | `q<N>` re-resolvable handles via `dusk_find` walk the live Semantics tree on every action call. Stale handles throw; they never silently act on the wrong widget |
| 🖼️ | **Lossless + Lossy Screenshots** | `dusk_screenshot` rasterises the app's RepaintBoundary via `OffsetLayer.toImage`; default JPEG q70 (40-120 KB), opt-in PNG for pixel-exact captures |
| 🔄 | **Hot Reload + Snap Round-trip** | `dusk_hot_reload_and_snap` drives `flutter run`'s stdin FIFO + log poll, returns `{reloaded, durationMs, snapshot, screenshot, exceptions}` in one call |
| 🖥️ | **CDP Device Emulation** | `dusk_resize_viewport` and `dusk_device_profile` (iphone-x, pixel-5, desktop-1440, plus 5 more) drive Chrome DevTools Protocol for responsive layout testing |
| 🎨 | **Snapshot Enricher Plug-in** | `DuskPlugin.enrichers.add()` lets `magic` register 5 core enrichers (form state, route, gate, middleware, auth user) and `wind` register a 6-field className enricher, neutral bridge via `fluttersdk_wind_diagnostics_contracts` |
| 🔒 | **Debug-Only Tree-Shake** | Consumer wraps `DuskPlugin.install()` in `kDebugMode`; release builds tree-shake the entire driver, web/desktop/mobile alike |

## Quick Start

### Option A (recommended): one-shot install

Add the dependency, then let Dusk bootstrap itself. No prior `fluttersdk_artisan` setup is required; Dusk ships its own Flutter-free CLI entry point so the install works from a fresh consumer:

```bash
flutter pub add fluttersdk_dusk
dart run fluttersdk_dusk dusk:install
```

The command patches `lib/main.dart` so `DuskPlugin.install()` runs inside `kDebugMode` before `runApp`. It detects Magic-stack apps via the `await Magic.init(` anchor and injects in the right order; vanilla Flutter apps get the install before `runApp(`. Idempotent, safe to re-run.

After install, boot the app once and every subsequent command reuses the recorded VM Service URI:

```bash
dart run fluttersdk_dusk start --device=macos     # or --device=chrome --cdp-port=9333
dart run fluttersdk_dusk dusk:snap                # YAML tree with [ref=eN] tokens
dart run fluttersdk_dusk dusk:tap --ref=e7        # increment Counter button (matches ref from snap)
dart run fluttersdk_dusk dusk:screenshot --output=after.png
dart run fluttersdk_dusk dusk:doctor              # green-yellow-red health check
```

`dusk:resize` and `dusk:device` require Chrome started with `--cdp-port=<N>` since both drive the Chrome DevTools Protocol. Every other command works on macos, ios, android, linux, and chrome.

### Option B: manual wiring

#### 1. Add the dependency

```yaml
# pubspec.yaml
dependencies:
  fluttersdk_dusk: ^0.0.1
```

#### 2. Install in `main.dart`

Install Dusk inside `kDebugMode` before `runApp` (or before `Magic.init()` on Magic-stack apps):

```dart
import 'package:flutter/foundation.dart';
import 'package:fluttersdk_dusk/dusk.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    DuskPlugin.install();
  }

  runApp(const MyApp());
}
```

For Magic-stack apps, also install the snapshot enrichers AFTER `Magic.init()` so they can resolve framework internals from the IoC container:

```dart
await Magic.init(configFactories: [...]);

if (kDebugMode) {
  MagicDuskIntegration.install();   // 5 magic enrichers (form, route, gate, middleware, auth)
  Wind.installDebugResolver();      // 6-field className enricher via WindDebugRegistry
}
```

#### 3. Wire the Artisan provider (MCP tools)

Dusk's 31 MCP tool descriptors surface through `DuskArtisanProvider`. The provider is auto-discovered via `lib/app/_plugins.g.dart` if you've run `dart run fluttersdk_artisan install`. To wire it manually, add `FluttersdkDuskArtisanProvider()` to the `baseProviders` list in `bin/dispatcher.dart`:

```dart
import 'package:fluttersdk_artisan/artisan.dart';
import 'package:fluttersdk_dusk/cli.dart' show FluttersdkDuskArtisanProvider;

exit(await runArtisan(
  args,
  baseProviders: [
    FluttersdkDuskArtisanProvider(),
    // ...other providers (TelescopeArtisanProvider, etc.)
  ],
));
```

## AI Agent Integration

Dusk is the first Flutter MCP server focused on **UI automation** (tap, snap, screenshot, observe) rather than runtime telemetry. The 31 `dusk_*` tools give Claude Code, Cursor, Windsurf, VS Code Copilot, or any MCP-compatible agent direct read-and-write access to a running Flutter app.

### One-line `.mcp.json` install

`dusk:install` calls `dart run fluttersdk_artisan mcp:install` which writes (or updates) the `mcpServers.fluttersdk` entry in `.mcp.json`. Or wire it manually for any MCP-compatible client:

```jsonc
// .mcp.json (project root): Claude Code / Cursor / Windsurf / Codex / Goose / VS Code Copilot
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

Restart the MCP client. The 31 `dusk_*` tools surface in `/mcp` alongside the artisan substrate tools.

### Before / after

| Without Dusk | With Dusk |
|---|---|
| You hot-reload, screenshot the result, drag the PNG into Claude, type "the counter button should be tappable but isn't, what's wrong?", scroll, copy the relevant widget source, paste back. | Claude calls `dusk_snap` → reads the YAML tree with `[ref=eN]` tokens. Claude calls `dusk_tap --ref=e7` → the gate fires, the counter increments, Claude verifies via a fresh snap. Loop closes without you in the middle. |
| You wonder if the failing test is a timing issue or a real bug. You add `Future.delayed(Duration(seconds: 2))` and re-run. | The 5-gate actionability check fires before every gesture: not enabled, zero rect, off-viewport, not stable (still animating), obscured by another widget. Errors carry agent-parseable reason strings. |

### Typical agent session

```
[agent] artisan_start { device: macos }            // launch the app, record VM Service URI
[agent] dusk_snap {}                                // semantic tree with stable refs
[agent] dusk_observe {}                             // structured candidate list (Stagehand-style)
[agent] dusk_tap { ref: "e7" }                      // tap a button by ref
[agent] dusk_screenshot { format: "jpeg" }          // verify visually
[agent] dusk_hot_reload_and_snap {}                 // reload + snap in one round-trip
[agent] dusk_exceptions {}                          // check for any uncaught exceptions (with telescope)
[agent] artisan_stop                                // tear down
```

For agents that read structured project context at attach time, the canonical entry point is [`llms.txt`](llms.txt) at the repo root (also published at `https://fluttersdk.com/dusk/llms.txt`). It enumerates the command surface, every MCP tool input schema, the ref token grammar, and the 5-gate actionability vocabulary in agent-readable form.

## CLI Commands

Dusk ships 32 CLI commands registered by `DuskArtisanProvider.commands()`. After `dusk:install`, invoke any command three ways: through the consumer's fast-cli (`./bin/fsa <command>`, ~110ms warm), through Dusk's standalone bin (`dart run fluttersdk_dusk <command>`, ~3s cold fallback), or through the consumer dispatcher (`dart run fluttersdk_artisan <command>`).

| Command | Purpose |
|---------|---------|
| `dusk:install` | Patch `lib/main.dart` to call `DuskPlugin.install()` inside `kDebugMode`. Detects Magic-stack apps via the `await Magic.init(` anchor; falls back to `runApp(` for vanilla Flutter. Idempotent. |
| `dusk:snap` | Capture a YAML snapshot of the Semantics tree with stable `[ref=eN]` tokens. |
| `dusk:tap` | Tap a widget by ref token (Down + 50ms + Up). Passes the 5-gate actionability check. |
| `dusk:dblclick` | Two primary clicks ~100ms apart. |
| `dusk:right_click` | Single secondary-button click. |
| `dusk:triple_click` | Three primary clicks ~100ms apart. |
| `dusk:hover` | Hover the mouse cursor over a widget (web and desktop only). |
| `dusk:drag` | Drag from one widget to another by `startRef` + `endRef`. |
| `dusk:scroll` | Scroll a `Scrollable` widget by ref token (dx + dy in pixels). |
| `dusk:type` | Type text into a `TextField` identified by ref token. Replaces existing content. |
| `dusk:clear` | Empty a `TextField` by ref token. |
| `dusk:focus` | Request keyboard focus on a widget by ref token. |
| `dusk:blur` | Drop keyboard focus from whatever currently holds it. |
| `dusk:press_key` | Synthesise a `LogicalKeyboardKey` press (Enter, Tab, ArrowDown, etc.) on the focused widget. |
| `dusk:set_checkbox` | Toggle a `Checkbox` or `Switch` to a target boolean state. |
| `dusk:select_option` | Select a `DropdownButton` or `PopupMenu` option by value. |
| `dusk:find` | Mint a re-resolvable `q<N>` Locator handle by `text`, `semanticsLabel`, or `keyValue`. |
| `dusk:observe` | Return a structured candidate list of every interactive widget (Stagehand observe-once-act-many). |
| `dusk:wait` | Wait until `text` / `textGone` / `expression` is satisfied, or the timeout expires. |
| `dusk:wait_for_network_idle` | Wait until pending HTTP requests count drops to zero (requires telescope). |
| `dusk:navigate` | Push a named route by URI. |
| `dusk:navigate_back` | Pop the topmost route. |
| `dusk:get_routes` | Print the active Navigator's route table + current location. |
| `dusk:modal` | Dismiss every open modal (dialog, bottom sheet, popup). |
| `dusk:screenshot` | Capture the current frame as base64-encoded JPEG (default) or PNG. |
| `dusk:hot_reload_and_snap` | Hot-reload via FIFO + log poll, then snap + screenshot in one round-trip. |
| `dusk:close_app` | Gracefully close the app via `SystemNavigator.pop()`. |
| `dusk:resize` | Set the Chrome viewport to a custom width × height × DPR via CDP. |
| `dusk:device` | Apply a device preset (iphone-x, pixel-5, desktop-1440, plus 5 more) via CDP. |
| `dusk:doctor` | Run 5 health checks: hot-restart staleness, `DUSK_DISABLE` env, enrichers, semantics on, Magic-init detection. |

Full per-command flag reference at the [commands catalog](https://fluttersdk.com/dusk/commands).

## MCP Tools

Exposed via `DuskArtisanProvider.mcpTools()` when the consumer registers the provider. 28 tools route through `ext.dusk.*` VM Service extensions; 3 (`dusk_hot_reload_and_snap`, `dusk_resize_viewport`, `dusk_device_profile`) route through `artisan:dusk:*` substrate prefixes since they need out-of-isolate execution (in-isolate hot-reload would deadlock; CDP needs a non-Flutter Dart context).

| Tool | Extension method | Captures |
|------|------------------|----------|
| `dusk_snap` | `ext.dusk.snap` | YAML semantic tree with `[ref=eN]` tokens. |
| `dusk_tap` | `ext.dusk.tap` | Tap a widget by ref (5-gate actionability + pointer synthesis). |
| `dusk_dblclick` | `ext.dusk.dblclick` | Two-tap sequence ~100ms apart. |
| `dusk_right_click` | `ext.dusk.right_click` | Secondary-button single click. |
| `dusk_triple_click` | `ext.dusk.triple_click` | Three-tap sequence. |
| `dusk_hover` | `ext.dusk.hover` | Pointer hover at widget center. |
| `dusk_drag` | `ext.dusk.drag` | Drag from `startRef` to `endRef`. |
| `dusk_scroll` | `ext.dusk.scroll` | Scrollable scroll-by-delta. |
| `dusk_type` | `ext.dusk.type` | Replace TextField content with text. |
| `dusk_clear` | `ext.dusk.clear` | Empty TextField content. |
| `dusk_focus` | `ext.dusk.focus` | Request keyboard focus on widget. |
| `dusk_blur` | `ext.dusk.blur` | Drop keyboard focus. |
| `dusk_press_key` | `ext.dusk.press_key` | Logical key press on focused widget. |
| `dusk_set_checkbox` | `ext.dusk.set_checkbox` | Set Checkbox/Switch to boolean. |
| `dusk_select_option` | `ext.dusk.select_option` | Dropdown/PopupMenu option select. |
| `dusk_find` | `ext.dusk.find` | Mint q-handle by text/label/key. |
| `dusk_observe` | `ext.dusk.observe` | Stagehand candidate list. |
| `dusk_wait_for` | `ext.dusk.wait_for` | Wait for text/textGone/expression. |
| `dusk_wait_for_network_idle` | `ext.dusk.wait_for_network_idle` | Wait until in-flight HTTP count == 0. |
| `dusk_navigate` | `ext.dusk.navigate` | Push named route. |
| `dusk_navigate_back` | `ext.dusk.navigate_back` | Pop route. |
| `dusk_get_routes` | `ext.dusk.get_routes` | Read route table + current location. |
| `dusk_dismiss_modals` | `ext.dusk.dismiss_modals` | Pop every modal. |
| `dusk_screenshot` | `ext.dusk.screenshot` | Base64 JPEG/PNG of the current frame. |
| `dusk_close_app` | `ext.dusk.close_app` | SystemNavigator.pop on the running app. |
| `dusk_console` | `ext.dusk.console` | Recent log entries from telescope (graceful empty without telescope). |
| `dusk_exceptions` | `ext.dusk.exceptions` | Recent uncaught exceptions from telescope. |
| `dusk_evaluate` | `ext.dusk.evaluate` | Dart expression evaluation in the running isolate (MCP-only; no CLI mirror). |
| `dusk_hot_reload_and_snap` | `artisan:dusk:hot_reload_and_snap` | Fused round-trip: hot reload + snap + screenshot + exceptions. |
| `dusk_resize_viewport` | `artisan:dusk:resize` | Chrome viewport resize via CDP. |
| `dusk_device_profile` | `artisan:dusk:device` | Apply device preset (iphone-x, pixel-5, etc.) via CDP. |

Full MCP tool reference (every input schema, every example call) at the [tool reference](https://fluttersdk.com/dusk/mcp/tool-reference).

## Compared to

| Tool | What it does | Where Dusk wins |
|---|---|---|
| **[integration_test](https://pub.dev/packages/integration_test)** (Flutter SDK) | In-process `WidgetTester` wrapper; runs tests via `flutter drive` | No test harness, no build step; attach to the running app, drive it from a terminal or an AI agent |
| **[patrol](https://pub.dev/packages/patrol)** (Leancode, 694 likes) | Native UI permissions/dialogs on top of `integration_test` | Complementary, not competitive: patrol owns *authored* tests with native dialogs; Dusk owns *unscripted* automation by humans and AI agents |
| **[flutter_driver](https://pub.dev/packages/flutter_driver)** (Flutter SDK) | Legacy one-off socket protocol; being phased out | Hot-restart safe (every extension via `registerExtensionIdempotent`); single contract for CLI + MCP, no test harness, no separate isolate |
| **[maestro](https://github.com/mobile-dev-inc/maestro)** (13.7K stars) | YAML DSL over OS accessibility layer | Drives the Flutter widget tree directly (Semantics nodes + RenderObjects), no Flutter Desktop limitation, zero YAML to author |
| **[mcp_flutter](https://github.com/Arenukvern/mcp_flutter)** (298 stars) | MCP toolkit with `fmt_*` tools, dynamic runtime registration | Published on pub.dev with verified publisher, framework-native Artisan plugin, `e<N>`/`q<N>` ref system, 5-gate actionability check |
| **[playwright-mcp](https://github.com/microsoft/playwright-mcp)** (33K stars) | Browser MCP via accessibility tree + `[ref=eN]` tokens | The Flutter native equivalent: same pattern (structured snapshots, no vision models), same ref token grammar, the engine you reach for on Flutter Mobile + Desktop |

## Architecture

Dusk is subsystem-first under `lib/src/`; every directory owns a single concern:

```
lib/
├── dusk.dart                    # Public barrel: DuskPlugin, RefRegistry, DuskArtisanProvider, DuskSnapshotEnricher
├── cli.dart                     # Flutter-free codegen barrel (FluttersdkDuskArtisanProvider typedef)
└── src/
    ├── extensions/              # 18 files: ext_snapshot, ext_pointer, ext_text_input, ext_screenshot, ...
    ├── commands/                # 32 ArtisanCommand subclasses (one file each)
    ├── utils/                   # actionability_gate (5-gate), error_envelope, chrome_reaper, dusk_exceptions
    ├── cdp/                     # cdp_client + chrome_finder + 8 device_presets
    ├── dusk_plugin.dart         # DuskPlugin.install() entry + enricher list + navigate adapter
    ├── ref_registry.dart        # e<N> + q<N> dual token system; live re-resolution for q-refs
    ├── dusk_snapshot_enricher.dart  # FROZEN typedef: String? Function(Element, RefRegistry)
    └── dusk_artisan_provider.dart   # 32 commands + 31 MCP tool descriptors
bin/fluttersdk_dusk.dart           # Flutter-free CLI entry (no dart:ui import)
install.yaml                       # V1 plugin manifest, zero stubs, post_install bootstrap
```

Boot flow:

```
DuskPlugin.install()                                    # inside kDebugMode in lib/main.dart
    ↓
Wrap app root in RepaintBoundary (no GlobalKey; render-tree walk finds it for screenshots)
    ↓
WidgetsBinding.instance.ensureSemantics()                # force semantics on
    ↓
registerAllDuskExtensions()                              # 24 ext.dusk.* via registerExtensionIdempotent
    ↓
Consumer registers DuskArtisanProvider (auto-wired by `dusk:install` via _plugins.g.dart)
    ↓
artisan mcp:serve   →   31 dusk_* tools surface to MCP clients (Claude Code, Cursor, Windsurf, Copilot, ...)
```

Every concrete command and record is a `final class`. The five frozen contracts (`DuskSnapshotEnricher` typedef, `DuskPlugin.install/registerEnricher`, `RefRegistry` public methods, the 6 alpha-1 MCP tool names + `ext.dusk.*` method names, the 5-precondition actionability gate order) require a coordinated bump across `magic` + `wind` + `dusk` to change.

## Examples

### `example/`

Vanilla Flutter showroom (no Magic framework) that gives every CLI command a live target widget on one route. TextField (type/clear/focus/blur), Dropdown + Checkbox + Switch (set_checkbox / select_option), counter button (tap / dblclick / triple_click / right_click / hover), Draggable + DragTarget (drag), dialog + bottom sheet triggers (modal), 30 ListTile rows (scroll), navigation buttons (navigate / navigate_back), and diagnostics triggers (console / exceptions / wait_for_network_idle).

```bash
cd example
flutter pub get
dart run fluttersdk_dusk start --device=macos
```

## Inspiration

Dusk borrows two patterns from the browser-automation world that became standard for AI-driven workflows in 2025-2026:

- **[Microsoft Playwright](https://playwright.dev)** Locator pattern and accessibility-tree snapshot. Dusk's `q<N>` re-resolvable handles mirror Playwright's `getByRole()`/`getByLabel()` semantics over the Flutter Semantics tree, and the 5-gate actionability check is the Flutter equivalent of Playwright's auto-wait.
- **[Browserbase Stagehand](https://stagehand.dev)** "observe-once-act-many" pattern. `dusk_observe` returns a candidate list the agent can act on without re-snapping for every gesture.

Where these tools target the web DOM, Dusk targets Flutter Semantics. Same pattern, same ergonomics, ported to the platform the rest of your stack already runs on.

## Part of the Magic SDK suite

Dusk is one of seven packages in the [FlutterSDK suite](https://fluttersdk.com), a Laravel-inspired Flutter ecosystem:

- **[magic](https://pub.dev/packages/magic)** Laravel-style framework: facades, ORM, providers, controllers, routing
- **[wind](https://pub.dev/packages/fluttersdk_wind)** Tailwind-style className UI primitives for Flutter
- **[fluttersdk_artisan](https://pub.dev/packages/fluttersdk_artisan)** Pure-Dart CLI + MCP substrate that Dusk extends
- **fluttersdk_dusk** (this package) E2E gesture + snapshot driver via VM extensions + MCP
- **[fluttersdk_telescope](https://pub.dev/packages/fluttersdk_telescope)** Runtime observability (HTTP, logs, exceptions, queries) via VM extensions + MCP
- **[magic_tinker](https://pub.dev/packages/magic_tinker)** Connected REPL into the running app
- **[magic_starter](https://pub.dev/packages/magic_starter)** Auth / profile / teams scaffolding

Dusk and Telescope pair naturally: Dusk drives the UI, Telescope reads the runtime. An AI agent calling `dusk_tap` then `telescope_requests` then `dusk_screenshot` gets the full request-response-render loop in three tool calls.

## Documentation

Full docs with live examples at **[fluttersdk.com/dusk](https://fluttersdk.com/dusk)**.

| Topic | |
|:------|:-|
| [Getting Started](https://fluttersdk.com/dusk/getting-started/) | Overview, requirements, the snapshot model |
| [Installation](https://fluttersdk.com/dusk/getting-started/installation) | `flutter pub add fluttersdk_dusk` plus `dusk:install` walkthrough |
| [Quickstart](https://fluttersdk.com/dusk/getting-started/quickstart) | The 3-step path from empty repo to first snapshot |
| [Commands](https://fluttersdk.com/dusk/commands) | The 32 CLI commands grouped by concern |
| [MCP Setup](https://fluttersdk.com/dusk/mcp/setup) | Per-client install (Claude Code, Cursor, Windsurf, Codex) |
| [MCP Tool Reference](https://fluttersdk.com/dusk/mcp/tool-reference) | Every tool, every input schema, every example call |
| [Actionability Gate](https://fluttersdk.com/dusk/reference/actionability-gate) | The 5 preconditions, failure reason vocabulary, opt-out flags |
| [Magic Integration](https://fluttersdk.com/dusk/plugins/magic-integration) | The 5 core magic enrichers, install order, framework-internals access |
| [Wind Integration](https://fluttersdk.com/dusk/plugins/wind-integration) | The 6-field WindClassNameEnricher via the neutral diagnostics bridge |
| [Enricher Authoring](https://fluttersdk.com/dusk/plugins/enricher-authoring) | Write your own `DuskSnapshotEnricher` for a custom framework |

## Contributing

```bash
git clone https://github.com/fluttersdk/dusk.git
cd dusk && flutter pub get
flutter test && dart analyze
```

The baseline is 787 tests green, 80.08% line coverage enforced by CI on every push to develop / main / master. New behavior ships with a failing test first (red, green, refactor). `dart format lib/ test/ bin/` must produce no diff and `dart analyze` must report zero issues.

Before opening a pull request, also run:

```bash
dart format --output=none --set-exit-if-changed lib/ test/ bin/    # zero diff
dart analyze lib/ test/ bin/                                        # zero issues
flutter test --exclude-tags=integration --coverage --timeout=30s    # 80%+ line coverage
dart pub publish --dry-run                                          # validate the publish archive
```

[Report a bug](https://github.com/fluttersdk/dusk/issues/new?template=bug_report.yml) · [Request a feature](https://github.com/fluttersdk/dusk/issues/new?template=feature_request.yml)

## License

MIT, see [LICENSE](LICENSE) for details.

---

<p align="center">
  <sub>Built with care by <a href="https://github.com/fluttersdk">FlutterSDK</a></sub><br/>
  <sub>If Dusk saves you debugging time, <a href="https://github.com/fluttersdk/dusk">give it a star</a>, it helps others discover it.</sub>
</p>
