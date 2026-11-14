---
name: tapir
description: "Drive, verify and profile a running Flutter app from an agent with tapir."
version: 1.0.0
when_to_use: "Use when driving, checking or profiling a running Flutter UI through tapir_* tools or tapir:* commands; app lifecycle and MCP wiring are dowel's, widget tests are flutter_test."
---

<!-- tapir v1.0.0 | Skill updated: 2026-11-14 -->

# tapir

Tapir lets an agent drive a Flutter app that is already running. The app registers `ext.tapir.*` VM Service extensions; you call them as `tapir_*` MCP tools or as `./bin/dowel tapir:*` commands from a shell, both reaching the same handler; the CLI flags can differ from the tool parameters (`${CLAUDE_SKILL_DIR}/references/cli-commands.md` lists them). The loop is: snapshot the Semantics tree, act on a ref from it, read what the action reports, wait for the result.

Scope: this skill drives and inspects the UI. Starting, reloading and stopping the app, `dowel_tinker` and MCP wiring are the `dowel` skill; HTTP, log and exception capture is the `crumbs` skill; a `flutter_test` widget test needs neither.

## Install

If a `tapir_*` call or `./bin/dowel tapir:snap` reports that no app or VM Service is reachable, the app is not running or tapir is not installed. From the Flutter app root:

```bash
dart pub add tapir
dart run tapir tapir:install        # patches lib/main.dart, scaffolds ./bin/dowel, registers the plugin
dart run tapir mcp:install          # writes the `dowel` entry into .mcp.json
./bin/dowel start --device=chrome   # or macos, linux, windows, a device id; add --cdp-port=9222 on web
./bin/dowel tapir:doctor            # wiring and session health
./bin/dowel tapir:snap              # the agent reaches the app
```

`tapir:install` puts `TapirPlugin.install()` behind `if (!kReleaseMode)` before `runApp(` (before `Magic.init(` on a Magic app), so debug and profile builds carry tapir and release builds drop it. On a Magic app it also adds `MagicTapirIntegration.install()` (from `package:magic_devtools/tapir.dart`) after `Magic.init()`, but only when the resolved `magic_devtools` is a release built on tapir; otherwise it warns and skips that line, so upgrade `magic_devtools` and rerun. Reconnect the MCP client after `mcp:install`; a stdio server is not reloaded on its own. A project that ran tapir's predecessor, `fluttersdk_dusk`, still holds its files: `tapir:install` and `tapir:doctor` list them (a stale `bin/dispatcher.dart` keeps `dowel install` from running), then name the commands to run after you delete them.

## Rules

### Refs

1. **Two ref spaces, never mixed.** `e<N>` comes from `tapir_snap` and names one Semantics node of that snapshot. `q<N>` comes from `tapir_find` or `tapir_observe`, stores the predicates and walks the live tree again on every action. Hold an `e<N>` for the next action after the snap; hold a `q<N>` across retries, animations, navigation and hot reload, because an `e<N>` whose node unmounted fails `defunct` unless tapir can relocate it safely (rule 2).
2. **A stale `e<N>` is relocated only when it is safe.** The action re-runs the label query bound to the ref and trusts it only when the live tree has the same number of nodes with that label on the same route; the response then lists the ref under `reresolved`. Otherwise it fails `defunct`: re-snap. An unlabelled ref is never relocated.
3. **Narrow the read before acting.** `tapir_snap { within: "e12", interactiveOnly: true }` walks one subtree and drops prose; `grep: "<regex>"` keeps matches plus their ancestors (an invalid regex is matched as text and the response carries `grepLiteral: true`). A full tree costs context, and on a shell whose sidebar repeats page labels the unscoped lookup lands on the nav item. `tapir_find { within: "e12", text: "Save" }` keeps the scope inside the handle; `within` alone is refused, so pair it with `text`, `contains`, `semanticsLabel` or `key`.
4. **A repeated label needs a narrower predicate.** `tapir_find` answers the first match plus `matchCount`; above 1 it adds `diagnostic`. Predicates are not intersected, so narrow by swapping to `key`, `text` or `contains`, adding `within`, or using `tapir_observe`, whose labelled handles carry their position among same-label nodes. A position is not an identity: after any action that adds or removes a row with that label, observe again, because a held handle then selects a neighbour and the action still reports success. An unlabelled candidate has no position, so take a snapshot ref or a `key` for it. Resolver order and the unlabelled case: `${CLAUDE_SKILL_DIR}/references/actionability-and-refs.md`.
5. **Trust the line markers.** A snapshot ref line ending ` [offscreen]` needs a scroll, one ending ` [occluded]` has something painted over its centre; observe candidates carry `inViewport` and `occluded`. A `typeable: true` sub-line marks the node `tapir_type` writes to.

### The actionability gate

6. **`tap`, `double_click`, `right_click`, `triple_click`, `hover`, `drag`, `type`, `fill` and `set_checkbox` pass a six-step gate first** (`set_checkbox` gates the control it taps, and only when it taps), in this frozen order: (0) defunct preflight, (1) enabled, (2) zero rect, (3) off-viewport, auto-scrolling once under a `Scrollable`, (4) stable, 2-frame drift above 0.5px, (5) receives events, the hit test at the centre reaches the target. `clear`, `focus`, `scroll`, `press_key` and `select_option` skip it, so a covered or disabled target is not refused there. `checkStable: false` and `checkReceivesEvents: false` skip steps 4 and 5 for one call; there is no global switch, so an exception stays visible.
7. **Branch on the reason substring, never on the full message.**

   | Substring | Meaning | Next move |
   |---|---|---|
   | `defunct` (`element no longer mounted` or `element no longer attached to a render object`, both frozen text) | The node left the tree | Re-snap and pick the ref again |
   | `not enabled` | Semantics `isEnabled` is false | Change the state that disables it; a retry fails the same way |
   | `zero rect` | Width or height is 0, layout pending | `tapir_wait_for` on content, then retry |
   | `off-viewport (rect=..., viewport=...)` | Auto-scroll did not bring it in | `tapir_scroll` toward it, retry |
   | `not stable (rect changed by Xpx)` | Animating | Wait; `checkStable: false` only for an intentional animation |
   | `obscured by other widget (top=...)` | Something covers it | `tapir_reset_overlays`, or `checkReceivesEvents: false` when the cover lets touches through |

   A stale `q<N>` fails with `Query handle ref=qN is stale: no live match for stored predicates`: find or observe again rather than retrying the handle. A target tapir will not act on at all (a ref that is not a text field, a container of several checkboxes, a perf call with no session) is not a gate reason but the error type `refused` (code `-32001`): choose another target, do not retry. A value it cannot use is `invalid_param` (`-32602`).
8. **On Flutter Web step 5 often cannot answer**, so the gate proceeds and the response carries `checks: {receivesEvents: "indeterminate", why, overlapCandidates, hint}`. The key is absent when the check confirmed. When it is present, judge the action by its `effect`, not by the success.

### Reading results

9. **A success means dispatched; `effect` says what the widget holds now.** `tap`: `{kind: "treeChanged", changed}`, where `changed: false` means nothing observable moved. `type`, `clear`, `fill`: `{kind: "text", verified, value, target}`, where `verified: false` means a formatter or keyboard type rejected the write; read `target.matchKind`, and when it is `nearest` the ref overlapped no field and a neighbour was written. `scroll`: `{kind: "scrollOffset", changed, before, after}`. `set_checkbox`: `{kind: "checked", verified, before, after}`, and its `value` is the state read back, equal to `after`, not the request. `select_option`: `{kind: "selected", verified, value}`. Do not re-snap to confirm what `effect` already answers.
10. **A `warnings` block means do not conclude.** It appears only while the app is not producing frames, and then a snapshot reads as empty and a gesture cannot land. Tapir wakes a hidden or paused desktop app at the start of every verb except the perf verbs, `console`, `exceptions`, `close_app` and `evaluate`, and stamps `framesForced: true`, which is normal (`--dart-define=TAPIR_FORCE_FRAMES=false` turns it off). A hidden browser tab cannot be woken from inside: follow `warnings.hint` (CDP `Page.bringToFront`), then retry. The CLI does that itself when the session has a `cdpPort`, repeating only `snap` and `observe`; after an acting verb run `tapir:snap` to see what it did.
11. **A merged control taps its own child.** A `MergeSemantics` boundary whose centre is not on its control shows a `tapOwner` sub-line (observe: a `tapOwner` field). `tapir_tap` goes to that control and reports `retargeted {from, to, ownerRect}`; `centreHandled: true` means the centre has a handler of its own, and `retarget: false` (CLI `--no-retarget`) taps the centre instead. `tapPointOutsideOwner` in the response means the tap stayed at the centre: check the result.
12. **Cut round trips.** Pass `snapshot: "diff"` (CLI `--snapshot=diff`) to `tap`, `fill`, `type`, `navigate` or `scroll` to get only the changed lines since the last unfiltered snapshot; a filtered snap leaves that baseline as it was, so after an earlier plain snapshot the diff also lists everything changed since then, and with none it is the full tree. Take a plain `tapir_snap` first when you want only the last action's effect. Batch steps whose inputs you already know with `tapir_run`, and between steps that change the screen use `--text`, `--key` or `q<N>`, since `e<N>` belongs to one snapshot. `tapir_tap { until: "Saved" }` polls for that text after the tap and adds `untilMatched`.

### What each verb can and cannot do

13. **Some tools run outside the app.** `tapir_hot_reload_and_snap`, `tapir_run`, `tapir_perf_run`, `tapir_perf_compare`, `tapir_perf_trace`, `tapir_resize_viewport` and `tapir_device_profile` route through `dowel:tapir:*` in the MCP server's process, because the isolate cannot reload itself and CDP needs a browser connection. The two viewport tools work only on web started with `--cdp-port` and fail with `CDP not enabled` elsewhere; their override ends when the call returns, and only `tapir:resize_viewport --hold` run in the background keeps one.
14. **`tapir_wait_for_network_idle` reports idle until the count is wired.** It reads the in-flight HTTP count through `pendingHttpCountReader`, which an app sets to `() => CrumbsStore.pendingHttpCount` from the `crumbs` package (published on pub.dev), and the count moves only when a registered HTTP adapter overrides `pendingCount`; until both are in place the count is always 0, so it answers `matched: true` after one idle window (about `idleMs`) with no traffic seen, or times out when `timeoutMs` is shorter than that: neither proves anything, so wait on the UI instead. `tapir_exceptions` is cumulative: read it as a delta (`since`, `clear: true`), or one boot-time fault rides along on every later read. Console ordering and the crumbs merge: `${CLAUDE_SKILL_DIR}/references/mcp-tools.md`.
15. **`tapir_set_checkbox` runs the gate; `tapir_select_option` does not.** `set_checkbox` reads the Semantics checked or toggled flag, so a checkbox, switch or radio from any library works; it taps only when the state differs (`toggled: false` when it already matched, and then nothing is gated) and reads it back into `value` and `effect.after`. The tap goes to the control that set the flag, so a bare `Switch` in a labelled container works. The gate scrolls a control below the fold into view and refuses a disabled, covered or moving one with its reason; there is no need to scroll first, and a `tapir_tap` on the control would toggle it. `checkStable` and `checkReceivesEvents` apply as on the other gated tools (the CLI command takes them as flags too), and `checks` appears when the gate could not confirm. A control whose owner ignores the tap reads `verified: false` (the CLI exits 1 unless `--json` or `--includeSnapshot` is set). A ref with no state, or a merged node whose own flag is missing while several descendants have one, is `refused`: snap again and pass the control's ref. A `value` other than `true`, `false`, `1` or `0` is `invalid_param`. `select_option` calls a `DropdownButton`'s `onChanged` with a string and taps nothing; for any other picker, tap it open and tap the option. Read order and return shapes: `${CLAUDE_SKILL_DIR}/references/mcp-tools.md`.
16. **`tapir_evaluate` runs one Dart expression in the app's root library.** Over MCP, dowel's server answers it through the VM Service (`dowel_tinker` and `./bin/dowel tinker --eval="<expr>"` evaluate the same way). A runtime exception, a compile error and a stale isolate come back as error results, and an expression with `await` returns the `Future`, not its value.
17. **The CLI differs from MCP in defaults and exits.** MCP action tools embed a post-action snapshot by default; the CLI does not (`--includeSnapshot` or `--snapshot=full`), and `--json` prints the raw envelope. `tapir:wait_for`, `tapir:wait_for_network_idle`, an unverified `tapir:fill`, `tapir:type` or `tapir:set_checkbox`, and a failed `tapir:hot_reload_and_snap` exit 1, so a script can chain on them; with `--json` or `--includeSnapshot` the write verbs print the response and exit 0, so read `effect.verified` there. Which verbs take `--json`, and every exit code: `${CLAUDE_SKILL_DIR}/references/cli-commands.md`.
18. **Each project needs its own running session.** dowel records one session per project and falls back to `~/.dowel/state.json`, the app started last anywhere, when the project has none. Run `dowel start` in each git worktree you drive, with its own ports, and start every run with `./bin/dowel tapir:doctor`, which flags a session that belongs to another project. A worktree nested inside the recorded root (`.claude/worktrees/<slug>`) counts as its owner, so doctor stays silent there; run `dowel start` in the worktree anyway.

### Performance

19. **Read `refused` first.** `tapir_perf_begin`, one driven interaction, `tapir_perf_end`. When the engine drew nothing in the session the report carries `refused: true`, a reason and no metrics, because a table of zeros would read as fast; the perf verbs do not wake a hidden app, so bring it to front and repeat. Then read `coverage.missing`, then `insights`, and drill into one with `tapir_perf_insight { id: "I1" }`. Attribution mode inflates milliseconds: rank by them, but compare milliseconds only between `mode: "timing"` sessions, and let `tapir_perf_compare` judge two `tapir_perf_run` files on counts per painted frame.

## Recipes

Snap, act, verify:

```text
tapir_snap { interactiveOnly: true }          pick e7 from the YAML
tapir_tap { ref: "e7", snapshot: "diff" }     read effect.changed and the diff
tapir_wait_for { text: "Saved" }              after HTTP, animation or navigation; check matched
```

Observe once, act many (forms, lists):

```text
tapir_observe { roles: "textbox,button" }     q1 Email, q2 Password, q3 Sign in
tapir_fill { ref: "q1", text: "user@example.com" }
tapir_fill { ref: "q2", text: "secret" }
tapir_tap { ref: "q3", until: "Dashboard" }   untilMatched confirms the landing
```

Edit, reload, verify: after saving a file call `tapir_hot_reload_and_snap { screenshot: false }`. On `reloaded: false` read `error`; on `reloaded: true` still read `recentExceptions`, since new code can throw on the next rebuild. A change to startup state needs `dowel_hot_restart`.

Navigate and confirm: `tapir_navigate { route: "/settings" }` returns `navigated` (the router shows the route or a page under it) and `exactPath` (the route itself); on `navigated: false` read `reason`. `tapir_get_routes` reports the current `uri`, not the declared routes.

The same flow from a shell:

```bash
./bin/dowel tapir:snap --interactiveOnly
./bin/dowel tapir:fill --ref=e4 --text="user@example.com"
./bin/dowel tapir:tap --ref=e7 --json | jq '.effect.changed'
./bin/dowel tapir:wait_for --text="Saved" --timeoutMs=8000 || echo "never appeared"
```

## Testing

A snapshot enricher adds YAML lines under each ref (shown with `includeEnrichers: true`). It is a synchronous `String? Function(Element, RefRegistry)` that returns `null` for an element it has nothing to say about and never keeps the `Element`; register it with `TapirPlugin.enrichers.add(...)` inside the `!kReleaseMode` block after `TapirPlugin.install()`. Test it by calling it directly:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapir/tapir.dart';

String? greetingEnricher(Element element, RefRegistry refs) {
  final Widget widget = element.widget;

  return widget is Text ? 'greeting: ${widget.data}' : null;
}

void main() {
  testWidgets('greetingEnricher reads the Text data', (WidgetTester tester) async {
    await tester.pumpWidget(
      const Text('Hello', textDirection: TextDirection.ltr),
    );

    final Element element = tester.element(find.text('Hello'));

    expect(greetingEnricher(element, RefRegistry.instance), 'greeting: Hello');
  });
}
```

In CI, drive the app with the CLI and chain on exit codes (rule 17).

## References

| Read when | File |
|---|---|
| Calling a `tapir_*` tool and you need its parameters, return shape or errors | `${CLAUDE_SKILL_DIR}/references/mcp-tools.md` |
| Running a `tapir:*` command from Bash: flags, output, exit codes | `${CLAUDE_SKILL_DIR}/references/cli-commands.md` |
| An action failed the gate, a ref went stale, or the error envelope needs parsing | `${CLAUDE_SKILL_DIR}/references/actionability-and-refs.md` |
| Composing a longer flow: modals, lists, long pages, logs, recovery | `${CLAUDE_SKILL_DIR}/references/workflows.md` |
