# Agent workflows

Concrete playbooks for the loops an LLM agent runs against a running
Flutter app through dusk. Every flow assumes the app is already running
and `./bin/fsa dusk:doctor` passes. Examples shown as MCP calls; the CLI
equivalents have identical params.

## Fill a form and submit

```
1. dusk_observe { roles: "textbox,button" }
   → candidates: [
       { ref: "q1", role: "textbox", label: "Email",    magicFormField: "email"    },
       { ref: "q2", role: "textbox", label: "Password", magicFormField: "password" },
       { ref: "q3", role: "button",  label: "Sign in" }
     ]

2. dusk_type { ref: "q1", text: "user@example.com" }
3. dusk_type { ref: "q2", text: "hunter2" }
4. dusk_tap  { ref: "q3" }

5. dusk_wait_for_network_idle { idleMs: 800, timeoutMs: 8000 }
6. dusk_snap

7. <look for an error label, success banner, or route change in the YAML>
```

Notes:

- `dusk_type` REPLACES field content. To append, snap the field, read
  the current value, then type the concatenation.
- The `magicFormField` enricher matches the form key on the Dart side;
  agents can map back to validation rules / API payload field names.
- If the submit button is disabled (validation pending), step 4 fails
  with `"not enabled"`. Snap or observe before tapping to inspect
  state, or re-type a field that is empty.

## Find a button that is below the fold

```
1. dusk_find { text: "Delete account" }
   → { ref: "q5", matched: true }

2. dusk_scroll { ref: "q5", intoView: true }
3. dusk_tap    { ref: "q5" }
```

`dusk_scroll --intoView` calls `Scrollable.ensureVisible` under the
hood. When no `Scrollable` ancestor exists, falls back to a no-op;
the actionability gate's auto-scroll on step 3 also helps for simple
cases.

If `dusk_find` returns `matched: false`, the widget is not in the live
tree at all. Common causes: the screen is collapsed (tab not selected,
expansion panel closed), or the data has not loaded yet. Wait or
navigate first.

## Open, fill, and close a modal

Refs in the call sequence below are illustrative; the agent reads the
actual `q<N>` numbers from each preceding tool's response. Numbers are
NOT meaningful tokens to copy; only the `q` / `e` prefix and the
integer minted by the tool are.

```
1. dusk_find { text: "Open settings" }
   → { ref: "q1" }                                          # the trigger button

2. dusk_tap { ref: "q1" }
3. dusk_wait_for { text: "Confirm action" }                 # wait for modal title

4. dusk_observe { intent: "modal contents", limit: 20 }
   → candidates: [
       { ref: "q2", role: "textbox", label: "Reason" },
       { ref: "q3", role: "button",  label: "Confirm" },
       { ref: "q4", role: "button",  label: "Cancel"  },
       ...
     ]

5. dusk_type { ref: "q2", text: "no longer needed" }
6. dusk_tap  { ref: "q3" }                                  # the Confirm candidate

7. dusk_wait_for { textGone: "Confirm action" }             # wait for dismissal
8. dusk_wait_for_network_idle
9. dusk_snap
```

If the modal does not dismiss (validation kept it open), step 6 times
out. Snap inside the modal again and look for inline errors. The
fallback is `dusk_dismiss_modals` to pop everything, but use it as a
last resort; the cancel button usually exists.

## Navigate and verify the new screen

```
1. dusk_navigate { route: "/monitors/abc-123" }
   → { navigated: true, route: "/monitors/abc-123", snapshot: "<yaml>" }

2. dusk_wait_for_network_idle              # detail load
3. dusk_wait_for { text: "abc-123" }       # presence of the id confirms the page

4. dusk_snap
```

When the app uses `GoRouter` or `auto_route`, `dusk_navigate` falls
through to `SystemNavigator.routeInformationUpdated`; the response
carries `reason` when the router rejected the push. For static routes
the `Navigator.pushNamed` path works directly.

`dusk_get_routes` returns the CURRENT route + page title only; it does
NOT enumerate every declared route. To discover available routes, scan
the source (`grep -r 'MagicRoute.page' lib/routes/`) or inspect the
tree (`Magic.find<MagicApplication>().routerConfig`).

## Pull-to-refresh, scroll, and assert idle

```
1. dusk_snap                               # to find the ListView ref
2. dusk_find { semanticsLabel: "Monitors list" }
   → { ref: "q7" }

3. dusk_scroll { ref: "q7", dy: -200 }     # pull down by 200px (negative = up = pull)
4. dusk_wait_for_network_idle { idleMs: 1000 }
5. dusk_snap

6. <compare the list contents in the new snap>
```

Real touch pull-to-refresh uses fling gestures (high-velocity drag).
Dusk's `dusk_scroll` is a `jumpTo` under the hood, which usually
triggers the same `RefreshIndicator` callback in practice but does not
animate. If a specific app's refresh handler requires a real fling,
fall back to `dusk_drag` with a long y delta.

## Edit code, hot-reload, verify

```
<edit a Dart file in lib/, save>

dusk_hot_reload_and_snap { screenshot: true }
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
startup, hot-reload will not pick it up. Use `dusk_close_app` then
`./bin/fsa start --device=<dev>` from the shell for a full restart.

## Wait for a specific log line or exception

```
1. dusk_console { minLevel: "WARNING", limit: 50 }
   → { logs: [...] }

2. dusk_exceptions { limit: 10 }
   → { exceptions: [...] }
```

Empty arrays mean either: nothing logged at that level, or telescope
is not wired. Verify telescope is active by triggering a known log
(call a controller, then read `dusk_console`); if still empty, run
`dusk:doctor` and check the enricher count.

For real-time log tailing during a workflow, no streaming MCP tool
exists; the agent polls `dusk_console` between actions. The CLI
equivalent for human watchers is `./bin/fsa telescope:tail`.

## Capture a "before / after" diff for a UI change

```
1. dusk_snap
   → save snapshot as "before"

2. <perform the action: tap, type, navigate, etc.>
3. dusk_wait_for or dusk_wait_for_network_idle

4. dusk_snap
   → save snapshot as "after"

5. <diff the two YAMLs locally>
```

For visual diffs, use `dusk_screenshot` before and after. PNG format
preserves details for pixel-diff tools; JPEG q70 is good enough for
"did the right widget appear" verification.

## Recovery patterns

### Pattern: action fails with `defunct`

```
<dusk_tap returns "defunct (element no longer mounted)">

1. dusk_snap                        # refresh tree
2. <pick a new e<N> for the same logical widget>
3. <retry the action>
```

If a fresh snap also shows the widget is gone, the assumption that it
exists is wrong; abandon the path or navigate to the screen where it
lives.

### Pattern: action fails with `obscured by`

```
<dusk_tap returns "obscured by other widget (top=_ModalScope)">

1. dusk_dismiss_modals              # pops every PopupRoute
2. dusk_tap { ref: <same ref> }     # retry the original action
```

When the obscurer is not a modal (snackbar, drawer, custom overlay),
inspect the YAML to find the overlay's ref and decide whether to
dismiss it or accept and tap through with `checkReceivesEvents: false`.

### Pattern: action fails with `not stable`

```
<dusk_tap returns "not stable (rect changed by 1.2px)">

1. <small wait: dusk_wait_for on a transient label that disappears
    when the animation finishes, OR explicitly wait via loop>
2. dusk_tap { ref: <same ref> }
```

If the widget is permanently animating (a pulsing indicator, an
endless spinner), the gate is correct to flag it as unstable; pass
`checkStable: false` if the underlying onTap is safe to fire mid-frame.

### Pattern: `q<N>` returns stale

```
<dusk_tap returns "Query handle ref=q3 is stale">

1. <call dusk_find or dusk_observe again with broader predicates>
2. <use the new q<N>>
```

A stale `q<N>` after a UI change is normal. After hot-reload, the
predicates may match a re-rendered widget but with a different
SemanticsNode; re-find rather than retry.

## Multi-tool composites worth knowing

| Goal | Composition |
|---|---|
| "Reload and check for errors" | `dusk_hot_reload_and_snap { screenshot: false }` then inspect `recentExceptions` |
| "Confirm a button is tappable" | `dusk_snap` → pick `e<N>` → `dusk_observe { roles: "button" }` → check `isEnabled` on the matching candidate |
| "Wait for HTTP, then for UI" | `dusk_wait_for_network_idle` → `dusk_wait_for { text: "Done" }` |
| "Fill 5 fields fast" | `dusk_observe { roles: "textbox" }` → 5 × `dusk_type` against `q<N>` from the candidates |
| "Find a row in a long list" | `dusk_find { contains: "..." }` → `dusk_scroll { ref: <q>, intoView: true }` → `dusk_tap` |
| "Set device and re-test" | `dusk_device_profile { preset: "iphone-15-pro" }` → `dusk_snap` |
| "Inspect controller state when YAML is not enough" | `dusk_evaluate { expression: "Magic.find<X>().rxState.value" }` |
