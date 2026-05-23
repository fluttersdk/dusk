# Dusk MCP Tool Reference

Per-tool input schema, return shape, and example payload for every `dusk_*` MCP tool
contributed by `DuskArtisanProvider`. 31 tools total: 28 dispatch through `ext.dusk.*` VM
Service extensions and 3 (`dusk_hot_reload_and_snap`, `dusk_resize_viewport`,
`dusk_device_profile`) route through the `artisan:dusk:*` substrate path to a CLI command
because the orchestration cannot run inside the target isolate.

Sections are ordered alphabetically. Every section names the dispatch surface
(`extensionMethod`) at the top so the consumer knows which path the server takes. All
example payloads show the `params.arguments` object inside the `tools/call` JSON-RPC
request; the substrate MCP server wraps the response as `CallToolResult` text content.

## Table of contents

- [`dusk_blur`](#dusk_blur)
- [`dusk_clear`](#dusk_clear)
- [`dusk_close_app`](#dusk_close_app)
- [`dusk_console`](#dusk_console)
- [`dusk_dblclick`](#dusk_dblclick)
- [`dusk_device_profile`](#dusk_device_profile)
- [`dusk_dismiss_modals`](#dusk_dismiss_modals)
- [`dusk_drag`](#dusk_drag)
- [`dusk_evaluate`](#dusk_evaluate)
- [`dusk_exceptions`](#dusk_exceptions)
- [`dusk_find`](#dusk_find)
- [`dusk_focus`](#dusk_focus)
- [`dusk_get_routes`](#dusk_get_routes)
- [`dusk_hot_reload_and_snap`](#dusk_hot_reload_and_snap)
- [`dusk_hover`](#dusk_hover)
- [`dusk_navigate`](#dusk_navigate)
- [`dusk_navigate_back`](#dusk_navigate_back)
- [`dusk_observe`](#dusk_observe)
- [`dusk_press_key`](#dusk_press_key)
- [`dusk_resize_viewport`](#dusk_resize_viewport)
- [`dusk_right_click`](#dusk_right_click)
- [`dusk_screenshot`](#dusk_screenshot)
- [`dusk_scroll`](#dusk_scroll)
- [`dusk_select_option`](#dusk_select_option)
- [`dusk_set_checkbox`](#dusk_set_checkbox)
- [`dusk_snap`](#dusk_snap)
- [`dusk_tap`](#dusk_tap)
- [`dusk_triple_click`](#dusk_triple_click)
- [`dusk_type`](#dusk_type)
- [`dusk_wait_for`](#dusk_wait_for)
- [`dusk_wait_for_network_idle`](#dusk_wait_for_network_idle)

---

## dusk_blur

Dispatch: `ext.dusk.blur`

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
{ "name": "dusk_blur", "arguments": { "includeSnapshot": false } }
```

Response:

```json
{ "blurred": true, "hadFocus": true }
```

---

## dusk_clear

Dispatch: `ext.dusk.clear`

Empty the `TextEditingController` backing the resolved text field (Playwright
`locator.clear()` parity).

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ref` | string | yes | Widget ref of a `TextField` / `TextFormField` / `EditableText` (e.g. `"e5"`). |
| `includeSnapshot` | boolean | no | Embed the post-clear snapshot. Default `false`. |

### Returns

Success: `{ ref: "e<N>", text: "" }`.

Error: `DuskActionabilityException` (when the gate fails) or `DuskStaleHandleException`
(when the ref is unknown / stale) surfaced as the wire error string `"Widget ref=<ref> is
not actionable: <reason>"`.

### Example call

```json
{ "name": "dusk_clear", "arguments": { "ref": "e5" } }
```

Response:

```json
{ "ref": "e5", "text": "" }
```

---

## dusk_close_app

Dispatch: `ext.dusk.close_app`

Request a graceful shutdown of the running Flutter app via `SystemNavigator.pop()`. On
mobile + desktop this terminates the app; on web the call is a no-op (browsers do not
allow programmatic tab close).

### Input schema

No parameters.

### Returns

Success: an empty object `{}`. After the call the VM Service URI is gone, so the next
`dusk_*` tool returns a VM-Service-unreachable error.

### Example call

```json
{ "name": "dusk_close_app", "arguments": {} }
```

---

## dusk_console

Dispatch: `ext.dusk.console`

Read recent log entries from the running app's telescope store. Missing-telescope graceful:
returns an empty list when the host has not wired telescope.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `limit` | integer | no | Maximum number of entries to return. Default `50`. |
| `minLevel` | string | no | Minimum severity level (`INFO`, `WARNING`, `ERROR`). Omit for all levels. |

### Returns

Success: `{ entries: [ { level, message, time, logger }, ... ] }`.

Error: never; missing telescope is treated as the empty-entries success path.

### Example call

```json
{ "name": "dusk_console", "arguments": { "limit": 10, "minLevel": "ERROR" } }
```

---

## dusk_dblclick

Dispatch: `ext.dusk.dblclick`

Double-click a widget by ref. Synthesizes two pointer Down+50ms+Up sequences at the
widget's center with ~100ms between them (Playwright double-click model). Triggers
`GestureDetector.onDoubleTap`.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ref` | string | yes | Widget ref from a prior `dusk_snap`. Shape `e<N>` or `q<N>`. |

### Returns

Success: `{ ref: "e<N>" }`. The actionability gate runs once before the first tap; the
post-action snapshot is captured after the second tap completes.

Error: `"Widget ref=<ref> is not actionable: <reason>"` (gate failure) or stale-handle
error when the ref is unknown.

### Example call

```json
{ "name": "dusk_dblclick", "arguments": { "ref": "e7" } }
```

---

## dusk_device_profile

Dispatch: `artisan:dusk:device`

Emulate a named device profile (viewport + DPR + touch + user agent) via Chrome DevTools
Protocol. Requires the substrate to have been started with `--cdp-port`.

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
{ "name": "dusk_device_profile", "arguments": { "preset": "iphone-x" } }
```

---

## dusk_dismiss_modals

Dispatch: `ext.dusk.dismiss_modals`

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
{ "name": "dusk_dismiss_modals", "arguments": {} }
```

---

## dusk_drag

Dispatch: `ext.dusk.drag`

Drag from one widget to another by ref tokens. Synthesizes pointer Down + 5x intermediate
Move events + Up sequence from `startRef`'s center to `endRef`'s center.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `startRef` | string | yes | Source widget ref (`e<N>`). |
| `endRef` | string | yes | Target widget ref (`e<N>`). |

### Returns

Success: `{ startRef, endRef }`. Both refs are echoed for caller bookkeeping.

Error: actionability gate failure on either ref, or stale-handle on either.

### Example call

```json
{ "name": "dusk_drag", "arguments": { "startRef": "e12", "endRef": "e18" } }
```

---

## dusk_evaluate

Dispatch: `ext.dusk.evaluate`

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
{ "name": "dusk_evaluate", "arguments": { "expression": "Auth.user?.email" } }
```

Response:

```json
{ "result": "user@example.com" }
```

---

## dusk_exceptions

Dispatch: `ext.dusk.exceptions`

Read recent exception entries from the telescope exception watcher. Missing-telescope
graceful: returns an empty list when telescope is not wired.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `limit` | integer | no | Maximum number of entries to return. Default `20`. |

### Returns

Success: `{ entries: [ { type, message, stackHead, time }, ... ] }`. `stackHead` is the
first 3 lines of the stack trace.

### Example call

```json
{ "name": "dusk_exceptions", "arguments": { "limit": 5 } }
```

---

## dusk_find

Dispatch: `ext.dusk.find`

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

At least one of the four must be supplied. When multiple are passed they form an
intersection.

### Returns

Success on first match: `{ ref: "q<N>", matched: true }`. No match: `{ ref: null, matched:
false }`.

Error: surfaced only when a follow-up action call finds zero live matches against the
handle (`"stale handle"`); the agent must re-find or re-snap, never silently retry.

### Example call

```json
{ "name": "dusk_find", "arguments": { "text": "Submit" } }
```

---

## dusk_focus

Dispatch: `ext.dusk.focus`

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
{ "name": "dusk_focus", "arguments": { "ref": "e5" } }
```

---

## dusk_get_routes

Dispatch: `ext.dusk.get_routes`

List the route paths declared by the running app's `MagicRouter`. Returns an empty list
when no Magic router is installed.

### Input schema

No parameters.

### Returns

Success: `{ routes: [ { path, name }, ... ] }`. Parameterised paths render with `:id`-style
placeholders.

### Example call

```json
{ "name": "dusk_get_routes", "arguments": {} }
```

Response:

```json
{ "routes": [ { "path": "/monitors", "name": "monitors.index" }, { "path": "/monitors/:id", "name": "monitors.show" } ] }
```

---

## dusk_hot_reload_and_snap

Dispatch: `artisan:dusk:hot_reload_and_snap`

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
recentExceptions: [...] }`. `snapshot` + `screenshot` are omitted on compile error.

### Example call

```json
{ "name": "dusk_hot_reload_and_snap", "arguments": { "screenshot": false } }
```

---

## dusk_hover

Dispatch: `ext.dusk.hover`

Hover a mouse cursor over a widget by ref. Mouse-only (no touch equivalent). Synthesizes a
`PointerHoverEvent` of `PointerDeviceKind.mouse` at the widget's center.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ref` | string | yes | Widget ref (`e<N>`). |

### Returns

Success: `{ ref: "<ref>" }`. No-op on touch-only devices.

Error: actionability gate failure, or stale-handle.

### Example call

```json
{ "name": "dusk_hover", "arguments": { "ref": "e8" } }
```

---

## dusk_navigate

Dispatch: `ext.dusk.navigate`

Navigate the running Flutter app to a route path. Resolves through `MagicRoute.to(...)`
when Magic is installed, falling back to `Navigator.of(root).pushNamed(...)`.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `route` | string | yes | Route path. Must start with `/`. Example: `/monitors/123`. |

### Returns

Success: `{ route: "<path>" }`. ALWAYS re-snap after; refs from a prior snapshot are
invalidated.

### Example call

```json
{ "name": "dusk_navigate", "arguments": { "route": "/login" } }
```

---

## dusk_navigate_back

Dispatch: `ext.dusk.navigate_back`

Pop the top route off the active navigator stack. Equivalent to pressing the system Back
button. No-op when the stack has only one route.

### Input schema

No parameters.

### Returns

Success: `{ popped: bool }`. `false` when the stack already had only one route.

### Example call

```json
{ "name": "dusk_navigate_back", "arguments": {} }
```

---

## dusk_observe

Dispatch: `ext.dusk.observe`

Return a structured candidate list of every interactive widget on screen. Implements
Stagehand's observe-once-act-many pattern (no server-side LLM). Each candidate carries a
re-resolvable `q<N>` ref.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `intent` | string | no | Free-form caller hint (e.g. `"login form"`). Echoed in audit logs, NOT used server-side. |
| `roles` | string | no | Comma-separated role filter (`button,textbox,link,checkbox,heading,image`). Omit for every role. |
| `limit` | integer | no | Maximum number of candidates. Default `50`. |
| `includeEnrichers` | string | no | `"true"` (default subset), `"false"` (none), or `"full"` (every field). |

### Returns

Success: `{ candidates: [ { ref, role, label, value, bounds, isEnabled, isVisible,
enrichers: { ... } }, ... ] }`. The enricher subset projects
`magicFormField`, `magicRoute`, `magicGateResult`, `wind.breakpoint`, `wind.states` by
default.

### Example call

```json
{ "name": "dusk_observe", "arguments": { "intent": "login form", "roles": "textbox,button", "limit": 20 } }
```

---

## dusk_press_key

Dispatch: `ext.dusk.press_key`

Press a hardware key (optionally with modifiers). Synthesizes `KeyDownEvent` +
`KeyUpEvent` through `ServicesBinding.instance.keyboard.handleKeyEvent`.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `key` | string | yes | Logical key label (e.g. `Enter`, `Escape`, `Tab`, `ArrowDown`, `S`). |
| `modifiers` | array<string> | no | Subset of `control`, `shift`, `alt`, `meta` held during the press. |

### Returns

Success: `{ key: "<label>", modifiers: [...] }`.

### Example call

```json
{ "name": "dusk_press_key", "arguments": { "key": "S", "modifiers": ["control"] } }
```

---

## dusk_resize_viewport

Dispatch: `artisan:dusk:resize`

Resize the running Flutter web app viewport via Chrome DevTools Protocol. Requires
artisan to have been started with `--cdp-port`.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `width` | integer | yes | Viewport width in CSS pixels (e.g. `375` for mobile, `1440` for desktop). |
| `height` | integer | yes | Viewport height in CSS pixels. |
| `deviceScaleFactor` | number | no | Device pixel ratio (default `1.0`). Use `2.0` for Retina, `3.0` for iPhone Pro. Must be > 0. |
| `mobile` | boolean | no | Enable mobile device profile. Default `false`. |
| `touch` | boolean | no | Enable touch event synthesis (browser fires touch events instead of mouse). Default `false`. |
| `reset` | boolean | no | Clear all viewport overrides (metrics + touch + user agent). When `true`, all other params are ignored. Default `false`. |

### Returns

Success: `{ viewport: { width, height, deviceScaleFactor, mobile, touch } }`. With `reset:
true`: `{ reset: true }`.

Error: `cdpPort` not configured.

### Example call

```json
{ "name": "dusk_resize_viewport", "arguments": { "width": 375, "height": 812, "deviceScaleFactor": 3.0, "mobile": true, "touch": true } }
```

---

## dusk_right_click

Dispatch: `ext.dusk.right_click`

Fire a right (secondary mouse) click (Playwright `locator.click({ button: "right" })`
parity). Injects `PointerDownEvent` + 50ms hold + `PointerUpEvent` (mouse kind,
`kSecondaryButton`).

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ref` | string | yes | Widget ref (`e<N>`). |
| `includeSnapshot` | boolean | no | Embed post-action snapshot. Default `false`. |
| `checkStable` | boolean | no | Run the Stable actionability gate. Default `true`. |
| `checkReceivesEvents` | boolean | no | Run the Receives-Events actionability gate. Default `true`. |

### Returns

Success: `{ ref: "<ref>" }`.

Error: actionability gate failure, or stale-handle.

### Example call

```json
{ "name": "dusk_right_click", "arguments": { "ref": "e5" } }
```

---

## dusk_screenshot

Dispatch: `ext.dusk.screenshot`

Capture a screenshot of the running Flutter app as a base64-encoded image. Renders the
current frame to JPEG or PNG.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `format` | string | no | `jpeg` or `png`. Default `png` (lossless). |
| `quality` | integer | no | JPEG quality 0-100 (higher is better). Default `80`. Ignored when format is `png`. |

### Returns

Success: `{ format: "<png|jpeg>", bytes: "<base64>" }`. Captures the WHOLE app surface.

### Example call

```json
{ "name": "dusk_screenshot", "arguments": { "format": "jpeg", "quality": 70 } }
```

---

## dusk_scroll

Dispatch: `ext.dusk.scroll`

Drive a `Scrollable` widget by ref. The extension walks up to the nearest `Scrollable`
ancestor of the widget identified by `ref`.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ref` | string | yes | Widget ref (`e<N>`) inside the target Scrollable. |
| `direction` | string | no | `up`, `down`, `left`, `right`. Default `down`. |
| `pixels` | number | no | Logical pixels to scroll. Default `300`. |

### Returns

Success: `{ ref, direction, pixels }`. Re-snap after; off-screen widgets gain refs only
once Flutter builds them.

### Example call

```json
{ "name": "dusk_scroll", "arguments": { "ref": "e12", "direction": "down", "pixels": 500 } }
```

---

## dusk_select_option

Dispatch: `ext.dusk.select_option`

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
{ "name": "dusk_select_option", "arguments": { "ref": "e7", "value": "GET" } }
```

---

## dusk_set_checkbox

Dispatch: `ext.dusk.set_checkbox`

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
{ "name": "dusk_set_checkbox", "arguments": { "ref": "e4", "value": "true" } }
```

---

## dusk_snap

Dispatch: `ext.dusk.snap`

Capture a YAML snapshot of the running Flutter app's Semantics tree with stable
`[ref=eN]` tokens. Call this FIRST, then pass the returned ref tokens to subsequent
action calls.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `depth` | integer | no | Max tree-traversal depth from the root. Omit for full tree. |

### Returns

Success: a YAML document where each node is annotated with a `[ref=e<N>]` token, its role,
label, actions, bounds, and any enricher-contributed indented lines.

### Example call

```json
{ "name": "dusk_snap", "arguments": { "depth": 8 } }
```

---

## dusk_tap

Dispatch: `ext.dusk.tap`

Tap a widget by ref. Synthesizes a pointer Down + 50ms hold + Up sequence at the widget's
center. Triggers `GestureDetector.onTap`, `InkWell.onTap`, button `onPressed`. For
`TextField` widgets the tap also requests keyboard focus.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ref` | string | yes | Widget ref (`e<N>`). |

### Returns

Success: `{ ref: "<ref>" }`.

Error: actionability gate failure (`"not enabled"` / `"zero rect"` / `"off-viewport"`) or
stale-handle.

### Example call

```json
{ "name": "dusk_tap", "arguments": { "ref": "e5" } }
```

---

## dusk_triple_click

Dispatch: `ext.dusk.triple_click`

Fire three primary clicks (~100ms apart) at the widget identified by `ref` (Playwright
`locator.click({ clickCount: 3 })` parity). In Material text fields this selects an entire
paragraph.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ref` | string | yes | Widget ref (`e<N>`). |
| `includeSnapshot` | boolean | no | Embed post-action snapshot. Default `false`. |
| `checkStable` | boolean | no | Run the Stable actionability gate. Default `true`. |
| `checkReceivesEvents` | boolean | no | Run the Receives-Events actionability gate. Default `true`. |

### Returns

Success: `{ ref: "<ref>" }`. The actionability gate runs once before the first tap.

### Example call

```json
{ "name": "dusk_triple_click", "arguments": { "ref": "e5" } }
```

---

## dusk_type

Dispatch: `ext.dusk.type`

Type text into a `TextField` widget by ref. Fires `userUpdateTextEditingValue` so
`onChanged` callbacks fire and form validators run. Replaces existing text (does not
append).

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ref` | string | yes | TextField widget ref (`e<N>`). |
| `text` | string | yes | Text to enter. Pass empty string to clear. |

### Returns

Success: `{ ref, text }`. Multi-line text uses `\n` line breaks.

### Example call

```json
{ "name": "dusk_type", "arguments": { "ref": "e9", "text": "hello@example.com" } }
```

---

## dusk_wait_for

Dispatch: `ext.dusk.wait_for`

Wait until a UI condition is satisfied or the timeout expires. Polls at 100ms; returns as
soon as the condition flips.

### Input schema

| Parameter | Type | Required | Description |
|---|---|---|---|
| `text` | string | no | Wait until a Semantics node with this exact label exists. |
| `textGone` | string | no | Wait until NO Semantics node with this label exists. |
| `expression` | string | no | Wait until this Dart expression (Tinker bridge) returns truthy. |
| `timeoutMs` | integer | no | Wait timeout in milliseconds. Default `5000`. |

Pass exactly ONE of `text`, `textGone`, `expression`; the handler errors when zero or
multiple are passed.

### Returns

Success: `{ matched: true, waitedMs: <int> }`.

Error on timeout: never silently continues; the call returns an MCP error result.

### Example call

```json
{ "name": "dusk_wait_for", "arguments": { "text": "Welcome", "timeoutMs": 3000 } }
```

---

## dusk_wait_for_network_idle

Dispatch: `ext.dusk.wait_for_network_idle`

Wait until the running app reports zero in-flight HTTP requests for a contiguous `idleMs`
window. Playwright `waitForLoadState` network-idle semantics. Missing-telescope graceful:
returns idle immediately when telescope is not wired.

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
{ "name": "dusk_wait_for_network_idle", "arguments": { "timeoutMs": 8000, "idleMs": 750 } }
```

---

## Related

- [overview.md](overview.md): tool catalog, dispatch surfaces, lifecycle.
- [setup.md](setup.md): per-client install matrix and reconnect ritual.
- [`lib/src/dusk_artisan_provider.dart`](../../lib/src/dusk_artisan_provider.dart): the
  source-of-truth `McpToolDescriptor` list.
