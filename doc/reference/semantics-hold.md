# The semantics hold

`DuskPlugin.install()` takes a semantics handle for the whole process, because every snapshot, `q<N>` handle and actionability check reads the semantics tree. The cost is that every frame of a dusk-driven app also builds that tree, which an app without dusk (and without a screen reader) does not. `ext.dusk.semantics_hold` lets `dusk:perf_run --semantics-pass` measure the app without it, for one timed window.

---

## ext.dusk.semantics_hold

| Param | Meaning |
|---|---|
| `action=release` | Drops dusk's handle. Refused unless a perf session is open, so the tree can only go away inside a timed window. |
| `action=acquire` | Takes the handle again, then awaits one frame (bounded, 200 ms) so the tree exists again when it answers. |

```json
{"action": "release", "released": true, "semanticsEnabled": false}
{"action": "acquire", "acquired": true, "semanticsEnabled": true, "treeReady": true}
```

`semanticsEnabled` stays `true` after a release when something else holds a handle (a screen reader, the test harness): the tree only goes away when the last handle does. `DuskPlugin.semanticsReleased` reads the state in-app.

The caller owns the pairing: acquire before `perf_end`, including when a step in between failed. `dusk:perf_run` does both.

---

## Driving while the tree is released

Anything that resolves a target reads the tree, so while it is released nothing may: `ext.dusk.find`, a `q<N>` action and a snapshot would all see no nodes, and a transient handle taken to look would rebuild the tree inside the window being measured. Resolve first, with the tree on, then dispatch by coordinates:

| Extension | Records the point (tree on) | Dispatches by coordinates |
|---|---|---|
| `ext.dusk.tap` | `reportPoint: true` adds `point: {x, y}` | `{x, y}` with no `ref` |
| `ext.dusk.drag` | `reportPoint: true` adds `from` and `to`; `startRef` plus `dx`/`dy` drags by an offset | `{x, y, toX, toY}` with no ref |
| `ext.dusk.hover` | `reportPoint: true` adds `point` | (a wheel then goes through CDP) |

A coordinate dispatch has no element, so none of the actionability gate's checks can run. Its response always carries:

```json
"checks": {"gate": "skipped", "semantics": "released", "why": "..."}
```

`semantics` is `held` or `released`; the enabled check is the one that reads the tree. Nothing about a coordinate dispatch proves what it landed on: it is a replay of a point that was valid when the tree was on, for a screen that is expected to be in the same state.

---

## See also

- [dusk:perf_run](../commands/dusk-perf-run.md#the-semantics-pass), which drives the pass.
- [The actionability gate](actionability-gate.md).
