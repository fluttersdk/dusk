# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0-alpha.2] - 2026-05-19

### Added

- **Deprecation + analyzer cleanup**: alpha-1 code purged of every Flutter 3.22 deprecation (`SchedulerBinding.scheduleFrameCallback` shape, `WidgetsBinding.instance.platformDispatcher`, `gestures` enum spellings). `dart analyze` returns zero issues across `lib/` and `test/` on the package's pinned Dart 3.4 / Flutter 3.22 floor.
- **Flutter-free CLI wrapper**: `bin/fluttersdk_dusk.dart` + `executables: fluttersdk_dusk` pubspec entry. `dart run fluttersdk_dusk <cmd>` proxies the full artisan CLI surface and exposes the dusk commands without dragging `dart:ui` into pure-Dart contexts (mirrors the `fluttersdk_telescope` pattern).
- **`install.yaml` plugin manifest + executables wiring**: V1 manifest at the package root with empty publish list + a post-install bootstrap message (the three-step Magic / Wind / verify recipe). Makes `plugin:install fluttersdk_dusk` work end-to-end via the artisan `PluginInstaller`, and registers `DuskArtisanProvider` into the consumer's `lib/app/_plugins.g.dart` codegen barrel.
- **7 new VM Service extension handlers**: `ext.dusk.scroll`, `ext.dusk.wait_for`, `ext.dusk.dismiss_modals`, `ext.dusk.navigate`, `ext.dusk.navigate_back`, `ext.dusk.get_routes`, `ext.dusk.press_key`, `ext.dusk.select_option`, `ext.dusk.evaluate`, `ext.dusk.close_app`, `ext.dusk.find`. Each follows the alpha-1 handler shape: parse `Map<String, String> params`, route through the actionability gate, return `ServiceExtensionResponse.result(jsonEncode(payload))`, register idempotently. (Eleven new method names; "7 new handlers" reflects the seven new `extensions/ext_*.dart` files contributing them.)
- **10 new MCP tool descriptors**: `dusk_scroll`, `dusk_wait_for`, `dusk_dismiss_modals`, `dusk_navigate`, `dusk_navigate_back`, `dusk_get_routes`, `dusk_press_key`, `dusk_select_option`, `dusk_evaluate`, `dusk_close_app`. All contributed via `DuskArtisanProvider.mcpTools()` as `McpToolDescriptor` const instances with Claude Code canonical descriptions (imperative opener + context paragraph + `Usage:` bullets). Brings the MCP surface to 17 tools (the 11th alpha-2 tool, `dusk_find`, is called out separately below).
- **8 new CLI commands**: `dusk:install`, `dusk:type`, `dusk:scroll`, `dusk:wait`, `dusk:hover`, `dusk:drag`, `dusk:modal`, `dusk:doctor`. Each wraps the matching VM Service extension; `dusk:install` is the one-shot bootstrap (see below). Provider `commands()` now returns 11 commands (3 alpha-1 + 8 alpha-2).
- **Actionability gate** (`lib/src/utils/actionability_gate.dart`): every action handler (`tap`, `hover`, `drag`, `type`, `scroll`, `select_option`, `press_key`) now resolves through a single gate that verifies the target's visibility, hit-testability, and enabled state BEFORE synthesising the pointer / key event. Replaces the alpha-1 silent no-op + best-effort path.
- **`dusk:find` Playwright-Locator pattern** (Step 16): mints `q<N>` query handles backed by the supplied predicates (`text` / `semanticsLabel` / `key`). Unlike `e<N>` refs (frozen at snap time), q-handles re-execute the Semantics + Element walk on every action call, so they survive widget rebuilds and route pushes as long as the predicates still match. Stale match returns an explicit `stale-handle` error result; the agent re-finds, never silently retries.
- **`dusk:install` one-shot bootstrap**: orchestrates `consumer:scaffold` + `plugin:install fluttersdk_dusk` + `lib/main.dart` injection. Detects Magic-stack apps via the `await Magic.init(` anchor and injects `DuskPlugin.install()` BEFORE Magic.init (then `MagicDuskIntegration.install()` + `WindDuskIntegration.install()` AFTER), falling back to the `runApp(` anchor for vanilla Flutter apps. Idempotent; safe to re-run.
- **Chrome reaper** (`lib/src/utils/chrome_reaper.dart`): graceful Chromium subprocess teardown between dusk:* runs so leftover headless tabs no longer accumulate. Detects orphans by VM Service URI, exits cleanly via `SystemNavigator.pop` first, falls back to SIGTERM.
- **`dusk:doctor`** (Step 21): diagnostic command that checks VM Service reachability, artisan plugin registration, the actionability gate's prerequisites, and the Chrome reaper's permissions in one pass. Emits a categorised report (OK / WARN / ERROR per check); exit code 0 when every check passes.
- **Example apps**: `example/` (vanilla Flutter) and `example_magic/` (Magic + Wind stack) for live e2e validation against the 17 MCP tools + 11 CLI commands. The Magic example registers `MagicDuskIntegration` + `WindDuskIntegration` to exercise all 8 snapshot enrichers (2 alpha-1 + 5 from Magic Step 17 + Wind's 6-field enricher).
- **`lib/cli.dart` codegen barrel**: Flutter-free typedef alias `FluttersdkDuskArtisanProvider`. Consumed by consumer-side `lib/app/_plugins.g.dart` auto-discovery without pulling Flutter symbols into the pure-Dart artisan codegen path.

### Changed

- **Actionability gate (behavior change)**: action handlers no longer silently succeed when the target widget is offscreen, hit-test-occluded, or disabled. They now return a structured `actionability` error result naming the failing precondition (`visibility` / `hit-test` / `enabled`). Callers that previously relied on the silent no-op must either re-snap into view first or pre-check via `dusk_find`. This is the only behavior change in alpha-2; everything else is additive.

### Magic-side coordinated changes (require magic ^[1.0.0-alpha.14] or unreleased main)

- `magic/lib/src/cli/dusk_integration.dart`: 5 new enrichers added by Magic Step 17 — `magicControllerEnricher`, `magicFormErrorsEnricher`, `magicGateResultEnricher`, `magicMiddlewareEnricher`, `magicAuthUserEnricher`. Combined with the 2 alpha-1 enrichers (`magicFormField`, `magicRoute`), `MagicDuskIntegration.install()` now registers 7 enrichers; Wind ships its own 6-field enricher (`WindDuskIntegration.install()`) for an 8-enricher total surface.
- `magic/lib/src/auth/gate_manager.dart` + `magic/lib/src/http/middleware_pipeline.dart`: small instrumentation hooks added so the new gate-result + middleware enrichers can read the last decision / pipeline trace from the Element being snapshotted. Backward compatible; no signature changes to public APIs.

### Test coverage

- Dusk: per-command + per-handler tests for the 8 new commands and 11 new handler entry points, plus actionability-gate unit tests (visibility / hit-test / enabled / disabled-edge), `dusk_find` stale-handle round-trip, Chrome reaper subprocess teardown, and `dusk:doctor` categorised-report shape.
- Magic: 1120 tests green (+5 from new enricher integration tests under `test/cli/dusk_integration_test.dart`).

### Backward compat

`DuskSnapshotEnricher` typedef, `DuskPlugin.install` / `registerEnricher`, `RefRegistry` public methods, and the 6 alpha-1 MCP tool names (`dusk_snap`, `dusk_tap`, `dusk_screenshot`, `dusk_hover`, `dusk_drag`, `dusk_type`) are all unchanged. The 11 new tools, 11 new extensions, 8 new commands, and `q<N>` handle space are pure additions. The actionability gate is the only behavior change in alpha-2; see Changed.

---

## [1.0.0-alpha.1] - 2026-04-12

Initial alpha release. E2E driver for Flutter apps with a framework-agnostic core, snapshot-enricher extension point for Magic / Wind, and VM Service surface for CLI + MCP tool access.

### Added

- **`RefRegistry`**: stable `e<N>` token system for Semantics-tree element handles. Refs are minted at `dusk_snap` time and consumed by every action tool.
- **`DuskPlugin.install()`**: idempotent host-side install entry. Wraps the app widget root in a `RepaintBoundary` (no `GlobalKey`) so `ext.dusk.screenshot` can find it via render-tree walk.
- **`DuskSnapshotEnricher` typedef**: snapshot-enricher extension point. Magic ships `MagicFormEnricher` + `MagicNavigationEnricher` via this contract; Wind ships `WindClassNameEnricher`. Contract: synchronous, stateless w.r.t. call ordering, first-write-wins on overlapping output keys, may return `null` to skip.
- **6 MCP tools**: `dusk_snap`, `dusk_tap`, `dusk_screenshot`, `dusk_hover`, `dusk_drag`, `dusk_type`. All contributed via `DuskArtisanProvider.mcpTools()`.
- **3 CLI commands**: `dusk:snap`, `dusk:tap`, `dusk:screenshot`. Each wraps the matching VM Service extension.
- **6 VM Service extensions** (`ext.dusk.*`): `snap`, `tap`, `screenshot`, `hover`, `drag`, `type`. All registered through `registerExtensionIdempotent` for hot-restart safety.
