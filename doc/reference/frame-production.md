# Frame production

Every dusk read and every dusk action depends on the app producing frames. When it stops, both go wrong at once and neither looks like a tooling problem. This page describes when that happens, what dusk does about it, and the fallback when it cannot.

## When frame production stops

Flutter turns frame production off for three lifecycle states:

| `AppLifecycleState` | Frames |
|---|---|
| `resumed`, `inactive` | on |
| `hidden`, `paused`, `detached` | off |

On Flutter web, Chrome reports `document.visibilityState: "hidden"` as soon as the tab is backgrounded or its window falls behind another, and the engine maps that to `AppLifecycleState.hidden`. Starting the app detached is enough to land there without touching anything.

On desktop the same state follows the window: hidden, minimised or fully occluded (macOS reports `hidden` after an occlusion event). Another app in front of a visible window is `inactive`, which still produces frames.

## What breaks, and why it reads as a product defect

Two separate symptoms, one cause:

- **A snapshot loses its text.** Semantics labels are rebuilt during a frame. With no frames, `dusk:snap` returns the buttons and none of the `- text` nodes, so a screen that renders perfectly reads as completely empty. This has been mistaken for "the dashboard is permanently stuck on loading skeletons"; the screen was fine and a screenshot proved it.
- **An action reports success and changes nothing.** A gesture is dispatched into the widget tree, but the frame that would apply it never runs. The handler returns a clean payload for a tap that could not possibly land. On a hidden macOS window a tap answered "no observable change" and a screenshot returned the last cached frame.

## What dusk does

### Frame forcing

Dusk wakes the engine itself. At the entry of every `ext.dusk.*` verb, when `SchedulerBinding.framesEnabled` is false and the lifecycle is `hidden` or `paused`, `ensureFramesProduced()` delivers `AppLifecycleState.inactive` through the `flutter/lifecycle` channel, the message the engine itself sends, and schedules a forced frame; once a frame has run it delivers `resumed`. (`inactive` first, because Flutter drops a message equal to the current state, which would hide a real engine `resumed` arriving during the wait.) `detached` and a null lifecycle are never forced: the first means the engine is going away, the second that it has not reported a state yet.

The wake counts only when a frame actually runs within `kFrameSyncTimeout` after it. If none does, dusk delivers the previous lifecycle again and the call proceeds as if it had not tried, so the `warnings` block below stays. That check stops a wake that did nothing (an asleep display) from being reported as forced. On web the wake is not attempted: see [Web](#web).

A response whose call had to force carries `framesForced: true`, so you know the app was occluded even though the result is fresh:

```json
{ "ref": "e7", "effect": { "kind": "treeChanged", "changed": true }, "framesForced": true }
```

The force is re-applied on every call, not once, because the OS flips the lifecycle back to `hidden` on its next occlusion event.

Verbs that must observe the engine as it is skip it: `perf_begin`, `perf_end`, `perf_insight`, `perf_trace`, `boot_id`, `close_app`, `console`, `exceptions`, `semantics_hold` and `evaluate`.

**Side effect.** The app's own lifecycle observers see `resumed` while its window is still hidden. An app that pauses work or tears down a socket on `hidden` will not have done so by the time dusk acts.

The same applies to routes: reading a ref's route (for `e<N>` relocation) uses `ModalRoute.of`, which makes each labelled element depend on its route's modal scope. A snapshot can therefore rebuild an element, and run its `didChangeDependencies`, when its route's status changes (a push or pop over it). Flutter offers no public way to read the route without that dependency.

**Opt-out.** Build the app with `--dart-define=DUSK_FORCE_FRAMES=false` (`kDuskForceFrames`) to leave a hidden app frameless. Every response then carries the `warnings` block below.

### macOS

Verified live with the window hidden (`osascript -e 'tell application "System Events" to set visible of process "<App>" to false'`): `dusk:tap`, `dusk:snap`, `dusk:screenshot` and `dusk:navigate` all work once the lifecycle is forced. Before forcing, taps reported "no observable change", snapshots went stale and screenshots returned the last cached frame.

One caveat remains: an asleep display can still starve frames. `caffeinate -u -t 3` wakes the display; that it fixes dusk's case has not been verified here.

### Web

A hidden Chrome tab has its `requestAnimationFrame` callbacks withheld by the browser, so no lifecycle message can make a frame run there; dusk does not attempt the wake on web, which would cost every verb a 200 ms wait and four lifecycle callbacks in the app for nothing. Verified live with a second tab in front: a tap answered `effect.changed: false` with the `warnings` block (`platform: web`, `lifecycleState: hidden`) and no `framesForced`; after the app tab was activated through CDP the same tap applied. On web the fix stays [`Page.bringToFront`](#the-fallback).

### Bounded settling

Handlers settle a gesture or an edit by awaiting one or two frames. Those awaits go through `awaitFrameOrTimeout` / `awaitFramesOrTimeout` and fall through after `kFrameSyncTimeout` (200ms per frame) rather than blocking on `WidgetsBinding.instance.endOfFrame`, which never completes while frames are off. Without the bound a `dusk:tap` against a hidden page sat for 45s+ with no output and no error until the caller's own timeout killed it.

A healthy engine is unaffected: a real frame lands in ~16ms and always wins the race.

### The `warnings` block

When dusk could not force frames (the opt-out above, a `detached` lifecycle, or a wake that produced no frame, or any hidden web tab) every `ext.dusk.*` success payload gains a `warnings` key while frame production is off:

```json
{
  "snapshot": "...",
  "groupId": "snapshot-1700000000000",
  "warnings": {
    "framesEnabled": false,
    "lifecycleState": "hidden",
    "platform": "web",
    "hint": "The engine is not producing frames, so the semantics tree is not being rebuilt and dispatched gestures cannot take effect. A backgrounded browser tab is the usual cause. Bring the page to front (CDP Page.bringToFront) and retry before trusting this result."
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `framesEnabled` | bool | Always `false` when the block is present. |
| `lifecycleState` | string \| null | The `AppLifecycleState` behind it (`hidden`, `paused`, `detached`), or null before the first lifecycle message. |
| `platform` | string | `web`, or the `TargetPlatform` name (`macOS`, `windows`, `linux`, `iOS`, ...). |
| `hint` | string | Advisory for that platform. Web names a backgrounded tab and CDP `Page.bringToFront`; desktop names a hidden, minimised or occluded window or an asleep display and says to bring the window to front. |

The block is **omitted entirely** on a healthy engine, so its presence is itself the signal and a clean run carries no extra bytes.

**CLI banner.** Commands that summarise rather than print the raw envelope (`dusk:snap` prints only the tree, `dusk:tap` prints `✓ Tapped e7`) would drop the block, so they print a banner to **stderr** instead. stdout stays the payload. On web:

```
⚠ The app is not producing frames (lifecycle: hidden), so this result may be stale. A
  backgrounded browser tab is the usual cause: bring the page to front and retry.
```

On desktop the second sentence reads "The window is hidden, minimised or occluded, or the display is asleep: bring the window to front and retry."

## The fallback

Forcing covers a hidden desktop window. It cannot cover a hidden browser tab, the opt-out, `detached` or an asleep display: bring the target to front yourself.

On web, over CDP:

```sh
# The app must have been started with a CDP port for this to be reachable.
./bin/fsa start --device=chrome --cdp-port=9333
```

```json
{ "method": "Page.bringToFront" }
```

One call flips the page back to `visible` and focused: the text nodes return, and a tap that hung answers immediately. When dusk behaves strangely on web, read `document.hidden` before concluding anything about the app.

On desktop, activate the window (macOS: `osascript -e 'tell application "<App>" to activate'`) and retry.

Two blank-screen causes look identical and are not, so read the console entry count before deciding which one you have. A mounted tree with missing text is a hidden page: `Page.bringToFront` fixes it on web, forcing on desktop. Zero glass panes, zero canvases and **zero console lines** is a dead bootstrap instead, which no amount of bringing-to-front repairs; restart the run.

## Related

- [Actionability gate](actionability-gate.md): the six preconditions each gesture passes before dispatch.
- [Driving real apps: gotchas for agents](../getting-started/driving-real-apps-gotchas.md)
