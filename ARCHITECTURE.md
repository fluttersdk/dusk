# tapir architecture

## Overview

Tapir is one request path split across two processes that meet only on the VM Service. In the app (a Flutter debug or profile build), `TapirPlugin.install()` registers the `ext.tapir.*` handlers, which read the Semantics tree, dispatch pointer, text and key events and answer in JSON. On the host (the plain Dart VM), `TapirDowelProvider` contributes the `tapir:*` commands and the `tapir_*` MCP descriptors, and each one calls a handler through dowel; the commands that cannot run inside the isolate (hot reload, CDP, the perf driver) do host-side work instead. Nothing here depends on `magic`, `wind_kit` or `crumbs`: they plug in through the hooks `lib/tapir.dart` exports (the enricher list, the navigate adapter, the perf pointers, and the log, exception and in-flight request readers) and through wind's `WindDebugRegistry`.

```text
agent ──tapir_* tool───▶ dowel mcp:serve ───┐
shell ──tapir:* command ▶ bin/tapir.dart ───┴─ VM Service ─▶ ext.tapir.<verb> ─▶ widget tree
        host process (plain Dart VM)                       app isolate (Flutter)
```

## Codemap

### `lib/src/extensions/` and `lib/src/utils/` (in the app)

- Owns: the `ext.tapir.*` handlers, one `ext_<name>.dart` per group, wired by `registerAllTapirExtensions`; and the helpers they share (`ensureActionable`, `awaitFrameOrTimeout`, `registerTapirExtension`, `tapirResult`, the effect reports, the perf report builder).
- Depends on: Flutter, `dowel` (`registerExtensionIdempotent`), `RefRegistry`.
- The exception is `utils/chrome_reaper.dart`: it imports no Flutter and serves `tapir:doctor` on the host.

### `TapirPlugin` (`lib/src/tapir_plugin.dart`)

- Owns: `install()`, the live `enrichers` list, the navigate adapter, the boot id, and the error and log capture.
- Depends on: `registerAllTapirExtensions`.

### `RefRegistry` (`lib/src/ref_registry.dart`)

- Owns: the disjoint `e<N>` and `q<N>` token spaces, and the `RefBinding` that relocates a stale `e<N>`.
- Depends on: Flutter's element and semantics trees.

### The host half (`lib/src/commands/`, `perf/`, `cdp/`, `TapirDowelProvider`, `cli_args.dart`, `bin/tapir.dart`, `lib/cli.dart`)

- Owns: the commands, the MCP descriptors (an `extensionMethod` is `ext.tapir.<verb>`, or a host-side `dowel:tapir:<verb>` route), the CDP client and device presets, the perf run driver, and the CLI wrapper.
- Depends on: `dowel`. It reaches the app over the VM Service (`ctx.callExtension('ext.tapir.<verb>', ...)`, or dowel's `VmServiceClient` in the perf driver), through the stdin FIFO of `tapir:hot_reload_and_snap`, or over CDP to Chrome.

### The perf pointers (declared here, assigned elsewhere)

`framePerfReader`, `perfExtrasReader`, `perfSessionBeginHook`, `perfSessionEndHook`, `perfInsightContributors` and `perfTimelineReader` are declared in `lib/src/utils/perf_readers.dart` and exported from `lib/tapir.dart`. `magic_devtools` assigns the readers and hooks from another repository and appends to `perfInsightContributors`; `rendererReader` is the seventh pointer and it does not assign that one.

## Invariants

| Rule | Why | Verify |
|------|-----|--------|
| Host-half files import no Flutter and no `dart:ui` | `dart run tapir` runs them on the plain VM, where `dart:ui` does not exist | `rg -n -e "^import 'package:flutter" -e "^import 'dart:ui" bin lib/cli.dart lib/src/commands lib/src/perf lib/src/cdp lib/src/cli_args.dart lib/src/tapir_dowel_provider.dart lib/src/utils/chrome_reaper.dart` prints nothing, and `dart run bin/tapir.dart --help` starts |
| `extensions/` and `utils/` import nothing from `commands/`, `perf/` or `cdp/` | The in-app half must stay loadable without the host half | `rg -n -e "^import '[^']*/commands/" -e "^import '[^']*/perf/" -e "^import '[^']*/cdp/" lib/src/extensions lib/src/utils lib/src/tapir_plugin.dart lib/src/ref_registry.dart` prints nothing |
| No `endOfFrame` await is unbounded | A hidden window or tab turns `framesEnabled` off, a bare await never completes, and the CLI times out with no output and no error | `rg -nP "^\s*(?!//)[^/]*\bendOfFrame\b(?!\s*\.timeout)" lib --glob '*.dart'` prints nothing |
| One hit test: `probeHitAt` is the only caller of `hitTestInView` | Two hit tests could disagree about what covers a target | `rg -n "hitTestInView\(" lib` prints only `lib/src/utils/viewport_visibility.dart` |
| The perf pointers and the key sets they return do not change | A renamed key compiles and silently empties one section of the performance report; `livenessCounter` also decides the stalled-engine refusal | `flutter test test/src/utils/perf_readers_test.dart` |
| `perf_end` refuses with no metrics when the liveness counter advanced by one frame or fewer, and `refused` is always present | `SchedulerBinding.framesEnabled` can read true on a hidden Chrome page that is not producing frames, so the counter is the authority and `refused` is the only discriminator | `flutter test test/src/extensions/ext_perf_test.dart --plain-name "refus"` |
| `perf_end` restores each profiling flag to the value `perf_begin` saw, and a second `perf_begin` restores before it saves | A host that had build profiling on for its own reasons gets it back, and a dropped connection cannot strand the flags on | `flutter test test/src/extensions/ext_perf_test.dart --plain-name "restores"` |
| Off-limits items 4 to 8 in CLAUDE.md hold, and `server.json` carries the `pubspec.yaml` version | `magic`, `wind_kit` and agents branch on them, and the MCP registry reads `server.json` | `flutter test test/src/utils/actionability_gate_test.dart test/src/ref_registry_test.dart test/src/utils/perf_readers_test.dart test/tapir_dowel_provider_mcp_tools_test.dart test/server_json_version_test.dart` |

## Flows

Install:

1. The consumer's `main()` calls `TapirPlugin.install()` before `runApp`; a second call only logs: `lib/src/tapir_plugin.dart:TapirPlugin.install`
2. It mints the boot id, forces Semantics on, registers every extension with `boot_id` last, then chains `FlutterError.onError` and `debugPrint` into the capture buffers: `lib/src/extensions/register_tapir_extensions.dart:registerAllTapirExtensions`, `installErrorCapture`, `installLogCapture`
3. `plugin:install tapir` wires `TapirDowelProvider` into the consumer's `lib/app/_plugins.g.dart`, so `dowel mcp:serve` surfaces the `tapir_*` tools: `install.yaml`

A tap (the other pointer and text verbs follow the same path):

1. The command calls the extension; `tap`, `type`, `fill`, `scroll`, `press_key`, `navigate`, `snap` and `observe` go through `callExtensionVisible`: `lib/src/commands/web_visibility.dart:callExtensionVisible`
2. The wrapper wakes a hidden window (`ensureFramesProduced`, unless the verb registered with `ensureFrames: false`) and opens the zone that carries per-call state: `lib/src/utils/tapir_register.dart:wrapTapirHandler`
3. The handler resolves the ref, relocating a stale `e<N>` through its `RefBinding` and re-walking a `q<N>`: `lib/src/extensions/ext_pointer.dart:resolveRefForAction`
4. The gate throws a `TapirActionabilityException` or returns an `ActionabilityReport`: `lib/src/utils/actionability_gate.dart:ensureActionable`
5. The handler dispatches the event, settles two frames through `awaitFramesOrTimeout`, and reads the result back into an `effect` block: `lib/src/utils/effect_report.dart`
6. `snapshotForAction` attaches a snapshot as the `snapshot` param asks, and `tapirResult` stamps the per-call diagnostics: `lib/src/extensions/ext_snapshot.dart:snapshotForAction`, `lib/src/utils/tapir_response.dart:tapirResult`

Frame production is off (hidden web tab):

1. The in-app wake is never attempted on web, because a hidden tab withholds `requestAnimationFrame`: `lib/src/utils/frame_sync.dart:ensureFramesProduced`
2. The response carries a `warnings` block with `platform: web`, or the call throws a timeout: `lib/src/utils/frame_sync.dart:frameProductionWarning`
3. With a `cdpPort` in the session state, the CLI sends CDP `Page.bringToFront` once, for either shape, and calls again only a `retry: true` verb (`snap`, `observe`): `lib/src/commands/web_visibility.dart:callExtensionVisible`
4. The command prints the matching stderr banner: `lib/src/commands/frame_warning_output.dart:reportFrameWarning`

Performance session:

1. `perf_begin` opens a session and switches the profiling flags on (`FlutterTimeline.debugCollectionEnabled` first: `startSync` and `finishSync` both check it); in timing mode it touches no flag: `lib/src/extensions/ext_perf.dart`
2. It zeroes the host counters through `perfSessionBeginHook` and reads the liveness baseline last: `lib/src/extensions/ext_perf.dart`
3. `perf_end` judges the liveness counter before anything else; otherwise it reads `framePerfReader`, `perfExtrasReader` and `WindDebugRegistry.currentPerf`, and `analysePerf` builds the report with the insight contributors: `lib/src/utils/perf_insights.dart:analysePerf`
4. The rows behind each insight stay behind `ext.tapir.perf_insight`.

Hot reload:

1. The command writes `r\n` to the stdin FIFO recorded as `stdinPipe` in the dowel session state: `lib/src/commands/tapir_hot_reload_and_snap_command.dart`
2. It tail-polls the flutter run log for `Reloaded N libraries` or `Try again after fixing`, then snapshots. A VM Service `IsolateReload` event is not used because it does not fire on a no-op reload.

## Decisions

| Decision | Why | Rejected alternatives | Status |
|----------|-----|-----------------------|--------|
| The snapshot baseline lives in `ext_snapshot.dart` module state | The `RefRegistry` surface is frozen, and a filtered snap never records it | A field on `RefRegistry` | Active |
| Gate step 5 proceeds on `indeterminate` and reports `overlapCandidates` | On Flutter Web, DWDS pipes hit tests through a snapshot view that does not mirror the live subtree, so the path can hold only the root render view; refusing would break every valid web tap | Refusing on an empty or root-only path | Active |
| An `observe` handle carries `TapirQuery.matchIndex`; `find` answers the first match and reports the total | An `observe` predicate is derived from a node the walk already holds, so without an index every namesake resolves to the first; a `find` predicate is chosen, so the next move belongs to the caller | Resolving by label alone | Active |
| `tapir:screenshot` goes over CDP when the session has a `cdpPort` | The in-isolate capture hangs under CanvasKit and DWDS; the `tapir_screenshot` MCP tool still calls `ext.tapir.screenshot` in the isolate | One path for every target | Active |
| Perf data reaches tapir through pointers the host assigns | Tapir depends on none of the packages that feed it, so the dependency points from them to tapir | A tapir dependency on `magic` or `wind_kit` | Active |

## Change guide

| To change | Touch | Also check |
|-----------|-------|------------|
| The snapshot line format or a merged-node rule | `ext_snapshot.dart`, `ext_observe.dart` | They list nodes in separate walks, so a rule in one needs the other; `utils/snapshot_diff.dart` parses the `[ref=eN]` lines; both print `tapOwner` through `tapOwnerBounds` in `utils/tap_owner.dart` |
| Which field a ref writes | `ext_text_input.dart` | `ext_fill.dart` shares `resolveTextFieldTarget` and `refuseNonTextRef` |
| A gate precondition or the hit probe | `utils/actionability_gate.dart`, `utils/viewport_visibility.dart` | `probeHitAt` also feeds `ext_snapshot.dart` (`[occluded]`), `ext_observe.dart` (`occluded`) and `tap_owner.dart` |
| A key every success response carries | `utils/tapir_response.dart` (`tapirResult`) | Per-call state travels in a zone value set by `tapir_register.dart`, never a parameter |
| The perf report shape | `ext_perf.dart`, `utils/perf_readers.dart`, `lib/tapir.dart` | The key sets are frozen (Invariants) |
| The frame wake or web recovery | `utils/frame_sync.dart`, `utils/tapir_register.dart`, `commands/web_visibility.dart` | `doc/reference/frame-production.md` documents the observable behaviour |

## Cross-cutting

- State: `RefRegistry`, the snapshot baseline and the perf session live in statics and module variables, so a hot restart clears them.
- Success means the widget received the input: `tap`, the text verbs, `scroll`, `select_option` and `set_checkbox` read the result back into an `effect` block through `utils/effect_report.dart`.

## Traps

- `ext_modal_router.dart:_settleFrame` carries its own 200 ms `endOfFrame.timeout` instead of calling `awaitFrameOrTimeout`: bounded, but a second copy of the bound.
- `tapir:device` overrides belong to its own DevTools session and Chrome drops them when the command exits; only the window bounds persist. A lasting viewport is `tapir:resize --hold`: `lib/src/commands/tapir_device_command.dart`
- `ext.tapir.screenshot` captures the nearest `isRepaintBoundary` render object; any `RepaintBoundary` is the consumer's, and `install()` adds none: `lib/src/extensions/ext_screenshot.dart`

Last reviewed: 2026-11-14 after restructuring to the architecture contract.
