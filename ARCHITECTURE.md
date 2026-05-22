# Architecture

Internal reference for contributors. The user-facing surface lives in [README.md](README.md) and the full docs at [fluttersdk.com/dusk](https://fluttersdk.com/dusk).

## Subsystems

Dusk is subsystem-first under `lib/src/`; every directory owns a single concern.

```
lib/
├── dusk.dart                    # Public barrel: DuskPlugin, RefRegistry, DuskArtisanProvider, DuskSnapshotEnricher
├── cli.dart                     # Flutter-free codegen barrel (FluttersdkDuskArtisanProvider typedef)
└── src/
    ├── extensions/              # 18 files: ext_snapshot, ext_pointer, ext_text_input, ext_screenshot, ext_navigation, ...
    ├── commands/                # 32 ArtisanCommand subclasses (one file each)
    ├── utils/                   # actionability_gate (5-gate), error_envelope, chrome_reaper, dusk_exceptions
    ├── cdp/                     # cdp_client + chrome_finder + 8 device_presets
    ├── dusk_plugin.dart         # DuskPlugin.install() entry, enricher list, navigate adapter
    ├── ref_registry.dart        # e<N> + q<N> dual token system; live re-resolution for q-refs
    ├── dusk_snapshot_enricher.dart  # FROZEN typedef: String? Function(Element, RefRegistry)
    └── dusk_artisan_provider.dart   # 32 commands + 31 MCP tool descriptors
bin/fluttersdk_dusk.dart           # Flutter-free CLI entry (no dart:ui import)
install.yaml                       # V1 plugin manifest, zero stubs, post_install bootstrap
```

## Boot flow

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

## CLI commands

The 32 commands registered by `DuskArtisanProvider.commands()`:

```
dusk:install           dusk:doctor              dusk:close_app
dusk:snap              dusk:screenshot          dusk:hot_reload_and_snap
dusk:tap               dusk:dblclick            dusk:right_click
dusk:triple_click      dusk:hover               dusk:drag
dusk:scroll            dusk:type                dusk:clear
dusk:focus             dusk:blur                dusk:press_key
dusk:set_checkbox      dusk:select_option       dusk:find
dusk:observe           dusk:wait                dusk:wait_for_network_idle
dusk:navigate          dusk:navigate_back       dusk:get_routes
dusk:modal             dusk:resize              dusk:device
dusk:console           dusk:exceptions
```

Each command file declares `name`, `description`, `boot` (`none` or `connected`), `configure(parser)` (flags), and `handle(ctx)` (validates args, calls `ctx.callExtension('ext.dusk.X', params)`, writes formatted output).

## MCP tools

The 31 `McpToolDescriptor` entries in `dusk_artisan_provider.dart:123-1435`. 28 route through `ext.dusk.*` VM Service extensions; 3 route through `artisan:dusk:*` substrate prefixes (`dusk_hot_reload_and_snap`, `dusk_resize_viewport`, `dusk_device_profile`) since they need out-of-isolate execution (in-isolate hot-reload would deadlock; CDP needs a non-Flutter Dart context).

`dusk_evaluate` is MCP-only (no CLI mirror) so `magic_tinker` owns the connected REPL surface.

## VM Service extension surface (24 ext.dusk.*)

```
ext.dusk.snap                  ext.dusk.screenshot          ext.dusk.tap
ext.dusk.hover                 ext.dusk.drag                ext.dusk.type
ext.dusk.scroll                ext.dusk.wait_for            ext.dusk.wait_for_network_idle
ext.dusk.dismiss_modals        ext.dusk.press_key           ext.dusk.select_option
ext.dusk.navigate              ext.dusk.navigate_back       ext.dusk.get_routes
ext.dusk.evaluate              ext.dusk.close_app           ext.dusk.find
ext.dusk.focus                 ext.dusk.blur                ext.dusk.clear
ext.dusk.right_click           ext.dusk.dblclick            ext.dusk.triple_click
ext.dusk.set_checkbox          ext.dusk.console             ext.dusk.exceptions
ext.dusk.observe
```

Every registration routes through `registerExtensionIdempotent` (from `fluttersdk_artisan`) for hot-restart safety.

## Frozen contracts (alpha-2)

These cannot change without a coordinated bump across `magic` + `wind` + `dusk`:

1. `DuskSnapshotEnricher` typedef shape: `String? Function(Element, RefRegistry)`
2. `DuskPlugin.install()` and `DuskPlugin.registerEnricher()` signatures
3. `RefRegistry` public method signatures (`mint`, `lookup`, `recordQuery`, `resolveQuery`, `clear`, `resetForTesting`)
4. The 6 alpha-1 MCP tool names (`dusk_snap`, `dusk_tap`, `dusk_screenshot`, `dusk_hover`, `dusk_drag`, `dusk_type`) and their `ext.dusk.*` extension method names
5. `DuskActionabilityException` `reason` substring vocabulary (`not enabled`, `zero rect`, `off-viewport`, `not stable`, `obscured by`)
6. Actionability gate 5-precondition order (defunct, enabled, zero-rect, off-viewport, stable, receives-events)
7. `e<N>` and `q<N>` token spaces are disjoint

## Actionability gate

`lib/src/utils/actionability_gate.dart` runs five preconditions in order before any tap, hover, drag, dblclick, right_click, triple_click, or type:

| Step | Check | Fail reason string | Notes |
|---|---|---|---|
| 0 | `findRenderObject()` returns non-null | `defunct (...)` | Element no longer attached after a rebuild |
| 1 | `node.flagsCollection.isEnabled != Tristate.isFalse` | `not enabled` | `Tristate.none` (default) passes |
| 2 | `rect.width > 0 && rect.height > 0` | `zero rect` | Collapsed or detached widget |
| 3 | rect overlaps viewport | `off-viewport (rect=..., viewport=...)` | Auto-scrolls via `showOnScreen` first if a `Scrollable` ancestor exists |
| 4 | 2-frame rect drift ≤ 0.5px | `not stable (rect changed by Xpx)` | Skipped when `--no-checkStable` |
| 5 | hit-test path at `rect.center` includes the target render object or a descendant | `obscured by other widget (top=...)` | Skipped when `--no-checkReceivesEvents` |

`scroll`, `select_option`, and `press_key` intentionally skip the gate (the parent scrollable, popup machinery, or focused widget owns its own enabled check).

## RefRegistry token systems

**`e<N>` (snapshot-frozen)**: minted at `dusk:snap` time. Stores element + rect + groupId + optional SemanticsNode/RenderObject. `node.id` dedup; the same widget across snapshots reuses the same `eN`. Element unmount triggers a `defunct` gate failure.

**`q<N>` (re-resolvable)**: minted at `dusk:find` time. Stores a predicate (`text` / `semanticsLabel` / `keyValue`) and re-walks the live tree on every action. Playwright Locator pattern. UI changes trigger a `DuskStaleHandleException`.

`resolveRefForAction(ref)` in `lib/src/extensions/ext_pointer.dart:52-89` dispatches by prefix.

## CDP layer

`lib/src/cdp/cdp_client.dart` connects to Chrome at `localhost:<cdp-port>/json`, picks the first `type:"page"` tab, opens a WebSocket, and dispatches JSON-RPC with an auto-incrementing id and a 30s per-request timeout.

`device_presets.dart` carries 8 named presets (iphone-x, iphone-13, iphone-15-pro, pixel-5, pixel-8, ipad-pro-12.9, desktop-1440, desktop-1920). Each preset is width × height × DPR × mobile flag × touch flag × userAgent.

`dusk:device` runs a 3-call CDP chain: `Emulation.setDeviceMetricsOverride` → optional `Emulation.setTouchEmulationEnabled` → `Emulation.setUserAgentOverride`, plus `Browser.getWindowForTarget` + `Browser.setWindowBounds` to resize the OS window (Emulation only changes the page view).

`FakeCdpServer` in `test/src/cdp/fake_cdp_server.dart` is the in-process mock for unit tests.

## Hot reload flow

`dusk:hot_reload_and_snap` lives CLI-side (an in-isolate handler cannot reload itself; the handler would block on the reload and the request would never return). The command writes `r\n` to the stdin FIFO recorded in `~/.artisan/state.json`, then tail-polls the flutter run log for the `Reloaded N libraries in Mms` marker (or the `Try again after fixing` compile-error marker). Resolves in ~170ms on desktop.

`IsolateReload` VM Service events are intentionally avoided because they do not fire on no-op (0-library) reloads, and `hot_reload_and_snap` is most useful precisely when the caller wants to force a reassemble without editing files.
