# MCP tools reference

The 31 `dusk_*` MCP tools an LLM agent calls to drive a running Flutter app.
Each entry: one-line purpose, input schema, return shape, when to use it,
common errors. Use this file as a lookup; the agent rarely needs all 31 in
the same session.

## How calls work

The MCP client forwards `tools/call` to the artisan server
(`dart run fluttersdk_dusk mcp:serve`). The server dispatches to one of:

- An `ext.dusk.*` VM Service extension running inside the Flutter isolate
  (28 tools).
- An `artisan:dusk:*` substrate command running outside the isolate
  (3 tools: `dusk_hot_reload_and_snap`, `dusk_resize_viewport`,
  `dusk_device_profile`).

Every tool returns a JSON object via `ServiceExtensionResponse.result` on
success. Failures return a `DuskErrorEnvelope`: at minimum `{ message }`,
often with `{ reason, ref, method }` for agent branching.

Prerequisites for every `dusk_*` MCP tool:

1. The app is running (`./bin/fsa start --device=<dev>`).
2. `DuskPlugin.install()` ran inside `kDebugMode` (handled by the
   one-time `dusk:install` CLI command).
3. The MCP server is wired in `.mcp.json` (handled by the one-time
   `mcp:install` CLI command).

Note that `dusk:install` and `dusk:doctor` are CLI commands run from a
shell during setup, not MCP tools surfaced to the agent. If an MCP tool
returns "VM Service URI absent", the app is not running or dusk is not
attached; if a substrate-routed CDP tool (`dusk_resize_viewport`,
`dusk_device_profile`) returns "CDP not enabled", Chrome was launched
without `--cdp-port`. From the shell, `./bin/fsa dusk:doctor` runs the
preflight checks.

---

## See: snap, screenshot, observe

### dusk_snap

**Purpose.** Capture the running app's Semantics tree as a YAML document
with stable `[ref=eN]` tokens.

**Input.**

| Param | Type | Required | Default | Note |
|---|---|---|---|---|
| `depth` | integer | no | unlimited | Maximum tree depth to walk |

**Returns.** `{ snapshot: "<yaml>", groupId: "snapshot-<timestamp>" }`.

YAML format per interactive node: `- <role> "<label>": "<value>" [ref=eN]`
followed by indented enricher lines (`magicFormField: email`, `magicRoute:
/login`, `wind: { breakpoint: lg, states: [hover] }`, etc.).

**Use it.** As the first call of any new agent session, or whenever the
UI mutates (navigation, modal open, hot-reload). Re-snap after each act
to refresh `e<N>` tokens against the live tree.

**Common pitfalls.** `e<N>` tokens become defunct when their node
unmounts. After a route push or a list rebuild, an old `e<N>` will fail
the gate with `"defunct (element no longer mounted)"`; re-snap and pick
a fresh ref. For multi-step flows prefer `dusk_find` / `dusk_observe` to
mint `q<N>` handles that survive disposal.

---

### dusk_observe

**Purpose.** Return a structured list of every interactive widget on
screen as `q<N>` query handles plus enricher fields. Stagehand pattern:
observe once, then act many times without re-observing.

**Input.**

| Param | Type | Required | Default | Note |
|---|---|---|---|---|
| `intent` | string | no | (none) | Free-form hint for the agent's own reasoning; not used server-side |
| `roles` | string | no | (all roles) | Comma-separated subset of `button`, `textbox`, `link`, `checkbox`, `heading`, `image` |
| `limit` | integer | no | 50 | Caps the candidate count |
| `includeEnrichers` | string | no | `"true"` | `"true"` (default subset), `"false"` (off), `"full"` (every enricher field) |

**Returns.**

```json
{
  "candidates": [
    {
      "ref": "q3",
      "role": "textbox",
      "label": "Email",
      "value": "",
      "bounds": { "x": 24.0, "y": 120.0, "w": 320.0, "h": 48.0 },
      "isEnabled": true,
      "isVisible": true,
      "magicFormField": "email",
      "magicRoute": "/login",
      "wind": { "breakpoint": "lg", "states": "[]" }
    }
  ],
  "count": 6
}
```

**Use it.** When the agent needs to enumerate candidates (form fill,
"find every submit button on the page", "list every link in the
navigation"). One observe call replaces a snap + multiple finds; the
candidates carry enough metadata to pick the right ref locally without
extra round-trips.

**Pitfalls.** Observe walks the entire live tree; on a long ListView
with many interactive rows, the candidates may exceed `limit` and
truncate. Narrow with `roles=button` first, then a second call with
`roles=textbox` if needed.

---

### dusk_screenshot

**Purpose.** Capture a base64-encoded image of the running app, or a
specific widget by ref, or a sub-rect within a widget.

**Input.**

| Param | Type | Required | Default | Note |
|---|---|---|---|---|
| `ref` | string | no | full viewport | Target a specific `e<N>` / `q<N>` |
| `rect` | string | no | full bounds | `"x,y,w,h"` logical pixels inside the ref's bounds |
| `format` | string | no | `jpeg` | `jpeg` or `png` |
| `quality` | integer | no | 70 | JPEG quality 1-100 |

**Returns.** `{ format, base64, width, height }`. JPEG q70 is typically
40-120 KB; PNG is 300-800 KB.

**Use it.** When the verification is visual (layout, colors, image
content) and the snapshot tree alone is not enough. For pure
correctness checks, snap is cheaper and faster than screenshot.

**Pitfalls.** The MCP payload carries the full base64 string; on slow
clients this can be lossy. Prefer ref-targeted screenshots when only one
widget matters.

---

## Find: query handles

### dusk_find

**Purpose.** Mint a re-resolvable `q<N>` handle that re-walks the live
Semantics tree on every action. Playwright Locator equivalent.

**Input.** At least one of:

| Param | Type | Note |
|---|---|---|
| `text` | string | Exact match on Text widget data or semantics label |
| `contains` | string | Substring match (looser; use when label is dynamic) |
| `semanticsLabel` | string | Exact match on `Semantics(label: ...)` only, ignores Text widgets |
| `key` | string | Stringified widget Key (`Key('login-submit')`) |

**Returns.** `{ ref: "q3", matched: true }` or `{ ref: null, matched: false }`.

**Use it.** For any retry-prone action: forms with validation errors,
async-loading content, navigation buttons that appear after a wait.
The same `q<N>` works after the widget rebuilds, after a scroll, after
a hot-reload (as long as the predicate still matches something).

**Pitfalls.** `dusk_find` returns the first match. When a label is not
unique, scope with `contains` plus another predicate, or use
`dusk_observe` to enumerate.

---

## Click family: tap, dblclick, right_click, triple_click, hover, drag

All gate-checked. All accept `ref` (required, `e<N>` or `q<N>`),
`checkStable` (default true), `checkReceivesEvents` (default true),
`includeSnapshot` (default true on click variants).

### dusk_tap

`ref` (required). Down + 50ms hold + Up at the widget's center.
Returns `{ ref, snapshot? }`.

### dusk_dblclick

`ref` (required). Two tap sequences ~100ms apart. Gate checked once
on the same ref. Returns `{ ref, snapshot? }`.

### dusk_right_click

`ref` (required). Secondary mouse button click. Returns
`{ ref, button: "right", snapshot? }`. Mouse-only.

### dusk_triple_click

`ref` (required). Three tap sequences ~100ms apart. Returns
`{ ref, clickCount: 3, snapshot? }`.

### dusk_hover

`ref` (required). PointerHoverEvent at the widget's center. Mouse-only;
on touch devices this is a no-op (`MouseRegion.onHover` will not fire
without a mouse pointer). Returns `{ ref, snapshot? }`.

### dusk_drag

`startRef` and `endRef` (both required). Down at start + 5 Move events
(16ms apart) + Up at end. Both endpoints gate-checked in order. Returns
`{ startRef, endRef, snapshot? }`.

---

## Text input: type, clear, press_key, focus, blur

### dusk_type

`ref` (required), `text` (required). Calls `userUpdateTextEditingValue`
on the resolved `EditableTextState`. This fires `onChanged` listeners,
which is what Wind / Magic form data bindings subscribe to. Gate
checked. Returns `{ text, snapshot? }`.

**Pitfall.** `dusk_type` REPLACES the field content, it does not
append. To add to existing text, snap or find the field, read its
current value, then type the concatenation.

### dusk_clear

`ref` (required), `includeSnapshot` (default false). Resolves the
TextEditingController and calls `.clear()`. No gate. Returns
`{ ref, text: "", snapshot? }`.

### dusk_press_key

`key` (required), `modifiers` (optional array of `control`, `shift`,
`alt`, `meta`). Synthesizes a `HardwareKeyboard` Down+Up. Targets the
currently focused widget, not a ref. Supported keys: `Enter`, `Tab`,
`Escape`, `Backspace`, `Delete`, `Space`, `ArrowUp`, `ArrowDown`,
`ArrowLeft`, `ArrowRight`, `Home`, `End`, `PageUp`, `PageDown`,
`F1`-`F12` (case-insensitive). Returns `{ ok: true, key, snapshot? }`.

**Pitfall.** Modifiers are reserved for future use; only the key
itself fires for now.

### dusk_focus

`ref` (required). Walks for a `Focus` ancestor or `EditableText` descendant
and calls `node.requestFocus()`. Returns `{ ref, focused: true, snapshot? }`.

### dusk_blur

`includeSnapshot` (default false). Calls
`FocusManager.instance.primaryFocus?.unfocus()` regardless of ref.
Returns `{ blurred: true, hadFocus, snapshot? }`.

---

## Form controls: set_checkbox, select_option

### dusk_set_checkbox

`ref` (required), `value` (required, `"true"` or `"false"`). Reads the
current Semantics `isChecked` flag; if it differs, taps the widget.
Idempotent (no-op when state already matches). Returns
`{ ref, previousValue, value, toggled, snapshot? }`.

### dusk_select_option

`ref` (required), `value` (required). Walks the ref subtree for a
`DropdownButton`, calls `onChanged(value)` directly. Skips the gate and
the popup walk. Returns `{ selected: true, value }`.

**Pitfall.** This only works on `DropdownButton`. For custom dropdowns
(bottom sheets, dialogs), tap to open then tap the option.

---

## Scroll

### dusk_scroll

| Param | Type | Required | Default | Note |
|---|---|---|---|---|
| `ref` | string | no | root scrollable | The scrollable to drive, or any widget within one |
| `dx` | number | no | 0 | Horizontal scroll in logical pixels |
| `dy` | number | no | 0 | Vertical scroll in logical pixels (positive = down) |
| `intoView` | boolean | no | false | When true with `ref`, calls `Scrollable.ensureVisible` instead of scrolling by delta |
| `includeSnapshot` | boolean | no | true | Append a post-scroll snapshot |

**Returns.** `{ scrolled: true, finalOffset, snapshot? }`.

**Use it.** Combine with `dusk_find` or `dusk_observe` to bring a
known-but-off-screen widget into reach, then `dusk_tap` it. The
actionability gate already auto-scrolls when a `Scrollable` ancestor
exists, so explicit `dusk_scroll` is only needed for nested scrollables
or horizontal scrolls where the gate's vertical default does not help.

---

## Wait

### dusk_wait_for

| Param | Type | Required | Default | Note |
|---|---|---|---|---|
| `text` | string | one-of | (none) | Wait for this text to appear |
| `textGone` | string | one-of | (none) | Wait for this text to disappear |
| `expression` | string | one-of | (none) | Treated as text-presence; no Dart eval here |
| `timeoutMs` | integer | no | 5000 | Hard cap; no maximum enforced |

**Returns.** `{ matched: true, elapsedMs }` or `{ matched: false, reason:
"timeout" }`. Polls every 200ms.

**Pitfall.** Use exactly one of `text` / `textGone` / `expression`. For
"wait until this widget is gone", `textGone` matches by text content,
not by ref disappearance. To wait for a ref to vanish, snap in a loop
until the ref is missing (or rely on `dusk_wait_for_network_idle` after
the action that should remove it).

### dusk_wait_for_network_idle

| Param | Type | Required | Default | Note |
|---|---|---|---|---|
| `timeoutMs` | integer | no | 5000 | Hard cap |
| `idleMs` | integer | no | 500 | Contiguous-zero window required |
| `pollIntervalMs` | integer | no | 200 | Minimum 100 |

**Returns.** `{ matched: true, idleAchievedMs }` or error envelope with
`type: "timeout", maxPending: <N>`.

**Use it.** After any action that fires HTTP (form submit, navigation
that loads data, manual refresh button). Combine with `dusk_wait_for`
on the success text for the strongest verification.

**Pitfall.** Requires `fluttersdk_telescope` wired via
`MagicTelescopeIntegration.install()`. Without it, pending-count is
constantly 0 and the call returns immediately with `matched: true`,
even when HTTP is in flight. Verify telescope is wired by calling
`dusk_console { limit: 1 }` first; an empty array on a busy app means
telescope is not active.

---

## Navigation

### dusk_navigate

`route` (required, must start with `/`), `includeSnapshot` (default
true). Tries three paths: (1) `Navigator.pushNamed(route)`, (2)
consumer-registered `DuskNavigateAdapter`, (3)
`SystemNavigator.routeInformationUpdated` (Router-based apps like
GoRouter, auto_route). Before navigating, dismisses every modal.

Returns `{ navigated: true|false, route, reason?, snapshot? }`. When
`navigated: false`, `reason` carries the diagnostic ("no navigator
found", "adapter rejected", "router did not accept").

### dusk_navigate_back

`includeSnapshot` (default true). Pops the top route if `canPop` is
true. Returns `{ navigatedBack: true, snapshot? }`.

### dusk_get_routes

No params. Returns `{ location: "<current-route-name>", title: "<page-title>" }`.

**Pitfall.** Despite the name, this does NOT enumerate every declared
route. It returns the current location only. To discover routes, snap
and look for nav buttons, or read the source.

### dusk_dismiss_modals

No params. Returns `{ popped: <count> }`. Pops every `PopupRoute`
subclass (dialog, bottom sheet) above the first persistent route.
Does not touch page routes.

---

## Diagnostics (telescope bridge)

### dusk_console

| Param | Type | Required | Default | Note |
|---|---|---|---|---|
| `limit` | integer | no | 50 | Newest-first cap |
| `minLevel` | string | no | (all) | `INFO`, `WARNING`, `ERROR`, etc. |

Returns `{ logs: [{ level, loggerName, message, time, error?, stackTrace? }], count }`.
Empty when telescope is not wired.

### dusk_exceptions

`limit` (default 20). Returns `{ exceptions: [{ exceptionType, message, time, stackTrace? }], count }`.
Empty when telescope is not wired.

---

## Evaluation (MCP-only)

### dusk_evaluate

`expression` (required, single Dart expression, no semicolons).
Evaluates in the running app isolate via the VM Service `evaluate`
RPC. Returns `{ expression, result: "<stringified result>" }`.

**Use it.** When state lives behind a singleton the agent cannot reach
through snap (e.g. `MyService.instance.state`,
`SharedPreferences.getInstance()`). For richer REPL needs (multi-line,
autocomplete, variable history), use `./bin/fsa tinker` instead.

**Pitfall.** No multi-statement input. Wrap in an immediately-invoked
closure if needed: `(() { final c = MyService.instance; return c.state.toString(); })()`.

---

## App control

### dusk_close_app

No params. Returns `{ closed: true }`. Calls `SystemNavigator.pop()`
on mobile / desktop, `SystemChannels.platform.invokeMethod` on web.
The browser may silently ignore `window.close()` when the tab was not
script-opened.

---

## Composite (substrate-routed)

### dusk_hot_reload_and_snap

`screenshot` (boolean, default true). Runs CLI-side because an
in-isolate handler cannot reload its own isolate. Sequence: write `r\n`
to the `flutter run` stdin, tail-poll the log for "Reloaded N
libraries" or a compile error, then call `ext.dusk.snap`,
`ext.dusk.screenshot`, `ext.dusk.exceptions`.

Returns on success:

```json
{
  "reloaded": true,
  "durationMs": 740,
  "snapshot": "<yaml>",
  "screenshot": "<base64 or null>",
  "recentExceptions": []
}
```

Returns on compile failure:

```json
{
  "reloaded": false,
  "durationMs": 215,
  "error": "lib/views/login.dart:42: Undefined name 'submitt'",
  "recentExceptions": []
}
```

When `reloaded: true` but `screenshot` returned an error, the payload
carries `screenshotError` alongside the successful snapshot.

**Use it.** As the main step of any edit-test loop. After editing a
file, one call returns enough state to reason about the result without
manual snap + screenshot + exceptions chaining.

---

## Device emulation (substrate-routed, CDP, web-only)

Both require the app launched with `artisan start --cdp-port=9222`.
On mobile, desktop, or web without the flag, returns
`CDP not enabled. Run artisan start --cdp-port=9222 first.`

### dusk_resize_viewport

| Param | Type | Required | Default | Note |
|---|---|---|---|---|
| `width` | integer | yes | -- | CSS pixels |
| `height` | integer | yes | -- | CSS pixels |
| `deviceScaleFactor` | number | no | 1.0 | Retina simulation |
| `mobile` | boolean | no | false | Mobile UA hints |
| `touch` | boolean | no | false | Touch emulation |
| `reset` | boolean | no | false | Clear all overrides |

### dusk_device_profile

| Param | Type | Required | Default | Note |
|---|---|---|---|---|
| `preset` | string | no | -- | One of the 8 presets below |
| `list` | boolean | no | false | Print presets, no CDP call |
| `reset` | boolean | no | false | Clear overrides |

Presets: `iphone-x` (375x812 @3.0), `iphone-13` (390x844 @3.0),
`iphone-15-pro` (393x852 @3.0), `pixel-5` (393x851 @2.75),
`pixel-8` (412x915 @2.625), `ipad-pro-12.9` (1024x1366 @2.0),
`desktop-1440` (1440x900 @1.0), `desktop-1920` (1920x1080 @1.0).

Sets viewport metrics + touch + user-agent + window bounds in one call.
