<p align="center">
  <img src="https://raw.githubusercontent.com/fluttersdk/magic/master/.github/magic-logo.svg" width="120" alt="Dusk Logo" />
</p>

# fluttersdk_dusk

<p align="center">
  <strong>E2E driver for Flutter apps over VM Service extensions and MCP.</strong><br/>
  Snapshot the Semantics tree, drive any gesture, capture screenshots, observe live state, all from one CLI and one stdio MCP server.
</p>

<p align="center">
  <a href="https://pub.dev/packages/fluttersdk_dusk"><img src="https://img.shields.io/pub/v/fluttersdk_dusk.svg" alt="pub package"></a>
  <a href="https://github.com/fluttersdk/dusk/actions"><img src="https://img.shields.io/github/actions/workflow/status/fluttersdk/dusk/ci.yml?branch=master&label=CI" alt="CI"></a>
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

## Why dusk?

End-to-end testing on Flutter is fragmented. `flutter_driver` ships a one-off socket protocol that does not survive hot restart, golden tests cover pixels but not behavior, and AI coding assistants that want to drive the running app reach for ad hoc `flutter test` invocations because there is no shared tool surface. Teams end up writing custom helper scripts, custom widget finders, and custom shell wrappers for every project, and every project rebuilds them from scratch.

**Dusk fixes this.** One VM Service extension family, one CLI namespace, one stdio MCP server. The same `ext.dusk.*` extensions back both human-driven CLI calls and agent-driven MCP tool calls, so the contract is identical at every layer.

```bash
# Before, the hand-rolled flutter_driver ritual
edit test_driver/main.dart                  # spawn the driver isolate
edit test_driver/app.dart                   # expose the SerializableFinder set
edit integration_test/*.dart                # write per-screen finder boilerplate
flutter drive --target=test_driver/app.dart # hope the socket survives hot restart
write golden_test/*.dart                    # add a parallel pixel-diff suite
```

```bash
# After, the dusk way
dart pub add fluttersdk_dusk
dart run :artisan dusk:install
dart run :artisan dusk:snap          # capture Semantics tree with stable refs
dart run :artisan dusk:tap --ref e7  # drive any gesture by ref token
```

Framework-agnostic, no Flutter runtime dependency in CLI calls, no `flutter_driver` isolate. Magic and Wind integrations ship inside those packages via the `DuskSnapshotEnricher` extension point, so a vanilla Flutter app gets every feature without pulling in `magic`.

## Features

| | Feature | Description |
|:--|:--------|:------------|
| 🌳 | **Semantics Snapshot** | `dusk_snap` emits a YAML tree with stable `[ref=eN]` tokens; every action tool targets a ref |
| 🛠️ | **32 CLI Commands** | Snapshot, tap, type, drag, scroll, hover, wait, find, navigate, modals, observe, hot reload, CDP device emulation |
| 🤖 | **31 MCP Tools** | The full CLI surface plus `dusk_evaluate`, exposed as stdio JSON-RPC tools to any MCP-capable agent |
| 🚪 | **5-Gate Actionability Gate** | Enabled, non-zero rect, in-viewport, stable, receives-events, every gesture passes the gate before the pointer fires |
| 🔖 | **RefRegistry q + e Tokens** | `e<N>` snap-frozen positions plus `q<N>` Playwright-Locator handles that re-resolve on every action call |
| 🎨 | **Snapshot Enricher Plugin** | `DuskPlugin.enrichers.add()` lets `magic` register 5 core enrichers (form state, route, gate, middleware, auth user) and `wind` register the 6-field className enricher |
| 🖥️ | **CDP Device Emulation** | `dusk_resize_viewport` and `dusk_device_profile` drive Chrome DevTools Protocol for responsive layout testing |
| 🔍 | **Telescope Bridge** | `dusk_console`, `dusk_exceptions`, `dusk_wait_for_network_idle` reach into telescope when installed, graceful no-op otherwise |
| ♻️ | **Hot Restart Safe** | Every extension registers through `registerExtensionIdempotent` so reload never throws `ArgumentError` |
| 🔒 | **Debug-Only by Default** | Consumer wraps `DuskPlugin.install()` in `kDebugMode`, release builds tree-shake the entire branch |

## Quick Start

### 1. Add the dependency

```bash
dart pub add fluttersdk_dusk
```

### 2. Wire `DuskPlugin.install()` inside `kDebugMode`

```dart
import 'package:flutter/foundation.dart';
import 'package:fluttersdk_dusk/dusk.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Install dusk core (wraps the widget root in a RepaintBoundary,
  //    registers every ext.dusk.* VM Service extension).
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
  MagicDuskIntegration.install();
  WindDuskIntegration.install();
}
```

Prefer the automated path. Run `dart run :artisan dusk:install` and the install command patches `lib/main.dart` for you, detecting Magic-stack via the `await Magic.init(` anchor and injecting the right call sites. Idempotent, safe to re-run.

### 3. Connect the MCP server for your AI agent

Dusk ships its MCP tool descriptors through `DuskArtisanProvider`. Register the provider in `bin/dispatcher.dart` and the artisan MCP server picks up every `dusk_*` tool automatically. Then point your agent at the artisan MCP entry:

```bash
dart run fluttersdk_artisan mcp:install
```

`mcp:install` writes (or updates) the `mcpServers.fluttersdk` entry in `.mcp.json`. Reconnect the MCP client once after install (for Claude Code, `/mcp reconnect fluttersdk`) and every `dusk_*` tool surfaces alongside the artisan substrate tools.

Read the full setup walkthrough at [MCP setup guide](https://fluttersdk.com/dusk/mcp/setup).

## CLI Commands

Dusk ships 32 CLI commands registered by `DuskArtisanProvider.commands()`, dispatched via `dart run :artisan <command>` once the provider is wired in `bin/dispatcher.dart`. The Flutter-free wrapper `dart run fluttersdk_dusk <command>` exposes the same surface from a pure-Dart context.

| Command | Purpose |
|---------|---------|
| `dusk:install` | Patch `lib/main.dart` to call `DuskPlugin.install()`. Detects Magic-stack via the `await Magic.init(` anchor; falls back to `runApp(` for vanilla Flutter. Idempotent. |
| `dusk:snap` | Capture a YAML snapshot of the Semantics tree with stable `[ref=eN]` tokens. |
| `dusk:tap` | Tap a widget by ref token from a prior `dusk:snap` (Down + 50ms + Up). |
| `dusk:screenshot` | Capture the current frame as a base64-encoded PNG or JPEG. |
| `dusk:type` | Type text into a `TextField` identified by ref token. Replaces existing content. |
| `dusk:scroll` | Scroll a `Scrollable` widget by ref token (direction + pixels). |
| `dusk:wait` | Wait until `text` / `textGone` / `expression` is satisfied, or the timeout expires. |
| `dusk:hover` | Hover a mouse cursor over a widget by ref token (web and desktop only). |
| `dusk:drag` | Drag from one widget to another by `startRef` + `endRef` tokens. |
| `dusk:modal` | Pop every modal route (dialog, bottom sheet, popup) above the first persistent route. |
| `dusk:navigate` | Push a route path onto the active navigator (`--route /dashboard`). |
| `dusk:navigate_back` | Pop the top route off the active navigator stack. |
| `dusk:get_routes` | Print the active navigator's location and title. |
| `dusk:press_key` | Synthesise `KeyDownEvent` + `KeyUpEvent` for a logical key with optional modifiers. |
| `dusk:select_option` | Drive a `DropdownButton` to the matching item (`--ref <ref> --value <value>`). |
| `dusk:close_app` | Graceful shutdown via `SystemNavigator.pop()` (no-op on web). |
| `dusk:find` | Mint a Playwright-Locator-style `q<N>` query handle by `--text` / `--semantics-label` / `--key`. |
| `dusk:doctor` | Diagnostic report: Chrome staleness, `DUSK_DISABLE` env var, enricher count, Semantics tree, Magic wiring. |
| `dusk:wait_for_network_idle` | Wait until the telescope-reported in-flight HTTP counter stays at zero for a contiguous window. |
| `dusk:console` | Read recent log entries from the telescope store (graceful no-op when telescope is absent). |
| `dusk:exceptions` | Read recent exception entries from the telescope store. |
| `dusk:dblclick` | Two tap sequences (~100ms apart) at the widget identified by ref. |
| `dusk:set_checkbox` | Read and conditionally toggle a `Checkbox` or `Switch` widget to the target state. |
| `dusk:observe` | Return a structured candidate list of every interactive widget (Stagehand observe-once-act-many). |
| `dusk:hot_reload_and_snap` | Trigger `reloadSources` over the VM Service, then capture snapshot + screenshot + exceptions in one call. |
| `dusk:focus` | Request keyboard focus on the widget identified by ref. |
| `dusk:blur` | Clear keyboard focus from whatever currently holds it. |
| `dusk:clear` | Empty the `TextEditingController` backing the resolved text field. |
| `dusk:right_click` | Fire a right (secondary mouse button) click at the widget identified by ref. |
| `dusk:triple_click` | Fire three primary clicks (~100ms apart) at the widget identified by ref. |
| `dusk:resize` | Resize the running Flutter web app viewport via Chrome DevTools Protocol. |
| `dusk:device` | Emulate a named device profile (iphone-x, pixel-5, ipad-pro-12.9, desktop-1440, etc.) via CDP. |

Full per-command flag reference at [commands catalog](https://fluttersdk.com/dusk/commands).

## MCP Tools

Dusk exposes 31 MCP tool descriptors through `DuskArtisanProvider.mcpTools()`. The artisan stdio MCP server picks them up automatically once the provider is registered. 28 tools route through `ext.dusk.*` VM Service extensions; 3 tools route through the `artisan:dusk:*` substrate dispatch prefix because they need to drive the VM Service from outside the running isolate (hot reload) or talk to Chrome DevTools Protocol from the CLI process (resize, device profile).

| Tool | Extension method | Purpose |
|------|------------------|---------|
| `dusk_snap` | `ext.dusk.snap` | YAML snapshot of the Semantics tree with stable `[ref=eN]` tokens. |
| `dusk_tap` | `ext.dusk.tap` | Tap a widget by ref token (Down + 50ms + Up). |
| `dusk_screenshot` | `ext.dusk.screenshot` | Base64-encoded PNG or JPEG of the current frame. |
| `dusk_hover` | `ext.dusk.hover` | `PointerHoverEvent` of `PointerDeviceKind.mouse` at widget center. |
| `dusk_drag` | `ext.dusk.drag` | Pointer Down + 5x Move + Up sequence between `startRef` and `endRef`. |
| `dusk_type` | `ext.dusk.type` | Type text into a `TextField` via `userUpdateTextEditingValue`. |
| `dusk_scroll` | `ext.dusk.scroll` | Drive the nearest `Scrollable` ancestor of `ref` (direction + pixels). |
| `dusk_wait_for` | `ext.dusk.wait_for` | Poll until `text` / `textGone` / `expression` flips, or timeout expires. |
| `dusk_dismiss_modals` | `ext.dusk.dismiss_modals` | Pop every modal route above the first persistent route. |
| `dusk_navigate` | `ext.dusk.navigate` | Push a route path onto the active router. |
| `dusk_navigate_back` | `ext.dusk.navigate_back` | Pop the top route off the active navigator stack. |
| `dusk_get_routes` | `ext.dusk.get_routes` | Return current router location and registered route paths. |
| `dusk_press_key` | `ext.dusk.press_key` | Synthesise `KeyDownEvent` + `KeyUpEvent` with optional modifiers. |
| `dusk_select_option` | `ext.dusk.select_option` | Drive a `DropdownButton` to the matching item. |
| `dusk_evaluate` | `ext.dusk.evaluate` | Evaluate a Dart expression in the running app isolate (MCP-only; tinker owns the CLI surface). |
| `dusk_close_app` | `ext.dusk.close_app` | Graceful shutdown via `SystemNavigator.pop()` (no-op on web). |
| `dusk_find` | `ext.dusk.find` | Mint a Playwright-Locator-style `q<N>` handle that re-resolves on every action call. |
| `dusk_wait_for_network_idle` | `ext.dusk.wait_for_network_idle` | Wait for telescope's in-flight HTTP counter to stay at zero for a contiguous idle window. |
| `dusk_console` | `ext.dusk.console` | Read recent log entries from the telescope store. |
| `dusk_exceptions` | `ext.dusk.exceptions` | Read recent exception entries from the telescope store. |
| `dusk_dblclick` | `ext.dusk.dblclick` | Two tap sequences (~100ms apart) at the widget identified by ref. |
| `dusk_set_checkbox` | `ext.dusk.set_checkbox` | Idempotent read + toggle of a `Checkbox` or `Switch` to the target state. |
| `dusk_observe` | `ext.dusk.observe` | Structured candidate list of every interactive widget (Stagehand observe pattern). |
| `dusk_focus` | `ext.dusk.focus` | Request keyboard focus on the widget identified by ref. |
| `dusk_blur` | `ext.dusk.blur` | Clear keyboard focus from whatever currently holds it. |
| `dusk_clear` | `ext.dusk.clear` | Empty the `TextEditingController` backing the resolved text field. |
| `dusk_right_click` | `ext.dusk.right_click` | Right (secondary mouse button) click at the widget identified by ref. |
| `dusk_triple_click` | `ext.dusk.triple_click` | Three primary clicks (~100ms apart) at the widget identified by ref. |
| `dusk_hot_reload_and_snap` | `artisan:dusk:hot_reload_and_snap` | Hot reload + snapshot + screenshot + exceptions in one round-trip. |
| `dusk_resize_viewport` | `artisan:dusk:resize` | Resize the running Flutter web app viewport via Chrome DevTools Protocol. |
| `dusk_device_profile` | `artisan:dusk:device` | Emulate a named device profile (iphone-x, pixel-5, ipad-pro-12.9, etc.) via CDP. |

Full MCP tool reference at [tool reference](https://fluttersdk.com/dusk/mcp/tool-reference).

## VM Service extensions

Dusk registers 28 `ext.dusk.*` VM Service extensions plus 3 substrate-routed MCP tools that drive the VM Service from the CLI process (hot reload from inside the same isolate would deadlock; CDP-driven resize and device profile need a non-Flutter Dart context to talk to Chrome over the DevTools port). Every extension registers via `registerExtensionIdempotent` (from `fluttersdk_artisan`) for hot-restart safety, runs through the actionability gate where relevant, and returns `ServiceExtensionResponse.result(jsonEncode(payload))` on success or `.error(extensionError, msg)` on bad input.

`ext.dusk.blur`, `ext.dusk.clear`, `ext.dusk.close_app`, `ext.dusk.console`, `ext.dusk.dblclick`, `ext.dusk.dismiss_modals`, `ext.dusk.drag`, `ext.dusk.evaluate`, `ext.dusk.exceptions`, `ext.dusk.find`, `ext.dusk.focus`, `ext.dusk.get_routes`, `ext.dusk.hover`, `ext.dusk.navigate`, `ext.dusk.navigate_back`, `ext.dusk.observe`, `ext.dusk.press_key`, `ext.dusk.right_click`, `ext.dusk.screenshot`, `ext.dusk.scroll`, `ext.dusk.select_option`, `ext.dusk.set_checkbox`, `ext.dusk.snap`, `ext.dusk.tap`, `ext.dusk.triple_click`, `ext.dusk.type`, `ext.dusk.wait_for`, `ext.dusk.wait_for_network_idle`.

Substrate-routed MCP tools (CLI-dispatched via the `artisan:dusk:*` prefix): `artisan:dusk:hot_reload_and_snap`, `artisan:dusk:resize`, `artisan:dusk:device`.

## Architecture

Dusk is subsystem-first under `lib/src/`. Every directory owns a single concern.

```
lib/
├── dusk.dart                       # Single barrel, re-exports the full public API
├── cli.dart                        # Flutter-free codegen barrel (FluttersdkDuskArtisanProvider typedef)
└── src/
    ├── extensions/                 # registerDuskExtensions() + per-concern VM Service handlers
    │                               #   (snapshot, screenshot, pointer, text_input, scroll, wait_find,
    │                               #    modal_router, navigation, evaluate, close_app, find, observe,
    │                               #    focus, checkbox, console, exceptions, hot_reload_and_snap)
    ├── commands/                   # 32 ArtisanCommand subclasses, one file each
    ├── cdp/                        # Chrome DevTools Protocol client (Emulation.* methods for resize + device)
    ├── utils/                      # actionability_gate, chrome_reaper, dusk_exceptions (typed errors)
    └── console/                    # YAML emitter for dusk_snap output (per-node ref + role + label + actions)
```

Cross-package contracts that other packages depend on:

- `DuskSnapshotEnricher` typedef: `String? Function(Element element, RefRegistry refs)`. Frozen for the alpha-2 cycle. `magic` registers 5 core enrichers via `MagicDuskIntegration` (form state, route, gate, middleware, auth user); `wind` registers the 6-field `WindClassNameEnricher`.
- `DuskPlugin.install()` and `DuskPlugin.registerEnricher()` signatures: frozen.
- `RefRegistry` public methods (`mint`, `lookup`, `recordQuery`, `resolveQuery`, `clear`, `resetForTesting`): frozen; the magic-side enrichers and the find handler call them directly.
- `q<N>` and `e<N>` token spaces: disjoint. `dusk_find` mints `q<N>` only; `dusk_snap` mints `e<N>` only.

## AI Agent Integration

Use dusk with AI coding assistants like Claude Code, Cursor, or GitHub Copilot. The artisan MCP server (which surfaces every dusk tool) gives the agent direct access: start the Flutter app, capture the Semantics tree, drive any gesture, inspect HTTP traffic, evaluate Dart expressions, all without spawning shells or pattern-matching log output.

A typical agent session looks like this:

```
[agent] artisan_doctor                                  // verify toolchain
[agent] artisan_start { device: chrome }                // launch the app
[agent] dusk_snap                                       // capture Semantics tree, get ref tokens
[agent] dusk_tap { ref: "e7" }                          // drive the gesture by ref
[agent] dusk_wait_for { text: "Welcome", timeoutMs: 3000 }  // bridge the async transition
[agent] dusk_screenshot                                 // visual verification
[agent] dusk_exceptions { limit: 5 }                    // assert no unexpected throws
[agent] artisan_stop                                    // tear down
```

For agents that read structured project context at attach time, the canonical entry point is [`llms.txt`](llms.txt) at the repo root (also published at `https://fluttersdk.com/dusk/llms.txt`). It enumerates the command surface, the MCP tool catalog, and the snapshot enricher contract in agent-readable form.

Skill files and per-agent setup recipes: **[fluttersdk/ai](https://github.com/fluttersdk/ai)**.

## Documentation

Full docs with live examples at **[fluttersdk.com/dusk](https://fluttersdk.com/dusk)**.

| Topic | |
|:------|:-|
| [Getting Started](https://fluttersdk.com/dusk/getting-started) | Overview, requirements, the snapshot model |
| [Installation](https://fluttersdk.com/dusk/getting-started/installation) | `dart pub add fluttersdk_dusk` plus `dusk:install` walkthrough |
| [Quickstart](https://fluttersdk.com/dusk/getting-started/quickstart) | The 3-step path from empty repo to first snapshot |
| [Commands](https://fluttersdk.com/dusk/commands) | The 32 CLI commands grouped by concern |
| [dusk:install](https://fluttersdk.com/dusk/commands/dusk-install) | Smart-merge install flow, Magic detection, idempotency rules |
| [dusk:snap](https://fluttersdk.com/dusk/commands/dusk-snap) | Snapshot YAML shape, enricher fields, ref token semantics |
| [dusk:tap](https://fluttersdk.com/dusk/commands/dusk-tap) | Tap synthesis, actionability gate failure modes |
| [dusk:screenshot](https://fluttersdk.com/dusk/commands/dusk-screenshot) | PNG vs JPEG, quality tuning, RepaintBoundary mechanics |
| [dusk:find](https://fluttersdk.com/dusk/commands/dusk-find) | Playwright-Locator handles, q-ref re-resolution, stale-handle errors |
| [dusk:doctor](https://fluttersdk.com/dusk/commands/dusk-doctor) | Categorised checks (OK / WARN / ERROR), troubleshooting matrix |
| [dusk:observe](https://fluttersdk.com/dusk/commands/dusk-observe) | Stagehand observe-once-act-many pattern, candidate list shape |
| [MCP Overview](https://fluttersdk.com/dusk/mcp/overview) | Substrate + plugin tool layers, lifecycle, missing-telescope graceful path |
| [MCP Setup](https://fluttersdk.com/dusk/mcp/setup) | Per-client install (Claude Code, Cursor, Continue) |
| [MCP Tool Reference](https://fluttersdk.com/dusk/mcp/tool-reference) | Every tool, every input schema, every example call |
| [Magic Integration](https://fluttersdk.com/dusk/plugins/magic-integration) | The 5 core magic enrichers, install order, framework-internals access |
| [Wind Integration](https://fluttersdk.com/dusk/plugins/wind-integration) | The 6-field WindClassNameEnricher, breakpoint and states fields |
| [Enricher Authoring](https://fluttersdk.com/dusk/plugins/enricher-authoring) | Writing your own DuskSnapshotEnricher, RefRegistry usage |
| [Actionability Gate](https://fluttersdk.com/dusk/reference/actionability-gate) | The 5 preconditions, error message format, agent-side branching |

## Contributing

```bash
git clone https://github.com/fluttersdk/dusk.git
cd dusk && flutter pub get
flutter test
flutter test --coverage
```

The baseline is 395+ tests green at 0.0.1. New behavior ships with the matching test (red, green, refactor). `dart format lib/ test/` must produce no diff and `dart analyze` must report zero issues across `lib/` and `test/`.

Before opening a pull request, also run:

```bash
dart format lib/ test/                # zero diff
dart analyze                          # zero issues
flutter test --coverage               # line coverage target 80%+
dart pub publish --dry-run            # validate the publish archive
```

Line coverage gate is 80% on `lib/`, enforced by CI (`Enforce 80% line coverage floor` step in `.github/workflows/ci.yml`); 0.0.1 ships at 80.08%. The `.pubignore` excludes platform shells under `example/`, `build/`, `coverage/`, and editor scaffolding from the pub archive; extend it if you add new top-level directories that should not ship.

[Report a bug](https://github.com/fluttersdk/dusk/issues/new?template=bug_report.yml) · [Request a feature](https://github.com/fluttersdk/dusk/issues/new?template=feature_request.yml)

## License

MIT, see [LICENSE](LICENSE) for details.

---

<p align="center">
  <sub>Built with care by <a href="https://github.com/fluttersdk">FlutterSDK</a></sub><br/>
  <sub>If dusk saves you time, <a href="https://github.com/fluttersdk/dusk">give it a star</a>, it helps others discover it.</sub>
</p>
