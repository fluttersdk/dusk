# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added: CDP driver (Chrome viewport / device emulation)

- **`CdpClient`** (`lib/src/cdp/cdp_client.dart`): minimal in-house Chrome DevTools Protocol client (~110 LoC, dart:io WebSocket + dart:convert; no pub.dev deps). Public surface: `connect(port:)`, `send(method, params)`, `close()`. Internals: monotonic `_nextId` + `Completer` correlation map, 30s per-request timeout, on-disconnect drain. Test seams `cdpHttpGet` / `cdpWsConnect` via `@visibleForTesting` static fields (mirrors `chrome_reaper.dart` injection pattern).
- **`DevicePresets`** (`lib/src/cdp/device_presets.dart`): 8 curated device presets with explicit DPR values (never 0): `iphone-x`, `iphone-13`, `iphone-15-pro`, `pixel-5`, `pixel-8`, `ipad-pro-12.9`, `desktop-1440`, `desktop-1920`. Each entry includes width, height, deviceScaleFactor, isMobile, hasTouch, userAgent. `lookupPreset(name)` normalises input (lowercase + underscore/space-to-hyphen + collapse adjacent hyphens).
- **`ChromeFinder`** (`lib/src/cdp/chrome_finder.dart`): probes `http://localhost:<port>/json/version` until Chrome answers or the timeout expires. Distinguishes connection-refused (retry), HTTP 404 (wrong-Chrome-instance fail-fast), and timeout. `DuskCdpException` re-exported from `cdp_client.dart`.
- **`DuskResizeCommand` + `dusk:resize` CLI** (`lib/src/commands/dusk_resize_command.dart`): `dart run fluttersdk_artisan dusk:resize --width=375 --height=812 [--dpr=3] [--mobile] [--touch]`. Reads `cdpPort` from state.json, opens `CdpClient`, sends `Emulation.setDeviceMetricsOverride` (+ optional `setTouchEmulationEnabled`). `--reset` sends 3-call clear chain (UA empty -> touch off -> clearMetrics). Fails loudly when CDP not enabled.
- **`DuskDeviceCommand` + `dusk:device` CLI** (`lib/src/commands/dusk_device_command.dart`): `dart run fluttersdk_artisan dusk:device --preset=iphone-x`. Applies the full emulation chain (metrics + conditional touch + UA) from the curated preset database. `--list` prints all 8 preset entries; `--reset` mirrors `dusk:resize --reset`.
- **2 new MCP tools** in `DuskArtisanProvider.mcpTools()`: `dusk_resize_viewport` + `dusk_device_profile`. Both dispatch via the existing `artisan:` substrate prefix (no `mcp_server.dart` changes). Tool count: 29 -> 31. Command count: 30 -> 32.
- **`FakeCdpServer` test harness** (`test/src/cdp/fake_cdp_server.dart`): dart:io `HttpServer` + `WebSocketTransformer.upgrade` on an ephemeral loopback port. Serves `/json/version` + accepts `/devtools/browser/abc` WS upgrade. Configurable failure modes (`failOnJsonVersion`, `dropWebSocket`, `delayResponseMs`). Used by `cdp_client_test.dart`, `dusk_resize_command_test.dart`, `dusk_device_command_test.dart`.
- **Integration smoke test** (`test/integration/cdp_smoke_test.dart`): exercises the full chain end-to-end (artisan start --cdp-port + dusk:resize + Browser.getVersion round-trip + FIFO hot reload smoke + artisan stop Chrome reap). Tagged `@Skip` so default `flutter test` skips it; run manually via `flutter test test/integration --tags integration` to validate `dart-lang/webdev#2642` regression status against the user's Flutter SDK.

### Risks Accepted

- **`dart-lang/webdev#2642` live regression**: "Hot restart broken when running DWDS without Chrome Debug Port". Integration smoke test (Test 2) surfaces this if active. Mitigation lives in the user's pinned Flutter SDK; plan does not block on regression resolution.
- **Flutter SDK >= 3.30.0** required for `--cdp-port` (per `flutter/flutter#170612`). Lower versions get an actionable error from both `artisan doctor` (advisory) and `artisan start --cdp-port` (fail-fast).

### Added: Wave 3 (Playwright-pattern action layer)

- **5-gate actionability**: Stable + Receives-Events gates added to
  `ensureActionable` (now async). Total preconditions in evaluation order:
  enabled, zero-rect, off-viewport, stable (rect unchanged across 2
  consecutive frames — Playwright auto-waiting), receives-events (hit-test
  confirms ref is the front-most pointer target). Opt-out via
  `checkStable=false` / `checkReceivesEvents=false` (both default `true`).
  Failure-reason substrings extended: `"not stable"`, `"obscured by"` join
  the existing 3-reason agent branch surface.
- **Snapshot-in-action-response** (Playwright `setIncludeSnapshot` pattern):
  8 action handlers (`tap`, `hover`, `drag`, `type`, `press_key`, `scroll`,
  `navigate`, `navigate_back`) accept `includeSnapshot=true` and append the
  post-action snapshot YAML to the success response. The agent no longer
  needs a mandatory follow-up `dusk_snap` call. `duskSnapBuild` widened
  from `@visibleForTesting` to public (legitimate production reuse).
  `press_key` handler endOfFrame omission fixed in passing.
- **Structured error envelope + fuzzy-match suggestions**: new
  `lib/src/utils/error_envelope.dart` with `DuskErrorEnvelope` carrying
  `type` + `widget_path` + `suggestions[]`. 10 type values: `timeout`,
  `not_found`, `obscured`, `disabled`, `stale`, `zero_rect`,
  `off_viewport`, `not_stable`, `missing_param`, `unexpected`. 6
  factories. Dual-write into `errorDetail` (JSON envelope alongside the
  free-form message) preserves backward compat for substring-matching
  agents. Levenshtein with prefix-bonus drives the suggestions list for
  `not_found`. `RefRegistry.activeRefs()` added to support candidate
  collection.
- **`ext.dusk.wait_for_network_idle`** (Step 3.4 cross-package): polls
  `TelescopeStore.pendingHttpCount` until the count hits zero for a
  configurable `idleMs` window. Params `timeoutMs` (5000), `idleMs` (500),
  `pollIntervalMs` (200). Function-pointer indirection
  (`pendingHttpCountReader` exported from `dusk.dart`) keeps dusk free of
  a hard telescope dependency; magic-side wires the real reader at
  install time. New CLI command `dusk:wait_for_network_idle`.
- **4 utility tools** (Step 3.5): `dusk_console` (telescope log reader,
  function-pointer indirection via `recentLogsReader`), `dusk_exceptions`
  (telescope exception reader via `recentExceptionsReader`),
  `dusk_dblclick` (two synthesised taps with 100ms inter-tap delay,
  shared 5-gate actionability + snapshot embed), `dusk_set_checkbox`
  (idempotent `Checkbox` / `Switch` toggle via element walk; no-op when
  current value matches target).

### Added — Wave 4 (agent loop optimization)

- **`ext.dusk.observe`** (Step 4.1): Stagehand-style observe-once-act-many
  pattern WITHOUT server-side LLM. Walks every active `PipelineOwner`
  semantics tree, filters interactive nodes (buttons / textfields /
  links / checkboxes / dropdowns via `_roleFor` / `_isInteractive` —
  mirrors `ext_snapshot.dart`), mints a re-resolvable `q<N>` ref per
  candidate (Playwright Locator pattern; never `e<N>`), and returns a
  structured JSON list `{candidates: [...], count: N}`. Each candidate
  carries `ref`, `role`, `label`, `value`, `bounds`, `isEnabled`,
  `isVisible`, plus enricher-projected fields under
  `includeEnrichers='defaults'` (subset: `magicFormField`, `magicRoute`,
  `magicGateResult`, `wind.{breakpoint,states}`) or
  `includeEnrichers='full'` (full enricher payload). Params: `intent`
  (caller hint, echoed only), `limit` (default 50), `roles`
  (comma-separated filter), `includeEnrichers`.
- **`dusk:hot_reload_and_snap`** (Step 4.2): mcp_flutter
  `fmt_hot_reload_and_capture` equivalent. CLI-side orchestration via
  `VmServiceClient.reloadSources` (in-isolate handler cannot reload its
  own isolate; deadlock avoidance). Sequence: reload → wait → snap →
  screenshot → exceptions → bundle. Success envelope
  `{reloaded, durationMs, snapshot, screenshot, recentExceptions}`;
  compile-error envelope skips snap/screenshot but still gathers
  exceptions. Screenshot failure surfaces as partial-result
  `screenshotError` rather than aborting the round-trip. MCP descriptor
  uses the artisan substrate routing prefix
  (`extensionMethod: 'artisan:dusk:hot_reload_and_snap'`) so the MCP
  server dispatches to the CLI command in-process.

### Surface deltas

- **CLI commands**: 18 → **25** (Wave 3.4 +1, Wave 3.5 +4, Wave 4.1 +1,
  Wave 4.2 +1).
- **MCP tool descriptors**: 17 → **24** (same breakdown).
- **VM Service extensions**: 17 → **23** (no extension for
  `dusk_hot_reload_and_snap` per the in-isolate constraint).
- **Tests**: 395 baseline → **547** (+152 across Wave 3 and Wave 4).

## [0.0.1] - 2026-05-19

Initial release. E2E driver for Flutter apps. Snapshot, tap, type, drag, scroll, screenshot, wait, find via VM Service extensions (`ext.dusk.*`). Framework-agnostic (vanilla Flutter friendly); Magic / Wind integrations ship inside those packages via `DuskPlugin.enrichers` extension point.

### Added

- **18 CLI commands** via `DuskArtisanProvider.commands()`: `dusk:install`, `dusk:snap`, `dusk:tap`, `dusk:screenshot`, `dusk:type`, `dusk:scroll`, `dusk:wait`, `dusk:hover`, `dusk:drag`, `dusk:modal`, `dusk:doctor`, `dusk:navigate`, `dusk:navigate_back`, `dusk:get_routes`, `dusk:press_key`, `dusk:select_option`, `dusk:close_app`, `dusk:find`. `dusk:install` is the one-shot bootstrap; the rest wrap the matching VM Service extension. Every CLI command has a matching MCP tool of the same name (with `dusk_` prefix swap).
- **17 MCP tool descriptors** via `DuskArtisanProvider.mcpTools()`: `dusk_snap`, `dusk_screenshot`, `dusk_tap`, `dusk_type`, `dusk_press_key`, `dusk_hover`, `dusk_drag`, `dusk_scroll`, `dusk_select_option`, `dusk_wait_for`, `dusk_dismiss_modals`, `dusk_navigate`, `dusk_navigate_back`, `dusk_get_routes`, `dusk_close_app`, `dusk_find`, `dusk_doctor`. All `McpToolDescriptor` const instances with Claude Code canonical descriptions (imperative opener + context paragraph + `Usage:` bullets).
- **17 VM Service extensions** under `ext.dusk.*`: `snap`, `screenshot`, `tap`, `hover`, `drag`, `type`, `scroll`, `wait_for`, `dismiss_modals`, `press_key`, `select_option`, `navigate`, `navigate_back`, `get_routes`, `evaluate`, `close_app`, `find`. All registered through `registerExtensionIdempotent` for hot-restart safety.
- **`DuskPlugin.install()`** — idempotent host-side install entry. Wraps the app widget root in a `RepaintBoundary` (no `GlobalKey`) so `ext.dusk.screenshot` can find it via render-tree walk. Hot-restart safe via static `_installCount` guard. Honors `DUSK_DISABLE` env var (`1` / `true` / `yes`, case-insensitive) as kill switch.
- **`DuskSnapshotEnricher` typedef** — snapshot-enricher extension point. `String? Function(Element, RefRegistry)`. Magic ships its enrichers via `MagicDuskIntegration`; Wind ships its 6-field `WindClassNameEnricher` via `WindDuskIntegration`. Contract: synchronous, stateless w.r.t. call ordering, may return `null` to skip, multi-line fragments split + indented under the ref entry by the dispatcher.
- **`RefRegistry`** — stable `e<N>` (snapshot-frozen) and `q<N>` (re-resolvable Playwright-Locator) token systems. `e<N>` refs are minted at `dusk_snap` time and consumed by every action tool; `q<N>` refs are minted by `dusk:find` and re-execute their stored predicates against the live tree on every action call (resilient to widget rebuild + route push).
- **Actionability gate** (`lib/src/utils/actionability_gate.dart`) — `tap` / `hover` / `drag` / `type` resolve through a single gate that verifies the target's enabled flag (`Tristate.isFalse` fails; `Tristate.none` and `Tristate.isTrue` pass), zero-area rect, and viewport overlap BEFORE synthesising the pointer / key event. Failures surface `ServiceExtensionResponse.error(extensionError, "Widget ref=$ref is not actionable: $reason")` with `$reason` ∈ {`"not enabled"`, `"zero rect"`, `"off-viewport (rect=..., viewport=...)"`}. `scroll`, `select_option`, and `press_key` intentionally skip the gate (see `### Known gaps`).
- **`dusk:install` one-shot bootstrap** — minimal install. Edits the consumer's `lib/main.dart` only (no `bin/artisan.dart` or `lib/app/` scaffolding for vanilla Flutter apps). Detects Magic-stack apps via the `await Magic.init(` anchor and injects `DuskPlugin.install()` BEFORE Magic.init (then `MagicDuskIntegration.install()` + `WindDuskIntegration.install()` AFTER), falling back to the `runApp(` anchor for vanilla Flutter apps. Vanilla consumers access dusk via `dart run fluttersdk_dusk <cmd>`. Idempotent; safe to re-run.
- **Flutter-free CLI wrapper** — `bin/fluttersdk_dusk.dart` + `executables: fluttersdk_dusk` pubspec entry. `dart run fluttersdk_dusk <cmd>` proxies the full artisan CLI surface and exposes the dusk commands without dragging `dart:ui` into pure-Dart contexts.
- **`install.yaml` plugin manifest** — V1 manifest at the package root makes `plugin:install fluttersdk_dusk` work end-to-end via the artisan `PluginInstaller`.
- **`lib/cli.dart` codegen barrel** — Flutter-free typedef alias `FluttersdkDuskArtisanProvider`. Consumed by consumer-side `lib/app/_plugins.g.dart` auto-discovery without pulling Flutter symbols into the pure-Dart artisan codegen path.
- **`dusk:find` Playwright-Locator pattern** — mints `q<N>` query handles backed by `text` / `semanticsLabel` / `key` predicates. Unlike `e<N>` refs (frozen at snap time), q-handles re-execute the Semantics + Element walk on every action call, so they survive widget rebuilds and route pushes as long as the predicates still match. Stale match returns an explicit `stale-handle` error; the agent re-finds, never silently retries.
- **`dusk:doctor`** — diagnostic command that checks `~/.artisan/state.json` Chrome PID staleness, `DUSK_DISABLE` env-var value, registered enricher count, Semantics-tree-forced flag, and Magic-init wiring in one pass. Emits a categorised report (OK / WARN / ERROR per check); exit code 0 when every check passes.
- **Chrome reaper** (`lib/src/utils/chrome_reaper.dart`) — graceful Chromium subprocess teardown between dusk:* runs so leftover headless tabs no longer accumulate. Detects orphans by VM Service URI, exits cleanly via `SystemNavigator.pop` first, falls back to SIGTERM.
- **Example apps**: `example/` (vanilla Flutter, 7 scenario screens: home menu + buttons / inputs / scroll / modals / drawer / forms) for live e2e validation against the 17 MCP tools + 18 CLI commands.

### Test coverage

- 395 tests green across handler entry points (params + error paths + happy paths where reachable under `flutter_test`), 18 CLI commands (name / boot / description / configure / handle / missing-arg validation), `DuskArtisanProvider.commands()` / `mcpTools()` shape, `DuskPlugin.install()` idempotency + `DUSK_DISABLE` env-var kill switch, `RefRegistry` mint / lookup / disposeGroup / disposeAll / refsForGroup / registerQuery / lookupQuery, actionability gate (enabled / zero-rect / off-viewport / `Tristate.none`-passes / empty-viewport edge case), `encodeToJpeg` PNG-to-JPEG roundtrip + quality boundaries (1, 100, error), modal-route classification, dispatcher contract.
- Coverage: **dusk 79%**, **artisan 84%**, **telescope 85%** (line coverage via `flutter test --coverage`). The remaining gap on dusk is engine-dependent paths that hang the `flutter_test` fake-clock harness: handler `endOfFrame` waits, `Future.delayed` poll loops in `wait_for`, real `toImage()` rasterisation in `screenshot` success paths, and private `_defaultProcessStartTime` / `_parsePsLstart` doctor seam defaults. End-to-end coverage for those paths is captured by the example/ playground sweep over the 18 CLI commands.

### Known gaps

- `dusk:doctor` runs in pure-Dart CLI context and cannot import `package:flutter/rendering.dart` without dragging `dart:ui` (breaks `dart run` invocation). Two checks defang gracefully as a result: `semanticsEnabledProbe` defaults to `true` (the only ERROR-class check, so doctor cannot ERROR from CLI) and `enrichersProbe` defaults to `0` (always WARNs on Check 3). The real probes belong to a future VM-Service-attached doctor invocation that calls into the running app.
- `scroll`, `select_option`, and `press_key` intentionally skip the actionability gate: scroll targets the parent scrollable not the ref, select_option dispatches through Material/Cupertino popup machinery that owns its own enabled check, and press_key targets the focused widget rather than a ref. Adding the gate to these three handlers is V1.x candidate work.
- `RefRegistry._queries` (q-handle store) is monotonically growing within a debug session; only `RefRegistry.disposeAll()` clears it. Worst-case memory bounded by debug-session lifetime; per-handle eviction is V1.x candidate work.

### Backward compat

`DuskSnapshotEnricher` typedef, `DuskPlugin.install` / `registerEnricher`, `RefRegistry` public methods, and every MCP tool name / `ext.dusk.*` extension name are part of the public 0.0.1 contract. Future releases keep these stable across the 0.x line; any change requires a coordinated bump with `magic` + `wind`.
