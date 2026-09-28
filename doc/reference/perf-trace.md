# Interactions and the perf trace

Inside a perf session, every gesture dusk dispatches opens an **interaction**: a handle that says which verb caused the work that follows. `ext.dusk.perf_trace` exports the closed session's interactions, frames and the host's timeline rows as Chrome Trace Event JSON, which opens as is in [ui.perfetto.dev](https://ui.perfetto.dev) and `chrome://tracing`.

---

## Table of contents

- [Interactions](#interactions)
- [Reaching an interaction from app code](#reaching-an-interaction-from-app-code)
- [ext.dusk.perf_trace](#ext-dusk-perf-trace)
- [Host timeline rows](#host-timeline-rows)
- [See also](#see-also)

---

<a name="interactions"></a>
## Interactions

The verbs that dispatch into the app open one: `tap`, `dblclick`, `triple_click`, `right_click`, `hover`, `drag`, `type`, `clear`, `fill`, `press_key`, `focus`, `blur`, `scroll`, `select_option`, `set_checkbox`, `navigate`, `navigate_back`, `dismiss_modals` and `reset_overlays`. Only while a session is open: outside one a verb runs exactly as before, with no handle, no zone and no timer. A gesture that fails the actionability gate dispatched nothing and opens nothing, with one exception: `fill` opens its interaction first and gates each of its steps inside it.

A `PerfInteraction` carries:

| Field | Meaning |
|---|---|
| `id` | `i<N>`, unique for the isolate's lifetime. |
| `verb` | The `ext.dusk.*` verb without its prefix. |
| `target` | The ref, route or key the verb acted on; `null` for `blur`, `navigate_back`, `dismiss_modals`, `reset_overlays`. |
| `startUs` | `FlutterTimeline.now` at dispatch. |
| `closedAtUs` | `FlutterTimeline.now` at settle; `null` while open. |

An interaction **closes at settle**: once no frame has been scheduled for 300 ms, after 5 s whatever the app does (an infinite animation never goes quiet), or when the session closes. A verb dispatched inside another joins it rather than opening its own: `fill` runs `focus`, `clear` and `type`, and to the app that is one gesture.

Interactions may overlap: an agent can tap again before the last tap settles.

---

<a name="reaching-an-interaction-from-app-code"></a>
## Reaching an interaction from app code

Two routes, because Dart zones reach some of a gesture's consequences and not others.

**The zone.** dusk dispatches the gesture inside `runZoned(zoneValues: {#fluttersdk_interaction: handle})`. Gesture callbacks run synchronously inside that dispatch, and Timers, microtasks, Futures and stream subscriptions created there keep the zone they were created in, so an `onTap` that starts a request hands it the interaction:

```dart
final Object? value = Zone.current[#fluttersdk_interaction];
final PerfInteraction? interaction =
    value is PerfInteraction && value.closedAtUs == null ? value : null;
```

`#fluttersdk_interaction` is a public symbol and equal across libraries, so a package reads it without importing dusk; `PerfInteraction.zoneKey` names the same symbol.

**Treat a closed handle as absent.** A Timer or a subscription keeps its zone forever: a Reverb socket opened during a login tap would otherwise attribute every later message to that tap. The close is what bounds the attribution.

**The active slot.** Frames, builds, `initState` and post-frame callbacks run in the binding's frame zone, not in the zone that marked a widget dirty, so a refetch fired from `initState` after a tap navigated never sees the zone value. That work joins by time through `activeInteraction()`, which returns the newest interaction still open (or `null` outside a session), and marks the join `linkedBy: 'frame'`. Work that read its own zone marks `linkedBy: 'zone'`.

---

<a name="ext-dusk-perf-trace"></a>
## ext.dusk.perf_trace

| Param | Meaning |
|---|---|
| `token` | Optional. The session's `sessionToken`; when given it must name the most recent closed session, the only one kept. |

```json
{
  "sessionToken": "perf-1",
  "traceEvents": [
    {"ph": "M", "name": "process_name", "pid": 1, "args": {"name": "fluttersdk_dusk perf-1"}},
    {"ph": "M", "name": "thread_name", "pid": 1, "tid": 1, "args": {"name": "interactions"}},
    {"ph": "X", "cat": "interaction", "name": "tap", "ts": 812345, "dur": 412000, "pid": 1, "tid": 1,
     "args": {"id": "i1", "target": "e3"}},
    {"ph": "X", "cat": "frame", "name": "Frame 212", "ts": 813001, "dur": 16200, "pid": 1, "tid": 2,
     "args": {"frameNumber": 212, "buildMs": 9.1, "rasterMs": 2.2, "interactionId": "i1", "linkedBy": "frame"}},
    {"ph": "b", "cat": "http", "name": "GET /monitors", "id": "r1", "ts": 812500, "pid": 1, "tid": 3,
     "args": {"interactionId": "i1", "linkedBy": "zone"}},
    {"ph": "e", "cat": "http", "name": "GET /monitors", "id": "r1", "ts": 1012500, "pid": 1, "tid": 3}
  ],
  "displayTimeUnit": "ms",
  "otherData": {"sessionToken": "perf-1", "startUs": 800000, "endUs": 2900000,
                "interactions": 1, "frames": 45, "rows": 12, "skippedRows": 0}
}
```

- **Interactions** are `X` slices on the `interactions` track, from `startUs` to `closedAtUs`; one still open when the session closed ends at the session's end.
- **Frames** are `X` slices on the `frames` track, placed at `vsyncStartUs` for `totalSpanMicros`. A frame record without `vsyncStartUs` cannot be placed and is left out.
- **Host spans with an `id`** become async `b`/`e` pairs keyed by that id, with `cat` set to the track: the shape for work that overlaps other work on its track, such as two requests in flight. Spans without an id become `X` slices, instants `i` events, counters `C` events.
- `X` slices must nest on their track for Perfetto to draw them. Two can straddle in ordinary use (a tap before the last one settled, a frame whose build starts while the previous one rasterizes), so a slice that would straddle another moves to an overflow lane, `interactions (2)`, rather than being trimmed. Durations stay true.
- Only what STARTED inside the session window is exported; the window runs from `perf_begin` to `perf_end`.

The frames and the host rows are read when you call `perf_trace`, not when the session closed. Export before the next `perf_begin`, whose host hook clears those buffers: while a session is open `perf_trace` answers an error rather than a trace that silently lost its frames. It also answers an error before any session closed, for a token that is not the one held, and when a host reader throws.

---

<a name="host-timeline-rows"></a>
## Host timeline rows

The host (magic_devtools) fills the `perfTimelineReader` pointer. One row per map:

```text
{kind: 'span'|'instant'|'counter', track: String, name: String,
 startUs: int, endUs: int?, id: String?, interactionId: String?,
 linkedBy: String?, value: num?, args: Map?}
```

Times are `FlutterTimeline.now` microseconds, the clock dusk stamps interactions and the session window with. A span with no `endUs` is still running and ends at the session's end. Return the whole buffer; dusk keeps the rows inside the window. A row missing `kind`, `track`, `name` or an int `startUs`, a kind outside the three above, or a counter without a numeric `value` is skipped and counted in `otherData.skippedRows`, never a failed export.

---

<a name="see-also"></a>
## See also

- [dusk:perf_begin](../commands/dusk-perf-begin.md): opens the session interactions are recorded in.
- [dusk:perf_end](../commands/dusk-perf-end.md): closes it; the trace exports that session.
- [Perfetto: other formats](https://perfetto.dev/docs/getting-started/other-formats): the Chrome JSON rules the trace follows.
