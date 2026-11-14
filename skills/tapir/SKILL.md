---
name: tapir
description: "Drive, verify and profile a running Flutter app from an agent with tapir."
version: 0.0.24
when_to_use: "Use when driving, checking or profiling a running Flutter UI via tapir_* tools or tapir:* commands; not for app lifecycle or MCP wiring (dowel), log capture (crumbs) or flutter_test."
---

<!-- tapir v0.0.24 | Skill updated: 2026-11-14 -->

# tapir

Tapir lets an agent drive a Flutter app that is already running. The app registers `ext.tapir.*` VM Service extensions; you call them as `tapir_*` MCP tools or as `./bin/dowel tapir:*` commands from a shell, both reaching the same handler; the CLI flags can differ from the tool parameters (`references/cli-commands.md` lists them). The loop is: snapshot the Semantics tree, act on a ref from it, read what the action reports, wait for the result.

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

`tapir:install` puts `TapirPlugin.install()` behind `if (!kReleaseMode)` before `runApp(` (before `Magic.init(` on a Magic app), so debug and profile builds carry tapir and release builds drop it. On a Magic app it also adds `MagicTapirIntegration.install()` (from `package:magic_devtools/tapir.dart`) after `Magic.init()`, but only when the resolved `magic_devtools` is a release built on tapir; otherwise it warns and skips that line, so upgrade `magic_devtools` and rerun. Reconnect the MCP client after `mcp:install`; a stdio server is not reloaded on its own.

## Rules

### Refs

1. **Two ref spaces, never mixed.** `e<N>` comes from `tapir_snap` and names one Semantics node of that snapshot. `q<N>` comes from `tapir_find` or `tapir_observe`, stores the predicates and walks the live tree again on every action. Hold an `e<N>` for the next action after the snap; hold a `q<N>` across retries, animations, navigation and hot reload, because an `e<N>` whose node unmounted fails `defunct` unless tapir can relocate it safely (rule 2).
2. **A stale `e<N>` is relocated only when it is safe.** The action re-runs the label query bound to the ref and trusts it only when the live tree has the same number of nodes with that label on the same route; the response then lists the ref under `reresolved`. Otherwise it fails `defunct`: re-snap. An unlabelled ref is never relocated.
3. **Narrow the read before acting.** `tapir_snap { within: "e12", interactiveOnly: true }` walks one subtree and drops prose; `grep: "<regex>"` keeps matches plus their ancestors (an invalid regex is matched as text and the response carries `grepLiteral: true`). A full tree costs context, and on a shell whose sidebar repeats page labels the unscoped lookup lands on the nav item. `tapir_find { within: "e12", text: "Save" }` keeps the scope inside the handle; `within` alone is refused, so pair it with `text`, `contains`, `semanticsLabel` or `key`.
4. **A repeated label needs a narrower predicate.** `tapir_find` answers the first match plus `matchCount`; above 1 it adds `diagnostic`. Predicates are not intersected (the first set of `key`, `semanticsLabel`, `text`, `contains` is used; the one exception is a `text` beside a `key`, which must also appear in a `Text` below the keyed widget), so narrow with `key`, swap to `text` or `contains`, add `within`, or use `tapir_observe`, whose labelled handles carry their position among same-label nodes (an unlabelled candidate has no position and matches its value text, so take a snapshot ref or a `key` for it). That position is not an identity, so row-by-row use holds only while the list is unchanged: a row inserted or removed above a held handle moves a neighbour into its place and the action still reports success, so observe again after any action that adds or removes a row with that label.
5. **Trust the line markers.** A snapshot ref line ending ` [offscreen]` needs a scroll, one ending ` [occluded]` has something painted over its centre; observe candidates carry `inViewport` and `occluded`. A `typeable: true` sub-line marks the node `tapir_type` writes to.

### The actionability gate

6. **`tap`, `dblclick`, `right_click`, `triple_click`, `hover`, `drag`, `type` and `fill` pass a six-step gate first**, in this frozen order: (0) defunct preflight, (1) enabled, (2) zero rect, (3) off-viewport, auto-scrolling once under a `Scrollable`, (4) stable, 2-frame drift above 0.5px, (5) receives events, the hit test at the centre reaches the target. `clear`, `focus`, `scroll`, `press_key`, `select_option` and `set_checkbox` skip it, so a covered or disabled target is not refused there. `checkStable: false` and `checkReceivesEvents: false` skip steps 4 and 5 for one call; there is no global switch, so an exception stays visible.
7. **Branch on the reason substring, never on the full message.**

   | Substring | Meaning | Next move |
   |---|---|---|
   | `defunct` (`element no longer mounted` or `element no longer attached to a render object`) | The node left the tree | Re-snap and pick the ref again |
   | `not enabled` | Semantics `isEnabled` is false | Change the state that disables it; a retry fails the same way |
   | `zero rect` | Width or height is 0, layout pending | `tapir_wait_for` on content, then retry |
   | `off-viewport (rect=..., viewport=...)` | Auto-scroll did not bring it in | `tapir_scroll` toward it, retry |
   | `not stable (rect changed by Xpx)` | Animating | Wait; `checkStable: false` only for an intentional animation |
   | `obscured by other widget (top=...)` | Something covers it | `tapir_reset_overlays`, or `checkReceivesEvents: false` when the cover lets touches through |

   A stale `q<N>` fails with `Query handle ref=qN is stale: no live match for stored predicates`: find or observe again rather than retrying the handle.
8. **On Flutter Web step 5 often cannot answer**, so the gate proceeds and the response carries `checks: {receivesEvents: "indeterminate", why, overlapCandidates, hint}`. The key is absent when the check confirmed. When it is present, judge the action by its `effect`, not by the success.

### Reading results

9. **A success means dispatched; `effect` says what the widget holds now.** `tap`: `{kind: "treeChanged", changed}`, where `changed: false` means nothing observable moved. `type`, `clear`, `fill`: `{kind: "text", verified, value, target}`, where `verified: false` means a formatter or keyboard type rejected the write; read `target.matchKind`, and when it is `nearest` the ref overlapped no field and a neighbour was written. `scroll`: `{kind: "scrollOffset", changed, before, after}`. `set_checkbox`: `{kind: "checked", verified, before, after}`. `select_option`: `{kind: "selected", verified, value}`. Do not re-snap to confirm what `effect` already answers.
10. **A `warnings` block means do not conclude.** It appears only while the app is not producing frames, and then a snapshot reads as empty and a gesture cannot land. Tapir wakes a hidden or paused desktop app at the start of every verb except the perf verbs, `console`, `exceptions`, `close_app` and `evaluate`, and stamps `framesForced: true`, which is normal (`--dart-define=TAPIR_FORCE_FRAMES=false` turns it off). A hidden browser tab cannot be woken from inside: follow `warnings.hint` (CDP `Page.bringToFront`), then retry. The CLI does that itself when the session has a `cdpPort`, repeating only `snap` and `observe`; after an acting verb run `tapir:snap` to see what it did.
11. **A merged control taps its own child.** A `MergeSemantics` boundary whose centre is not on its control shows a `tapOwner` sub-line (observe: a `tapOwner` field). `tapir_tap` goes to that control and reports `retargeted {from, to, ownerRect}`; `centreHandled: true` means the centre has a handler of its own, and `retarget: false` (CLI `--no-retarget`) taps the centre instead. `tapPointOutsideOwner` in the response means the tap stayed at the centre: check the result.
12. **Cut round trips.** Pass `snapshot: "diff"` (CLI `--snapshot=diff`) to `tap`, `fill`, `type`, `navigate` or `scroll` to get only the changed lines since the last unfiltered snapshot; a filtered snap leaves that baseline as it was, so after an earlier plain snapshot the diff also lists everything changed since then, and with none it is the full tree. Take a plain `tapir_snap` first when you want only the last action's effect. Batch steps whose inputs you already know with `tapir_run`, and between steps that change the screen use `--text`, `--key` or `q<N>`, since `e<N>` belongs to one snapshot. `tapir_tap { until: "Saved" }` polls for that text after the tap and adds `untilMatched`.

### What each verb can and cannot do

13. **Some tools run outside the app.** `tapir_hot_reload_and_snap`, `tapir_run`, `tapir_perf_run`, `tapir_perf_compare`, `tapir_perf_trace`, `tapir_resize_viewport` and `tapir_device_profile` route through `dowel:tapir:*` in the MCP server's process, because the isolate cannot reload itself and CDP needs a browser connection. The two viewport tools work only on web started with `--cdp-port` and fail with `CDP not enabled` elsewhere; their override ends when the call returns, and only `tapir:resize --hold` run in the background keeps one.
14. **`tapir_wait_for_network_idle` needs crumbs.** It reads the in-flight HTTP count through `crumbs`, a separate package that is not published yet; without it the count is always 0 and it answers `matched: true` at once, which proves nothing, so assume it always reports idle and wait on the UI instead. `tapir_console` lists the app's own `debugPrint` output and adds crumbs entries when wired; `tapir_exceptions` keeps its own buffer. That buffer is cumulative, so read it as a delta with `since` or `clear: true`, or one boot-time fault rides along on every later read.
15. **`tapir_set_checkbox` reads the Semantics checked or toggled flag.** A flag on the ref's own node is the state, even when a merging tile folded several controls into it (never refused as ambiguous); an own node without one falls back to its single flagged descendant, tapped at that descendant; a `find_by_text` ref whose render object owns no node reads the nearest node above, its own flag only. So a checkbox, switch or radio from any library works (Flutter material, `material_ui`, `wind_kit`, a hand-built `Semantics(checked: ...)`). It taps only when the state differs, at the control it read, and reads it back; when it already equals `value` it returns `toggled: false` without a tap. It refuses a ref with no state anywhere, and one whose own node has no flag while several descendants do, so snap again and pass the control's ref. A mixed checkbox is always tapped once and reports `previousValue: null`. It skips the gate, so it does not scroll: an `[offscreen]` or covered control is missed and reads `verified: false` (the CLI exits 1, or 0 with `--json` or `--includeSnapshot`); bring it on screen first with `tapir_scroll` on the list (its ref or a visible row's), never a `tapir_tap`, which toggles the control. `tapir_select_option` calls a `DropdownButton`'s `onChanged` with the value as a string and skips the gate; for any other picker, tap it open and tap the option.
16. **`tapir_evaluate` runs a Dart expression in the app's root library.** Over MCP, dowel's server answers it through the VM Service `evaluate` RPC, so use it for a one-off expression; `dowel_tinker` and `./bin/dowel tinker --eval="<expr>"` evaluate the same way. A runtime exception, a compile error and a stale isolate come back as error results, and an expression with `await` returns the `Future`, not its value. The `ext.tapir.evaluate` extension is a debug-only sentinel and never evaluates by itself.
17. **The CLI differs from MCP in defaults and exits.** MCP action tools embed a post-action snapshot by default; the CLI does not (`--includeSnapshot` or `--snapshot=full`). `--json` prints the raw envelope on the action verbs, the waits and `snap`; `find`, `observe`, `get_routes`, `console`, `exceptions` and `reset_overlays` print JSON already. `tapir:wait` and `tapir:wait_for_network_idle` exit 1 when the wait never resolved, `tapir:fill` and `tapir:type` exit 1 on an unverified write, `tapir:set_checkbox` on an unverified toggle, and `tapir:hot_reload_and_snap` exits 1 on a failed reload.
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
./bin/dowel tapir:wait --text="Saved" --timeoutMs=8000 || echo "never appeared"
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
