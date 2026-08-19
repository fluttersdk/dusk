# Frame production

Every dusk read and every dusk action depends on the app producing frames. When it stops, both go wrong at once and neither looks like a tooling problem. This page describes when that happens, what dusk does about it, and the one call that fixes it.

## When frame production stops

Flutter turns frame production off for three lifecycle states:

| `AppLifecycleState` | Frames |
|---|---|
| `resumed`, `inactive` | on |
| `hidden`, `paused`, `detached` | off |

On Flutter web, Chrome reports `document.visibilityState: "hidden"` as soon as the tab is backgrounded or its window falls behind another, and the engine maps that to `AppLifecycleState.hidden`. Starting the app detached is enough to land there without touching anything.

## What breaks, and why it reads as a product defect

Two separate symptoms, one cause:

- **A snapshot loses its text.** Semantics labels are rebuilt during a frame. With no frames, `dusk:snap` returns the buttons and none of the `- text` nodes, so a screen that renders perfectly reads as completely empty. This has been mistaken for "the dashboard is permanently stuck on loading skeletons"; the screen was fine and a screenshot proved it.
- **An action reports success and changes nothing.** A gesture is dispatched into the widget tree, but the frame that would apply it never runs. The handler returns a clean payload for a tap that could not possibly land.

## What dusk does

### Bounded settling

Handlers settle a gesture or an edit by awaiting one or two frames. Those awaits go through `awaitFrameOrTimeout` / `awaitFramesOrTimeout` and fall through after `kFrameSyncTimeout` (200ms per frame) rather than blocking on `WidgetsBinding.instance.endOfFrame`, which never completes while frames are off. Without the bound a `dusk:tap` against a hidden page sat for 45s+ with no output and no error until the caller's own timeout killed it.

A healthy engine is unaffected: a real frame lands in ~16ms and always wins the race.

### The `warnings` block

Every `ext.dusk.*` success payload gains a `warnings` key while frame production is off:

```json
{
  "snapshot": "...",
  "groupId": "snapshot-1700000000000",
  "warnings": {
    "framesEnabled": false,
    "lifecycleState": "hidden",
    "hint": "The engine is not producing frames, so the semantics tree is not being rebuilt and dispatched gestures cannot take effect. A backgrounded browser tab is the usual cause. Bring the page to front (CDP Page.bringToFront) and retry before trusting this result."
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `framesEnabled` | bool | Always `false` when the block is present. |
| `lifecycleState` | string \| null | The `AppLifecycleState` behind it (`hidden`, `paused`, `detached`), or null before the first lifecycle message. |
| `hint` | string | Fixed advisory naming the usual cause and the fix. |

The block is **omitted entirely** on a healthy engine, so its presence is itself the signal and a clean run carries no extra bytes.

**CLI banner.** Commands that summarise rather than print the raw envelope (`dusk:snap` prints only the tree, `dusk:tap` prints `✓ Tapped e7`) would drop the block, so they print a banner to **stderr** instead. stdout stays the payload:

```
⚠ The app is not producing frames (lifecycle: hidden). The semantics tree is not being
  rebuilt and gestures cannot take effect, so this result may be stale. A backgrounded
  browser tab is the usual cause: bring the page to front and retry.
```

## The fix

Bring the page to front over CDP before interacting:

```sh
# The app must have been started with a CDP port for this to be reachable.
./bin/fsa start --device=chrome --cdp-port=9333
```

```json
{ "method": "Page.bringToFront" }
```

One call flips the page back to `visible` and focused: the text nodes return, and a tap that hung answers immediately. When dusk behaves strangely on web, read `document.hidden` before concluding anything about the app.

Two blank-screen causes look identical and are not, so read the console entry count before deciding which one you have. A mounted tree with missing text is a hidden page and `Page.bringToFront` fixes it. Zero glass panes, zero canvases and **zero console lines** is a dead bootstrap instead, which no amount of bringing-to-front repairs; restart the run.

## Related

- [Actionability gate](actionability-gate.md): the six preconditions each gesture passes before dispatch.
- [Driving real apps: gotchas for agents](../getting-started/driving-real-apps-gotchas.md)
