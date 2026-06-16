# Driving real apps: gotchas for agents

A long real-app E2E session surfaces a recurring set of traps that every agent
re-discovers the hard way. This page collects them, with the workaround each one
now has built into `fluttersdk_dusk`. Read it once before driving a non-trivial
app; it will save you a dozen dead-end round trips.

---

## Table of contents

- [1. Refs go stale on rebuild](#1-refs-go-stale-on-rebuild)
- [2. Text fields may snapshot nested](#2-text-fields-may-snapshot-nested)
- [3. dusk:console needs (less than) you think](#3-duskconsole)
- [4. dusk:exceptions is cumulative](#4-duskexceptions-is-cumulative)
- [5. restart preserves the CDP port](#5-restart-preserves-the-cdp-port)
- [6. Overlays get stuck](#6-overlays-get-stuck)

---

<a name="1-refs-go-stale-on-rebuild"></a>
## 1. Refs go stale on rebuild

`e<N>` refs from `dusk:snap` freeze the widget at snapshot time. A navigation,
a modal open/close, a `setState`, or any significant rebuild invalidates them:
the next action on a stale `e<N>` fails with a not-found or stale envelope.

**Workaround:**

- Re-snap (`dusk:snap`) after any action that changes the screen, and use the
  fresh refs.
- For a target that survives re-renders (a stable `Text`, accessibility label,
  or `Key`), prefer `dusk:find` / `dusk:observe`, which mint a re-resolvable
  `q<N>` handle that re-walks the live tree on every action call. `q<N>`
  handles survive rebuild, route push, and snapshot disposal as long as the
  predicates still match.
- Pointer verbs (`dusk:tap`, `dusk:hover`, `dusk:drag`, ...) now dispatch at the
  element's LIVE rect, not the cached snapshot rect, so a target that merely
  shifted slots (same `Element`/`RenderObject`) is still hit correctly. The
  false-success class (gate passes, pointer lands on the stale position,
  `onTap` never fires) is gone for slot shifts; genuine rebuilds still need a
  re-snap.

---

<a name="2-text-fields-may-snapshot-nested"></a>
## 2. Text fields may snapshot nested

A wind `WInput` (and any `TextField` wrapped in `Semantics(textField: true)`)
historically snapshotted as TWO nested `textbox` nodes, because `RenderEditable`
unconditionally owns its own `textField` Semantics node and `MergeSemantics`
cannot absorb it. Agents naturally targeted the inner leaf, where `dusk:type`
threw a `-32000`.

**Workaround:**

- `dusk:snap` now collapses the nested pair (by render-object containment, never
  label/value equality, so two sibling fields sharing a label stay distinct) and
  emits a single ref for the outer node, marked `typeable: true`. Target the
  node carrying `typeable: true`.
- Better: use `dusk:fill --ref=<ref> --text=<value>`, which focuses, clears,
  types, and settles in one call (and retries once on a stale handle). It
  resolves the right editable for you and composes the gated focus/clear/type
  handlers, so you do not re-build the focus + clear + type + settle dance.

---

<a name="3-duskconsole"></a>
## 3. dusk:console captures debugPrint in-package now

`dusk:console` historically surfaced full structured logs only when
`fluttersdk_telescope` was installed and wired.

**Workaround:**

- `DuskPlugin.install()` now chains a `debugPrint` override that records every
  `debugPrint(...)` / `print(...)` call into a bounded in-package ring buffer,
  so those entries appear in `dusk:console` even without telescope.
- When telescope IS installed it enriches the output with `Logger.root.onRecord`
  entries and its other watchers. Direct `dart:developer log()` calls that
  bypass `debugPrint` still require telescope's `LogWatcher`.

---

<a name="4-duskexceptions-is-cumulative"></a>
## 4. dusk:exceptions is cumulative

`dusk:exceptions` returns the full exception history by default, so a single
pre-existing error keeps re-appearing after every action and produces false
positives when you are checking whether YOUR action raised something new.

**Workaround:**

- Record the current time before the action, then pass
  `dusk:exceptions --since=<iso8601>` afterwards to get only exceptions raised
  strictly after that timestamp. Unparseable `since` values are treated as
  absent (full list).

---

<a name="5-restart-preserves-the-cdp-port"></a>
## 5. restart preserves the CDP port

When artisan was started with `--cdp-port` (the web path that backs
`dusk:screenshot` CDP fallback, `dusk:resize`, `dusk:device`), a naive restart
used to drop the port, breaking those CDP-routed tools until you restarted with
the flag again.

**Workaround:**

- `artisan restart` (and bare `start`) now re-read the prior `cdpPort` from
  `~/.artisan/state.json` and reuse it as the default, so CDP stays wired across
  restarts. An explicit `--cdp-port` still wins.

---

<a name="6-overlays-get-stuck"></a>
## 6. Overlays get stuck

A left-over dialog, bottom sheet, dropdown menu, or barrier modal blocks the
next screen from rendering, and a single `dusk:modal` (dismiss-modals) does not
clear overlays that are not `PopupRoute`s.

**Workaround:**

- Use `dusk:reset_overlays`, which runs three idempotent layers: dismiss every
  `PopupRoute`, press `Escape` (for shortcut-driven overlays), then tap a
  Cancel/Dismiss/Close/OK/Done affordance as a last resort. Safe to call
  speculatively between flows; the response (`popped`, `escaped`,
  `dismissTapped`) tells you which layer cleared the screen.

---

## See also

- [dusk:fill](../commands/dusk-fill.md), [dusk:reset_overlays](../commands/dusk-reset-overlays.md)
- [dusk:tap](../commands/dusk-tap.md) (`--verify`, `--until`)
- [dusk:exceptions](../commands/index.md), [dusk:find](../commands/dusk-find.md)
- [Reference: Actionability gate](../reference/actionability-gate.md)
