# Tapir MCP Tool Reference

Per-tool input schema, return shape, and example payload for every `tapir_*` MCP tool
contributed by `TapirDowelProvider`. 40 tools total: 33 dispatch through `ext.tapir.*` VM
Service extensions and 7 (`tapir_hot_reload_and_snap`, `tapir_resize_viewport`,
`tapir_device_profile`, `tapir_perf_run`, `tapir_perf_compare`, `tapir_perf_trace`, `tapir_run`)
route through the `dowel:tapir:*` substrate path to a CLI command because the orchestration
cannot run inside the target isolate.

Sections are ordered alphabetically. Every section names the dispatch surface
(`extensionMethod`) at the top so the consumer knows which path the server takes. All
example payloads show the `params.arguments` object inside the `tools/call` JSON-RPC
request; the substrate MCP server wraps the response as `CallToolResult` text content.

## Universal response fields: `framesForced`, `warnings`, `reresolved`

A hidden or minimised desktop window and a backgrounded browser tab stop the app producing
frames, and a snapshot then reads as empty while an action reports a success that could not
have landed. Tapir wakes a hidden or paused app at the entry of every `ext.tapir.*` verb
except the perf verbs, `boot_id`, `close_app`, `console`, `exceptions`, `semantics_hold`
and `evaluate`, and a response that had to wake it carries `"framesForced": true`. The app's
lifecycle observers see `resumed` while that happens;
`--dart-define=TAPIR_FORCE_FRAMES=false` turns it off. A browser tab is the exception: Chrome
withholds animation frames from a hidden tab, so tapir does not attempt the wake on web and
the `warnings` block stays. The CLI (not the MCP tool) covers that case itself when the
session has a `cdpPort`: see [Frame production](../reference/frame-production.md).

When tapir could not force frames (the opt-out, a `detached` lifecycle, or a wake that produced
no frame) the success payload
gains a `warnings` block instead:

```json
{
  "warnings": {
    "framesEnabled": false,
    "lifecycleState": "hidden",
    "platform": "web",
    "hint": "... Bring the page to front (CDP Page.bringToFront) and retry ..."
  }
}
```

`platform` is `web` or the desktop `TargetPlatform` name, and `hint` names the usual cause
for it: a backgrounded browser tab on web, a hidden, minimised or occluded window or an
asleep display on desktop. The block is omitted entirely on a healthy engine, so its
presence is the signal. See [Frame production](../reference/frame-production.md) for the
full picture and the fallback.

A call that relocated a stale `e<N>` ref to the control that replaced it adds
`"reresolved": ["e5"]`. See [`tapir_tap`](#tapir_tap).

## Universal response field: `effect`

Every side-effect verb reports what the widget HOLDS afterwards, not what it was asked to
do. A tapir action confirms that it DISPATCHED; the `effect` block is what confirms the
widget received.

| Verb | `kind` | Fields |
|---|---|---|
| `tapir_tap` | `treeChanged` | `changed` |
| `tapir_type`, `tapir_clear`, `tapir_fill` | `text` | `verified`, `value` (read back off the live controller after the settle), `target` (`matchKind`, `label`, `rect`: which field was written) |
| `tapir_scroll` | `scrollOffset` | `changed`, `before`, `after` |
| `tapir_set_checkbox` | `checked` | `verified`, `before`, `after` |

```json
{ "ref": "e5", "effect": { "kind": "text", "verified": false, "value": "" } }
```

That example is the real case it exists for: a fill against a number field reported the
text it had been handed while the widget kept nothing, and the resulting defect-shaped
story survived two rewrites of the widget before anyone read the field back.

## Table of contents

- [`tapir_blur`](#tapir_blur)
- [`tapir_clear`](#tapir_clear)
- [`tapir_close_app`](#tapir_close_app)
- [`tapir_console`](#tapir_console)
- [`tapir_dblclick`](#tapir_dblclick)
- [`tapir_device_profile`](#tapir_device_profile)
- [`tapir_dismiss_modals`](#tapir_dismiss_modals)
- [`tapir_drag`](#tapir_drag)
- [`tapir_evaluate`](#tapir_evaluate)
- [`tapir_exceptions`](#tapir_exceptions)
- [`tapir_fill`](#tapir_fill)
- [`tapir_find`](#tapir_find)
- [`tapir_focus`](#tapir_focus)
- [`tapir_get_routes`](#tapir_get_routes)
- [`tapir_hot_reload_and_snap`](#tapir_hot_reload_and_snap)
- [`tapir_hover`](#tapir_hover)
- [`tapir_navigate`](#tapir_navigate)
- [`tapir_navigate_back`](#tapir_navigate_back)
- [`tapir_observe`](#tapir_observe)
- [`tapir_perf_begin`](#tapir_perf_begin)
- [`tapir_perf_end`](#tapir_perf_end)
- [`tapir_perf_compare`](#tapir_perf_compare)
- [`tapir_perf_insight`](#tapir_perf_insight)
- [`tapir_perf_run`](#tapir_perf_run)
- [`tapir_perf_trace`](#tapir_perf_trace)
- [`tapir_press_key`](#tapir_press_key)
- [`tapir_reset_overlays`](#tapir_reset_overlays)
- [`tapir_resize_viewport`](#tapir_resize_viewport)
- [`tapir_right_click`](#tapir_right_click)
- [`tapir_run`](#tapir_run)
- [`tapir_screenshot`](#tapir_screenshot)
- [`tapir_scroll`](#tapir_scroll)
- [`tapir_select_option`](#tapir_select_option)
- [`tapir_set_checkbox`](#tapir_set_checkbox)
- [`tapir_snap`](#tapir_snap)
- [`tapir_tap`](#tapir_tap)
- [`tapir_triple_click`](#tapir_triple_click)
- [`tapir_type`](#tapir_type)
- [`tapir_wait_for`](#tapir_wait_for)
- [`tapir_wait_for_network_idle`](#tapir_wait_for_network_idle)

---

## tapir_blur

Dispatch: `ext.tapir.blur`

Clear keyboard focus from whatever currently holds it (Playwright
`locator.blur()` / `document.activeElement.blur()` parity).

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `includeSnapshot` | boolean | no | Embed the post-blur snapshot in the response. Default `false`. |

### Returns

Success: `{ blurred: true, hadFocus: bool }`. `hadFocus` is `false` when no node held focus
at call time (still treated as success, idempotent).

Error: returned via MCP `isError: true` when the focus-tree walk fails internally.

### Example call

```json
{ "name": "tapir_blur", "arguments": { "includeSnapshot": false } }
```

Response:

```json
{ "blurred": true, "hadFocus": true }
```

---

## tapir_clear

Dispatch: `ext.tapir.clear`

Empty the `TextEditingController` backing the resolved text field (Playwright
`locator.clear()` parity).

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ref` | string | yes | Widget ref of a `TextField` / `TextFormField` / `EditableText` (e.g. `"e5"`). |
| `includeSnapshot` | boolean | no | Embed the post-clear snapshot. Default `false`. |

### Returns

Success: `{ ref: "e<N>", text: "" }`.

Error: `TapirActionabilityException` (when the gate fails) or `TapirStaleHandleException`
(when the ref is unknown / stale) surfaced as the wire error string `"Widget ref=<ref> is
not actionable: <reason>"`.

### Example call

```json
{ "name": "tapir_clear", "arguments": { "ref": "e5" } }
```

Response:

```json
{ "ref": "e5", "text": "" }
```

---

## tapir_close_app

Dispatch: `ext.tapir.close_app`

Request a graceful shutdown of the running Flutter app via `SystemNavigator.pop()`. On
mobile + desktop this terminates the app; on web the call is a no-op (browsers do not
allow programmatic tab close).

### Input schema

No parameters.

### Returns

Success: an empty object `{}`. After the call the VM Service URI is gone, so the next
`tapir_*` tool returns a VM-Service-unreachable error.

### Example call

```json
{ "name": "tapir_close_app", "arguments": {} }
```

---

## tapir_console

Dispatch: `ext.tapir.console`

Read recent log entries from the running app's crumbs store. Missing-crumbs graceful:
returns an empty list when the host has not set crumbs up.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `limit` | integer | no | Maximum number of entries to return. Default `50`. |
| `minLevel` | string | no | Minimum severity level (`INFO`, `WARNING`, `ERROR`). Omit for all levels. |

### Returns

Success: `{ entries: [ { level, message, time, logger }, ... ] }`.

Error: never; missing crumbs is treated as the empty-entries success path.

### Example call

```json
{ "name": "tapir_console", "arguments": { "limit": 10, "minLevel": "ERROR" } }
```

---

## tapir_dblclick

Dispatch: `ext.tapir.dblclick`

Double-click a widget by ref. Synthesizes two pointer Down+50ms+Up sequences at the
widget's center with ~100ms between them (Playwright double-click model). Triggers
`GestureDetector.onDoubleTap`.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ref` | string | yes | Widget ref from a prior `tapir_snap`. Shape `e<N>` or `q<N>`. |
| `snapshot` | string | no | `full`, `diff` or `none`. Overrides `includeSnapshot`. |
| `includeSnapshot` | boolean | no | Embed post-action snapshot. Default `true`. |
| `checkStable` | boolean | no | Run the Stable actionability gate. Default `true`. |
| `checkReceivesEvents` | boolean | no | Run the Receives-Events actionability gate. Default `true`. |

### Returns

Success: `{ ref: "e<N>" }`. The actionability gate runs once before the first tap; the
post-action snapshot is captured after the second tap completes.

Error: `"Widget ref=<ref> is not actionable: <reason>"` (gate failure) or stale-handle
error when the ref is unknown.

### Example call

```json
{ "name": "tapir_dblclick", "arguments": { "ref": "e7" } }
```

---

## tapir_device_profile

Dispatch: `dowel:tapir:device`

Emulate a named device profile (viewport + DPR + touch + user agent) via Chrome DevTools
Protocol. Requires the substrate to have been started with `--cdp-port`. The emulated
viewport, DPR, touch and user agent last only as long as the CDP session the call opens,
which closes when it returns; only the Chrome window size it sets stays. For a viewport
that lasts, run the CLI `tapir:resize --hold` in the background.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `preset` | string | no | One of `iphone-x`, `iphone-13`, `iphone-15-pro`, `pixel-5`, `pixel-8`, `ipad-pro-12.9`, `desktop-1440`, `desktop-1920`. Omit when using `list` or `reset`. |
| `list` | boolean | no | List all available presets. When `true`, `preset` + `reset` are ignored. Default `false`. |
| `reset` | boolean | no | Clear all viewport overrides (metrics + touch + user agent). Default `false`. |

### Returns

Success (`preset`): `{ applied: "<preset-name>", viewport: { width, height, dpr, mobile,
touch } }`. Success (`list`): `{ presets: [ { name, width, height, dpr, mobile }, ... ] }`.
Success (`reset`): `{ reset: true }`.

Error: unknown preset name (the response suggests running with `list: true`); `cdpPort`
not configured.

### Example call

```json
{ "name": "tapir_device_profile", "arguments": { "preset": "iphone-x" } }
```

---

## tapir_dismiss_modals

Dispatch: `ext.tapir.dismiss_modals`

Pop every modal route (dialog, bottom sheet, popup) currently above the first persistent
route. Idempotent.

### Input schema

No parameters.

### Returns

Success: `{ popped: <int> }`: the number of modals that were popped. `0` when no modals
were open.

Error: never; safe to call speculatively.

### Example call

```json
{ "name": "tapir_dismiss_modals", "arguments": {} }
```

---

## tapir_drag

Dispatch: `ext.tapir.drag`

Drag from one widget to another by ref tokens. Synthesizes pointer Down + 5x intermediate
Move events + Up sequence from `startRef`'s center to `endRef`'s center.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `startRef` | string | yes | Source widget ref (`e<N>`). |
| `endRef` | string | yes | Target widget ref (`e<N>`). |
| `snapshot` | string | no | `full`, `diff` or `none`. Overrides `includeSnapshot`. |
| `includeSnapshot` | boolean | no | Embed post-action snapshot. Default `true`. |
| `checkStable` | boolean | no | Run the Stable actionability gate. Default `true`. |
| `checkReceivesEvents` | boolean | no | Run the Receives-Events actionability gate. Default `true`. |

### Returns

Success: `{ startRef, endRef }`. Both refs are echoed for caller bookkeeping.

Error: actionability gate failure on either ref, or stale-handle on either.

### Example call

```json
{ "name": "tapir_drag", "arguments": { "startRef": "e12", "endRef": "e18" } }
```

---

## tapir_evaluate

Dispatch: `ext.tapir.evaluate`

Evaluate a Dart expression in the running app isolate via the Tinker bridge
(`ext.tinker.evaluate`). MCP-only: `magic_tinker` owns the connected REPL surface.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `expression` | string | yes | Single Dart expression. No statements, no trailing semicolon. |

### Returns

Success: `{ result: "<stringified expression value>" }`.

Error: returns an MCP error when the Tinker plugin is not installed; never crashes the
app.

### Example call

```json
{ "name": "tapir_evaluate", "arguments": { "expression": "Auth.user?.email" } }
```

Response:

```json
{ "result": "user@example.com" }
```

---

## tapir_exceptions

Dispatch: `ext.tapir.exceptions`

Read recent exceptions recorded by the running app, including non-fatal `FlutterError`s.
Returns the merged union of two sources: the in-package non-fatal `FlutterError.onError`
capture buffer (installed by `TapirPlugin.install()`) and the crumbs exception watcher
(when `crumbs` is present). Entries are deduped by
`(type, message, stackHead)`, sorted newest-first, and clipped to `limit`. RenderFlex
overflow errors appear with `type: "overflow"`. Missing-crumbs graceful: the in-package
buffer ensures non-fatal errors are visible even without crumbs.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `limit` | integer | no | Maximum number of entries to return. Default `20`. |
| `since` | string | no | ISO8601 timestamp. When set, only exceptions whose `time` is strictly after this value are returned. Omit to return the full cumulative list. Unparseable values are silently ignored. |

### Returns

Success: `{ exceptions: [ { type, message, stackHead, library, fatal, time }, ... ],
count: <int> }`. `stackHead` is the first 3 lines of the stack trace. `fatal` is always
`false` for in-package captured entries.

### Example call

```json
{ "name": "tapir_exceptions", "arguments": { "limit": 5, "since": "2024-01-01T10:00:00.000Z" } }
```

---

## tapir_fill

Dispatch: `ext.tapir.fill`

Fill a text field by ref in one call: focus, clear, type, settle. Composes the gated
`ext.tapir.focus`, `ext.tapir.clear`, and `ext.tapir.type` handlers (so the actionability
gate, IME focus, and `onChanged`/validator firing all run) and retries the whole sequence
once when the ref goes stale mid-fill. Replaces the manual focus + clear + type dance.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ref` | string | yes | Text-field ref token (`e<N>` or `q<N>`) from a prior `tapir_snap` / `tapir_find`. |
| `text` | string | yes | Value to set. Replaces existing content. Pass `""` to clear. |
| `includeSnapshot` | boolean | no | Embed the post-fill snapshot (default `true`). |
| `checkStable` | boolean | no | Run the Stable actionability gate. Default `true`. |
| `checkReceivesEvents` | boolean | no | Run the Receives-Events actionability gate. Default `true`. |
| `snapshot` | string | no | `full`, `diff` or `none`. Overrides `includeSnapshot`. `diff` returns only the snapshot lines the fill changed since your last unfiltered snapshot (see [`tapir_tap`](#tapir_tap)). |

### Returns

Success: `{ ref, text, filled: true, effect }` plus an optional `snapshot` (YAML). The
`effect` block is `{kind: "text", verified, value, target}`: `value` is read after the
two-frame settle, so a formatter or echo that reverts the write reports `verified: false`,
and `target` is `{matchKind: "overlap"|"nearest"|"element", label, rect}`, which field was
written. A label or static-text handle keeps the `nearest` fallback; read `target` when
`matchKind` is `nearest`. A ref whose node is an interactive non-text control (button,
checkbox, radio, switch, slider, link) is refused with `ref eN is a <role>, not a text
field`. On a permanently stale handle (after the single retry) the response is a typed
`stale` error envelope.

### Example call

```json
{ "name": "tapir_fill", "arguments": { "ref": "e7", "text": "alice@example.com" } }
```

---

## tapir_find

Dispatch: `ext.tapir.find`

Find a widget by semantic query (text / semanticsLabel / key) and return a re-resolvable
`q<N>` handle. Unlike snapshot-frozen `e<N>` refs, `q<N>` re-executes the tree walk on
every subsequent action call, so the handle survives widget rebuilds as long as the
predicates still match.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `text` | string | no | Exact match against accessibility label first, then `Text.data`. |
| `contains` | string | no | Substring match against accessibility label first, then `Text.data` (case-sensitive). Use when the visible label is dynamic (counters, timestamps, plurals). |
| `semanticsLabel` | string | no | Exact match against `SemanticsNode.label` only (no Text fallback). |
| `key` | string | no | Match against a widget `Key`. For `ValueKey`, pass the inner value's `toString()`. |
| `within` | string | no | Evaluate the predicates inside one subtree: the `e<N>` ref of the region to search. The scope becomes part of the minted `q<N>` handle, so it survives every re-resolve; once the scope stops resolving the handle reports `matched: false` with a diagnostic naming it. |

At least one of the four must be supplied. When multiple are passed they form an
intersection.

### Returns

Success on first match: `{ ref: "q<N>", matched: true }`. No match: `{ ref: null, matched:
false }`.

Error: surfaced only when a follow-up action call finds zero live matches against the
handle (`"stale handle"`); the agent must re-find or re-snap, never silently retry.

### Example call

```json
{ "name": "tapir_find", "arguments": { "text": "Submit" } }
```

---

## tapir_focus

Dispatch: `ext.tapir.focus`

Request keyboard focus on the widget identified by `ref` (Playwright `locator.focus()`
parity). Walks to the nearest `Focus` ancestor and calls `requestFocus()`.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ref` | string | yes | Widget ref (e.g. `"e5"`). |
| `includeSnapshot` | boolean | no | Embed the post-focus snapshot. Default `false`. |

### Returns

Success: `{ ref: "<ref>", focused: true }`.

### Example call

```json
{ "name": "tapir_focus", "arguments": { "ref": "e5" } }
```

---

## tapir_get_routes

Dispatch: `ext.tapir.get_routes`

Report where the running app is: the mounted Router's location, the top page's name and a
title hint. Read it to confirm a `tapir_navigate` landed or to see where a redirect took the
app; it does not list the declared routes.

### Input schema

No parameters.

### Returns

Success: `{ location, title, uri }`.

| Field | Meaning |
|---|---|
| `uri` | The first mounted `Router`'s location, the value `tapir_navigate` verifies against. `null` while no Router is mounted, as on a loading screen right after a restart. |
| `location` | The root Navigator's top page name. A Router-based app (go_router, MagicRouter) names no page, so it reads `""` on every screen there; read `uri`. |
| `title` | A location hint from the platform's default route name; `""` when there is none. |

### Example call

```json
{ "name": "tapir_get_routes", "arguments": {} }
```

Response:

```json
{ "location": "", "title": "", "uri": "/monitors?page=2" }
```

---

## tapir_hot_reload_and_snap

Dispatch: `dowel:tapir:hot_reload_and_snap`

Hot reload the running Flutter app, then capture a snapshot, screenshot, and recent
exceptions in one round-trip. Routes through the CLI command because an in-isolate handler
cannot reload itself.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `screenshot` | boolean | no | Capture a screenshot after the reload. Default `true`. |

### Returns

Success: `{ reloaded: true, durationMs: <int>, snapshot: "<yaml>", screenshot: "<base64
or screenshotError>", recentExceptions: [...] }`.

Compile error: `{ reloaded: false, durationMs: <int>, error: "<compile message>",
recentExceptions: [...] }`. `snapshot` + `screenshot` are omitted on compile error, and the
call is returned as an error result, so a client never reads a compile failure as success.

### Example call

```json
{ "name": "tapir_hot_reload_and_snap", "arguments": { "screenshot": false } }
```

---

## tapir_hover

Dispatch: `ext.tapir.hover`

Hover a mouse cursor over a widget by ref. Mouse-only (no touch equivalent). Synthesizes a
`PointerHoverEvent` of `PointerDeviceKind.mouse` at the widget's center.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ref` | string | yes | Widget ref (`e<N>`). |
| `snapshot` | string | no | `full`, `diff` or `none`. Overrides `includeSnapshot`. |
| `includeSnapshot` | boolean | no | Embed post-action snapshot. Default `true`. |
| `checkStable` | boolean | no | Run the Stable actionability gate. Default `true`. |
| `checkReceivesEvents` | boolean | no | Run the Receives-Events actionability gate. Default `true`. |

### Returns

Success: `{ ref: "<ref>" }`. No-op on touch-only devices.

Error: actionability gate failure, or stale-handle.

### Example call

```json
{ "name": "tapir_hover", "arguments": { "ref": "e8" } }
```

---

## tapir_navigate

Dispatch: `ext.tapir.navigate`

Navigate the running Flutter app to a route path. Resolves through `MagicRoute.to(...)`
when Magic is installed, falling back to `Navigator.of(root).pushNamed(...)`.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `route` | string | yes | Route path. Must start with `/`. Example: `/monitors/123`. |
| `includeSnapshot` | boolean | no | Embed the post-navigation snapshot. Default `true`. |
| `snapshot` | string | no | `full`, `diff` or `none`. Overrides `includeSnapshot`. After a navigation `diff` mostly shows a whole new screen; it pays off when the route only changes a part of it. |

### Returns

Success: `{ navigated, route: "<path>", exactPath, reason?, snapshot?, snapshotMode? }`. `navigated` is
read off the first mounted Router two frames after the dispatch: `true` when its path is
the route's or a page under it (a navigate to `/monitors` that shows `/monitors/7`, a
default child), `false` with a `reason` when the router dropped or redirected it.
`exactPath` is `true` only when the path is the route's own, query aside, and `false`
beside `navigated: false`; branch on it when the named screen itself matters. ALWAYS
re-snap after; refs from a prior snapshot are invalidated.

### Example call

```json
{ "name": "tapir_navigate", "arguments": { "route": "/login" } }
```

---

## tapir_navigate_back

Dispatch: `ext.tapir.navigate_back`

Pop the top route off the active navigator stack. Equivalent to pressing the system Back
button. No-op when no Navigator has a page to leave.

The Navigator popped is the outermost one that can pop. A page pushed on the root Navigator
covers whatever a shell shows, so it is left first; a page stacked inside a shell (a
go_router `ShellRoute` builds its own nested Navigator, and MagicRouter's `.stacked()` pushes
onto it) is left once the root has nothing to pop. The root Navigator of such an app holds
the shell alone, so popping it would do nothing. A Navigator the user cannot see is skipped:
a go_router `StatefulShellRoute` keeps every branch alive and hides the inactive ones under
`Offstage` and a disabled `TickerMode`, so a page stacked on a hidden branch is never the one
left (a subtree under `Offstage(offstage: true)`, `TickerMode(enabled: false)` or
`Visibility(visible: false)` is not walked).

### Input schema

| Parameter | Type | Default | Meaning |
|---|---|---|---|
| `includeSnapshot` | boolean | `true` | Embed the post-pop snapshot in the response. |
| `snapshot` | string | (none) | `full`, `diff` or `none`. Overrides `includeSnapshot`. |

### Returns

Success: `{ navigatedBack, popped, snapshot? }`. `navigatedBack` equals `popped`. `popped`
is `false` when no Navigator had a page to leave (the bottom of every stack, the root route),
so the call did nothing; read
`tapir_get_routes` `uri`, or the snapshot, to see where the app is.

### Example call

```json
{ "name": "tapir_navigate_back", "arguments": {} }
```

---

## tapir_observe

Dispatch: `ext.tapir.observe`

Return a structured candidate list of every interactive widget on screen. Implements
Stagehand's observe-once-act-many pattern (no server-side LLM). Each candidate carries a
re-resolvable `q<N>` ref, and candidates sharing one label stay distinct: the handle carries
its position among the nodes that label matched, so a list of rows offering the same action
is safe to work row by row. A control wrapped in `MergeSemantics` is listed once, as its
boundary node; the descendants it absorbs get no candidate.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `intent` | string | no | Free-form caller hint (e.g. `"login form"`). Echoed in audit logs, NOT used server-side. |
| `roles` | string | no | Comma-separated role filter (`button,textbox,link,checkbox,heading,image`). Omit for every role. |
| `limit` | integer | no | Maximum number of candidates. Default `50`. |
| `includeEnrichers` | string | no | `"true"` (default subset), `"false"` (none), or `"full"` (every field). |

### Returns

Success: `{ candidates: [ { ref, role, label, value, bounds, isEnabled, isVisible,
inViewport, occluded, enrichers: { ... } }, ... ] }`. `inViewport` is `false` when the
bounds lie outside the view; `occluded` is `true` when a hit test at the bounds' centre
reaches a widget painted above the candidate instead of the candidate itself (`false` for
a candidate that is not visible, since it has no centre worth probing). `isVisible` keeps
its meaning: non-empty bounds that overlap the viewport. A merged candidate whose bounds'
centre is not on its own control also carries `tapOwner: {x, y, w, h}` (the control's rect,
which a `tapir_tap` goes to); every other candidate omits it. The enricher subset projects
`magicFormField`, `magicRoute`, `magicGateResult`, `wind.breakpoint`, `wind.states` by
default.

### Example call

```json
{ "name": "tapir_observe", "arguments": { "intent": "login form", "roles": "textbox,button", "limit": 20 } }
```

---

## tapir_perf_begin

Dispatch: `ext.tapir.perf_begin`

Open a performance measurement session around an interaction you are about to
drive. Zeroes the frame buffer and the wind and magic counters and records the
liveness baseline `tapir_perf_end` judges the run against. In `attribution` mode
it also switches `FlutterTimeline` collection and Flutter's build profiling on;
that instrumentation costs real time, so keep the session tight: begin, drive
one interaction, end.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `mode` | string | no | `attribution` (default): blocks by self time, counts per painted frame, wind and magic counters, insights. `timing`: no profiling flag is touched and the report carries frame timings only. |
| `phases` | boolean | no | Also profile layout and paint, not just builds. Default `false`; the span volume multiplies. Rejected with `mode: "timing"`. |

### Returns

Success: `{ sessionToken: "perf-1", mode: "attribution", phases: bool,
livenessBaseline: <int>, restartedPreviousSession: bool }`.

An unknown `mode`, or `phases` with `timing`, is an `invalidParams` error and
opens nothing. A begin on an already-open session RESTARTS it rather than
failing, restoring the previous session's flags before saving the current ones,
so a `perf_end` that never landed cannot strand the profiling flags on.

Attribution milliseconds are inflated by the profiling. Rank by them; compare
milliseconds only between `timing` sessions.

### Example call

```json
{ "name": "tapir_perf_begin", "arguments": { "mode": "timing" } }
```

---

## tapir_perf_end

Dispatch: `ext.tapir.perf_end`

Close the session and read a bounded report (about 6 KB at most) with ranked
insights. Restores every profiling flag to the value it had BEFORE the session,
not to `false`.

### Input schema

No parameters. Requires a prior `tapir_perf_begin`; without one the call returns
a typed error rather than an empty report.

### Returns

Success: `{ sessionToken, refused: false, mode, env, coverage, summary,
counters, insights, omitted }`. Every duration is in milliseconds; every count
is given raw and per painted frame.

- `env`: `{platform, isWeb, buildMode, renderer, semanticsEnabled, phases}`,
  read in the app. `buildMode` comes from `kProfileMode` / `kDebugMode`;
  `renderer` is `canvaskit` or `skwasm` on web and `unknown` elsewhere unless a
  host assigns `rendererReader`; `semanticsEnabled` is `true` whenever tapir is
  installed, because tapir holds a semantics handle for the whole process.
- `coverage`: `{framesDrawn, framesSummarized, framesOutsideSession, complete,
  missing}`. `framesDrawn` is the liveness counter's advance;
  `framesSummarized` counts the frame records Flutter delivered inside the
  session window, which it batches, so a session can close before the last
  arrive; `framesOutsideSession` counts the delivered records left out because
  they lie outside the window (drawn before `perf_begin`, or the flush frame). `missing` names sources never read: `wind` (no perf
  resolver, so `counters.wind` is `null`, not zeros), `blocks` (profiling was
  on and no frame carried a block map), `blockSelfTime` (blocks without
  `selfMicros`). Read it before the numbers.
- `summary`: `{durationMs, budgetMs: 16.7, frames, blocksBySelf,
  blocksByCount, routeTransitions}`. `frames` is `{count, painted, dropped,
  overBudget, overBudgetBuild, overBudgetRaster, buildMs, rasterMs}`, the last
  two as `{p50, p90, p99, worst}`; `dropped` comes from `frameNumber` gaps and
  `count` is `painted + dropped`. `blocksBySelf` is `[{name, selfMs, frames}]`
  ranked by EXCLUSIVE time (a parent's inclusive time contains its children's,
  so ranking by it blames the parent); `blocksByCount` is `[{name, count,
  perFrame}]`. Both keep the top 10. `timing` mode carries `durationMs`,
  `budgetMs` and `frames` only.
- `counters`: `{columns: ["name", "count", "perFrame"], wind, magic}`, `null`
  in `timing` mode. A scalar counter is `{count, perFrame}` (`cacheSize` is a
  gauge and stays bare); a breakdown (`widgetBuilds`, `controllerNotifies`,
  ...) is its top 3 as positional rows in `columns` order.
- `insights`: at most 6, sorted by severity then `estimatedSavingsMs`, each
  `{id, severity, title, evidence: {metric, value, perFrame, threshold},
  estimatedSavingsMs?, nextStep}`. Ids (`I1`, `I2`, ...) are assigned before
  the sort and the cut. Built-in rules, with the thresholds each states in its
  evidence: `framesOverBudget` (slower thread past 16.7ms; `error` past a 0.1
  share), `framesDropped` (a `frameNumber` step of 2 or more; `error` past a
  0.1 share), `blockSelfMs` (one block owning at least 0.3 of all self time and
  1ms per painted frame; `error` past 8.35ms per frame), `blockCountPerFrame`
  (at least 20 runs per painted frame and 10 times the median block),
  `framesUnreported` / `sourcesMissing` (coverage). The host may add rules
  through `perfInsightContributors`; a contributor that throws becomes a
  `warn` insight named `contributorErrors`.
- `omitted`: how many entries each ranked list cut, keyed by list
  (`blocksBySelf`, `blocksByCount`, `routeTransitions`, `insights`,
  `wind.widgetBuilds`, `magic.controllerNotifies`, ...).

Refusal: `{ sessionToken, refused: true, mode, coverage: {framesDrawn,
livenessBaseline, livenessFinal, complete: false}, reason }`.

Check `refused` FIRST. When the liveness counter advanced by 1 or less, the
engine rendered nothing, the response carries NO metrics at all, and the reason
says so. A zero report would have read as "fast"; that is the reading a live
probe produced three times against a tab that was merely behind another window.
The liveness counter is the authority rather than the `warnings` block on the
same response, because `SchedulerBinding.framesEnabled` was measured reporting
`true` on a hidden page.

### Example call

```json
{ "name": "tapir_perf_end", "arguments": {} }
```

---

## tapir_perf_compare

Dispatch: `dowel:tapir:perf_compare` (runs the CLI command in the MCP server's
process; reads two files, needs no app)

Judge run `b` against run `a`, both `tapir_perf_run` files. Gates on counts per
painted frame, never raw counts; milliseconds only from timing-mode medians;
emulator raster ms are info. A change inside either run's repeat-to-repeat
range is `unchanged`. Thresholds: warn +10%, error +25%, or the scenario's.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `a` | string | yes | Baseline run file. |
| `b` | string | yes | Candidate run file. |
| `json` | boolean | no | Return the JSON result instead of the table. |

### Returns

`{ verdict, thresholds, frames: {painted: {a, b}}, rows: [{metric, a, b,
deltaPct, verdict, severity}], unchanged, timing: {gated, note?} }`. `rows`
lists what changed plus info rows, worst first. The call fails on an
error-level regression, or when a run has no measured repeat.

### Example call

```json
{ "name": "tapir_perf_compare", "arguments": { "a": "build/perf/list-before.json", "b": "build/perf/list-after.json", "json": true } }
```

---

## tapir_perf_insight

Dispatch: `ext.tapir.perf_insight`

Drill into one insight of the report `tapir_perf_end` last returned. Only the
most recent closed session is kept.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `id` | string | yes | Insight id (`I<n>`) from `insights[]`. One counted in `omitted.insights` is drillable too. |
| `token` | string | no | The report's `sessionToken`; a token naming any other session is refused. |

### Returns

Success: `{ sessionToken, id, severity, title, summary, detail,
estimatedSavingsMs, nextStep }`. `detail` holds the rows behind the insight:
`worstFrames` (each `{frameNumber, buildMs, rasterMs, blocks: [{name, selfMs,
count}]}`) for the budget rule, `gaps` (`{after, next, missing}`) for dropped
frames, the block and the frames where it weighed most for the block rules,
and the coverage map for a coverage insight.

Errors, each naming what to read instead: no `id` (`invalidParams`), no closed
session, a stale token, a refused session, and an id the session never issued,
which points at `perf_end`'s `insights[]`.

### Example call

```json
{ "name": "tapir_perf_insight", "arguments": { "id": "I1", "token": "perf-3" } }
```

---

## tapir_perf_run

Dispatch: `dowel:tapir:perf_run` (runs the CLI command in the MCP server's
process: it restarts the app, drives Chrome DevTools and writes files)

Run a scenario YAML several times from a clean start: setup (its hot restart,
or a relaunch on a profile build), `perf_begin`, the steps with targets
resolved on the live screen, `perf_end` with `full=true`. Writes
`<out>/<scenario>-<label>.json`.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `scenario` | string | yes | Scenario YAML path. |
| `variant` | string | no | The `variants` key to run: required when the file declares `variants`, refused when it does not; applies to `against` too. |
| `label` | string | no | `[a-z0-9_-]`, default `run`. |
| `out` | string | no | Output directory, default `build/perf`. |
| `repeat` | integer | no | Repeats per series; overrides the scenario's. |
| `platform` | string | no | `chrome`, `android` or `ios`; read from the session when omitted. |
| `timing` | boolean | no | Interleaved timing-mode repeats, the ms `tapir_perf_compare` gates on. |
| `against` | string | no | Baseline scenario run in the same rounds, one file each. |
| `semantics-pass` | boolean | no | Also measure with the semantics tree released (`semanticsOff`). |
| `json` | boolean | no | Return the run file minus `repeats[]`, plus `path`. |

### Returns

The run file: `scenario`, `label`, `env` (the app's own plus `target`,
`device`, `emulator`, `restartMode`, `host`, `renderer`), `summary`
(`repeats`, `refused`, median `frames`, `perFrame`, `ms`, `spread`, and
`timing` with `--timing`), `insights` of the median repeat, `repeats[]`, and
with the semantics pass `semanticsPass` plus `semanticsOff` or
`semanticsPassReason`. `semanticsPass` is `unsupported` when a release leaves
semantics on, which on chrome is every app tapir has snapshotted (the web
engine keeps semantics on once it has received a tree); the reason names the
platform and what holds it. A refused repeat is recorded and left out of the
medians; the call fails when every repeat refused. See
[tapir:perf_run](../commands/tapir-perf-run.md).

### Example call

```json
{ "name": "tapir_perf_run", "arguments": { "scenario": "tool/perf/scenarios/list.yaml", "variant": "1440", "label": "before", "timing": true, "json": true } }
```

---

## tapir_perf_trace

Dispatch: `dowel:tapir:perf_trace` (runs the CLI command in the MCP server's
process, so the trace goes to a file and only the path comes back)

Write the last closed session's `ext.tapir.perf_trace` export as a Chrome Trace
JSON file. Export before the next `tapir_perf_begin`, which clears the frames
the trace reads.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `out` | string | yes | File to write. |
| `token` | string | no | The session's `sessionToken`; a stale one is refused. |

### Returns

The absolute path of the written file.

### Example call

```json
{ "name": "tapir_perf_trace", "arguments": { "out": "build/perf/list.trace.json" } }
```

---

## tapir_press_key

Dispatch: `ext.tapir.press_key`

Press a hardware key (optionally with modifiers). Delivers `KeyDownEvent` +
`KeyUpEvent` through the binding's `onKeyData`, the path real key data takes, so
`Focus.onKeyEvent`, `Shortcuts` and `CallbackShortcuts` hear the key as they
would a real press. A single letter or digit presses the key that carries
that character; text entry still goes through `tapir_type`.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `key` | string | yes | Logical key label (e.g. `Enter`, `Escape`, `Tab`, `ArrowDown`), or one letter or digit (`S`, `7`). |
| `snapshot` | string | no | `full`, `diff` or `none`. Overrides `includeSnapshot`. |
| `includeSnapshot` | boolean | no | Embed the post-key snapshot. Default `true`. |
| `modifiers` | array<string> | no | Subset of `control` (or `ctrl`), `shift`, `alt`, `meta`, in any case. Each is held down before the key and released after it, even when delivery throws, so exact-match shortcuts such as Shift+Tab or Ctrl+S fire. An unknown name is an error before anything is pressed. On the CLI this is a comma list (`--modifiers=control,shift`). |

### Returns

Success: `{ key: "<label>", modifiers: [...] }`.

### Example call

```json
{ "name": "tapir_press_key", "arguments": { "key": "S", "modifiers": ["control"] } }
```

---

## tapir_reset_overlays

Dispatch: `ext.tapir.reset_overlays`

Reset the app to a clean screen via three escalating, idempotent layers: (1) pop every
`PopupRoute` (dialogs, bottom sheets, popups) without touching the page stack; (2) an
`Escape` key press for overlays driven by the dismiss shortcut; (3) a
Cancel/Dismiss/Close/OK/Done labelled tap for modal barriers that need an explicit
affordance. Each layer is a no-op when the prior already cleared the overlays, so the call
is safe to issue speculatively between flows.

### Input schema

No parameters.

### Returns

Success: `{ popped: <int>, escaped: <bool>, dismissTapped: <bool> }`. On a clean tree all
three indicate no work was done, confirming idempotency.

### Example call

```json
{ "name": "tapir_reset_overlays", "arguments": {} }
```

---

## tapir_resize_viewport

Dispatch: `dowel:tapir:resize`

Resize the running Flutter web app viewport via Chrome DevTools Protocol. Requires
dowel to have been started with `--cdp-port`. Chrome drops the override when the
DevTools session that sent it detaches, so through this tool it ends when the call
returns; the CLI's `--hold` flag (`tapir:resize --hold`, run in the background) keeps
the session open and is the way to drive the app at the new size.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `width` | integer | no | Viewport width in CSS pixels (e.g. `375` for mobile, `1440` for desktop). Required unless `reset`: the command refuses a resize without it. |
| `height` | integer | no | Viewport height in CSS pixels. Required unless `reset`. |
| `dpr` | number | no | Device pixel ratio (default `1.0`). Use `2.0` for Retina, `3.0` for iPhone Pro. Must be > 0. |
| `mobile` | boolean | no | Enable mobile device profile. Default `false`. |
| `touch` | boolean | no | Enable touch event synthesis (browser fires touch events instead of mouse). Default `false`. |
| `reset` | boolean | no | Clear all viewport overrides (metrics + touch + user agent). When `true`, all other params are ignored. Default `false`. |

### Returns

Success: the command's text output, `Viewport override sent: 375x812 @ 3.0x (mobile=true
touch=true).` followed by a note that the override ends with the call. With `reset: true`:
`Viewport reset to defaults.`

Errors (the call is reported with `isError`): `CDP not enabled` when the session has no
`cdpPort`; `A resize needs a positive --width and --height ... or --reset` when neither a size
nor `reset` is given. An argument the schema does not list, such as the old
`deviceScaleFactor`, is refused before the command runs.

### Example call

```json
{ "name": "tapir_resize_viewport", "arguments": { "width": 375, "height": 812, "dpr": 3.0, "mobile": true, "touch": true } }
```

---

## tapir_right_click

Dispatch: `ext.tapir.right_click`

Fire a right (secondary mouse) click (Playwright `locator.click({ button: "right" })`
parity). Injects `PointerDownEvent` + 50ms hold + `PointerUpEvent` (mouse kind,
`kSecondaryButton`).

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ref` | string | yes | Widget ref (`e<N>`). |
| `includeSnapshot` | boolean | no | Embed post-action snapshot. Default `true`. |
| `checkStable` | boolean | no | Run the Stable actionability gate. Default `true`. |
| `checkReceivesEvents` | boolean | no | Run the Receives-Events actionability gate. Default `true`. |
| `snapshot` | string | no | `full`, `diff` or `none`. Overrides `includeSnapshot`. |

### Returns

Success: `{ ref: "<ref>" }`.

Error: actionability gate failure, or stale-handle.

### Example call

```json
{ "name": "tapir_right_click", "arguments": { "ref": "e5" } }
```

---

## tapir_run

Dispatch: `dowel:tapir:run` (substrate-routed)

Run several tapir verbs against the running app in one call. Each step is a CLI verb line
without the `tapir:` prefix, tokenised like a shell (quotes and backslash escapes), and takes
the same options as the standalone command. Saves a round trip per step when the next refs
are already known. See [tapir:run](../commands/tapir-run.md) for the step grammar.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `steps` | array<string> | yes | Verb lines, run in order (e.g. `"tap --ref=e5"`). |
| `continue` | boolean | no | Keep running after a failing step (default `false`). |

### Returns

Text: one line per step (`[1/3] tap --ref=e5 ok: <first output line, cut to 120
characters>`), then the last step's full output. The batch stops at the first failing step
and returns `step N failed (exit C): <step>` with that step's output; with `continue: true`
it runs every step and reports the first failure. A step cannot be another `tapir_run`, nor a
verb that does not run on the connected app (resize, device, install, doctor). Use `--text`,
`--key` or `q<N>` handles between steps that change the screen: `e<N>` refs belong to one
snapshot.

### Example call

```json
{ "name": "tapir_run", "arguments": { "steps": ["tap --ref=e5", "fill --ref=q1 --text=\"a b\"", "snap --grep Total"] } }
```

---

## tapir_screenshot

Dispatch: `ext.tapir.screenshot` (in-isolate, all targets). The CDP `Page.captureScreenshot` web fallback is implemented in the CLI command `tapir:screenshot --output=<path>`, NOT in this MCP tool.

Capture a screenshot of the running Flutter app as a base64-encoded image. This MCP tool
always dispatches the in-isolate `ext.tapir.screenshot` extension.

**Web limitation:** the in-isolate path can hang under CanvasKit+DWDS (the `toImage()`
future never completes). For reliable web screenshots, use the CLI command
`tapir:screenshot --output=<path>`: when dowel was started with `--cdp-port`, the CLI
falls back to CDP `Page.captureScreenshot`, honouring `--ref` / `--rect` there too. That
fallback is CLI-only and does not apply to this MCP tool.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `format` | string | no | `jpeg` or `png`. Default `jpeg`. |
| `quality` | integer | no | JPEG quality 0-100 (higher is better). Default `70`. Ignored when format is `png`. |
| `ref` | string | no | Capture only this widget: an `e<N>` from `tapir_snap` or a `q<N>` from `tapir_find`. Omit for the whole viewport. |
| `rect` | string | no | Sub-rect `"x,y,w,h"` in logical pixels, relative to the ref's top-left. Requires `ref`. |

Reach for `ref` whenever the question is about one component. A full-screen capture of a
tall page costs far more tokens than the region under review and buries the thing you are
checking, and it forces the resize dance for anything below the fold.

`rect` alone is a hard error rather than a silent full-frame capture: a sub-rect is
meaningless without the widget it is relative to.

### Returns

Success: `{ format: "<jpeg|png>", base64: "<base64>", width: <int>, height: <int> }`.

A hidden or minimised desktop window is woken before the capture, so the image is a fresh
frame and not the last cached one; the response then carries `framesForced: true`. The CLI
infers `format` from the `--output` extension; this tool takes `format` as given.

Without `ref` the capture is the app-root viewport (the `RepaintBoundary` the host wraps
the app in under `!kReleaseMode`). With `ref` it is the widget's own render-object region,
rasterised out of its nearest repaint-boundary ancestor.

The extension has a third mode, `geometry: "true"`, that returns
`{ rect: {x, y, width, height}, devicePixelRatio: <double> }` and skips rasterising
altogether. It exists so the CLI can build a CDP clip on web, where rasterising is the
step that hangs, and it is not part of this tool's schema: an MCP call that sends
`geometry` is refused with `Additional property "geometry" is not allowed`. Agents want
the pixels instead.

### Example call

```json
{ "name": "tapir_screenshot", "arguments": { "ref": "e42", "format": "png" } }
```

---

## tapir_scroll

Dispatch: `ext.tapir.scroll`

Drive a `Scrollable` widget by ref. The extension walks up to the nearest `Scrollable`
ancestor of the widget identified by `ref`.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ref` | string | no | Widget ref (`e<N>`) inside the target Scrollable. Without it the first Scrollable found is scrolled. |
| `direction` | string | no | `up`, `down`, `left`, `right`. Default `down`. |
| `pixels` | number | no | Logical pixels to scroll. Default `300`. |
| `dx` | number | no | Horizontal delta in logical pixels (positive = right). Overrides `direction` / `pixels`. |
| `dy` | number | no | Vertical delta in logical pixels (positive = down). Overrides `direction` / `pixels`. |
| `intoView` | boolean | no | Bring `ref` itself into view (`Scrollable.ensureVisible`) instead of scrolling by a delta. |
| `snapshot` | string | no | `full`, `diff` or `none`. Overrides `includeSnapshot`. |
| `includeSnapshot` | boolean | no | Embed the post-scroll snapshot. Default `true`. |

### Returns

Success: `{ scrolled, finalOffset, effect, snapshot? }`. `scrolled` is `true` only when the
scroll offset moved; with `intoView` and no `Scrollable` around the ref, or a list already at
its edge, it is `false` and `effect.changed` is `false` (a delta scroll with no laid-out
`Scrollable` at all returns a not-found error). A delta is clamped to the scroll extents. Re-snap after; off-screen widgets gain refs only
once Flutter builds them.

### Example call

```json
{ "name": "tapir_scroll", "arguments": { "ref": "e12", "direction": "down", "pixels": 500 } }
```

---

## tapir_select_option

Dispatch: `ext.tapir.select_option`

Select an option in a `DropdownButton` / `DropdownButtonFormField` by ref + value. Opens
the dropdown, finds the matching item, and taps it.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ref` | string | yes | Dropdown widget ref (`e<N>`). |
| `value` | string | yes | Option to select. Matches displayed label first, then `toString()` of the underlying value. |

### Returns

Success: `{ ref, value }`. Re-snap after; the dropdown closes and downstream widgets may
re-render.

Error: option not found, or actionability gate failure on the dropdown itself.

### Example call

```json
{ "name": "tapir_select_option", "arguments": { "ref": "e7", "value": "GET" } }
```

---

## tapir_set_checkbox

Dispatch: `ext.tapir.set_checkbox`

Read + conditionally toggle a `Checkbox` or `Switch` widget by ref. Idempotent: when the
current value already matches `value`, the call returns without tapping.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ref` | string | yes | Checkbox or Switch widget ref (`e<N>`). |
| `value` | string | yes | `"true"` or `"false"` (target checked state). |

### Returns

Success: `{ ref, previousValue, value, toggled: bool }`. `toggled` is `false` when the
state already matched.

### Example call

```json
{ "name": "tapir_set_checkbox", "arguments": { "ref": "e4", "value": "true" } }
```

---

## tapir_snap

Dispatch: `ext.tapir.snap`

Capture a YAML snapshot of the running Flutter app's Semantics tree with stable
`[ref=eN]` tokens. Call this FIRST, then pass the returned ref tokens to subsequent
action calls.

Interactive nodes inside a currently-overflowing render ancestor carry an additive
`overflow: true` sub-line (live `RenderFlex.toStringShort()` check). This is a
current-state signal; call `tapir_exceptions` for the full non-fatal error history.

Text fields collapse to a single ref. A field that produces two nested `textbox`
Semantics nodes (an outer wrapper plus the `RenderEditable` leaf that always owns its
own node) emits one ref for the outer node, tagged with an additive `typeable: true`
sub-line; the inner duplicate is suppressed when its render object is a render-tree
descendant of the outer node's render object. Collapse is by render-object containment
only, so two sibling fields sharing a label stay two distinct refs. Target the node
carrying `typeable: true` when calling `tapir_type`.

A control wrapped in `MergeSemantics` (a magic_starter `MSSwitch` row, a wind `WAnchor`)
is listed once. Flutter keeps each absorbed descendant in the tree as its own node
flagged `isMergedIntoParent`; the walk prints no line and mints no ref for it, and
still descends through it. The boundary line already carries the merged label, flags
and actions, which is what the platform exposes.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `depth` | integer | no | Max tree-traversal depth from the root. Omit for full tree. |
| `within` | string | no | Scope the walk to one subtree: the `e<N>` ref of the region to read. `q<N>` handles are not addressable here. An unknown ref is an error, not a silent widening. |
| `interactiveOnly` | boolean | no | Emit only nodes carrying a ref; drop the plain `- text` lines. Default `false`. |
| `includeEnrichers` | boolean | no | Add the Magic and Wind enricher lines under each ref. Default `false`. |
| `grep` | string | no | Emit only nodes whose label or value matches this regular expression, plus the ancestors leading to them. A pattern that is not a valid regex (an unbalanced `(` in a label, say) is matched as a literal substring and the response carries `grepLiteral: true`. |

A full tree is the wrong default answer to most questions. It costs context on any real
screen, and on a shell whose sidebar repeats the labels of the pages it opens it is also
the misleading answer: the unscoped lookup resolves the nav item. `within` +
`interactiveOnly` is the usual shape before an action.

### Returns

Success: `{ "snapshot": "<yaml>", "groupId": "<id>" }`. The `snapshot` value is a YAML
document where each node is annotated with a `[ref=e<N>]` token, its role, label, actions,
bounds, optional `overflow: true` and `typeable: true` sub-lines, and any enricher-contributed
indented lines.

A ref line may end with ` [offscreen]` (the widget lies outside the viewport) and/or
` [occluded]` (a hit test at its centre reaches something painted above it), after
`[ref=e<N>]`. Both are absent on a healthy screen. An offscreen node is never probed for
occlusion, and a node with no area carries neither marker.

A merged node whose centre is not on its own control also gets an indented
`tapOwner: {"x":..,"y":..,"w":..,"h":..}` sub-line (the control's rect); a `tapir_tap` on that
ref goes to the control.

When non-fatal render or build `FlutterError`s are in the capture buffer (for example a
`ParentDataWidget` misuse or a layout overflow), a `renderErrors` block is added to the
response:

```json
{
  "snapshot": "...",
  "groupId": "snapshot-1700000000000",
  "renderErrors": {
    "count": 1,
    "recent": [ { "type": "FlutterError", "message": "Incorrect use of ParentDataWidget." } ],
    "hint": "Run tapir:exceptions for full messages + stack traces."
  }
}
```

`renderErrors` is omitted entirely when the screen is clean. `recent` contains at most 3
entries, each with `type` (string) and `message` (first line of the error). `count` reflects
the full buffer depth, which may exceed 3. Use `tapir_exceptions` to retrieve full messages and
stack traces.

### Example call

```json
{ "name": "tapir_snap", "arguments": { "depth": 8 } }
```

---

## tapir_tap

Dispatch: `ext.tapir.tap`

Tap a widget by ref. Synthesizes a pointer Down + 50ms hold + Up sequence at the widget's
LIVE center. Triggers `GestureDetector.onTap`, `InkWell.onTap`, button `onPressed`. For
`TextField` widgets the tap also requests keyboard focus.

The pointer dispatches at the target's live rect, re-resolved immediately after the
actionability gate passes (it falls back to the cached snapshot rect only for slivers /
detached render objects). A button whose host rebuilt it into a shifted slot between
`tapir_snap` and `tapir_tap` is still hit correctly.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ref` | string | yes | Widget ref (`e<N>`). |
| `snapshot` | string | no | Post-tap snapshot: `full` (the default), `diff` or `none`. `diff` returns only the lines the tap changed since your last unfiltered snapshot (a `tapir_snap` or an earlier action): a changed row is `- <old line>` then `+ <new line>`, an added row `+ `, a removed row `- `, then a `(K of N lines changed)` footer, and the payload adds `snapshotMode: "diff"`. With no baseline yet the full text comes back. A filtered `tapir_snap` (`grep`, `within`, `depth`, `interactiveOnly`) never records the baseline, and a hot restart clears it. |
| `includeSnapshot` | boolean | no | Embed post-action snapshot. Default `true`. |
| `checkStable` | boolean | no | Run the Stable actionability gate. Default `true`. |
| `checkReceivesEvents` | boolean | no | Run the Receives-Events actionability gate. Default `true`. |
| `retarget` | boolean | no | Default `true`: a tap on a merged boundary goes to its one labelled control. `false` taps the boundary centre. |
| `until` | string | no | After the tap settles, poll the live element tree for a `Text` equal to this value (up to `untilTimeoutMs`) and add an `untilMatched` boolean. Confirms a navigation / state change in one call. Default off, which keeps the response shape unchanged. |
| `untilTimeoutMs` | integer | no | Poll ceiling for `until`, in milliseconds. Default `3000`. |

### Returns

Success: `{ ref: "<ref>", effect: {kind: "treeChanged", changed: bool} }`. The `effect`
block is always present: `changed` is true when the target's own route or semantics
subtree differed after the tap, false when nothing observable happened. With `until` set
the response also carries `untilMatched: true|false` (true when the expected text appeared
within the window).

**A merge boundary taps its own control.** A tap at the centre of a `MergeSemantics`
boundary can land on another handler (a full-frame stage) while the gate still says
confirmed (issue #60). When exactly one labelled control owns the merged label and a hit test
at its centre reaches it inside the viewport, the pointer goes there and the response adds
`retargeted: {from: {x, y}, to: {x, y}, ownerRect: {left, top, width, height}, centreHandled?}`
(`centreHandled: true` when the centre has a tap handler of its own). Pass `retarget: false` to
tap the centre instead. When retargeting is not safe (several candidates, or the control is
covered or off screen) the tap stays at the centre and the response adds
`tapPointOutsideOwner: {ownerRect, point}`. The gate is unchanged. `tapir_snap` and
`tapir_observe` show the control's rect ahead of time as `tapOwner` (with `retargets: false`
when a tap cannot go there). Only `tapir_tap` retargets.

Error: actionability gate failure (`"not enabled"` / `"zero rect"` / `"off-viewport"`) or
stale-handle.

**Stale `e<N>` refs.** When the element behind an `e<N>` ref has left the tree, the
action relocates it through the label-and-index query the snapshot bound to the ref, and
trusts the result only if the live tree has the same number of nodes with that label as at
snapshot time and the hit sits on the route the ref was minted on. A relocation adds
`reresolved: ["e5"]` to the response. With a different count, or on another route, the ref
fails as before with `defunct (element no longer mounted)`; re-snap. Known limit: the bound
query has no role, so a node of another role with the same label in the same position on
the same route could match.

### Example call

```json
{ "name": "tapir_tap", "arguments": { "ref": "e5" } }
```

---

## tapir_triple_click

Dispatch: `ext.tapir.triple_click`

Fire three primary clicks (~100ms apart) at the widget identified by `ref` (Playwright
`locator.click({ clickCount: 3 })` parity). In Material text fields this selects an entire
paragraph.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ref` | string | yes | Widget ref (`e<N>`). |
| `includeSnapshot` | boolean | no | Embed post-action snapshot. Default `true`. |
| `checkStable` | boolean | no | Run the Stable actionability gate. Default `true`. |
| `checkReceivesEvents` | boolean | no | Run the Receives-Events actionability gate. Default `true`. |
| `snapshot` | string | no | `full`, `diff` or `none`. Overrides `includeSnapshot`. |

### Returns

Success: `{ ref: "<ref>" }`. The actionability gate runs once before the first tap.

### Example call

```json
{ "name": "tapir_triple_click", "arguments": { "ref": "e5" } }
```

---

## tapir_type

Dispatch: `ext.tapir.type`

Type text into a `TextField` widget by ref. Fires `userUpdateTextEditingValue` so
`onChanged` callbacks fire and form validators run. Replaces existing text (does not
append).

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ref` | string | yes | TextField widget ref (`e<N>`). |
| `text` | string | yes | Text to enter. Pass empty string to clear. |
| `snapshot` | string | no | `full`, `diff` or `none`. Overrides `includeSnapshot`. |
| `includeSnapshot` | boolean | no | Embed post-action snapshot. Default `true`. |
| `checkStable` | boolean | no | Run the Stable actionability gate. Default `true`. |
| `checkReceivesEvents` | boolean | no | Run the Receives-Events actionability gate. Default `true`. |

### Returns

Success: `{ ref, text }`. Multi-line text uses `\n` line breaks.

### Example call

```json
{ "name": "tapir_type", "arguments": { "ref": "e9", "text": "hello@example.com" } }
```

---

## tapir_wait_for

Dispatch: `ext.tapir.wait_for`

Wait until a UI condition is satisfied or the timeout expires. Polls at 200ms; returns as
soon as the condition flips.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `text` | string | no | Wait until a `Text` with this exact data exists. |
| `textGone` | string | no | Wait until no such `Text` exists. |
| `expression` | string | no | Matched as text, exactly like `text`; it is not evaluated as Dart (use `tapir_evaluate` for that). |
| `timeoutMs` | integer | no | Wait timeout in milliseconds. Default `5000`. |

Pass one of `text`, `textGone`, `expression`; the handler errors when none is passed.

### Returns

Match: `{ matched: true, elapsedMs: <int> }`.

Timeout: a normal result, `{ matched: false, reason: "timeout" }`, not an MCP error, so check
`matched` before continuing (the CLI, `tapir:wait`, exits 1 in that case). With none of the
three keys the call errors; with several it uses the first of `text`, `textGone`, `expression`.

### Example call

```json
{ "name": "tapir_wait_for", "arguments": { "text": "Welcome", "timeoutMs": 3000 } }
```

---

## tapir_wait_for_network_idle

Dispatch: `ext.tapir.wait_for_network_idle`

Wait until the running app reports zero in-flight HTTP requests for a contiguous `idleMs`
window. Playwright `waitForLoadState` network-idle semantics. Missing-crumbs graceful:
returns idle immediately when crumbs is not set up.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `timeoutMs` | integer | no | Maximum total wait time. Default `5000`. |
| `idleMs` | integer | no | Contiguous-zero window before declaring idle. Default `500`. |
| `pollIntervalMs` | integer | no | Poll cadence in milliseconds. Minimum `100`; default `200`. |

### Returns

Success: `{ matched: true, idleAchievedMs: <int> }`.

Error on timeout: structured error envelope `{ type: "timeout", message: "max in-flight
count observed: <int>" }`.

### Example call

```json
{ "name": "tapir_wait_for_network_idle", "arguments": { "timeoutMs": 8000, "idleMs": 750 } }
```

---

## Related

- [overview.md](overview.md): tool catalog, dispatch surfaces, lifecycle.
- [setup.md](setup.md): per-client install matrix and reconnect ritual.
- [`lib/src/tapir_dowel_provider.dart`](../../lib/src/tapir_dowel_provider.dart): the
  source-of-truth `McpToolDescriptor` list.
