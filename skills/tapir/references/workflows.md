# Workflows

Playbooks for the longer loops an agent runs through tapir. Each assumes the app is running and `./bin/dowel tapir:doctor` is clean. Calls are shown as MCP tools; the `tapir:*` command takes most of the same parameters as flags, but not all (`tapir:screenshot` requires `--output`, which the tool does not); `cli-commands.md` lists each command's flags. Ref numbers are illustrative: use the ones the previous call returned.

## Contents

- [Fill a form and submit](#fill-a-form-and-submit)
- [Reach a control below the fold](#reach-a-control-below-the-fold)
- [Open, fill and close a modal](#open-fill-and-close-a-modal)
- [Navigate and confirm the screen](#navigate-and-confirm-the-screen)
- [Refresh a list](#refresh-a-list)
- [Edit, hot reload, verify](#edit-hot-reload-verify)
- [Check logs and exceptions per screen](#check-logs-and-exceptions-per-screen)
- [Before and after a change](#before-and-after-a-change)
- [Recovery](#recovery)
- [Field rules from real runs](#field-rules-from-real-runs)

## Fill a form and submit

```text
1. tapir_observe { roles: "textbox,button" }
   candidates: q1 textbox "Email" (magicFormField: email), q2 textbox "Password", q3 button "Sign in"
2. tapir_fill { ref: "q1", text: "user@example.com" }     effect.verified must be true
3. tapir_fill { ref: "q2", text: "secret" }
4. tapir_tap { ref: "q3" }                                a disabled button fails "not enabled"
5. tapir_wait_for_network_idle { idleMs: 800, timeoutMs: 8000 }   only with crumbs (not published yet)
6. tapir_snap { interactiveOnly: true }                   an error label, a banner, or the next screen
```

`fill` replaces the content; to append, read the value and fill the whole string. `magicFormField` names the form key on a Magic app, which maps the field to its validation rule and API field. When `effect.target.matchKind` is `nearest`, the ref overlapped no field and a neighbour was written: check `target.label`. With all refs known up front, steps 2 to 4 fit in one `tapir_run`.

## Reach a control below the fold

```text
1. tapir_find { text: "Delete account" }       { ref: "q5", matched: true }
2. tapir_scroll { ref: "q5", intoView: true }  Scrollable.ensureVisible
3. tapir_tap { ref: "q5" }
```

The gate already scrolls a target into view under one `Scrollable`, so step 2 matters for nested or horizontal lists. A row Flutter has not built yet has no node: scroll the list by a delta first (`tapir_scroll { ref: "<a visible row>", dy: 600 }`), then find. `matched: false` means nothing in the live tree matches: a collapsed section, an unselected tab, data still loading.

## Open, fill and close a modal

```text
1. tapir_tap { ref: "q1" }                          the trigger
2. tapir_wait_for { text: "Confirm action" }        the dialog title
3. tapir_observe { roles: "textbox,button", limit: 20 }
4. tapir_fill { ref: "q2", text: "no longer needed" }
5. tapir_tap { ref: "q3" }                          Confirm
6. tapir_wait_for { textGone: "Confirm action" }    matched: false means validation kept it open
7. tapir_snap { interactiveOnly: true }
```

When the dialog stays, snap inside it for the inline error. `tapir_reset_overlays` clears whatever is left (pops popup routes, presses Escape, taps a Cancel-style button); use it as the fallback, since the dialog's own Cancel keeps the app's state consistent.

## Navigate and confirm the screen

```text
1. tapir_navigate { route: "/monitors/abc-123", snapshot: "none" }
   { navigated: true, route: "/monitors/abc-123", exactPath: true }
2. tapir_wait_for { text: "abc-123" }
3. tapir_snap { interactiveOnly: true }
```

`navigated` is read off the mounted Router two frames after the push: `true` covers a page under the route, `exactPath` the route itself, and `navigated: false` carries `reason` (dropped or redirected). A Navigator 1.0 app has no Router to read, so it reports `navigated: false` even when the push landed; confirm with a snapshot. Register a `TapirNavigateAdapter` with `TapirPlugin.registerNavigateAdapter` (on a Magic app, typically `MagicRoute.to`) so the push goes through the app's own router. `tapir_get_routes` answers where the app is (`uri`), never the declared routes: read the router configuration in the source for those.

## Refresh a list

A delta scroll is a `jumpTo` clamped to the extents, so it cannot overscroll and does not fire a `RefreshIndicator`. Pull with a real gesture instead, from the leading edge of the list: a drag on a list that is scrolled down only scrolls it back towards the top and never overscrolls, so no refresh runs.

```text
1. tapir_observe { roles: "button,link" }       a row that is on screen now; q1
2. tapir_scroll { ref: "q1", dy: -100000 }      a row ref resolves to its enclosing list, clamped to the top
3. tapir_observe { roles: "button,link" }       again: the top rows are built now and the old handles may point at other rows
4. tapir_drag { startRef: "q1", endRef: "q4" }  a top row and a row further down: down, five moves, up
5. tapir_wait_for { text: "<text the refresh adds>" }
6. tapir_snap { interactiveOnly: true }
```

Step 1 uses a row that is visible, not the top one: on a lazy list that is scrolled down the top row is not built, so no query can find it until step 2 has scrolled there. A `tapir_scroll` without `ref` drives the first laid-out scrollable in the tree, which can be another list. If the list is already at the top, `effect.changed` is false and nothing is lost. A very long list can be further than 100000 pixels from the top: repeat step 2 with a fresh visible row ref until `effect.changed` is false, and only then observe again.

When the rows are plain text, `tapir_observe` lists only interactive nodes and may return no row to use. Locate rows by their text instead: `tapir_find { text: "<visible row text>" }` gives the ref for step 1; after step 2, `tapir_find { text: "<top row text>" }` and `tapir_find { text: "<lower row text>" }` give the drag ends for step 4. A snapshot with `interactiveOnly: false` shows the labels to search for. `tapir_find` takes the first match anywhere on screen, so a row text that also appears outside the list, or twice in it, can give a wrong ref or the same ref for both drag ends; add `within` (an `e<N>` ref of the list from `tapir_snap`; a `q<N>` ref is not looked up there) or search by a `key`, and check `matchCount` is 1.

Step 5 waits on the UI because `tapir_wait_for_network_idle` reads the in-flight HTTP count from crumbs and, without that wiring, reports idle at once. With crumbs wired, `tapir_wait_for_network_idle { idleMs: 1000 }` is a useful extra before step 5 but never the only wait: it counts HTTP requests only, so a refresh that reads a local cache, or keeps processing after the response, can pass it before the UI has changed. Wait for something the refresh adds (a new row, a changed count). `tapir_wait_for { textGone: ... }` succeeds whenever no matching `Text` exists, so it also succeeds for a spinner that has no text label or has not appeared yet while the refresh is still running; use it only after `tapir_wait_for { text: "<spinner label>" }` has confirmed the spinner showed, and treat an absent label as no proof of completion.

## Edit, hot reload, verify

```text
<save the edit>
tapir_hot_reload_and_snap { screenshot: false }
  reloaded: true   read snapshot and recentExceptions
  reloaded: false  read error, fix, call again
```

Read `recentExceptions` even after a clean reload: new code can throw on the next rebuild. A change to state that only runs at startup (`main`, a provider's boot, a `static final`) needs `dowel_hot_restart`; a refresh of the whole process is `dowel_restart`.

## Check logs and exceptions per screen

```text
1. tapir_exceptions { clear: true }                 drop tapir's buffer; note the time now (ISO 8601)
2. tapir_navigate { route: "/reports" }
3. tapir_exceptions { since: "<time from step 1>", limit: 10 }   only this screen's faults
4. tapir_console { minLevel: "WARNING", limit: 50 }
```

The exception buffer is cumulative; without `clear` (or a `since` pinned before the action) one boot-time fault is reported against every screen of a sweep. `clear: true` empties only tapir's own buffer, not the crumbs store, so the `since` in step 3 is what keeps an earlier fault that crumbs still holds out of the answer. `tapir_console` lists the app's own `debugPrint` output even without crumbs; HTTP and the rest of the runtime buffers are the `crumbs` skill. There is no streaming tool: poll between actions.

## Before and after a change

```text
1. tapir_snap                                  an unfiltered snap records the baseline
2. tapir_tap { ref: "e7", snapshot: "diff" }   only the changed lines, with a (K of N lines changed) footer
```

For a visual check, `tapir_screenshot { ref: "e7", format: "png" }` before and after keeps the image to the component.

## Recovery

| Symptom | Move |
|---|---|
| `defunct (element no longer mounted)` | Re-snap, pick the ref again; if the widget is gone from a fresh snap, the screen changed under you |
| `obscured by other widget (top=...)` | `tapir_reset_overlays`, retry; for a cover that lets touches through, `checkReceivesEvents: false` |
| `not stable (rect changed by Xpx)` | Wait for the animation (`tapir_wait_for { textGone: ... }`), retry; an endless animation takes `checkStable: false` |
| `not enabled` | Change the state that disables it; a retry fails the same way |
| `Query handle ref=qN is stale` | Find or observe again with broader predicates |
| A success with `effect.changed: false` | Nothing observable moved: check `checks`, `tapPointOutsideOwner`, `warnings` before trying again |
| `warnings` present | Frames are off; follow its `hint` (web: CDP `Page.bringToFront`), then retry |

## Field rules from real runs

- Start every run with `./bin/dowel tapir:doctor`; its session-ownership and CDP checks catch the two failures that look like a broken app.
- Give each git worktree its own `dowel start` and ports. dowel keys sessions by project root and falls back to `~/.dowel/state.json` (whichever app started last) when the project has none, so a worktree without its own session drives someone else's app, successfully.
- A success is dispatch, not effect: read `effect`, and on the CLI let `tapir:fill` and `tapir:type` fail on an unverified write.
- Take a plain `tapir:snap` before the first `--snapshot=diff`, or that diff is the full tree.
- A `tapOwner` sub-line marks a merged boundary whose centre is not its control; `tapir:tap` goes to the control and says `retargeted`. A `tapPointOutsideOwner` warning means it could not: check with `tapir:snap`.
- On web with a CDP port the CLI brings a hidden tab to front itself, but repeats only `snap` and `observe`; after an acting verb run `tapir:snap`.
- A hidden macOS window is woken by tapir (`framesForced: true`); an asleep display can still starve frames, and then `warnings` stays.
