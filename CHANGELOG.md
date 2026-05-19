# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0-alpha.2] - 2026-05-19

### Added

- **Deprecation + analyzer cleanup**: alpha-1 code purged of every Flutter 3.22 deprecation (`SchedulerBinding.scheduleFrameCallback` shape, `WidgetsBinding.instance.platformDispatcher`, `gestures` enum spellings). `dart analyze` returns zero issues across `lib/` and `test/` on the package's pinned Dart 3.4 / Flutter 3.22 floor.
- **Flutter-free CLI wrapper**: `bin/fluttersdk_dusk.dart` + `executables: fluttersdk_dusk` pubspec entry. `dart run fluttersdk_dusk <cmd>` proxies the full artisan CLI surface and exposes the dusk commands without dragging `dart:ui` into pure-Dart contexts (mirrors the `fluttersdk_telescope` pattern).
- **`install.yaml` plugin manifest + executables wiring**: V1 manifest at the package root with empty publish list + a post-install bootstrap message (the three-step Magic / Wind / verify recipe). Makes `plugin:install fluttersdk_dusk` work end-to-end via the artisan `PluginInstaller`, and registers `DuskArtisanProvider` into the consumer's `lib/app/_plugins.g.dart` codegen barrel.
- **11 new VM Service extension method names**: `ext.dusk.scroll`, `ext.dusk.wait_for`, `ext.dusk.dismiss_modals`, `ext.dusk.navigate`, `ext.dusk.navigate_back`, `ext.dusk.get_routes`, `ext.dusk.press_key`, `ext.dusk.select_option`, `ext.dusk.evaluate`, `ext.dusk.close_app`, `ext.dusk.find`. Six new handler bodies arrived as fresh `extensions/ext_*.dart` files (`ext_navigation.dart` contributing navigate / navigate_back / get_routes, `ext_evaluate.dart`, `ext_close_app.dart`, `ext_find.dart`); the remaining five (`scroll`, `wait_for`, `dismiss_modals`, `press_key`, `select_option`) were pre-existing alpha-1 surfaces that landed via test-coverage + aggregator registration in alpha-2. Each follows the alpha-1 handler shape: parse `Map<String, String> params`, route through the actionability gate where applicable (tap / hover / drag / type), return `ServiceExtensionResponse.result(jsonEncode(payload))`, register idempotently.
- **10 new MCP tool descriptors**: `dusk_scroll`, `dusk_wait_for`, `dusk_dismiss_modals`, `dusk_navigate`, `dusk_navigate_back`, `dusk_get_routes`, `dusk_press_key`, `dusk_select_option`, `dusk_evaluate`, `dusk_close_app`. All contributed via `DuskArtisanProvider.mcpTools()` as `McpToolDescriptor` const instances with Claude Code canonical descriptions (imperative opener + context paragraph + `Usage:` bullets). Brings the MCP surface to 17 tools (the 11th alpha-2 tool, `dusk_find`, is called out separately below).
- **8 new CLI commands**: `dusk:install`, `dusk:type`, `dusk:scroll`, `dusk:wait`, `dusk:hover`, `dusk:drag`, `dusk:modal`, `dusk:doctor`. Each wraps the matching VM Service extension; `dusk:install` is the one-shot bootstrap (see below). Provider `commands()` now returns 11 commands (3 alpha-1 + 8 alpha-2).
- **Actionability gate** (`lib/src/utils/actionability_gate.dart`): the four direct-action handlers (`tap`, `hover`, `drag`, `type`) now resolve through a single gate that verifies the target's enabled flag (only `Tristate.isFalse` fails; `Tristate.none` and `Tristate.isTrue` pass), zero-area rect, and viewport overlap BEFORE synthesising the pointer / key event. Replaces the alpha-1 silent no-op + best-effort path. Failures throw `DuskActionabilityException` with a free-form `reason` string (`"not enabled"` / `"zero rect"` / `"off-viewport (rect=..., viewport=...)"`); handlers surface it as `ServiceExtensionResponse.error(extensionError, message)`. `scroll`, `select_option`, and `press_key` intentionally skip the gate in alpha-2 (see `### Known gaps`).
- **`dusk:find` Playwright-Locator pattern** (Step 16): mints `q<N>` query handles backed by the supplied predicates (`text` / `semanticsLabel` / `key`). Unlike `e<N>` refs (frozen at snap time), q-handles re-execute the Semantics + Element walk on every action call, so they survive widget rebuilds and route pushes as long as the predicates still match. Stale match returns an explicit `stale-handle` error result; the agent re-finds, never silently retries.
- **`dusk:install` one-shot bootstrap**: orchestrates `consumer:scaffold` + `plugin:install fluttersdk_dusk` + `lib/main.dart` injection. Detects Magic-stack apps via the `await Magic.init(` anchor and injects `DuskPlugin.install()` BEFORE Magic.init (then `MagicDuskIntegration.install()` + `WindDuskIntegration.install()` AFTER), falling back to the `runApp(` anchor for vanilla Flutter apps. Idempotent; safe to re-run.
- **Chrome reaper** (`lib/src/utils/chrome_reaper.dart`): graceful Chromium subprocess teardown between dusk:* runs so leftover headless tabs no longer accumulate. Detects orphans by VM Service URI, exits cleanly via `SystemNavigator.pop` first, falls back to SIGTERM.
- **`dusk:doctor`** (Step 21): diagnostic command that checks VM Service reachability, artisan plugin registration, the actionability gate's prerequisites, and the Chrome reaper's permissions in one pass. Emits a categorised report (OK / WARN / ERROR per check); exit code 0 when every check passes.
- **Example apps**: `example/` (vanilla Flutter) and `example_magic/` (Magic + Wind stack) for live e2e validation against the 17 MCP tools + 11 CLI commands. The Magic example registers `MagicDuskIntegration` + `WindDuskIntegration` to exercise all 8 snapshot enrichers (2 alpha-1 + 5 from Magic Step 17 + Wind's 6-field enricher).
- **`lib/cli.dart` codegen barrel**: Flutter-free typedef alias `FluttersdkDuskArtisanProvider`. Consumed by consumer-side `lib/app/_plugins.g.dart` auto-discovery without pulling Flutter symbols into the pure-Dart artisan codegen path.

### Changed

- **Actionability gate (behavior change)**: action handlers no longer silently succeed when the target widget is disabled, has a zero-area rect, or sits off-viewport. They now surface a `ServiceExtensionResponse.error(extensionError, "Widget ref=$ref is not actionable: $reason")` envelope with `$reason` ∈ {`"not enabled"`, `"zero rect"`, `"off-viewport (rect=..., viewport=...)"`}. Callers that previously relied on the silent no-op must either re-snap into view first or pre-check via `dusk_find`. This is the only behavior change in alpha-2; everything else is additive.

### Magic-side coordinated changes (require magic ^[1.0.0-alpha.14] or unreleased main)

- `magic/lib/src/cli/dusk_integration.dart`: 5 new enrichers added by Magic Step 17 — `magicControllerEnricher`, `magicFormErrorsEnricher`, `magicGateResultEnricher`, `magicMiddlewareEnricher`, `magicAuthUserEnricher`. Combined with the 2 alpha-1 enrichers (`magicFormField`, `magicRoute`), `MagicDuskIntegration.install()` now registers 7 enrichers; Wind ships its own 6-field enricher (`WindDuskIntegration.install()`) for an 8-enricher total surface.
- `magic/lib/src/auth/gate_manager.dart` + `magic/lib/src/http/middleware_pipeline.dart`: small instrumentation hooks added so the new gate-result + middleware enrichers can read the last decision / pipeline trace from the Element being snapshotted. Backward compatible; no signature changes to public APIs.

### Test coverage

- Dusk: per-command + per-handler tests for the 8 new commands and 11 new handler entry points, plus actionability-gate unit tests (enabled / zero-rect / off-viewport / Tristate.none-passes / empty-viewport edge case), `dusk_find` stale-handle round-trip, Chrome reaper subprocess teardown, and `dusk:doctor` categorised-report shape.
- Dusk full suite: 248 tests green (up from the alpha-1 baseline of 11). New surfaces: 12 ext.dusk.find tests, 23 dusk:doctor tests, 16 chrome_reaper tests, 10 actionability_gate tests, 26 ext.dusk.navigate tests, 8 dispatcher-contract tests, 6 ext.dusk.close_app + 5 ext.dusk.evaluate tests, 14 DuskInstallCommand tests, 57 CLI command tests, plus 5 press_key + 4 select_option pre-existing-handler coverage backfills.
- Magic full suite: 1163 tests green (+43 from new enricher integration + GateResult equality + GateManager.lastResult MRU + MagicRouter.currentRoute reactivity, across `test/cli/dusk_integration_test.dart` and `test/auth/`).

### Known gaps

- `dusk:doctor` runs in pure-Dart CLI context and cannot import `package:flutter/rendering.dart` without dragging `dart:ui` (breaks `dart run` invocation). Two checks defang gracefully as a result: `semanticsEnabledProbe` defaults to `true` (the only ERROR-class check, so doctor cannot ERROR from CLI) and `enrichersProbe` defaults to `0` (always WARNs on Check 3). The real probes belong to a future VM-Service-attached doctor invocation that calls into the running app; tests override per scenario to exercise both branches.
- `scroll`, `select_option`, and `press_key` intentionally skip the actionability gate in alpha-2: scroll targets the parent scrollable not the ref, select_option dispatches through Material/Cupertino popup machinery that owns its own enabled check, and press_key targets the focused widget rather than a ref. Adding the gate to these three handlers is alpha-3 candidate work.
- `RefRegistry._queries` (q-handle store) is monotonically growing within a debug session; only `RefRegistry.disposeAll()` clears it. Worst-case memory bounded by debug-session lifetime; per-handle eviction is alpha-3 candidate work.

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
