# fluttersdk_dusk

E2E driver for Flutter apps: snapshot, tap, type, drag, scroll, hover, screenshot, wait, navigate, find, evaluate over `ext.dusk.*` VM Service extensions. Framework-agnostic (vanilla Flutter friendly); Magic / Wind integrations ship inside those packages via the `DuskSnapshotEnricher` extension point.

---

> **Alpha Release**: Dusk is under active development. APIs may change before stable.

## CLI Commands

Registered via `DuskArtisanProvider.commands()` and dispatched through `dart run :artisan <command>` once the provider is wired in `bin/artisan.dart`. The Flutter-free wrapper `dart run fluttersdk_dusk <command>` exposes the same surface from a pure-Dart context.

| Command | Purpose |
|---------|---------|
| `dusk:install` | One-shot bootstrap: scaffolds the consumer artisan harness, runs `plugin:install fluttersdk_dusk`, and injects `DuskPlugin.install()` into `lib/main.dart`. Detects Magic-stack apps via the `await Magic.init(` anchor and injects BEFORE Magic.init (with `MagicDuskIntegration.install()` + `WindDuskIntegration.install()` AFTER); falls back to `runApp(` for vanilla Flutter. Idempotent. |
| `dusk:snap` | Capture a YAML snapshot of the running app's Semantics tree with stable `[ref=eN]` tokens. |
| `dusk:tap` | Tap a widget by ref token from a prior `dusk:snap`. |
| `dusk:screenshot` | Capture a screenshot of the running app as a base64-encoded image (PNG or JPEG). |
| `dusk:type` | Type text into a TextField identified by ref token. Replaces existing content. |
| `dusk:scroll` | Scroll a Scrollable widget by ref token. Optional direction + pixels. |
| `dusk:wait` | Wait until a UI condition (`text` / `textGone` / `expression`) is satisfied or the timeout expires. |
| `dusk:hover` | Hover a mouse cursor over a widget by ref token (web + desktop only). |
| `dusk:drag` | Drag from one widget to another by `startRef` + `endRef` tokens. |
| `dusk:modal` | Pop every modal route (dialog, bottom sheet, popup) currently above the first persistent route. |
| `dusk:doctor` | Diagnostic command: checks VM Service reachability, artisan plugin registration, actionability-gate prerequisites, Chrome reaper permissions. Categorised report (OK / WARN / ERROR per check). |

## MCP Tools

Exposed via `DuskArtisanProvider` when the consumer registers it in `bin/artisan.dart`. All tools route through `ext.dusk.*` VM Service extensions and require a running Flutter app with `DuskPlugin.install()` called.

| Tool | Extension method | Purpose |
|------|------------------|---------|
| `dusk_snap` | `ext.dusk.snap` | YAML snapshot of the Semantics tree with stable `[ref=eN]` tokens. |
| `dusk_tap` | `ext.dusk.tap` | Tap a widget by ref token (Down + 50ms + Up). |
| `dusk_screenshot` | `ext.dusk.screenshot` | Base64-encoded PNG / JPEG of the current frame. |
| `dusk_hover` | `ext.dusk.hover` | `PointerHoverEvent` of `PointerDeviceKind.mouse` at widget center. |
| `dusk_drag` | `ext.dusk.drag` | Pointer Down + 5x Move + Up sequence between `startRef` and `endRef`. |
| `dusk_type` | `ext.dusk.type` | Type text into a TextField via `userUpdateTextEditingValue`. Replaces existing content. |
| `dusk_scroll` | `ext.dusk.scroll` | Drive the nearest Scrollable ancestor of `ref` (direction + pixels). |
| `dusk_wait_for` | `ext.dusk.wait_for` | Poll until `text` / `textGone` / `expression` condition flips, or the timeout expires. |
| `dusk_dismiss_modals` | `ext.dusk.dismiss_modals` | Pop every modal route above the first persistent route. |
| `dusk_navigate` | `ext.dusk.navigate` | Push a route path onto the active router (`MagicRoute.to` or `Navigator.pushNamed`). |
| `dusk_navigate_back` | `ext.dusk.navigate_back` | Pop the top route off the active navigator stack. |
| `dusk_get_routes` | `ext.dusk.get_routes` | List declared route paths from the active `MagicRouter` (empty when no Magic router). |
| `dusk_press_key` | `ext.dusk.press_key` | Synthesise a `KeyDownEvent` + `KeyUpEvent` with optional modifiers (`control` / `shift` / `alt` / `meta`). |
| `dusk_select_option` | `ext.dusk.select_option` | Drive a `DropdownButton` / `DropdownButtonFormField` to the matching item by `ref` + `value`. |
| `dusk_evaluate` | `ext.dusk.evaluate` | Forward a Dart expression to the Tinker bridge (`ext.tinker.evaluate`) and return the stringified result. |
| `dusk_close_app` | `ext.dusk.close_app` | Graceful shutdown via `SystemNavigator.pop()` (no-op on web). |
| `dusk_find` | `ext.dusk.find` | Mint a Playwright-Locator-style `q<N>` query handle. Re-executes the Semantics + Element walk on every action call; survives widget rebuilds and route pushes as long as the predicates still match. |

## VM Service extensions

All extensions register through `registerExtensionIdempotent` (from `fluttersdk_artisan`) for hot-restart safety, route through the actionability gate where relevant, and return `ServiceExtensionResponse.result(jsonEncode(payload))` on success or `.error(kInvalidParams, msg)` on bad input.

`ext.dusk.snap`, `ext.dusk.screenshot`, `ext.dusk.tap`, `ext.dusk.hover`, `ext.dusk.drag`, `ext.dusk.type`, `ext.dusk.scroll`, `ext.dusk.wait_for`, `ext.dusk.dismiss_modals`, `ext.dusk.press_key`, `ext.dusk.select_option`, `ext.dusk.navigate`, `ext.dusk.navigate_back`, `ext.dusk.get_routes`, `ext.dusk.evaluate`, `ext.dusk.close_app`, `ext.dusk.find`.

## Quick Start

### Option A (recommended): one-shot install

Once the consumer has `fluttersdk_artisan` wired (`bin/artisan.dart` + `.artisan/plugins.json`), let dusk install itself end-to-end:

```bash
dart run :artisan dusk:install
```

The command scaffolds the consumer artisan harness if it's missing, runs `plugin:install fluttersdk_dusk`, and patches `lib/main.dart` so `DuskPlugin.install()` runs before `Magic.init()` (or before `runApp` on vanilla Flutter). When Magic is detected, the patch also adds `MagicDuskIntegration.install()` + `WindDuskIntegration.install()` AFTER `Magic.init()` so all 8 snapshot enrichers register. Idempotent; safe to re-run.

### Option B: manual wiring

#### 1. Add the dependency

```yaml
# pubspec.yaml
dependencies:
  fluttersdk_dusk:
    path: ../path/to/fluttersdk_dusk
```

#### 2. Install in `main.dart`

Install Dusk before `Magic.init()` (or before `runApp` for plain Flutter). Wrap every install call in `kDebugMode` so the entire tooling branch is tree-shaken in release builds.

```dart
import 'package:flutter/foundation.dart';
import 'package:fluttersdk_dusk/dusk.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Install Dusk core (wraps the widget root in a RepaintBoundary,
  //    registers the 17 ext.dusk.* VM Service extensions).
  if (kDebugMode) {
    DuskPlugin.install();
  }

  // 2. Magic + Wind enrichers run AFTER Magic.init() because they resolve
  //    framework internals (form state, route, gate result, controller) from
  //    the IoC container.
  await Magic.init(configFactories: [...]);

  if (kDebugMode) {
    MagicDuskIntegration.install();
    WindDuskIntegration.install();
  }

  runApp(MyApp());
}
```

#### 3. Register the Artisan provider (MCP tools + CLI commands)

In `bin/artisan.dart`, register `DuskArtisanProvider` so the 17 `dusk_*` MCP tools + 11 `dusk:*` CLI commands surface to Claude Code and other MCP / CLI clients:

```dart
import 'package:fluttersdk_dusk/dusk.dart' show DuskArtisanProvider;

exit(await runArtisan(
  args,
  baseProviders: [
    MagicArtisanProvider(),
    DuskArtisanProvider(),
    ...plugins.autoDiscoveredProviders(),
  ],
));
```

## Examples

### `example/`

Vanilla Flutter app (no Magic framework) that exercises the framework-agnostic capture + drive surface: snapshot, tap, type, screenshot, scroll, drag, hover, wait, find. Demonstrates the minimal install pattern.

```bash
cd example && flutter run -d chrome
```

### `example_magic/`

Magic + Wind stack app that exercises all 8 snapshot enrichers via `MagicDuskIntegration` (`magicFormField`, `magicRoute`, `magicControllerEnricher`, `magicFormErrorsEnricher`, `magicGateResultEnricher`, `magicMiddlewareEnricher`, `magicAuthUserEnricher`) + `WindDuskIntegration` (6-field enricher: breakpoint, brightness, platform, states, bgColor, textColor). Use the artisan MCP server from this directory to verify all 17 `dusk_*` MCP tools surface correctly.

```bash
cd example_magic && flutter run -d chrome
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.
