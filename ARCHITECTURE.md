# Architecture

Internal reference for contributors. The user-facing surface lives in [README.md](README.md) and the full docs at [fluttersdk.com/dusk](https://fluttersdk.com/dusk).

## Subsystems

Dusk is subsystem-first under `lib/src/`; every directory owns a single concern.

```
lib/
├── dusk.dart                    # Public barrel: DuskPlugin, RefRegistry, DuskArtisanProvider, DuskSnapshotEnricher, the perf pointers
├── cli.dart                     # Flutter-free codegen barrel (FluttersdkDuskArtisanProvider typedef)
└── src/
    ├── extensions/              # in-isolate: one ext_<verb>.dart per ext.dusk.* group + register_dusk_extensions.dart aggregator
    ├── commands/                # host-side: one ArtisanCommand per file + shared helpers (json_output, frame_warning_output, web_visibility)
    ├── utils/                   # mostly in-isolate helpers (actionability_gate, dusk_register, dusk_response, effect_report, frame_sync, viewport_visibility, snapshot_diff, tap_owner, key_press, error_envelope, perf_readers, perf_interaction); dusk_exceptions and chrome_reaper are plain Dart
    ├── perf/                    # host-side only (never imports Flutter): scenario/campaign loading and the perf_run driver
    ├── cdp/                     # cdp_client, chrome_finder, page_visibility, device_presets
    ├── dusk_plugin.dart         # DuskPlugin.install() entry, enricher list, navigate adapter
    ├── dusk_error_capture.dart  # Non-fatal FlutterError ring buffer; dusk_log_capture.dart does the same for debugPrint
    ├── ref_registry.dart        # e<N> + q<N> dual token system; live re-resolution for q-refs
    ├── dusk_snapshot_enricher.dart  # FROZEN typedef: String? Function(Element, RefRegistry)
    ├── dusk_navigate_adapter.dart   # FROZEN typedef: Future<bool> Function(String route)
    ├── cli_args.dart            # Pure arg massagers for the CLI wrapper (no IO, no Flutter)
    └── dusk_artisan_provider.dart   # The command list and the MCP tool descriptors; its test owns the counts
bin/fluttersdk_dusk.dart           # Flutter-free CLI entry (no dart:ui import)
install.yaml                       # V1 plugin manifest, zero stubs, post_install bootstrap
```

The split that matters: `extensions/` and most of `utils/` run inside the app's isolate and import Flutter; `commands/`, `perf/`, `cdp/` and `bin/` run in the host CLI process on the plain Dart VM and must not import `package:flutter` or `dart:ui`. A command reaches the app only through `ctx.callExtension('ext.dusk.<verb>', ...)`.

## Boot flow

```
DuskPlugin.install()                                    # consumer calls it inside !kReleaseMode, before runApp
    ↓
mintBootId()                                             # fresh per run of main(); dusk:perf_run tells a restart by it
    ↓
RendererBinding.instance.ensureSemantics()               # force semantics on
    ↓
registerAllDuskExtensions()                              # every ext.dusk.* through registerDuskExtension; boot_id registers last
    ↓
installErrorCapture() / installLogCapture()              # chain FlutterError.onError and debugPrint into bounded ring buffers; prior handlers preserved
    ↓
Consumer registers DuskArtisanProvider (auto-wired by `dusk:install` via _plugins.g.dart)
    ↓
artisan mcp:serve   →   dusk_* tools surface to MCP clients (Claude Code, Cursor, Windsurf, Copilot, ...)
```

The `RepaintBoundary` that `ext.dusk.screenshot` finds by render-tree walk is the consumer's: `runApp(RepaintBoundary(child: app))`, not something `install()` adds.

### Plugin wrapper interceptions (`bin/fluttersdk_dusk.dart`)

The Flutter-free CLI wrapper applies two interceptions before delegating to `runArtisan`:

- `mcp:install` detected: injects `--invocation=fluttersdk_dusk` into the forwarded args (idempotent; user-supplied `--invocation` wins). This surfaces the plugin executable name to the substrate's `.mcp.json` writer so the fastcli-absent fallback writes `dart run fluttersdk_dusk mcp:serve` instead of the generic `:dispatcher` shape.
- `mcp:serve` detected: forces `collectMcpTools: true` and `delegateToConsumer: false`, mirroring `fluttersdk_artisan/bin/mcp.dart`. Without this, `dart run fluttersdk_dusk mcp:serve` would boot with 0 plugin tools.

## CLI commands

`DuskArtisanProvider.commands()` is the list; `test/dusk_artisan_provider_mcp_tools_test.dart` owns the counts. Most commands are one-to-one with an `ext.dusk.<verb>`; the ones that are not (`install`, `doctor`, `resize`, `device`, `hot_reload_and_snap`, the `perf_*` drivers, `run`) do host-side work.

`dusk:run` is the one command that runs other commands: it tokenises each step, parses it with the verb's own `configure`, and calls that command's `handle` on a child connected context that shares the batch's single VM connection (`ctx.registry` finds the verb). Only `CommandBoot.connected` verbs qualify, and a step cannot be another `dusk:run`.

Each command file declares `name`, `description`, `boot` (`none` or `connected`), `configure(parser)` (flags), and `handle(ctx)` (validates args, calls `ctx.callExtension('ext.dusk.X', params)`, writes formatted output).

## MCP tools

The `McpToolDescriptor` entries in `DuskArtisanProvider.mcpTools()`. Most route through an `ext.dusk.*` VM Service extension; a few route through `artisan:dusk:*` substrate prefixes: `dusk_hot_reload_and_snap`, `dusk_resize_viewport` and `dusk_device_profile` need out-of-isolate execution (in-isolate hot-reload would deadlock; CDP needs a non-Flutter Dart context), and `dusk_perf_run`, `dusk_perf_compare`, `dusk_perf_trace` and `dusk_run` need the MCP dispatch to write a host file or run CLI commands rather than call the isolate directly.

`dusk_evaluate` is MCP-only (no CLI mirror) so `magic_tinker` owns the connected REPL surface.

## VM Service extension surface

Every `ext.dusk.<verb>` registers through `registerDuskExtension` (`lib/src/utils/dusk_register.dart`), which wraps `registerExtensionIdempotent` from `fluttersdk_artisan` for hot-restart safety and runs the frame wake below. The register calls are grouped per `ext_<name>.dart` file and called once from `registerAllDuskExtensions`. `find_by_text`, `find_by_label` and `boot_id` are internal helpers with no MCP tool of their own.

### Frame settling is always bounded

A handler that dispatches a gesture, a text edit, or a navigation awaits one or two frames afterwards so the gesture arena drains and any implicit animation starts. Those awaits go through `awaitFrameOrTimeout` / `awaitFramesOrTimeout` in `lib/src/utils/frame_sync.dart`, never `WidgetsBinding.instance.endOfFrame` directly.

`endOfFrame` schedules a frame only while `SchedulerBinding.framesEnabled` is true. A hidden desktop window or a backgrounded browser tab (Chrome reports `document.visibilityState: "hidden"` and Flutter Web turns frame production off) stops frame production, so a bare await there never completes: the extension blocks until the calling CLI's own timeout kills it, with no output and no error. `kFrameSyncTimeout` (200ms, twelve frames at 60Hz) is long enough that a healthy engine always resolves on the real frame and short enough that a starved one degrades into an early return. The actionability gate uses the same helper for its stability and scroll-into-view awaits.

The bound only stops the hang; `ensureFramesProduced()` in the same file makes the frame happen. When frames are off and the lifecycle is `hidden` or `paused` (never `detached`, never null) it delivers `AppLifecycleState.inactive` on `flutter/lifecycle` and schedules a forced frame, and counts the wake only when a frame runs within `kFrameSyncTimeout`, after which it delivers `resumed`; otherwise it delivers the previous lifecycle again, unless the engine sent a lifecycle of its own inside that window (a real engine `resumed` is never overwritten). `inactive` first, because Flutter drops a message equal to the current state and the watch for an engine `resumed` would otherwise see nothing. Web is never attempted: a hidden tab has its `requestAnimationFrame` callbacks withheld, so no wake can take. `registerDuskExtension` / `wrapDuskHandler` in `lib/src/utils/dusk_register.dart` run it at the entry of every `ext.dusk.*` verb, per call because the OS re-hides the window, and a zone value carries "this call forced" to `duskResult`, which stamps `framesForced: true`. Verbs that must see the engine as it is (perf, `boot_id`, `close_app`, `console`, `exceptions`, `semantics_hold`, `evaluate`) register with `ensureFrames: false`. `--dart-define=DUSK_FORCE_FRAMES=false` turns it off. Behaviour and side effects: `doc/reference/frame-production.md`.

Web recovery is CLI-side, because the in-isolate wake cannot take on a hidden tab. `callExtensionVisible` in `lib/src/commands/web_visibility.dart` wraps the call for snap, observe, tap, fill, type, navigate, scroll and press_key: when the answer carries a web `warnings` block (or the call throws and `lib/src/cdp/page_visibility.dart` reports the tab `hidden`) and the session state has a `cdpPort`, it sends CDP `Page.bringToFront` once. A read-only verb (snap, observe) is then called again once; a mutating verb is never repeated, since its gesture may already have fired, and a stderr notice says to run `dusk:snap`. A CDP failure keeps the first result and exit code; without a `cdpPort` nothing changes.

`lib/src/utils/viewport_visibility.dart` holds the off-viewport helper and `probeHitAt`, the one hit probe behind the gate's receives-events check, the snapshot `[occluded]` marker and the observe `occluded` field (verdicts `reached`, `platformOnly`, `ancestorOnly`, `covered`), plus the markers themselves (`[offscreen]` / `[occluded]`, observe `inViewport` / `occluded`). The gate's `resolveViewFor` picks an element's own `FlutterView` (then the implicit view, then the first attached one) for the viewport check and the pointer dispatch alike.

### The snapshot baseline

`snapshotForAction` in `lib/src/extensions/ext_snapshot.dart` is the one place the action verbs (tap, fill, type, navigate, scroll and the other pointer verbs) decide what snapshot to attach: the `snapshot` param (`full`, `diff`, `none`) wins over `includeSnapshot`. `diff` compares against `snapshotBaseline`, the text of the last unfiltered snapshot (a `dusk:snap` or an earlier action), and `diffSnapshots` in `lib/src/utils/snapshot_diff.dart` returns only the changed lines with a `(K of N lines changed)` footer, matching ref lines by their `[ref=eN]` token and ignoring the `[offscreen]` / `[occluded]` markers. The baseline lives in `ext_snapshot.dart` module state rather than `RefRegistry`, whose surface is frozen, so a hot restart clears it, and a filtered snap (`grep`, `within`, `depth`, `interactiveOnly`) or an enricher walk never records it. With no baseline the full text comes back.

### One success-response seam

Every handler returns through `duskResult(payload)` in `lib/src/utils/dusk_response.dart` rather than constructing `ServiceExtensionResponse.result(jsonEncode(...))` itself. One seam means a diagnostic that belongs on every reply is added once and the next handler cannot forget it.

Alongside it, five verbs carry an `effect` block built from `lib/src/utils/effect_report.dart`: `tap`, the three text verbs (`type` / `clear` / `fill`), `scroll` and `set_checkbox`. A dusk action confirms that it DISPATCHED; the block is what confirms the widget received. `tap` compares a target-scoped semantics-subtree signal, the text verbs read the live `TextEditingController` back after the two-frame settle (so a formatter or echo that reverts the write reports `verified: false`) instead of echoing the request, and say which field they wrote in `effect.target` (`matchKind` `overlap`, `nearest` or `element`; a ref that is an interactive non-text control is refused by `refuseNonTextRef` in `ext_text_input.dart`), `scroll` reports the offset on both sides, and `set_checkbox` re-reads the control. Each of those was a measured false success: a fill onto a field covered by a pinned footer, a fill against a number field that kept nothing, a scroll against a ref that was not a scrollable.

Today the response-level diagnostics are `framesForced` and `reresolved` (both set per call through `dusk_register.dart`) and `frameProductionWarning()`: a `warnings` block, carrying `platform` and a platform-aware `hint`, appears only while frame production is off and dusk could not force it back on, which is the state in which a snapshot returns a screen with no text and an action reports a dispatch that could not have landed. CLI-side, `reportFrameWarning` in `lib/src/commands/frame_warning_output.dart` prints the matching stderr banner, because the commands that summarise (`dusk:snap` prints only the tree, `dusk:tap` prints `✓ Tapped e7`) would otherwise drop the block. See `doc/reference/frame-production.md`.

### The performance session

`ext.dusk.perf_begin` and `ext.dusk.perf_end` (`lib/src/extensions/ext_perf.dart`) are one verb split in half around a driven interaction. `perf_begin` sets `FlutterTimeline.debugCollectionEnabled` first (both `startSync` and `finishSync` check that flag, so turning the build flags on first would push a finish with no matching start), then `debugProfileBuildsEnabled` + `debugProfileBuildsEnabledUserWidgets` from `package:flutter/widgets.dart`, and on `--phases` also `debugProfileLayoutsEnabled` + `debugProfilePaintsEnabled` from `package:flutter/rendering.dart`. It saves each flag's prior value in the session and `perf_end` restores THOSE values rather than forcing `false`: a host that had build profiling on for its own reasons must get it back. A `perf_begin` on an already-open session restarts it, restoring before re-saving, so a dropped connection cannot strand the profiling flags on.

`perf_end` reads the frames and the liveness counter through `framePerfReader`, the magic-side counters through `perfExtrasReader`, and wind's aggregate through `WindDebugRegistry.currentPerf`. dusk depends on none of those packages; `magic_devtools` assigns the pointers. The report carries `frameSummary` (Flutter's own metric-name strings, from `lib/src/utils/frame_summary.dart`), a session-wide `blockAttribution` ranking, `wind`, `magic`, and a `note` stating that per-type absolute durations are indicative rather than representative.

When the liveness counter has not advanced between the two calls, `perf_end` REFUSES: `refused: true`, a reason, and no metrics at all. That counter is the authority rather than the `warnings` block on the same response, because `SchedulerBinding.framesEnabled` was measured reporting `true` with lifecycle `resumed` on a hidden Chrome page that had produced one frame in two seconds. Both signals can appear on one payload, so `refused` is always present and is the only discriminator.

## Frozen contracts

The list of frozen signatures, names and substrings is CLAUDE.md "Off-limits"; a change to one is a coordinated bump across `magic`, `wind` and `dusk`. This section carries what that list leaves out and how each contract is checked.

The seven perf pointers exported from `lib/dusk.dart` (`framePerfReader`, `perfExtrasReader`, `perfSessionBeginHook`, `perfSessionEndHook`, `perfInsightContributors`, `perfTimelineReader`, `rendererReader`, declared in `lib/src/utils/perf_readers.dart`) and the key sets they return are frozen too. `magic_devtools` assigns the first six from another repository, so a renamed key does not fail to compile: it empties one section of the performance report with no error anywhere. `framePerfReader`'s `livenessCounter` is load-bearing beyond that, since `ext.dusk.perf_end`'s stalled-engine refusal is computed from it.

| Contract | Verify |
|---|---|
| Gate reason substrings and order | `flutter test test/src/utils/actionability_gate_test.dart` |
| `e<N>` / `q<N>` token spaces stay disjoint | `flutter test test/src/ref_registry_test.dart` |
| Perf pointers and their key sets | `flutter test test/src/utils/perf_readers_test.dart` |
| MCP descriptors under 2048 characters, alpha-1 names | `flutter test test/dusk_artisan_provider_mcp_tools_test.dart` |
| `server.json` version equals `pubspec.yaml` | `flutter test test/server_json_version_test.dart` |

## Actionability gate

`lib/src/utils/actionability_gate.dart` runs six preconditions in order (Step 0 defunct preflight + Steps 1-5 ordered) before any tap, hover, drag, dblclick, right_click, triple_click, or type:

| Step | Check | Fail reason string | Notes |
|---|---|---|---|
| 0 | `findRenderObject()` returns non-null | `defunct (...)` | Element no longer attached after a rebuild |
| 1 | `node.flagsCollection.isEnabled != Tristate.isFalse` | `not enabled` | `Tristate.none` (default) passes |
| 2 | `rect.width > 0 && rect.height > 0` | `zero rect` | Collapsed or detached widget |
| 3 | rect overlaps the visible viewport (view minus `viewInsets`) | `off-viewport (rect=..., viewport=...)` | Auto-scrolls via `showOnScreen` first when the center is outside it and a `Scrollable` ancestor exists |
| 4 | live rect drift ≤ 0.5px across one frame | `not stable (rect changed by Xpx)` | Skipped when `--no-checkStable` |
| 5 | hit-test path at `rect.center` includes the target render object or a descendant | `obscured by other widget (top=...)` | Skipped when `--no-checkReceivesEvents` |

The gate returns an `ActionabilityReport` alongside throwing. Step 5 has three outcomes, not two: `confirmed`, `indeterminate` (the hit-test could not answer), and `skipped` (`--no-checkReceivesEvents`). Only the first is silent; the other two surface as a `checks` block on the response, because a clean pass used to be indistinguishable from a confirmed one and that is how a fill printed a green tick four times onto a row covered by a pinned footer.

`indeterminate` is the Flutter Web case: DWDS pipes hit-tests through a snapshot view that does not mirror the live element subtree, so the path comes back carrying only the root render view. The gate proceeds (breaking every valid tap on that artifact is the worse failure) and attaches `overlapCandidates` from a rect scan: render objects that overlap the target and paint after it. Advisory, since an overlap is not proof of occlusion.

`scroll`, `select_option`, and `press_key` intentionally skip the gate (the parent scrollable, popup machinery, or focused widget owns its own enabled check).

## RefRegistry token systems

**`e<N>` (snapshot-frozen)**: minted at `dusk:snap` time. Stores element + rect + groupId + optional SemanticsNode/RenderObject. `node.id` dedup; the same widget across snapshots reuses the same `eN`. Element unmount triggers a `defunct` gate failure, unless the ref can be relocated: each labelled ref carries a `RefBinding` (a `DuskQuery` with label and `matchIndex`, plus the match count at mint time), and `resolveRefForAction` relocates a stale ref only when the live tree has the same number of namesakes, rebinding the token and reporting it as `reresolved`. `RefBinding`, `bind`, `lookupBinding` and `rebind` are additive statics, not changes to the frozen signatures below. Nested duplicate `textbox` nodes (e.g. an outer `Semantics(textField:true)` wrapper around a `RenderEditable` leaf that owns its own node) collapse during the walk: a `textbox` whose render object is a render-tree descendant of an enclosing `textbox`'s render object is suppressed, so only the outer typeable node mints an `eN`. The surviving line carries `typeable: true`. Collapse is by render-object containment only; sibling fields sharing a label stay distinct. A node flagged `isMergedIntoParent` (absorbed by a `MergeSemantics` boundary) mints no `eN` and prints no line; the walk descends through it, so a merged control is one ref on its boundary node.

**`q<N>` (re-resolvable)**: minted at `dusk:find` and `dusk:observe` time. Stores a predicate (`text` / `semanticsLabel` / `keyValue`) and re-walks the live tree on every action. Playwright Locator pattern. UI changes trigger a `DuskStaleHandleException`.

A `dusk:observe` handle carries one extra field, `DuskQuery.matchIndex`, and the two mint sites differ for a reason. A `dusk:find` predicate is CHOSEN, so answering the first match and reporting the total (`label 'X' matched N nodes; refine with ...`) puts the next move where it belongs. An observe predicate is DERIVED from a node the walk already holds, and observe promises one candidate per interactive node (a node merged into a `MergeSemantics` boundary is not one of its own: the control is listed once, as the boundary), so without an index every candidate sharing a label resolves to the first and an agent acting on the third row moves the first with both calls reporting success. The index is the node's position among every node whose label matched, in walk order, counted before observe's role filter, its interactivity check and its merged-node skip so the two walks count the same universe. Playwright's `locator.nth(i)` is the same pair. An index that no longer resolves is a no-match rather than a fall back to a surviving namesake.

`resolveRefForAction(ref)` in `lib/src/extensions/ext_pointer.dart` dispatches by prefix.

A tap on a ref inside a `MergeSemantics` boundary lands on the boundary's centre, because the merged node reports the boundary's own rect and the absorbed controls (flagged `isMergedIntoParent`) get no ref (issue #60). `judgeTapPoint` in `lib/src/utils/tap_owner.dart` finds the tap carriers beneath the boundary through the element tree. The owner is the labelled one: a `Semantics` whose label is part of the node's merged label, so a full-frame handler with no label can never hide the miss. With exactly one owner whose centre a hit probe reaches, `aiTestTapHandler` sends the pointer there (`retargeted`); otherwise it taps the centre and reports `tapPointOutsideOwner`, a warning `dusk:tap` prints. With no labelled carrier it compares against every carrier. Snapshot and observe call the same function (`tapOwnerBounds`) to print a `tapOwner` sub-line and field. The gate still judges the boundary's centre, and a carrier the element tree does not expose is not detected.

## CDP layer

`lib/src/cdp/cdp_client.dart` connects to Chrome at `localhost:<cdp-port>/json`, picks the first `type:"page"` tab, opens a WebSocket, and dispatches JSON-RPC with an auto-incrementing id and a 30s per-request timeout.

`device_presets.dart` carries 8 named presets (iphone-x, iphone-13, iphone-15-pro, pixel-5, pixel-8, ipad-pro-12.9, desktop-1440, desktop-1920). Each preset is width × height × DPR × mobile flag × touch flag × userAgent.

`dusk:device` runs a 3-call CDP chain: `Emulation.setDeviceMetricsOverride` → optional `Emulation.setTouchEmulationEnabled` → `Emulation.setUserAgentOverride`, plus `Browser.getWindowForTarget` + `Browser.setWindowBounds` to resize the OS window (Emulation only changes the page view).

`dusk:screenshot` on web sends `Page.enable` + `Page.captureScreenshot` (`format`, `quality`, `fromSurface: true`) via CDP, bypassing the in-isolate `ext.dusk.screenshot` extension that hangs under CanvasKit+DWDS. Native targets use the in-isolate path. The command captures the full app frame; region capture is not exposed by the CLI command or the `dusk_screenshot` MCP tool (both dispatch full-frame). This CDP fallback is CLI-only; the `dusk_screenshot` MCP tool dispatches `ext.dusk.screenshot` in-isolate.

`FakeCdpServer` in `test/src/cdp/fake_cdp_server.dart` is the in-process mock for unit tests.

## Hot reload flow

`dusk:hot_reload_and_snap` lives CLI-side (an in-isolate handler cannot reload itself; the handler would block on the reload and the request would never return). The command writes `r\n` to the stdin FIFO recorded in `~/.artisan/state.json`, then tail-polls the flutter run log for the `Reloaded N libraries in Mms` marker (or the `Try again after fixing` compile-error marker). Resolves in ~170ms on desktop.

`IsolateReload` VM Service events are intentionally avoided because they do not fire on no-op (0-library) reloads, and `hot_reload_and_snap` is most useful precisely when the caller wants to force a reassemble without editing files.

## Change guide

The steps for adding a verb are in `.claude/rules/extensions.md` and `commands.md`. These are the other places that move together, taken from the git log.

| Change | Touch | Also check |
|---|---|---|
| Snapshot line format or a merged-node rule | `ext_snapshot.dart` and `ext_observe.dart` | They list nodes separately: #56 fixed snapshot and #58 had to fix observe again. `snapshot_diff.dart` parses the snapshot's `[ref=eN]` lines. Both print the merged node's `tapOwner` through `tapOwnerBounds` in `utils/tap_owner.dart`. |
| Text-input resolution (which field a ref writes) | `ext_text_input.dart` | `ext_fill.dart` shares `resolveTextFieldTarget` and `refuseNonTextRef`; four consecutive `text-input` fixes touched only `ext_text_input.dart`, so check that `fill` still agrees. |
| Gate precondition or hit probe | `utils/actionability_gate.dart`, `utils/viewport_visibility.dart` | `probeHitAt` also feeds the snapshot `[occluded]` marker and observe `occluded`; the gate's reason substrings are frozen. |
| A key every success response should carry | `utils/dusk_response.dart` (`duskResult`) | Per-call state travels in a zone value set by `dusk_register.dart`, not a parameter. |
| Perf report shape | `ext_perf.dart`, `utils/perf_readers.dart`, `lib/dusk.dart` | `magic_devtools` assigns the pointers from another repository; a changed key set fails silently there. |
| Frame wake, web visibility | `utils/frame_sync.dart`, `utils/dusk_register.dart`, `commands/web_visibility.dart` | `doc/reference/frame-production.md` documents the observable behaviour and its side effects. |
| Release | version stamps listed in CLAUDE.md Branching | `test/server_json_version_test.dart` guards `server.json` only. |

## Traps

- The snapshot baseline is module state in `ext_snapshot.dart`, not part of `RefRegistry`: a hot restart clears it, and a test that builds a snapshot calls `resetSnapshotBaselineForTesting`.
- `SchedulerBinding.framesEnabled` can read `true` on a hidden Chrome page that is not producing frames; `framePerfReader`'s `livenessCounter` is the authority.
- `dusk_evaluate` has an MCP tool and no CLI command on purpose (`magic_tinker` owns the connected REPL); do not mirror it under `dusk:`.
- A web tap or fill can throw a DWDS timeout instead of returning a `warnings` block when the tab is hidden; `callExtensionVisible` recovers both shapes.

Last reviewed: 2026-11-07, after agent-reliability rounds 1 and 2 (frame wake, `dusk:run`, snapshot diff, ref relocation, web tab recovery).
