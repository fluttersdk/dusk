# Commands

Catalog of every user-facing command shipped by `fluttersdk_dusk`. Thirty-four commands, grouped by intent.

Every command is invoked as `dart run fluttersdk_dusk <name>` (Flutter-free wrapper at `bin/fluttersdk_dusk.dart`), or via the consumer-side artisan dispatcher (`./bin/fsa <name>` / `dart run artisan <name>`) once the project has run `dusk:install`. Commands are auto-discovered through `DuskArtisanProvider`; nothing wires by hand.

Need a quick reminder of what a command does without leaving the terminal? Run `dart run artisan list` for the full registry grouped by namespace, or `dart run artisan help <name>` for the per-command flag surface. This page exists for the deeper view: the boot mode, the backing VM Service extension, and the grouping rationale.

## Table of contents

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

## How to read this page

Each group section ships a single table with four columns:

- **Command** is the canonical name you type after `dart run fluttersdk_dusk` (or via the artisan dispatcher).
- **Description** is the one-line summary returned by the command's `description` getter; the same string surfaces in `dart run artisan list`.
- **Boot Mode** is the `CommandBoot` value the dispatcher reads before invoking `handle()`. `none` means pure CLI: no VM Service connection. `connected` means the command dials `~/.artisan/state.json` and fails fast if no app is running.
- **VM Extension** is the `ext.dusk.*` method the command calls over the VM Service. `none` for commands that operate purely on the consumer filesystem.

Deep-dive pages exist for the seven commands whose flag surface, return shape, or composition rules outgrow a single table row. The remaining twenty-five commands share this index page; reach for `dart run artisan help <name>` for their full flag surface.

## Snapshot and screenshot

The two foundational read commands. `dusk:snap` walks the Semantics tree and emits YAML with `[ref=eN]` tokens that every subsequent action command consumes. `dusk:screenshot` captures the rendered pixel buffer over Chrome DevTools Protocol (web) or `RepaintBoundary.toImage` (desktop, mobile).

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| [`dusk:snap`](dusk-snap.md) | Capture Semantics tree YAML of the running Flutter app with [ref=eN] tokens. | connected | ext.dusk.snap |
| [`dusk:screenshot`](dusk-screenshot.md) | Capture a screenshot of the running Flutter app to a file. | connected | ext.dusk.screenshot |

## Gestures

Pointer-driven actions that synthesise touch, mouse, or pen events at a widget located by ref token. All four route through the actionability gate (enabled, zero-rect, off-viewport) before the event leaves the VM.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| [`dusk:tap`](dusk-tap.md) | Tap a widget by ref token (from prior dusk:snap). | connected | ext.dusk.tap |
| `dusk:hover` | Hover the pointer over a widget by ref token (from prior dusk:snap). | connected | ext.dusk.hover |
| `dusk:drag` | Drag from one widget to another using ref tokens from a prior dusk:snap. | connected | ext.dusk.drag |
| `dusk:scroll` | Scroll inside a scrollable widget by ref token from a prior dusk:snap. | connected | ext.dusk.scroll |

## Inputs

Keyboard-shaped actions. `dusk:type` emits a character sequence; `dusk:press_key` synthesises a single hardware-key event; `dusk:clear` empties the focused text field; `dusk:select_option` drives `DropdownButton` / `PopupMenuButton`; `dusk:set_checkbox` drives `Checkbox` / `Switch`.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| `dusk:type` | Type text into a focused widget by ref token. | connected | ext.dusk.type |
| [`dusk:fill`](dusk-fill.md) | Focus, clear, type, and settle a text field by ref in one call (retries once on a stale handle). | connected | ext.dusk.fill |
| `dusk:press_key` | Synthesise a hardware-key event on the currently focused widget. | connected | ext.dusk.press_key |
| `dusk:clear` | Empty the text content of the focused widget by ref. | connected | ext.dusk.clear |
| `dusk:select_option` | Select an option in a DropdownButton or PopupMenuButton by ref token. | connected | ext.dusk.select_option |
| `dusk:set_checkbox` | Set the checked state of a Checkbox or Switch widget by ref. | connected | ext.dusk.set_checkbox |
| `dusk:wait` | Wait for a text, text-gone, or expression condition in the running app. | connected | ext.dusk.wait_for |
| `dusk:wait_for_network_idle` | Wait until the running app reports zero in-flight HTTP requests for a contiguous idleMs window. | connected | ext.dusk.wait_for_network_idle |

## Navigation

Route-table manipulation against the active `Navigator`. `dusk:modal` dismisses any open modal, sheet, or dialog. `dusk:close_app` ends the session via `SystemNavigator.pop()`.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| `dusk:navigate` | Navigate the running app to a named route via the active Navigator. | connected | ext.dusk.navigate |
| `dusk:navigate_back` | Pop the topmost route off the active Navigator (mirrors browser back). | connected | ext.dusk.navigate_back |
| `dusk:get_routes` | Print the active Navigator's route table + current location as JSON. | connected | ext.dusk.get_routes |
| `dusk:modal` | Dismiss all open modals, bottom sheets, and dialogs in the running app. | connected | ext.dusk.dismiss_modals |
| [`dusk:reset_overlays`](dusk-reset-overlays.md) | Reset to a clean screen: dismiss modals + Escape + Cancel-tap fallback (idempotent). | connected | ext.dusk.reset_overlays |
| `dusk:close_app` | Gracefully close the running app via SystemNavigator.pop(). | connected | ext.dusk.close_app |

## Find

The Playwright Locator surface: mint a re-resolvable `q<N>` handle backed by text, semanticsLabel, or key predicates. Every action call against a `q<N>` handle re-walks the live tree, so the handle survives intermediate rebuilds.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| [`dusk:find`](dusk-find.md) | Mint a re-resolvable q-handle by text / semanticsLabel / key (Playwright Locator pattern). | connected | ext.dusk.find |

## Diagnostics

Pure-CLI checks that verify the consumer wiring and the running session health. Neither command dials the VM Service.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| [`dusk:doctor`](dusk-doctor.md) | Verify dusk plugin runtime + consumer wiring health | none | none |

## Install

The one-shot bootstrap. Injects three lines into the consumer's `lib/main.dart` and is otherwise idempotent. No `bin/artisan.dart` scaffold; `fluttersdk_dusk` ships its own Flutter-free CLI entry point.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| [`dusk:install`](dusk-install.md) | Wire DuskPlugin.install() into lib/main.dart AND chain artisan install + plugin:install so ./bin/fsa surfaces all 34 dusk:* commands (idempotent on re-run; Phase 2 chain is best-effort). | none | none |

## CDP

Chrome DevTools Protocol commands that manipulate the browser viewport directly. Web target only; desktop and mobile no-op gracefully.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| `dusk:device` | Emulate a device profile (viewport + DPR + touch + user agent) via Chrome DevTools Protocol. | connected | none (CDP direct) |
| `dusk:resize` | Resize the running Flutter web app viewport via Chrome DevTools Protocol. | connected | none (CDP direct) |

## Click variants

Pointer gestures that go beyond the primary tap. All four route through the actionability gate.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| `dusk:dblclick` | Fire a double-click at the widget identified by a snapshot ref. | connected | ext.dusk.tap |
| `dusk:triple_click` | Fire three primary clicks (~100ms apart) at the widget identified by --ref. | connected | ext.dusk.tap |
| `dusk:right_click` | Fire a right (secondary mouse button) click at the widget identified by --ref. | connected | ext.dusk.tap |

## Focus and blur

Keyboard-focus shaping. `dusk:focus` requests focus on a ref; `dusk:blur` releases the currently focused widget.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| `dusk:focus` | Request keyboard focus on the widget identified by --ref. | connected | ext.dusk.focus |
| `dusk:blur` | Remove keyboard focus from the currently-focused widget. | connected | ext.dusk.blur |

## Console and exceptions

Diagnostics readers backed by dusk's own in-package capture plus an optional telescope augmentation.

`dusk:console` reads from dusk's in-package `debugPrint` ring buffer (populated by `installLogCapture()`,
wired by `DuskPlugin.install()`). This buffer captures every call that routes through the `debugPrint` global
callback (`debugPrint(...)`, `print(...)`, and any Flutter framework path that calls `debugPrint`). It does NOT
capture direct `dart:developer` `log()` calls that bypass `debugPrint`; those require `fluttersdk_telescope`'s
`LogWatcher`. When telescope is wired the two sources are merged and deduped; telescope also adds `package:logging`
(`Logger.root.onRecord`) and any other watcher it ships.

`dusk:exceptions` is similar: dusk's own `FlutterError.onError` capture (non-fatal errors including overflow)
is always present; telescope augments when wired.

The `--since=<iso8601>` flag on `dusk:exceptions` (and the matching `since` param on `dusk_exceptions` MCP)
lets agents compute true before/after deltas: record the time before an action, then call
`dusk:exceptions --since=<time>` afterwards to see only exceptions raised by that action.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| `dusk:console` | Read recent log entries (in-package debugPrint capture; augmented by telescope when wired). | connected | ext.dusk.console |
| `dusk:exceptions [--limit=<n>] [--since=<iso8601>]` | Read recent exception entries (in-package FlutterError capture + telescope when wired). Optionally filter to entries strictly after `--since`. | connected | ext.dusk.exceptions |

## Observe

The Stagehand observe-once-act-many surface. Returns a structured candidate list of every interactive widget on screen; the agent decides which refs to act on. No server-side LLM.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| [`dusk:observe`](dusk-observe.md) | Return a structured candidate list of every interactive widget on screen (Stagehand observe-once-act-many; no server-side LLM). | connected | ext.dusk.observe |

## Hot reload and snap

The single-round-trip composite that hot-reloads the running app and then captures snapshot, screenshot, and recent exceptions in one shot. Dispatched via the `artisan:` substrate routing prefix to avoid a same-isolate deadlock.

| Command | Description | Boot Mode | VM Extension |
|---------|-------------|-----------|--------------|
| `dusk:hot_reload_and_snap` | Hot reload the running app, then capture snapshot + screenshot + recent exceptions in a single round-trip. | connected | artisan:reload + ext.dusk.snap |

## Boot mode and deep-dives

Two of thirty-two commands run with `CommandBoot.none` (`dusk:install`, `dusk:doctor`). Every other command is `CommandBoot.connected`: it dials the VM Service URI in `~/.artisan/state.json` and fails fast when the running app cannot be reached.

Nine commands earn their own pages: [dusk:install](dusk-install.md), [dusk:snap](dusk-snap.md), [dusk:tap](dusk-tap.md), [dusk:fill](dusk-fill.md), [dusk:reset_overlays](dusk-reset-overlays.md), [dusk:screenshot](dusk-screenshot.md), [dusk:find](dusk-find.md), [dusk:doctor](dusk-doctor.md), [dusk:observe](dusk-observe.md). Slug rule: the URL replaces the `:` separator with `-`. The remaining twenty-five commands share this index page; reach for `dart run artisan help <name>` for their full flag surface.
