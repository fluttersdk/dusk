# Driving real apps: gotchas for agents

The recurring traps of a long real-app E2E session, each with the workaround `tapir` has built in.

Every agent re-discovers these the hard way. Read the page once before driving a non-trivial
app; it will save you a dozen dead-end round trips.

- [Quick Reference](#quick-reference)
- [1. Refs go stale on rebuild](#1-refs-go-stale-on-rebuild)
- [2. Text fields may snapshot nested](#2-text-fields-may-snapshot-nested)
- [3. tapir:console captures debugPrint in-package now](#3-tapirconsole)
- [4. tapir:exceptions is cumulative](#4-tapirexceptions-is-cumulative)
- [5. restart preserves the CDP port](#5-restart-preserves-the-cdp-port)
- [6. Overlays get stuck](#6-overlays-get-stuck)
- [7. A green tick is dispatch, not effect](#7-a-green-tick-is-dispatch-not-effect)
- [8. A hidden desktop app](#8-a-hidden-desktop-app)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

| Trap | Use |
|:-----|:----|
| An `e<N>` ref fails after a rebuild or navigation. | Re-snap with `tapir:snap`, or mint a `q<N>` handle with `tapir:find` / `tapir:observe`. |
| A text field snapshots as two nested `textbox` nodes. | Target the node marked `typeable: true`, or use `tapir:fill`. |
| `tapir:console` misses `debugPrint` output. | Nothing to do: `TapirPlugin.install()` captures it in-package. |
| `tapir:exceptions` keeps reporting an old error. | Pass `--since=<iso8601>` recorded before the action. |
| A web restart loses the CDP port. | Nothing to do: `restart` reuses the recorded `cdpPort`. |
| A dialog, sheet or menu blocks the next screen. | Run `tapir:reset_overlays`. |
| A green tick with no visible result. | Read the `effect` block on the response. |
| A hidden desktop app reports no change. | Nothing by default; read `framesForced` and `warnings` on the response. |

---

<a name="1-refs-go-stale-on-rebuild"></a>
## 1. Refs go stale on rebuild

`e<N>` refs from `tapir:snap` freeze the widget at snapshot time. A navigation,
a modal open/close, a `setState`, or any significant rebuild invalidates them:
the next action on a stale `e<N>` fails with a not-found or stale envelope.

**Workaround:**

- Re-snap (`tapir:snap`) after any action that changes the screen, and use the
  fresh refs.
- For a target that survives re-renders (a stable `Text`, accessibility label,
  or `Key`), prefer `tapir:find` / `tapir:observe`, which mint a re-resolvable
  `q<N>` handle that re-walks the live tree on every action call. `q<N>`
  handles survive rebuild, route push, and snapshot disposal as long as the
  predicates still match.
- Pointer verbs (`tapir:tap`, `tapir:hover`, `tapir:drag`, ...) now dispatch at the
  element's LIVE rect, not the cached snapshot rect, so a target that merely
  shifted slots (same `Element`/`RenderObject`) is still hit correctly. The
  false-success class (gate passes, pointer lands on the stale position,
  `onTap` never fires) is gone for slot shifts.
- An `e<N>` ref whose widget was rebuilt is relocated by its label when the live
  tree still has the same number of nodes with that label on the same route,
  and the response names it under `reresolved`. When the count differs, or
  you have navigated to another route, the ref still fails as
  `defunct (element no longer mounted)`; re-snap.

---

<a name="2-text-fields-may-snapshot-nested"></a>
## 2. Text fields may snapshot nested

A wind `WInput` (and any `TextField` wrapped in `Semantics(textField: true)`)
historically snapshotted as TWO nested `textbox` nodes, because `RenderEditable`
unconditionally owns its own `textField` Semantics node and `MergeSemantics`
cannot absorb it. Agents naturally targeted the inner leaf, where `tapir:type`
threw a `-32000`.

**Workaround:**

- `tapir:snap` now collapses the nested pair (by render-object containment, never
  label/value equality, so two sibling fields sharing a label stay distinct) and
  emits a single ref for the outer node, marked `typeable: true`. Target the
  node carrying `typeable: true`.
- Better: use `tapir:fill --ref=<ref> --text=<value>`, which focuses, clears,
  types, and settles in one call (and retries once on a stale handle). It
  resolves the right editable for you and composes the gated focus/clear/type
  handlers, so you do not re-build the focus + clear + type + settle dance.

---

<a name="3-tapirconsole"></a>
## 3. tapir:console captures debugPrint in-package now

`tapir:console` historically surfaced full structured logs only when
`crumbs` was installed and wired.

**Workaround:**

- `TapirPlugin.install()` now chains a `debugPrint` override that records every
  `debugPrint(...)` / `print(...)` call into a bounded in-package ring buffer,
  so those entries appear in `tapir:console` even without crumbs.
- When crumbs IS installed it enriches the output with `Logger.root.onRecord`
  entries and its other watchers. Direct `dart:developer log()` calls that
  bypass `debugPrint` still require the crumbs `LogWatcher`.

---

<a name="4-tapirexceptions-is-cumulative"></a>
## 4. tapir:exceptions is cumulative

`tapir:exceptions` returns the full exception history by default, so a single
pre-existing error keeps re-appearing after every action and produces false
positives when you are checking whether YOUR action raised something new.

**Workaround:**

- Record the current time before the action, then pass
  `tapir:exceptions --since=<iso8601>` afterwards to get only exceptions raised
  strictly after that timestamp. Unparseable `since` values are treated as
  absent (full list).

---

<a name="5-restart-preserves-the-cdp-port"></a>
## 5. restart preserves the CDP port

When dowel was started with `--cdp-port` (the web path that backs
`tapir:screenshot` CDP fallback, `tapir:resize`, `tapir:device`), a naive restart
used to drop the port, breaking those CDP-routed tools until you restarted with
the flag again.

**Workaround:**

- `dowel restart` (and bare `start`) now re-read the prior `cdpPort` from
  this project's session state (`state.json` under `~/.dowel/sessions/`) and reuse it as the default, so CDP stays wired across
  restarts. An explicit `--cdp-port` still wins.

---

<a name="6-overlays-get-stuck"></a>
## 6. Overlays get stuck

A left-over dialog, bottom sheet, dropdown menu, or barrier modal blocks the
next screen from rendering, and a single `tapir:modal` (dismiss-modals) does not
clear overlays that are not `PopupRoute`s.

**Workaround:**

- Use `tapir:reset_overlays`, which runs three idempotent layers: dismiss every
  `PopupRoute`, press `Escape` (for shortcut-driven overlays), then tap a
  Cancel/Dismiss/Close/OK/Done affordance as a last resort. Safe to call
  speculatively between flows; the response (`popped`, `escaped`,
  `dismissTapped`) tells you which layer cleared the screen.

---

<a name="7-a-green-tick-is-dispatch-not-effect"></a>
## 7. A green tick is dispatch, not effect

`✓ Tapped e7` and `✓ Filled e5` say the event left tapir, not that the widget
took it. A number field can swallow a fill and keep nothing; a button the gate
accepted can have an `onTap` that never fires.

**Workaround:**

- Read the `effect` block on the response: `effect.changed` for `tap` and
  `scroll`, `effect.verified` and `effect.value` for `type`, `fill` and `clear`.
- In summary mode `tapir:fill` and `tapir:type` exit `1` when `effect.verified` is
  false, and `tapir:navigate`, `tapir:navigate_back` and `tapir:scroll` say so when
  nothing happened. With `--json` or `--includeSnapshot` you get the raw
  envelope and read the field yourself.

---

<a name="8-a-hidden-desktop-app"></a>
## 8. A hidden desktop app

A hidden, minimised or occluded window moves the app to `AppLifecycleState.hidden`
and stops frame production, so a tap used to report "no observable change", a
snapshot went stale and a screenshot returned the last cached frame. This is
not specific to a browser tab.

**Workaround:**

- Nothing, by default: tapir delivers `resumed` and forces a frame at the start of
  each verb, and a response that did so carries `framesForced: true`. Verified on
  macOS with the window hidden. The app's own lifecycle observers see `resumed`.
- If a response still carries a `warnings` block, tapir could not force frames
  (`--dart-define=TAPIR_FORCE_FRAMES=false`, a `detached` app, a wake that
  produced no frame, or any hidden web tab). Bring the
  window to front and retry.
- An asleep macOS display can still starve frames; `caffeinate -u -t 3` wakes it
  (unverified for tapir). See [Frame production](../reference/frame-production.md).

---

<a name="related-documentation"></a>
## Related Documentation

- [tapir:fill](../commands/tapir-fill.md) and [tapir:reset_overlays](../commands/tapir-reset-overlays.md): the two built-in workarounds for nested text fields and stuck overlays.
- [tapir:tap](../commands/tapir-tap.md): the `effect` block and `--until`.
- [tapir:exceptions](../commands/index.md#console-and-exceptions) and [tapir:find](../commands/tapir-find.md): the `--since` delta and the re-resolvable `q<N>` handle.
- [Reference: Actionability gate](../reference/actionability-gate.md): why an action is refused and with which reason.
- [Reference: Frame production](../reference/frame-production.md): the hidden-window and backgrounded-tab failure mode.
