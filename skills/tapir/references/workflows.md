# Agent workflows

Concrete playbooks for the loops an LLM agent runs against a running
Flutter app through tapir. Every flow assumes the app is already running
and `./bin/dowel tapir:doctor` passes. Examples shown as MCP calls; the CLI
equivalents have identical params.

## Contents

- [Fill a form and submit](#fill-a-form-and-submit)
- [Find a button that is below the fold](#find-a-button-that-is-below-the-fold)
- [Open, fill, and close a modal](#open-fill-and-close-a-modal)
- [Navigate and verify the new screen](#navigate-and-verify-the-new-screen)
- [Pull-to-refresh, scroll, and assert idle](#pull-to-refresh-scroll-and-assert-idle)
- [Edit code, hot-reload, verify](#edit-code-hot-reload-verify)
- [Wait for a specific log line or exception](#wait-for-a-specific-log-line-or-exception)
- [Capture a "before / after" diff for a UI change](#capture-a-before--after-diff-for-a-ui-change)
- [Recovery patterns](#recovery-patterns)
- [Multi-tool composites worth knowing](#multi-tool-composites-worth-knowing)
- [Field rules from real agent runs](#field-rules-from-real-agent-runs)

## Fill a form and submit

```
1. tapir_observe { roles: "textbox,button" }
   → candidates: [
       { ref: "q1", role: "textbox", label: "Email",    magicFormField: "email"    },
       { ref: "q2", role: "textbox", label: "Password", magicFormField: "password" },
       { ref: "q3", role: "button",  label: "Sign in" }
     ]

2. tapir_type { ref: "q1", text: "user@example.com" }
3. tapir_type { ref: "q2", text: "hunter2" }
4. tapir_tap  { ref: "q3" }

5. tapir_wait_for_network_idle { idleMs: 800, timeoutMs: 8000 }
6. tapir_snap

7. <look for an error label, success banner, or route change in the YAML>
```

Notes:

- `tapir_type` REPLACES field content. To append, snap the field, read
  the current value, then type the concatenation.
- The `magicFormField` enricher matches the form key on the Dart side;
  agents can map back to validation rules / API payload field names.
- If the submit button is disabled (validation pending), step 4 fails
  with `"not enabled"`. Snap or observe before tapping to inspect
  state, or re-type a field that is empty.

## Find a button that is below the fold

```
1. tapir_find { text: "Delete account" }
   → { ref: "q5", matched: true }

2. tapir_scroll { ref: "q5", intoView: true }
3. tapir_tap    { ref: "q5" }
```

`tapir_scroll --intoView` calls `Scrollable.ensureVisible` under the
hood. When no `Scrollable` ancestor exists, falls back to a no-op;
the actionability gate's auto-scroll on step 3 also helps for simple
cases.

If `tapir_find` returns `matched: false`, the widget is not in the live
tree at all. Common causes: the screen is collapsed (tab not selected,
expansion panel closed), or the data has not loaded yet. Wait or
navigate first.

## Open, fill, and close a modal

Refs in the call sequence below are illustrative; the agent reads the
actual `q<N>` numbers from each preceding tool's response. Numbers are
NOT meaningful tokens to copy; only the `q` / `e` prefix and the
integer minted by the tool are.

```
1. tapir_find { text: "Open settings" }
   → { ref: "q1" }                                          # the trigger button

2. tapir_tap { ref: "q1" }
3. tapir_wait_for { text: "Confirm action" }                 # wait for modal title

4. tapir_observe { intent: "modal contents", limit: 20 }
   → candidates: [
       { ref: "q2", role: "textbox", label: "Reason" },
       { ref: "q3", role: "button",  label: "Confirm" },
       { ref: "q4", role: "button",  label: "Cancel"  },
       ...
     ]

5. tapir_type { ref: "q2", text: "no longer needed" }
6. tapir_tap  { ref: "q3" }                                  # the Confirm candidate

7. tapir_wait_for { textGone: "Confirm action" }             # wait for dismissal
8. tapir_wait_for_network_idle
9. tapir_snap
```

If the modal does not dismiss (validation kept it open), step 6 times
out. Snap inside the modal again and look for inline errors. The
fallback is `tapir_dismiss_modals` to pop everything, but use it as a
last resort; the cancel button usually exists.

## Navigate and verify the new screen

```
1. tapir_navigate { route: "/monitors/abc-123" }
   → { navigated: true, route: "/monitors/abc-123", exactPath: true, snapshot: "<yaml>" }

2. tapir_wait_for_network_idle              # detail load
3. tapir_wait_for { text: "abc-123" }       # presence of the id confirms the page

4. tapir_snap
```

When the app uses `GoRouter` or `auto_route`, `tapir_navigate` falls
through to `SystemNavigator.routeInformationUpdated`; the response
carries `reason` when the router rejected the push. For static routes
the `Navigator.pushNamed` path works directly.

`tapir_get_routes` returns where the app is now: `uri` is the mounted
Router's location (the same read `tapir_navigate` verifies against; null
while no Router is mounted), and `location` / `title` are the root
Navigator's page name and a title hint, both empty in a Router-based app.
It does NOT enumerate every declared route. To discover available routes, scan
the source (`grep -rEn 'GoRoute|MaterialPage|name:' lib/`) or evaluate
the router config directly via `./bin/dowel tinker` against whatever the
app exposes its `RouterConfig` through.

## Pull-to-refresh, scroll, and assert idle

```
1. tapir_snap                               # to find the ListView ref
2. tapir_find { semanticsLabel: "Monitors list" }
   → { ref: "q7" }

3. tapir_scroll { ref: "q7", dy: -200 }     # pull down by 200px (negative = up = pull)
4. tapir_wait_for_network_idle { idleMs: 1000 }
5. tapir_snap

6. <compare the list contents in the new snap>
```

Real touch pull-to-refresh uses fling gestures (high-velocity drag).
Tapir's `tapir_scroll` is a `jumpTo` under the hood, which usually
triggers the same `RefreshIndicator` callback in practice but does not
animate. If a specific app's refresh handler requires a real fling,
fall back to `tapir_drag` with a long y delta.

## Edit code, hot-reload, verify

```
<edit a Dart file in lib/, save>

tapir_hot_reload_and_snap { screenshot: true }
   On success: { reloaded: true, durationMs: 740,
                 snapshot, screenshot, recentExceptions: [] }
   On compile fail: { reloaded: false, error: "<text>",
                      recentExceptions: [] }

<inspect snapshot for the visible result; inspect recentExceptions
 for any runtime error that fired on rebuild>

<if compile failed, fix the code and call again>
<if reloaded but exceptions appeared, fix the bug and reload again>
```

Hot-reload is the agent's main loop for iterative UI changes. Always
inspect `recentExceptions` even on `reloaded: true`: a successful
reload can still throw at runtime (e.g. a build-time null assertion
firing in the new code).

When a code change touches state initialization that runs only at
startup, hot-reload will not pick it up. Use `tapir_close_app` then
`./bin/dowel start --device=<dev>` from the shell for a full restart.

## Wait for a specific log line or exception

```
1. tapir_console { minLevel: "WARNING", limit: 50 }
   → { logs: [...] }

2. tapir_exceptions { limit: 10 }
   → { exceptions: [...] }
```

Empty arrays mean either: nothing logged at that level, or crumbs
is not set up. Verify crumbs is active by triggering a known log
(call a controller, then read `tapir_console`); if still empty, run
`tapir:doctor` and check the enricher count.

For real-time log tailing during a workflow, no streaming MCP tool
exists; the agent polls `tapir_console` between actions. The CLI
equivalent for human watchers is `./bin/dowel crumbs:tail`.

## Capture a "before / after" diff for a UI change

```
1. tapir_snap
   → save snapshot as "before"

2. <perform the action: tap, type, navigate, etc.>
3. tapir_wait_for or tapir_wait_for_network_idle

4. tapir_snap
   → save snapshot as "after"

5. <diff the two YAMLs locally>
```

To skip steps 4 and 5, take the baseline snap and then pass
`snapshot: "diff"` to the action: it returns only the lines it changed.

For visual diffs, use `tapir_screenshot` before and after. PNG format
preserves details for pixel-diff tools; JPEG q70 is good enough for
"did the right widget appear" verification.

## Recovery patterns

### Pattern: action fails with `defunct`

```
<tapir_tap returns "defunct (element no longer mounted)">

1. tapir_snap                        # refresh tree
2. <pick a new e<N> for the same logical widget>
3. <retry the action>
```

If a fresh snap also shows the widget is gone, the assumption that it
exists is wrong; abandon the path or navigate to the screen where it
lives.

### Pattern: action fails with `obscured by`

```
<tapir_tap returns "obscured by other widget (top=_ModalScope)">

1. tapir_dismiss_modals              # pops every PopupRoute
2. tapir_tap { ref: <same ref> }     # retry the original action
```

When the obscurer is not a modal (snackbar, drawer, custom overlay),
inspect the YAML to find the overlay's ref and decide whether to
dismiss it or accept and tap through with `checkReceivesEvents: false`.

### Pattern: action fails with `not stable`

```
<tapir_tap returns "not stable (rect changed by 1.2px)">

1. <small wait: tapir_wait_for on a transient label that disappears
    when the animation finishes, OR explicitly wait via loop>
2. tapir_tap { ref: <same ref> }
```

If the widget is permanently animating (a pulsing indicator, an
endless spinner), the gate is correct to flag it as unstable; pass
`checkStable: false` if the underlying onTap is safe to fire mid-frame.

### Pattern: `q<N>` returns stale

```
<tapir_tap returns "Query handle ref=q3 is stale">

1. <call tapir_find or tapir_observe again with broader predicates>
2. <use the new q<N>>
```

A stale `q<N>` after a UI change is normal. After hot-reload, the
predicates may match a re-rendered widget but with a different
SemanticsNode; re-find rather than retry.

## Multi-tool composites worth knowing

| Goal | Composition |
|---|---|
| "Reload and check for errors" | `tapir_hot_reload_and_snap { screenshot: false }` then inspect `recentExceptions` |
| "Confirm a button is tappable" | `tapir_snap` → pick `e<N>` → `tapir_observe { roles: "button" }` → check `isEnabled` on the matching candidate |
| "Wait for HTTP, then for UI" | `tapir_wait_for_network_idle` → `tapir_wait_for { text: "Done" }` |
| "Fill 5 fields fast" | `tapir_observe { roles: "textbox" }` → 5 × `tapir_type` against `q<N>` from the candidates, or one `tapir_run` with 5 `fill --ref=q<N> --text=...` steps |
| "Find a row in a long list" | `tapir_find { contains: "..." }` → `tapir_scroll { ref: <q>, intoView: true }` → `tapir_tap` |
| "Set device and re-test" | `tapir_device_profile { preset: "iphone-15-pro" }` → `tapir_snap` |
| "Inspect singleton state when YAML is not enough" | `tapir_evaluate { expression: "MyService.instance.state.toString()" }` (replace with the host app's singleton accessor) |

## Field rules from real agent runs

- Start every run with `./bin/dowel tapir:doctor`.
- Give each git worktree its own `dowel start` and its own ports. A worktree
  nested under the repo passes dowel's ownership guard, so a tapir call
  made there can drive the main checkout's app.
- A green tick is dispatch, not effect. Read `effect` (`changed`,
  `verified`, `value`); `tapir:fill` and `tapir:type` exit `1` on an
  unverified write.
- The `tapir:wait` timeout flag is `--timeoutMs`, not `--timeout`.
- Reach an off-screen row with `tapir:scroll --ref=<ref> --intoView`, and
  trust a `[offscreen]` or `[occluded]` marker on a snapshot line before
  tapping it.
- `e<N>` refs re-resolve after a rebuild when the label count is unchanged;
  `reresolved` in the response tells you it happened.
- `tapir:press_key --modifiers=control,shift` holds the modifiers down for the
  press and releases them after it, so exact-match shortcuts fire; an unknown
  modifier name is an error before anything is pressed.
- Batch steps whose inputs you already know with `tapir:run` (or `tapir_run`):
  one call, one summary line per step, the last step's output. Between steps
  that change the screen use `--text`, `--key` or `q<N>` refs, since `e<N>`
  refs belong to one snapshot, and end with `snap` to read the new refs.
- Prefer `--snapshot=diff` (`snapshot: "diff"` over MCP) on `tap`, `fill`,
  `type`, `navigate` and `scroll`: it returns only the lines that changed
  since your last unfiltered snapshot. Take a plain `tapir:snap` first, or the
  first diff is the full tree.
- A refused `fill` (`ref eN is a button, not a text field`) means the ref is
  not a text field: pick the field's own ref, or use `tap`, `select_option` or
  `set_checkbox` for that control. When `effect.target.matchKind` is
  `nearest`, the ref overlapped no field and a neighbour was written; check
  `target.label` and `target.rect` before moving on.
- A `tapOwner` line under a snapshot ref (or field on an observe candidate)
  marks a merged boundary whose centre is not its control; `tapir:tap` goes to
  that control and says so (`retargeted`). A warning about
  `tapPointOutsideOwner` means it could not, and the tap landed at the centre
  of the merged boundary; check the result with `tapir:snap`.
- On web with a CDP port, the CLI brings a hidden tab to front itself. It
  repeats `snap` and `observe` only; after an acting verb run `tapir:snap`.
- MCP clients should wait for `tools/list_changed` (or re-list tools) after
  `initialize`: dowel's MCP server answers `tools/list` with an empty list
  until its plugin tools register (seen from `example/`; a dowel-side
  finding, not a tapir change).
- On web, a WPopover trigger may need a real CDP mouse click rather than a
  tapir tap (a hypothesis, not confirmed).
- A hidden macOS window is woken by tapir (`framesForced: true`), but an
  asleep display can still starve frames.
