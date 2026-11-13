# The semantics hold

`ext.tapir.semantics_hold` releases tapir's semantics handle for one timed window, so `tapir:perf_run --semantics-pass` can measure the app without the semantics tree.

`TapirPlugin.install()` takes a semantics handle for the whole process, because every snapshot, `q<N>` handle and actionability check reads the semantics tree. The cost is that every frame of a tapir-driven app also builds that tree, which an app without tapir (and without a screen reader) does not.

- [ext.tapir.semantics_hold](#exttapirsemantics_hold)
- [Driving while the tree is released](#driving-while-the-tree-is-released)
- [Related Documentation](#related-documentation)

<a name="exttapirsemantics_hold"></a>
## ext.tapir.semantics_hold

| Param | Meaning |
|:---|:---|
| `action=release` | Drops tapir's handle. Refused unless a perf session is open, so the tree can only go away inside a timed window. |
| `action=acquire` | Takes the handle again, then awaits one frame (bounded, 200 ms) so the tree exists again when it answers. |

```json
{"action": "release", "released": true, "semanticsEnabled": false, "heldByPlatform": false}
{"action": "acquire", "acquired": true, "semanticsEnabled": true, "treeReady": true}
```

`semanticsEnabled` stays `true` after a release when something else holds a handle: the tree only goes away when the last handle does. `heldByPlatform` is `platformDispatcher.semanticsEnabled`, true when the platform holds a handle of its own. On Flutter web that is every real app once it has sent a semantics tree: the engine turns semantics on at the first update and nothing turns it off, so a release there answers `semanticsEnabled: true, heldByPlatform: true`. On a native device it is true while an accessibility service runs. `heldByPlatform: false` with `semanticsEnabled: true` is another `SemanticsHandle` in the app (or the test harness). `TapirPlugin.semanticsReleased` reads the state in-app.

The caller owns the pairing: acquire after `perf_end`, so the acquire's full tree rebuild is not a frame of the session, and acquire even when a step or `perf_end` failed. `perf_end` also re-takes a handle left released, as a safety net for a caller that died in between. `tapir:perf_run` does all of it.

---

<a name="driving-while-the-tree-is-released"></a>
## Driving while the tree is released

Anything that resolves a target reads the tree, so while it is released nothing may: `ext.tapir.find`, a `q<N>` action and a snapshot would all see no nodes, and a transient handle taken to look would rebuild the tree inside the window being measured. Resolve first, with the tree on, then dispatch by coordinates:

| Extension | Records the point (tree on) | Dispatches by coordinates |
|:---|:---|:---|
| `ext.tapir.tap` | `reportPoint: true` adds `point: {x, y}` | `{x, y}` with no `ref` |
| `ext.tapir.drag` | `reportPoint: true` adds `from` and `to`; `startRef` plus `dx`/`dy` drags by an offset | `{x, y, toX, toY}` with no ref |
| `ext.tapir.hover` | `reportPoint: true` adds `point` | (a wheel then goes through CDP) |

A coordinate dispatch has no element, so none of the actionability gate's checks can run. Its response always carries:

```json
"checks": {"gate": "skipped", "semantics": "released", "why": "..."}
```

`semantics` is `held` or `released`; the enabled check is the one that reads the tree. Nothing about a coordinate dispatch proves what it landed on: it is a replay of a point that was valid when the tree was on, for a screen that is expected to be in the same state.

---

<a name="related-documentation"></a>
## Related Documentation

- [tapir:perf_run](../commands/tapir-perf-run.md#the-semantics-pass): the command that drives the pass.
- [Actionability gate](actionability-gate.md): the checks a coordinate dispatch skips.
