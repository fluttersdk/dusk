# Commands

Every `tapir` command, grouped by intent, with its boot mode and the VM Service extension behind it.

Every command is invoked as `dart run tapir <name>` (Flutter-free wrapper at `bin/tapir.dart`), or via the consumer-side dowel dispatcher (`./bin/dowel <name>` / `dart run dowel <name>`) once the project has run `tapir:install`. Commands are auto-discovered through `TapirDowelProvider`; nothing wires by hand.

Need a quick reminder of what a command does without leaving the terminal? Run `dart run dowel list` for the full registry grouped by namespace, or `dart run dowel help <name>` for the per-command flag surface. This page exists for the deeper view: the boot mode, the backing VM Service extension, and the grouping rationale.

- [How to read this page](#how-to-read-this-page)
- [Snapshot and screenshot](#snapshot-and-screenshot)
- [Gestures](#gestures)
- [Inputs](#inputs)
- [Navigation](#navigation)
- [Find](#find)
- [Diagnostics](#diagnostics)
- [Install](#install)
- [CDP](#cdp)
- [Click variants](#click-variants)
- [Focus and blur](#focus-and-blur)
- [Console and exceptions](#console-and-exceptions)
- [Observe](#observe)
- [Hot reload and snap](#hot-reload-and-snap)
- [Batch](#batch)
- [Performance](#performance)
- [Boot mode and deep-dives](#boot-mode-and-deep-dives)
- [Related Documentation](#related-documentation)

<a name="how-to-read-this-page"></a>
## How to read this page

Each group section ships a single table with four columns:

- **Command** is the canonical name you type after `dart run tapir` (or via the dowel dispatcher).
- **Description** is a one-line summary of the command; `dart run dowel list` prints each command's own wording, which differs for a few.
- **Boot Mode** is the `CommandBoot` value the dispatcher reads before invoking `handle()`. `none` means pure CLI: no VM Service connection. `connected` means the command dials the VM Service URI recorded for this project's dowel session and fails fast if no app is running.
- **VM Extension** is the `ext.tapir.*` method the command calls over the VM Service. `none` for commands that operate purely on the consumer filesystem.

Deep-dive pages exist for the commands whose flag surface, return shape, or composition rules outgrow a single table row; the tables below link them. The other commands share this index page; reach for `dart run dowel help <name>` for their full flag surface.

<a name="snapshot-and-screenshot"></a>
## Snapshot and screenshot

The two foundational read commands. `tapir:snap` walks the Semantics tree and emits YAML with `[ref=eN]` tokens that every subsequent action command consumes. `tapir:screenshot` captures a frame of the running app and writes it to a file.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| [`tapir:snap`](tapir-snap.md) | Capture Semantics tree YAML of the running Flutter app with [ref=eN] tokens. | connected | ext.tapir.snap |
| [`tapir:screenshot`](tapir-screenshot.md) | Capture a screenshot of the running Flutter app to a file. | connected | ext.tapir.screenshot |

<a name="gestures"></a>
## Gestures

Pointer-driven actions that synthesise touch, mouse, or pen events at a widget located by ref token. `tapir:tap`, `tapir:hover` and `tapir:drag` route through the actionability gate (see [Reference: Actionability gate](../reference/actionability-gate.md)) before the event leaves the VM. `tapir:scroll` skips the gate on purpose: it acts on the parent scrollable, so it can bring an off-viewport target into view (see [Intentional gate skips](../reference/actionability-gate.md#intentional-gate-skips)).

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| [`tapir:tap`](tapir-tap.md) | Tap a widget by ref token (from prior tapir:snap). | connected | ext.tapir.tap |
| `tapir:hover` | Hover the pointer over a widget by ref token (from prior tapir:snap). | connected | ext.tapir.hover |
| `tapir:drag` | Drag from one widget to another using ref tokens from a prior tapir:snap. | connected | ext.tapir.drag |
| `tapir:scroll` | Scroll inside a scrollable widget by ref token from a prior tapir:snap. | connected | ext.tapir.scroll |

<a name="inputs"></a>
## Inputs

Keyboard-shaped actions. `tapir:type` emits a character sequence; `tapir:press_key` synthesises a single hardware-key event; `tapir:clear` empties the focused text field; `tapir:select_option` drives `DropdownButton` / `PopupMenuButton`; `tapir:set_checkbox` drives `Checkbox` / `Switch`.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| `tapir:type` | Type text into a focused widget by ref token. | connected | ext.tapir.type |
| [`tapir:fill`](tapir-fill.md) | Focus, clear, type, and settle a text field by ref in one call (retries once on a stale handle). | connected | ext.tapir.fill |
| `tapir:press_key` | Synthesise a hardware-key event on the currently focused widget. | connected | ext.tapir.press_key |
| `tapir:clear` | Empty the text content of the focused widget by ref. | connected | ext.tapir.clear |
| `tapir:select_option` | Select an option in a DropdownButton or PopupMenuButton by ref token. | connected | ext.tapir.select_option |
| `tapir:set_checkbox` | Set the checked state of a Checkbox or Switch widget by ref. | connected | ext.tapir.set_checkbox |
| `tapir:wait` | Wait for a text, text-gone, or expression condition in the running app. | connected | ext.tapir.wait_for |
| `tapir:wait_for_network_idle` | Wait until the running app reports zero in-flight HTTP requests for a contiguous idleMs window. | connected | ext.tapir.wait_for_network_idle |

<a name="navigation"></a>
## Navigation

Route-table manipulation against the active `Navigator`. `tapir:modal` dismisses any open modal, sheet, or dialog. `tapir:close_app` ends the session via `SystemNavigator.pop()`.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| `tapir:navigate` | Navigate the running app to a named route via the active Navigator. | connected | ext.tapir.navigate |
| `tapir:navigate_back` | Pop the topmost route off the active Navigator (mirrors browser back). | connected | ext.tapir.navigate_back |
| `tapir:get_routes` | Print the mounted Router's location (`uri`), the top page name and a title hint as JSON. | connected | ext.tapir.get_routes |
| `tapir:modal` | Dismiss all open modals, bottom sheets, and dialogs in the running app. | connected | ext.tapir.dismiss_modals |
| [`tapir:reset_overlays`](tapir-reset-overlays.md) | Reset to a clean screen: dismiss modals + Escape + Cancel-tap fallback (idempotent). | connected | ext.tapir.reset_overlays |
| `tapir:close_app` | Gracefully close the running app via SystemNavigator.pop(). | connected | ext.tapir.close_app |

<a name="find"></a>
## Find

The Playwright Locator surface: mint a re-resolvable `q<N>` handle backed by text, semanticsLabel, or key predicates. Every action call against a `q<N>` handle re-walks the live tree, so the handle survives intermediate rebuilds.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| [`tapir:find`](tapir-find.md) | Mint a re-resolvable q-handle by text / semanticsLabel / key (Playwright Locator pattern). | connected | ext.tapir.find |

<a name="diagnostics"></a>
## Diagnostics

Pure-CLI checks that verify the consumer wiring and the running session health. Neither command dials the VM Service.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| [`tapir:doctor`](tapir-doctor.md) | Verify tapir plugin runtime + consumer wiring health | none | none |

<a name="install"></a>
## Install

The one-shot bootstrap. Patches the consumer's `lib/main.dart`, then chains `dowel install` and `plugin:install tapir` on a best-effort basis; `tapir` ships its own Flutter-free CLI entry point, so the chain only adds the faster `./bin/dowel` path. Idempotent on re-run.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| [`tapir:install`](tapir-install.md) | Wire TapirPlugin.install() into lib/main.dart AND chain dowel install + plugin:install so ./bin/dowel surfaces every tapir:* command (idempotent on re-run; Phase 2 chain is best-effort). | none | none |

<a name="cdp"></a>
## CDP

Chrome DevTools Protocol commands that manipulate the browser viewport directly. Web target only; desktop and mobile no-op gracefully.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| `tapir:device` | Emulate a device profile (viewport + DPR + touch + user agent) via Chrome DevTools Protocol. The emulation lasts only as long as the command's CDP session, which closes on exit; only the window size stays. | none | none (CDP direct) |
| `tapir:resize` | Resize the running Flutter web app viewport via Chrome DevTools Protocol. Chrome drops the override when the command exits; `--hold` keeps it until Ctrl-C or Chrome exits. | none | none (CDP direct) |

<a name="click-variants"></a>
## Click variants

Pointer gestures that go beyond the primary tap. All three route through the actionability gate.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| `tapir:dblclick` | Fire a double-click at the widget identified by a snapshot ref. | connected | ext.tapir.dblclick |
| `tapir:triple_click` | Fire three primary clicks (~100ms apart) at the widget identified by --ref. | connected | ext.tapir.triple_click |
| `tapir:right_click` | Fire a right (secondary mouse button) click at the widget identified by --ref. | connected | ext.tapir.right_click |

<a name="focus-and-blur"></a>
## Focus and blur

Keyboard-focus shaping. `tapir:focus` requests focus on a ref; `tapir:blur` releases the currently focused widget.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| `tapir:focus` | Request keyboard focus on the widget identified by --ref. | connected | ext.tapir.focus |
| `tapir:blur` | Remove keyboard focus from the currently-focused widget. | connected | ext.tapir.blur |

<a name="console-and-exceptions"></a>
## Console and exceptions

Diagnostics readers backed by tapir's own in-package capture plus an optional crumbs augmentation.

`tapir:console` reads from tapir's in-package `debugPrint` ring buffer (populated by `installLogCapture()`,
wired by `TapirPlugin.install()`). This buffer captures every call that routes through the `debugPrint` global
callback (`debugPrint(...)`, `print(...)`, and any Flutter framework path that calls `debugPrint`). It does NOT
capture direct `dart:developer` `log()` calls that bypass `debugPrint`; those require the crumbs
`LogWatcher`. When crumbs is wired the two sources are merged and deduped; crumbs also adds `package:logging`
(`Logger.root.onRecord`) and any other watcher it ships.

`tapir:exceptions` is similar: tapir's own `FlutterError.onError` capture (non-fatal errors including overflow)
is always present; crumbs augments when wired.

The `--since=<iso8601>` flag on `tapir:exceptions` (and the matching `since` param on `tapir_exceptions` MCP)
lets agents compute true before/after deltas: record the time before an action, then call
`tapir:exceptions --since=<time>` afterwards to see only exceptions raised by that action.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| `tapir:console` | Read recent log entries (in-package debugPrint capture; augmented by crumbs when wired). | connected | ext.tapir.console |
| `tapir:exceptions [--limit=<n>] [--since=<iso8601>]` | Read recent exception entries (in-package FlutterError capture + crumbs when wired). Optionally filter to entries strictly after `--since`. | connected | ext.tapir.exceptions |

<a name="observe"></a>
## Observe

The Stagehand observe-once-act-many surface. Returns a structured candidate list of every interactive widget on screen; the agent decides which refs to act on. No server-side LLM.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| [`tapir:observe`](tapir-observe.md) | Return a structured candidate list of every interactive widget on screen (Stagehand observe-once-act-many; no server-side LLM). | connected | ext.tapir.observe |

<a name="hot-reload-and-snap"></a>
## Hot reload and snap

The single-round-trip composite that hot-reloads the running app and then captures snapshot, screenshot, and recent exceptions in one shot. Dispatched via the `dowel:` substrate routing prefix to avoid a same-isolate deadlock. The reload itself is a keystroke, not a VM Service `reloadSources` call: the command writes `r` to the stdin FIFO recorded in the session state and waits for the "Reloaded N libraries" line in the `flutter run` log. A session started by `dart run tapir start` has that FIFO; one started by plain `flutter run` does not, and the command reports it as missing.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| `tapir:hot_reload_and_snap` | Hot reload the running app, then capture snapshot + screenshot + recent exceptions in a single round-trip. | connected | `r` written to the `flutter run` stdin FIFO, then `ext.tapir.snap`, `ext.tapir.screenshot`, `ext.tapir.exceptions` |

<a name="batch"></a>
## Batch

One call, several verbs. `tapir:run` takes each step as a verb line, runs them in order on the one VM connection, and prints a summary line per step plus the last step's output. Steps may be any connected-boot verb except `tapir:run` itself.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| [`tapir:run`](tapir-run.md) | Run several tapir verbs in one call, e.g. tapir:run "tap --ref=e5" "snap --grep Counter". | connected | each step's own extension |

<a name="performance"></a>
## Performance

One measurement session and its drill-down. `tapir:perf_begin` opens it (`--mode=attribution` profiles builds, `--mode=timing` touches no flag), you drive one interaction, `tapir:perf_end` closes it with a bounded report of ranked insights, and `tapir:perf_insight` returns the rows behind one of them. `tapir:perf_run` repeats a scenario from a clean start and writes the medians to a file, `tapir:perf_compare` judges one such file against another, and `tapir:perf_trace` writes a session's timeline for Perfetto. `tapir:perf_campaign` runs a whole campaign of scenarios, each from a cold start.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| [`tapir:perf_begin`](tapir-perf-begin.md) | Open a performance measurement session: zero the frame, wind and magic counters and, in attribution mode, switch on build profiling. | connected | ext.tapir.perf_begin |
| [`tapir:perf_end`](tapir-perf-end.md) | Close the performance measurement session and report frames, ranked blocks, counters and insights. | connected | ext.tapir.perf_end |
| [`tapir:perf_insight`](tapir-perf-insight.md) | Drill into one insight of the last perf_end report: title, summary, the rows behind it, estimated savings and the next step. | connected | ext.tapir.perf_insight |
| [`tapir:perf_run`](tapir-perf-run.md) | Run a perf scenario N times from a clean start and write medians, spread, insights and every repeat to <out>/<scenario>-<label>.json. | connected | ext.tapir.perf_begin + perf_end (+ semantics_hold) |
| [`tapir:perf_compare`](tapir-perf-compare.md) | Compare two tapir:perf_run files on counts per painted frame (and timing-mode ms) and print a verdict table. | none | none |
| [`tapir:perf_trace`](tapir-perf-trace.md) | Write the last closed perf session as a Chrome Trace JSON file (ui.perfetto.dev, chrome://tracing) and print its path. | connected | ext.tapir.perf_trace |
| [`tapir:perf_campaign`](tapir-perf-campaign.md) | Run every scenario of a perf campaign on one platform, each from a cold start (hooks, Android preparation, after_start, tapir:perf_run, retries), and summarise which passed. | none | none (starts the app through dowel) |

<a name="boot-mode-and-deep-dives"></a>
## Boot mode and deep-dives

`tapir:install`, `tapir:doctor`, `tapir:perf_compare`, `tapir:perf_campaign`, `tapir:device` and `tapir:resize` run with `CommandBoot.none` (the last two dial Chrome DevTools Protocol directly rather than the VM Service). Every other command is `CommandBoot.connected`: it dials the VM Service URI recorded for the project's dowel session and fails fast when the running app cannot be reached.

These commands earn their own pages: [tapir:install](tapir-install.md), [tapir:run](tapir-run.md), [tapir:snap](tapir-snap.md), [tapir:tap](tapir-tap.md), [tapir:fill](tapir-fill.md), [tapir:reset_overlays](tapir-reset-overlays.md), [tapir:screenshot](tapir-screenshot.md), [tapir:find](tapir-find.md), [tapir:doctor](tapir-doctor.md), [tapir:observe](tapir-observe.md), [tapir:perf_begin](tapir-perf-begin.md), [tapir:perf_end](tapir-perf-end.md), [tapir:perf_insight](tapir-perf-insight.md), [tapir:perf_run](tapir-perf-run.md), [tapir:perf_compare](tapir-perf-compare.md), [tapir:perf_trace](tapir-perf-trace.md), [tapir:perf_campaign](tapir-perf-campaign.md). Slug rule: the URL replaces the `:` separator with `-`. The other commands share this index page; reach for `dart run dowel help <name>` for their full flag surface.

<a name="related-documentation"></a>
## Related Documentation

- [Installation](../getting-started/installation.md): add `tapir` to an app and wire `TapirPlugin.install()`.
- [Quickstart](../getting-started/quickstart.md): a first snap, tap and screenshot.
- [MCP tool reference](../mcp/tool-reference.md): the same verbs as `tapir_*` tools, with their schemas.
- [Reference: Actionability gate](../reference/actionability-gate.md): the checks every gesture command runs first.
