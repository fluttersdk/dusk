# Actionability gate

## Overview

The actionability gate is the precondition check the four direct-action handlers
(`tap`, `hover`, `drag`, `type`) run BEFORE synthesising the pointer or key
event. It lives in [`lib/src/utils/actionability_gate.dart`][src] and is invoked
through `ensureActionable(entry, ref: ...)`. The gate guards an agent against
firing a gesture against a widget that cannot accept it: disabled, collapsed,
off-screen, animating, or covered by another widget.

A failed gate throws a typed `DuskActionabilityException` whose `message` is
re-emitted by the VM-Service handler as
`ServiceExtensionResponse.error(extensionError, exception.message)`. Agents
parse the failure-reason substring to decide whether to re-snap, re-find,
scroll, wait, or abort.

[src]: ../../lib/src/utils/actionability_gate.dart

## Precondition chain

The gate evaluates six preconditions in evaluation order (Step 0 defunct preflight + Steps 1-5 ordered checks). **The order is
FROZEN** per `CLAUDE.md` Off-limits: agents branch on the failure-reason
substring, so adding, removing, or reordering checks is a breaking change.

0. **Defunct (preflight)**; the entry's `Element` may have been deactivated by parent
   rebuild, route pop, or list-item recycle since the snapshot minted the ref.
   `findRenderObject()` returns null, or the framework throws on the inactive element.
   This guard runs before the five ordered checks below. Failure reasons:
   `defunct (element no longer attached to a render object)` or
   `defunct (element no longer mounted)`. The agent's recovery is to re-snap.
1. **Enabled**; the entry's `SemanticsNode` is non-null AND its
   `flagsCollection.isEnabled` is `Tristate.isFalse`. `Tristate.none` (no
   enabled flag set, e.g. plain `Text`) and `Tristate.isTrue` both pass. The
   gate only fails when the framework has explicitly marked the widget
   disabled. Synthetic entries without a captured `SemanticsNode` (for example,
   `find_by_text` results) pass through this check untouched.
2. **Zero-area rect**; the entry's `rect.width == 0 || rect.height == 0`. A
   zero-area rect cannot receive a pointer event at `rect.center` and almost
   always indicates the widget has been collapsed or detached between snapshot
   and action.
3. **Off-viewport**; the entry's rect does not intersect the active
   `FlutterView`'s logical viewport (recomputed every call from
   `WidgetsBinding.instance.platformDispatcher.views.firstOrNull` so window
   resizes between actions are honored). The gate first attempts
   `RenderObject.showOnScreen` to bring the element into view, then re-checks;
   it fails only when scroll-into-view cannot place the target inside the
   viewport. Skipped gracefully when no `FlutterView` is attached (headless
   test harnesses, multi-view race).
4. **Stable** (Wave 3 addition); the entry's bounding box, re-resolved from
   the live `RenderBox` after one frame, has not drifted by more than 0.5
   logical pixels on any side. Animated widgets (sliding sheets, expanding
   tiles, page transitions) fail this gate so the agent waits for the
   animation to settle before retrying. Baseline is the post-auto-scroll
   rect from step 3, not the original entry rect, so deliberate scroll motion
   does not trip this check. Opt out via `checkStable: false`.
5. **Receives events** (Wave 3 addition); a hit-test at `rect.center` on the
   active view confirms the entry's render object (or a descendant) appears
   in the hit-test path. If the topmost target is anything else, an overlay,
   modal scrim, or stacked widget is swallowing the pointer. The thrown reason
   carries the obscurer's `runtimeType`. A graceful degradation accepts the
   action when the hit-test path contains only a root `RenderView` /
   `_ReusableRenderView` (Flutter Web's debug compositor sometimes pipes
   hit-tests through a snapshot view that does not mirror the live element
   subtree). Opt out via `checkReceivesEvents: false`.

## Live-rect dispatch (post-gate, pre-dispatch)

After the gate passes and BEFORE the pointer is synthesised, every pointer verb
(`tap`, `hover`, `drag` start + end endpoints, `dblclick`, `right_click`,
`triple_click`) re-resolves the target's CURRENT bounding rect via
`dispatchRectOf(entry)` and dispatches at that live center, falling back to the
cached `entry.rect.center` only when the live rect is `null` (a sliver, a
detached / unsized render object, or a synthetic test entry). `dispatchRectOf`
reuses the same `_liveRectOf(entry.element)` helper the stable check (step 4)
measures, guarded by the `renderObject.attached` precondition Flutter's
`localToGlobal` asserts.

This is purely additive to the FROZEN gate: it runs after the gate passes and
before dispatch, so it touches neither the evaluation order nor any
failure-reason substring. It fixes the false-success class where a host rebuilt
the target into a shifted slot between snapshot and action: the `Element` /
`RenderObject` identity (and thus `SemanticsNode.id`) is retained across a
same-type-and-key rebuild, so the live rect is valid and the pointer lands on
the moved target instead of its stale gate-time position. A residual TOCTOU
window remains between the live-rect re-resolve and the dispatch itself (the
smallest achievable without a frame lock); the opt-in `verify` flag on
`ext.dusk.tap` lets an agent confirm the tap produced an observable effect.

## Failure reason substrings

The thrown message has the shape
`Widget ref=$ref is not actionable: $reason`. Agents perform substring matches
against `$reason` to branch their recovery. **The substring list is FROZEN**:

| Reason substring   | Trips when                                                                  | Suggested agent recovery                      |
|--------------------|-----------------------------------------------------------------------------|-----------------------------------------------|
| `defunct (...)`    | `findRenderObject()` returns null OR Element is in `_ElementLifecycle.defunct` lifecycle state | Re-snap; the widget was deactivated. |
| `not enabled`      | `flagsCollection.isEnabled == Tristate.isFalse`                             | Re-snap; the widget may enable later.         |
| `zero rect`        | `rect.width == 0 \|\| rect.height == 0`                                     | Re-snap or re-find; layout has shifted.       |
| `off-viewport`     | rect does not overlap the viewport even after `showOnScreen` + one frame    | `dusk_scroll_to_ref` then retry.              |
| `not stable`       | live rect drifted > 0.5 logical pixels on any side after one frame          | `dusk_wait_for_network_idle` or settle delay. |
| `obscured by`      | hit-test at `rect.center` resolves to a non-descendant render object first  | Dismiss the obscurer (modal, scrim, overlay). |

The off-viewport reason carries the rect and viewport
(`off-viewport (rect=..., viewport=...)`); the not-stable reason carries the
maximum side delta (`not stable (rect changed by X.Xpx)`); the obscured reason
carries the obscurer's runtime type (`obscured by other widget (top=...)`).
Match on the leading substring shown above, not the trailing detail.

## Opt-out flags

`ensureActionable` exposes two opt-out parameters; both default to `true` to
match Playwright's "4-gate" actionability semantics:

```dart
Future<void> ensureActionable(
  RefEntry entry, {
  required String ref,
  bool checkStable = true,
  bool checkReceivesEvents = true,
});
```

| Flag                      | Disables                       | When to opt out                                                                                            |
|---------------------------|--------------------------------|------------------------------------------------------------------------------------------------------------|
| `checkStable: false`      | the stable precondition (4)    | widget tests that fabricate synthetic `RefEntry` rects which do not match the live render-object geometry. |
| `checkReceivesEvents: false` | the receives-events precondition (5) | the same widget-test scenarios, plus environments where the platform compositor swallows hit-tests.   |

Action handlers in production never override the defaults; only widget tests
of the gate itself flip these flags.

## Intentional gate skips

Three action handlers do NOT route through the actionability gate. The skips
are deliberate, documented under `Known gaps` in `CHANGELOG.md`, and listed
here so contributors do not add the gate "for symmetry":

- **`scroll`**; operates on the parent `Scrollable` rather than the ref
  target. Gating the ref would refuse scrolls against widgets that are
  off-viewport, which is exactly the scenario `dusk_scroll` is meant to fix.
- **`select_option`**; dispatches through Material / Cupertino popup machinery
  that owns its own enabled check. Adding the gate would double-check enabled
  state and miss the popup-specific failure modes.
- **`press_key`**; targets the currently focused widget, not a ref. The gate
  contract requires a `RefEntry`; the focused widget may not have a token.

Promoting these skips to gated handlers is a deferred candidate; see the
CHANGELOG `### Known gaps` section.

## Cross-package implications

The four gated actions share a common error envelope. `DuskActionabilityException`
is caught by the VM-Service handler and re-emitted via
`ServiceExtensionResponse.error(extensionError, exception.message)`. The
MCP/CLI layer wraps the wire error in a `DuskErrorEnvelope` carrying the
flat message string; consuming agents (Claude Code, Cursor, Windsurf via the
MCP tool surface) parse the envelope and branch on the reason substring.

The contract guarantee is:

- The reason substrings are frozen and listed above.
- The evaluation order is frozen so substring branching stays deterministic.
- The exception is always typed; the wire format is always the flat string.
- Agents re-snap or re-find on failure. The gate never silently retries; the
  cost of a silent retry on an animating or obscured widget is a flaky test
  the agent cannot diagnose.

A change to any of these guarantees requires a coordinated bump across
`fluttersdk_dusk` (this package), `magic` (whose `MagicDuskIntegration` ships
seven enrichers and may surface gated actions through Magic facades), and
`wind` (whose `WindClassNameEnricher` participates in the snapshot pipeline
that mints the refs the gate guards). Treat the gate's public contract as
load-bearing across the FlutterSDK ecosystem.
