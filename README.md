# fluttersdk_dusk

E2E driver for Flutter apps: snapshot, tap, type, drag, scroll, hover, screenshot, wait, navigate, find, evaluate over `ext.dusk.*` VM Service extensions. Framework-agnostic (vanilla Flutter friendly); Magic / Wind integrations ship inside those packages via the `DuskSnapshotEnricher` extension point.

---

> **0.0.1**: Initial release. APIs may evolve across the 0.x line; the typedef + plugin install signatures stay stable.

## CLI Commands

Registered via `DuskArtisanProvider.commands()` and dispatched through `dart run :artisan <command>` once the provider is wired in `bin/artisan.dart`. The Flutter-free wrapper `dart run fluttersdk_dusk <command>` exposes the same surface from a pure-Dart context.

| Command | Purpose |
|---------|---------|
| `dusk:install` | Minimal install. Edits `lib/main.dart` only. Detects Magic-stack via the `await Magic.init(` anchor and injects `DuskPlugin.install()` BEFORE (with `MagicDuskIntegration.install()` + `WindDuskIntegration.install()` AFTER); falls back to `runApp(` for vanilla Flutter. Idempotent. |
| `dusk:snap` | Capture a YAML snapshot of the Semantics tree with stable `[ref=eN]` tokens. |
| `dusk:tap` | Tap a widget by ref token from a prior `dusk:snap` (Down + 50ms + Up). |
| `dusk:screenshot` | Capture the current frame as a base64-encoded image (PNG or JPEG). |
| `dusk:type` | Type text into a TextField identified by ref token. Replaces existing content. |
| `dusk:scroll` | Scroll a Scrollable widget by ref token (`dy` / `dx` deltas, or `intoView`). |
| `dusk:wait` | Wait until `text` / `textGone` / `expression` is satisfied, or the timeout expires. |
| `dusk:hover` | Hover a mouse cursor over a widget by ref token (web + desktop only). |
| `dusk:drag` | Drag from one widget to another by `startRef` + `endRef` tokens. |
| `dusk:modal` | Pop every modal route (dialog, bottom sheet, popup) above the first persistent route. |
| `dusk:navigate` | Push a route path onto the active navigator (`--route /dashboard`). |
| `dusk:navigate_back` | Pop the top route off the active navigator stack. |
| `dusk:get_routes` | Print the active navigator's location + title. |
| `dusk:press_key` | Synthesise `KeyDownEvent` + `KeyUpEvent` for a logical key (`--key Enter`, optional `--modifiers`). |
| `dusk:select_option` | Drive a `DropdownButton` to the matching item (`--ref <ref> --value <value>`). |
| `dusk:close_app` | Graceful shutdown via `SystemNavigator.pop()` (no-op on web). |
| `dusk:find` | Mint a Playwright-Locator-style `q<N>` query handle (`--text` / `--semantics-label` / `--key`). Re-executes on every action call. |
| `dusk:doctor` | Diagnostic command: Chrome staleness, `DUSK_DISABLE` env-var, enricher count, Semantics tree, Magic-init wiring. Categorised report (OK / WARN / ERROR per check). |

## MCP Tools

Exposed via `DuskArtisanProvider` when the consumer registers it in `bin/artisan.dart`. All tools route through `ext.dusk.*` VM Service extensions and require a running Flutter app with `DuskPlugin.install()` called.

| Tool | Extension method | Purpose |
|------|------------------|---------|
| `dusk_snap` | `ext.dusk.snap` | YAML snapshot of the Semantics tree with stable `[ref=eN]` tokens. |
| `dusk_screenshot` | `ext.dusk.screenshot` | Base64-encoded PNG / JPEG of the current frame. |
| `dusk_tap` | `ext.dusk.tap` | Tap a widget by ref token (Down + 50ms + Up). |
| `dusk_type` | `ext.dusk.type` | Type text into a TextField via `userUpdateTextEditingValue`. Replaces existing content. |
| `dusk_press_key` | `ext.dusk.press_key` | Synthesise `KeyDownEvent` + `KeyUpEvent` with optional modifiers. |
| `dusk_hover` | `ext.dusk.hover` | `PointerHoverEvent` of `PointerDeviceKind.mouse` at widget center. |
| `dusk_drag` | `ext.dusk.drag` | Pointer Down + 5x Move + Up sequence between `startRef` and `endRef`. |
| `dusk_scroll` | `ext.dusk.scroll` | Drive the nearest Scrollable ancestor of `ref` (direction + pixels, or `intoView`). |
| `dusk_select_option` | `ext.dusk.select_option` | Drive a `DropdownButton` to the matching item by `ref` + `value`. |
| `dusk_wait_for` | `ext.dusk.wait_for` | Poll until `text` / `textGone` / `expression` flips, or the timeout expires. |
| `dusk_dismiss_modals` | `ext.dusk.dismiss_modals` | Pop every modal route above the first persistent route. |
| `dusk_navigate` | `ext.dusk.navigate` | Push a route path onto the active router (`MagicRoute.to` or `Navigator.pushNamed`). |
| `dusk_navigate_back` | `ext.dusk.navigate_back` | Pop the top route off the active navigator stack. |
| `dusk_get_routes` | `ext.dusk.get_routes` | Return current router location + page title. |
| `dusk_close_app` | `ext.dusk.close_app` | Graceful shutdown via `SystemNavigator.pop()` (no-op on web). |
| `dusk_find` | `ext.dusk.find` | Mint a Playwright-Locator-style `q<N>` handle. Re-executes on every action call; survives widget rebuilds + route pushes. |
| `dusk_doctor` | `ext.dusk.doctor` | Diagnostic snapshot of the runtime + consumer wiring (mirrors `dusk:doctor`). |

`dusk_evaluate` is intentionally MCP-only (no matching CLI): the `magic_tinker` plugin owns the connected REPL surface; the dusk tool exists so MCP-only agents can fan out to evaluate without juggling two plugins.

## VM Service extensions

All extensions register through `registerExtensionIdempotent` (from `fluttersdk_artisan`) for hot-restart safety, route through the actionability gate where relevant, and return `ServiceExtensionResponse.result(jsonEncode(payload))` on success or `.error(extensionError, msg)` on bad input.

`ext.dusk.snap`, `ext.dusk.screenshot`, `ext.dusk.tap`, `ext.dusk.hover`, `ext.dusk.drag`, `ext.dusk.type`, `ext.dusk.scroll`, `ext.dusk.wait_for`, `ext.dusk.dismiss_modals`, `ext.dusk.press_key`, `ext.dusk.select_option`, `ext.dusk.navigate`, `ext.dusk.navigate_back`, `ext.dusk.get_routes`, `ext.dusk.evaluate`, `ext.dusk.close_app`, `ext.dusk.find`.

## Quick Start

### Option A (recommended): one-shot install

Once the consumer has `fluttersdk_artisan` wired (`bin/artisan.dart` + `.artisan/plugins.json`), let dusk install itself:

```bash
dart run :artisan dusk:install
```

The command patches `lib/main.dart` so `DuskPlugin.install()` runs before `Magic.init()` (or before `runApp` on vanilla Flutter). When Magic is detected, the patch also adds `MagicDuskIntegration.install()` + `WindDuskIntegration.install()` AFTER `Magic.init()` so the snapshot enrichers register. Idempotent; safe to re-run.

For vanilla Flutter apps (no Magic), the consumer does NOT need `bin/artisan.dart` or `lib/app/` scaffolding — just `dart run fluttersdk_dusk <cmd>` from the package root.

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

In `bin/artisan.dart`, register `DuskArtisanProvider` so the 17 `dusk_*` MCP tools + 18 `dusk:*` CLI commands surface to Claude Code and other MCP / CLI clients:

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

Vanilla Flutter app (no Magic framework) with 7 scenario screens: home menu, buttons, inputs, scroll, modals, drawer, forms. Exercises the framework-agnostic capture + drive surface: snapshot, tap, type, screenshot, scroll, drag, hover, wait, find, select_option, press_key, modal dismiss, navigate, navigate_back.

```bash
cd example && flutter run -d chrome
```

Then drive it from a separate terminal:

```bash
dart run fluttersdk_dusk dusk:snap
dart run fluttersdk_dusk dusk:tap --ref e7
dart run fluttersdk_dusk dusk:type --ref e12 --text 'hello dusk'
```

## DUSK_DISABLE kill switch

Set the `DUSK_DISABLE` env var (or `--dart-define=DUSK_DISABLE=1`) to `1`, `true`, or `yes` (case-insensitive) to skip `DuskPlugin.install()` even when called from `kDebugMode` code. Useful for screenshot-only release builds or pixel-diff CI pipelines that need a clean tree.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.
