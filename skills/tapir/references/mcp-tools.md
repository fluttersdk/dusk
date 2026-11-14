# MCP tools reference

Every `tapir_*` tool `TapirDowelProvider.mcpTools()` registers: parameters, return shape, and the traps. Look up the tool you are about to call; nobody needs all of them in one session.

## Contents

- [How calls work](#how-calls-work)
- [See: snap, observe, screenshot](#see-snap-observe-screenshot)
- [Find](#find)
- [Pointer: tap, dblclick, right_click, triple_click, hover, drag](#pointer-tap-dblclick-right_click-triple_click-hover-drag)
- [Text and keys: fill, type, clear, press_key, focus, blur](#text-and-keys-fill-type-clear-press_key-focus-blur)
- [Form controls: set_checkbox, select_option](#form-controls-set_checkbox-select_option)
- [Scroll](#scroll)
- [Wait](#wait)
- [Navigation and overlays](#navigation-and-overlays)
- [Diagnostics](#diagnostics)
- [App control](#app-control)
- [Performance](#performance)
- [Substrate-routed: run, hot reload, viewport](#substrate-routed-run-hot-reload-viewport)

## How calls work

The MCP server is dowel's (`./bin/dowel mcp:serve` or `dart run tapir mcp:serve`, client key `dowel`). Most tools call an `ext.tapir.*` extension inside the app isolate. `tapir_run`, `tapir_hot_reload_and_snap`, `tapir_perf_run`, `tapir_perf_compare`, `tapir_perf_trace`, `tapir_resize_viewport` and `tapir_device_profile` run a `dowel:tapir:*` command in the server's process instead.

Every schema is closed (`additionalProperties: false`): an argument a tool does not list is refused with `Additional property "..." is not allowed`. A few knobs exist only on the CLI or for the perf runner (`tapir:resize --hold`, screenshot `geometry`, coordinate taps); do not send them over MCP.

An error is a JSON string with the human message and a machine envelope:

```json
{
  "message": "Widget ref=e7 is not actionable: not stable (rect changed by 1.2px)",
  "envelope": { "type": "not_stable", "widget_path": "e7", "suggestions": [] }
}
```

`envelope.type` is one of `timeout`, `not_found`, `obscured`, `disabled`, `stale`, `zero_rect`, `off_viewport`, `not_stable`, `missing_param`, `unexpected`. A `not_found` error lists up to three near matches in `suggestions`. The gate's reason substring sits verbatim inside `message`.

Keys any success payload can carry:

| Key | Meaning |
|---|---|
| `framesForced: true` | A hidden or paused app was woken for this call. Normal. Not done by the perf verbs, `console`, `exceptions`, `close_app` and `evaluate`; `--dart-define=TAPIR_FORCE_FRAMES=false` turns it off. |
| `warnings: {framesEnabled, lifecycleState, platform, hint}` | The app is not producing frames and could not be woken (a hidden browser tab, the opt-out, a `detached` app). The result cannot be trusted; follow `hint` and retry. Absent on a healthy engine. |
| `reresolved: ["e5"]` | A stale `e<N>` was relocated by label to the control that replaced it. |
| `checks: {receivesEvents, why?, overlapCandidates?, hint?}` | Gate step 5 could not confirm the target (`indeterminate`) or was skipped (`skipped`). Absent when confirmed. |
| `effect` | What the widget holds after the action; see each verb. |

The `snapshot` parameter (`full`, `diff`, `none`) overrides `includeSnapshot` on the tools that accept it. `diff` returns only the lines changed since the last unfiltered snapshot: a changed row is `- <old>` then `+ <new>`, then a `(K of N lines changed)` footer, and the payload adds `snapshotMode: "diff"`. A filtered `tapir_snap` (`grep`, `within`, `depth`, `interactiveOnly`) records no baseline, and a hot restart clears it, so the next diff is the full text.

## See: snap, observe, screenshot

### tapir_snap

| Param | Type | Default | Note |
|---|---|---|---|
| `depth` | integer | full tree | Maximum depth from the root |
| `within` | string | whole tree | `e<N>` of the subtree to walk; a `q<N>` is not accepted, an unknown ref is an error |
| `interactiveOnly` | boolean | false | Only ref-bearing nodes, no `- text` lines |
| `grep` | string | none | Nodes whose label or value match the regex, plus their ancestors; an invalid regex is matched as text and the payload adds `grepLiteral: true` |
| `includeEnrichers` | boolean | false | Magic, Wind and custom enricher lines under each ref |

Returns `{ snapshot: "<yaml>", groupId }`. A node line is `- <role> "<label>" [ref=eN]`, roles `textbox`, `checkbox`, `link`, `heading`, `image`, `button`. It may end with ` [offscreen]` or ` [occluded]`, and carry sub-lines `overflow: true` (inside an overflowing ancestor), `typeable: true` (the node `tapir_type` writes to when a field has two nested `textbox` nodes) and `tapOwner: {"x":..,"y":..,"w":..,"h":..}` (a merged boundary's own control). A `MergeSemantics` control is one line on its boundary. When non-fatal render errors were captured the payload adds `renderErrors: {count, recent: [{type, message}], hint}`.

### tapir_observe

| Param | Type | Default | Note |
|---|---|---|---|
| `intent` | string | none | Your own note; not used by the handler |
| `roles` | string | all | Comma list of `button`, `textbox`, `link`, `checkbox`, `heading`, `image` |
| `limit` | integer | 50 | Candidate cap |
| `includeEnrichers` | string | `"true"` | `"true"` (`magicFormField`, `magicRoute`, `magicGateResult`, `wind.breakpoint`, `wind.states`), `"false"`, or `"full"` |

Returns `{ candidates: [{ ref, role, label, value, bounds, isEnabled, isVisible, inViewport, occluded, tapOwner?, ...enricher fields }] }`. Each `ref` is a `q<N>`; a labelled candidate also carries its position among same-label nodes, so rows offering one action stay distinct while the list is unchanged; after a same-label row is added or removed the handle selects a neighbour and the action still succeeds, so observe again. An unlabelled candidate has no position: its handle matches its value text (and can land on another control with the same text), and one with no value is stale at once, so use a snapshot ref or a `key` for those. A long list can exceed `limit`; narrow with `roles`.

### tapir_screenshot

| Param | Type | Default | Note |
|---|---|---|---|
| `ref` | string | whole viewport | Capture only this widget (`e<N>` or `q<N>`) |
| `rect` | string | ref bounds | `"x,y,w,h"` relative to the ref; without `ref` it is an error |
| `format` | string | `jpeg` | `jpeg` or `png` |
| `quality` | integer | 70 | JPEG quality |

Returns `{ format, base64, width, height }`. Prefer `ref`: a full tall page costs far more tokens and buries the component. On web the in-isolate capture can hang under CanvasKit; use the CLI `tapir:screenshot --ref=<ref> -o <path>`, which falls back to CDP `Page.captureScreenshot` when the session has a `cdpPort`.

## Find

### tapir_find

| Param | Type | Note |
|---|---|---|
| `text` | string | Exact match on the accessibility label, then `Text.data` |
| `contains` | string | Case-sensitive substring of the same; for dynamic labels |
| `semanticsLabel` | string | Exact match on `SemanticsNode.label` only |
| `key` | string | A widget `Key`; for a `ValueKey` pass the value's `toString()` |
| `within` | string | `e<N>` of the region to search; stored in the handle, so the scope survives every re-resolve |

At least one of the first four; `within` alone is refused. Predicates are not all intersected: the resolver takes the first of these that is set and ignores the others except as noted. `key` wins (a `text` beside it must also appear in a `Text` below the widget; `semanticsLabel` and `contains` are ignored); then `semanticsLabel` (exact label; `text` and `contains` are ignored); then `text`; then `contains`. `within` bounds whichever one applies. When `semanticsLabel` or `text` meets several nodes with that label, the first interactive one wins, and the first in tree order only when none is. Returns `{ ref: "q<N>", matched: true, matchCount, diagnostic? }`, or `{ ref: null, matched: false, diagnostic? }` (the diagnostic names a scope that no longer resolves). `diagnostic` appears when `matchCount > 1`: the handle points at the first match, so narrow the predicate.

## Pointer: tap, dblclick, right_click, triple_click, hover, drag

All run the actionability gate and accept `snapshot`, `includeSnapshot` (default true), `checkStable` and `checkReceivesEvents` (default true).

| Tool | Params | Returns | Gesture |
|---|---|---|---|
| `tapir_tap` | `ref`, `retarget` (default true), `until`, `untilTimeoutMs` (default 3000) | `{ ref, effect: {kind: "treeChanged", changed}, untilMatched?, retargeted?, tapPointOutsideOwner? }` | Down, 50ms, Up at the live centre, re-read after the gate |
| `tapir_dblclick` | `ref` | `{ ref }` | Two taps about 100ms apart, one gate |
| `tapir_right_click` | `ref` | `{ ref, button: "right" }` | Secondary mouse button |
| `tapir_triple_click` | `ref` | `{ ref, clickCount: 3 }` | Three taps about 100ms apart |
| `tapir_hover` | `ref` | `{ ref }` | Mouse hover at the centre; does nothing on a touch-only target |
| `tapir_drag` | `startRef`, `endRef` | `{ startRef, endRef }` | Down, five moves 16ms apart, Up; both ends gated |

`tapir_tap` on a merged boundary goes to its one labelled control and adds `retargeted: {from, to, ownerRect, centreHandled?}`; `centreHandled: true` means the centre has its own handler, and `retarget: false` taps the centre. When retargeting is unsafe (several candidates, the control covered or off screen) the tap stays at the centre and adds `tapPointOutsideOwner: {ownerRect, point}`. Only `tapir_tap` retargets. `until` polls the live tree for a `Text` equal to the value after the tap.

## Text and keys: fill, type, clear, press_key, focus, blur

### tapir_fill

`ref`, `text` (required; `""` clears), `includeSnapshot` (default true), `snapshot`, `checkStable`, `checkReceivesEvents`. Focus, clear, type and a two-frame settle in one call, retried once when the ref goes stale mid-fill; prefer a `q<N>` so that retry can re-resolve. Returns `{ ref, text, filled: true, effect }`.

`effect` is `{kind: "text", verified, value, target: {matchKind, label, rect}}`. `value` is read after the settle, so a formatter or echo that reverts the write gives `verified: false`. `matchKind` is `overlap`, `nearest` or `element`; on `nearest` the ref overlapped no field and the nearest one was written. A ref that is a button, checkbox, radio, switch, slider or link is refused with `ref eN is a <role>, not a text field`.

### tapir_type

`ref`, `text` (required), `snapshot`, `includeSnapshot`, `checkStable`, `checkReceivesEvents`. Gated. Writes through `userUpdateTextEditingValue`, so `onChanged` and validators fire. It replaces the content; to append, read the value and type the whole string. Returns `{ text, effect }` with the same `effect` as fill.

### tapir_clear

`ref` (required), `includeSnapshot` (default false). Not gated. Clears the field's controller. Returns `{ ref, text: "", effect }`.

### tapir_press_key

`key` (required), `modifiers`, `snapshot`, `includeSnapshot`. Not gated and not aimed at a ref: the key goes to the focused widget through the binding's key data path, so `Focus.onKeyEvent`, `Shortcuts` and `CallbackShortcuts` hear it. Keys: `Enter`, `Tab`, `Escape`, `Backspace`, `Delete`, `Space`, `ArrowUp`, `ArrowDown`, `ArrowLeft`, `ArrowRight`, `Home`, `End`, `PageUp`, `PageDown`, `F1` to `F12`, or one letter or digit. `modifiers` is a list of `control` (or `ctrl`), `shift`, `alt`, `meta`, held before the key and released after it even when delivery throws; an unknown name fails before anything is pressed. Text goes through `tapir_type`, not key presses. Returns `{ ok: true, key }`.

### tapir_focus, tapir_blur

`tapir_focus`: `ref` (required), `includeSnapshot` (default false); requests focus on the nearest `Focus` (or the field's own) node. Returns `{ ref, focused: true }`. `tapir_blur`: `includeSnapshot`; unfocuses whatever holds focus. Returns `{ blurred: true, hadFocus }`.

## Form controls: set_checkbox, select_option

### tapir_set_checkbox

`ref`, `value` (`"true"` or `"false"`), both required. Not gated. Reads the state from the first that applies: (1) the ref's own node carries a checked or toggled flag, which is the state even when a merging tile has folded several controls into that node (they cannot be told apart, so this is never refused as ambiguous); (2) the own node carries none and exactly one descendant node does, which is read and tapped at its own centre; (3) a ref minted without a node (a `find_by_text` entry) whose render object owns none takes the nearest node above it, from that node's own flag only, never its subtree. It is refused when none of these finds a state, and when the own node carries no flag and several descendants do. So a checkbox, switch or radio from any library works: Flutter material, `material_ui`, `wind_kit` or a hand-built `Semantics(checked: ...)`. It taps only when the state differs and reads it back. Returns `{ ref, previousValue, value, toggled, effect: {kind: "checked", verified, before, after} }`. A missing state is never assumed unchecked. A mixed checkbox is always tapped once and reports `previousValue: null`. When the state already equals `value` it does not tap and returns `toggled: false`. The tap goes to the control whose state was read. Being ungated, it does not scroll: an `[offscreen]` or covered control is missed and reads `verified: false`, so bring it on screen first with `tapir_scroll` on the containing list (its ref or the ref of a visible row). Do not `tapir_tap` the control to reveal it: the tap activates it, so the value can change before the read, and a value that already matched gets toggled twice. The `tapir:set_checkbox` CLI exits 1 on `verified: false`, except with `--json` or `--includeSnapshot`, which print the response and exit 0.

### tapir_select_option

`ref`, `value`, both required. Not gated. Calls the `onChanged` of the first `DropdownButton` at or under the ref with `value` as a string, so the dropdown's value type has to be `String`. Returns `{ selected: true, value, effect: {kind: "selected", verified, value} }`. A custom picker (bottom sheet, menu) needs a tap to open and a tap on the option.

## Scroll

### tapir_scroll

| Param | Type | Default | Note |
|---|---|---|---|
| `ref` | string | first `Scrollable` | A widget inside the scrollable to drive |
| `direction` | string | `down` | `up`, `down`, `left`, `right` |
| `pixels` | number | 300 | Distance for `direction` |
| `dx`, `dy` | number | none | Signed delta in logical pixels (positive is right, down); wins over `direction` |
| `intoView` | boolean | false | `Scrollable.ensureVisible` on `ref` instead of a delta |
| `snapshot`, `includeSnapshot` | | true | Post-scroll snapshot |

Not gated; a delta is a `jumpTo` clamped to the extents. Returns `{ scrolled, finalOffset, effect: {kind: "scrollOffset", changed, before, after} }`; `scrolled: false` means nothing moved (no scrollable around the ref, or already at the edge). Re-snap after: an off-screen row gets a ref only once Flutter builds it. The gate already scrolls a target into view under one `Scrollable`; reach for this for nested or horizontal lists.

## Wait

### tapir_wait_for

`text`, `textGone` or `expression` (one of them; with several the first in that order wins), `timeoutMs` (default 5000). Polls every 200ms for a `Text` with that exact data. `expression` is matched as text, not evaluated. Returns `{ matched: true, elapsedMs }`, or `{ matched: false, reason: "timeout" }` as a normal result, so check `matched`.

### tapir_wait_for_network_idle

`timeoutMs` (5000), `idleMs` (500, the contiguous zero window), `pollIntervalMs` (200, minimum 100). Returns `{ matched: true, idleAchievedMs }`; a timeout is an error of type `timeout` whose message names `maxPending`. The in-flight count comes from crumbs, a separate package that is not published yet: without it the count is always 0 and the call returns `matched: true` at once, so assume it always reports idle.

## Navigation and overlays

### tapir_navigate

`route` (required, starts with `/`), `snapshot`, `includeSnapshot` (default true). Dismisses open modals, then pushes through the registered `TapirNavigateAdapter` (on a Magic app, typically `MagicRoute.to`), else `Navigator.pushNamed`, else a route-information update every `Router` hears. Two frames later it reads the mounted Router: `{ navigated, route, exactPath, reason? }`. `navigated: true` covers a page under the route (`/monitors/7` for `/monitors`); `exactPath: true` only for the route itself; `navigated: false` carries `reason` (dropped or redirected). A Navigator 1.0 app has no Router to read, so a push that landed there also reports `navigated: false`: check with a snapshot. Refs from before the navigation are gone; re-snap.

### tapir_navigate_back

`snapshot`, `includeSnapshot` (default true). Pops the outermost Navigator that can pop, a page stacked inside a shell included; a branch hidden offstage (a `StatefulShellRoute`) is skipped. Returns `{ navigatedBack, popped }`; `false` means nothing could pop.

### tapir_get_routes

No params. Returns `{ location, title, uri }`. `uri` is the mounted Router's location (null before one mounts); `location` is the root Navigator's top page name, empty in a Router-based app. It does not list declared routes.

### tapir_dismiss_modals, tapir_reset_overlays

`tapir_dismiss_modals`: no params; pops every `PopupRoute` (dialog, sheet, popup menu) on every Navigator. Returns `{ popped }`. `tapir_reset_overlays`: no params; pops every `PopupRoute`, then presses Escape, then taps a Cancel, Dismiss, Close, OK or Done affordance, each layer a no-op once the screen is clear. Returns `{ popped, escaped, dismissTapped }`. Use it for an overlay that is not a `PopupRoute` (an `OverlayEntry`, a barrier dialog); it is safe to call between flows.

## Diagnostics

### tapir_console

`limit` (50), `minLevel` (`INFO`, `WARNING`, `ERROR`). Returns `{ logs: [{ level, message, time, logger }], count }`: the app's own `debugPrint` output (logger `debugPrint`, newest first; a direct Dart `print` does not go through `debugPrint` and is not captured) followed by crumbs log entries when crumbs is wired. The two lists are appended, not sorted by `time`, and the `limit` clip cuts from the end, so a newer crumbs entry can sit below an older buffered one or be cut; sort by `time` yourself when order matters. A direct `developer.log` call is not captured.

### tapir_exceptions

`limit` (20), `since` (ISO 8601; only entries strictly after it), `clear` (empty tapir's buffer after the read). Returns `{ exceptions: [{ type, message, stackHead, library, fatal, time }], count }`, deduped and newest first; a layout overflow has `type: "overflow"`. Tapir keeps its own non-fatal `FlutterError` buffer and merges crumbs when wired. The buffer is cumulative: one boot-time fault rides along on every later read, so pass `clear: true` between routes or pin a `since`.

## App control

### tapir_evaluate

`expression` (required). Over MCP, dowel's server answers the call itself with the VM Service `evaluate` RPC in the app's root library, so anything imported by `lib/main.dart` is in scope; an expression with `await` is wrapped in an async closure that the VM evaluates without waiting, so you get the `Future`, not its value. Returns `{ expression, result }`. A runtime exception, a compile error and a stale isolate (after a hot restart) come back as error results. Use it for a one-off expression; `dowel_tinker { eval: "..." }` and `./bin/dowel tinker --eval="..."` evaluate the same way. The `ext.tapir.evaluate` extension is a debug-only sentinel that never evaluates by itself.

### tapir_close_app

No params. Calls `SystemNavigator.pop()` and answers `{ closed: true }`. A browser may ignore the close of a tab it did not open by script, and then the app and its VM Service stay up. Where the app does close, the next call finds no app.

## Performance

### tapir_perf_begin

`mode` (`attribution`, the default, profiles builds; `timing` touches no profiling flag), `phases` (attribution only: also layout and paint). Zeroes the frame buffer and the Wind and Magic counters and records the liveness baseline. Returns `{ sessionToken, mode, phases, livenessBaseline, restartedPreviousSession }`; a begin on an open session restarts it. Drive one interaction, then end.

### tapir_perf_end

No params. Returns `{ sessionToken, refused, mode, env, coverage, summary, counters, insights, omitted }` and restores every profiling flag to its earlier value. Read `refused` first: when the engine drew nothing the payload has `refused: true`, a `reason` and no metrics, and the perf verbs do not wake a hidden app. Then read `coverage.missing` (a source never read: `wind`, `blocks`, `blockSelfTime`). `summary.blocksBySelf` ranks by exclusive time. `insights` (id `I<n>`, `severity`, `title`, `evidence`, `estimatedSavingsMs?`, `nextStep`) are sorted by severity, then savings. Attribution milliseconds are inflated by profiling; compare milliseconds only between timing sessions.

### tapir_perf_insight

`id` (required, `I<n>`), `token` (the report's `sessionToken`; another session's is refused). Returns `{ sessionToken, id, severity, title, summary, detail, estimatedSavingsMs, nextStep }`; `detail` holds the rows behind it. Only the last closed session is kept.

### tapir_perf_run (substrate)

`scenario` (required, a YAML path), `variant`, `label` (`[a-z0-9_-]`, default `run`), `out` (default `build/perf`), `repeat`, `platform` (`chrome`, `android`, `ios`), `timing`, `against`, `semantics-pass`, `json`. Runs the scenario several times from a clean start (hot restart, or a relaunch on a profile build) and writes `<out>/<scenario>-<label>.json` with medians, spread, insights and every repeat. A refused repeat is left out of the medians; the call fails only when all refused. Chrome needs the app started with a CDP port.

### tapir_perf_compare (substrate)

`a`, `b` (required, run files), `json`. Judges `b` against `a` on counts per painted frame, never raw counts (a run that drew fewer frames would read as faster), and on milliseconds only from timing-mode medians. Returns `{ verdict, thresholds, frames, rows, unchanged, timing }`; fails on an error-level regression.

### tapir_perf_trace (substrate)

`out` (required), `token`. Writes the last closed session as Chrome Trace JSON (ui.perfetto.dev, chrome://tracing) and returns only the path. Export before the next `tapir_perf_begin`, which clears the frames it reads.

## Substrate-routed: run, hot reload, viewport

### tapir_run

`steps` (required, verb lines without `tapir:`, such as `"tap --ref=q3"`, `"fill --ref=q1 --text=\"a b\""`, `"snap --grep Total"`), `continue` (default false). Each step is tokenised like a shell and takes that command's own flags. The answer is one line per step (`[1/3] tap --ref=q3 ok: <first output line>`) and then the last step's full output; it stops at the first failure with `step N failed (exit C): <step>`, and `continue: true` runs every step. A step cannot be another `run` or a verb that does not use the connected app (`resize`, `device`, `install`, `doctor`, `perf_campaign`, `perf_compare`); one that ends the app (`close_app`, `perf_run`) goes last.

### tapir_hot_reload_and_snap

`screenshot` (default true). Sends `r` to the `flutter run` of the dowel session, waits for the reload or a compile error, then snaps, screenshots and reads exceptions. Returns `{ reloaded: true, durationMs, snapshot, screenshot, recentExceptions }` (a failed capture adds `screenshotError`), or `{ reloaded: false, durationMs, error, recentExceptions }` as an error result. Read `recentExceptions` even on success.

### tapir_resize_viewport

`width`, `height` (required unless `reset`), `dpr` (1.0), `mobile`, `touch`, `reset`. Sets a CDP viewport override on Chrome. Needs the session started with `--cdp-port`, otherwise `CDP not enabled`. The override ends when the call returns; `./bin/dowel tapir:resize ... --hold` in the background keeps it.

### tapir_device_profile

`preset`, `list`, `reset`. Presets: `iphone-x`, `iphone-13`, `iphone-15-pro`, `pixel-5`, `pixel-8`, `ipad-pro-12.9`, `desktop-1440`, `desktop-1920`. Sets viewport, pixel ratio, touch, user agent and window size; only the window size outlasts the call. Same CDP requirement as resize.
