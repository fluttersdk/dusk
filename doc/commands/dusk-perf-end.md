# dusk:perf_end

Close the measurement session opened by `dusk:perf_begin` and read the attribution: which widget and RenderObject types ran, how many times and for how long, next to wind's cache counters and magic's controller notifies. It also restores every profiling flag the session changed, so a session you forget to close is the one that taxes every later frame.

---

## Table of contents

- [Synopsis](#synopsis)
- [Returns](#returns)
- [The refusal](#the-refusal)
- [Examples](#examples)
- [See also](#see-also)

---

<a name="synopsis"></a>
## Synopsis

```
dart run fluttersdk_dusk dusk:perf_end [--json]
```

`dusk:perf_end` requires a running Flutter session (`CommandBoot.connected`) and calls `ext.dusk.perf_end`. It takes no arguments beyond `--json`. Without a prior `dusk:perf_begin` it returns a typed error: the session carries the flag values to restore and the liveness baseline the report is judged against, and neither can be reconstructed afterwards.

---

<a name="returns"></a>
## Returns

| Exit code | Meaning |
|-----------|---------|
| `0` | Report returned. |
| `1` | The run was REFUSED (see below), or the handler returned an error. |

**Success envelope:**

```json
{
  "sessionToken": "perf-1",
  "refused": false,
  "phases": true,
  "liveness": {"baseline": 412, "final": 457, "advanced": 45},
  "coverage": {"framesDrawn": 45, "framesSummarized": 45, "complete": true},
  "frameSummary": {
    "average_frame_build_time_millis": 3.2,
    "90th_percentile_frame_build_time_millis": 8.1,
    "worst_frame_build_time_millis": 20.0,
    "missed_frame_build_budget_count": 1,
    "dropped_frame_count": 0,
    "frame_count": 45,
    "worst_frames": []
  },
  "blockAttribution": [
    {"name": "MonitorRow", "micros": 10200, "count": 10, "frames": 2}
  ],
  "wind": {"cacheHits": 12, "cacheMisses": 3, "cacheBypasses": 40},
  "magic": {"controllerNotifies": {"MonitorController": 12}, "routeTransitions": []},
  "note": "Per-type absolute durations are indicative, not representative ..."
}
```

- `coverage` says whether the summary describes every frame the engine drew. `framesDrawn` comes from the liveness counter, which a post-frame callback increments once per frame; `framesSummarized` counts the records Flutter's `onReportTimings` delivered, and Flutter batches those, so a session that ends shortly after the work can close before the last timings arrive. When `complete` is `false` a `detail` string is present and `frameSummary` plus `blockAttribution` describe a SUBSET: an empty attribution then means "not reported", not "nothing was slow". Read this before reading the numbers. Measured driving a real app: a theme toggle drew 4 frames, 2 were reported, and the report looked complete.
- `frameSummary` uses `flutter_driver`'s metric-name strings verbatim, so a reading here is comparable to devicelab's. `dropped_frame_count` comes from gaps in the frame-number sequence, because on web a dropped scene is a missing frame number rather than a slow frame.
- `blockAttribution` aggregates every frame's spans across the whole session, ranked by microseconds. `frames` separates a block that cost 10ms once from one that cost 0.1ms in each of a hundred frames; those need opposite fixes.
- `wind` is `null` when no wind perf resolver registered. That is a different finding from a wind section of zeros, so the two are not collapsed.
- `note` says per-type absolute durations are indicative rather than representative. Flutter's own docs say the instrumentation overhead is significant relative to the work it measures, and this is a debug build. Read the counts, the ratios and the ranking; do not quote a per-type millisecond as a fact about production.

---

<a name="the-refusal"></a>
## The refusal

Check `refused` before anything else.

```json
{
  "sessionToken": "perf-1",
  "refused": true,
  "phases": true,
  "liveness": {"baseline": 412, "final": 412, "advanced": 0},
  "reason": "The liveness counter did not advance between perf_begin and perf_end ..."
}
```

When the liveness counter did not advance, the engine rendered nothing during the session and every metric would be a zero that reads as "fast". The response therefore carries no metrics at all, and the command exits `1` so a shell caller cannot chain on a report that does not exist.

The ordinary cause is an idle app, not a broken one. Flutter schedules a frame only when something is dirty, so a session that opens, sleeps and closes legitimately draws nothing: drive an interaction inside the session, and aim a scroll at something that actually scrolls. The second cause is a hidden or backgrounded page, which produces exactly one frame rather than zero, which is why the threshold is `1` and not `0`.

That counter is the authority here, not the `warnings` block that may sit on the same response: `SchedulerBinding.framesEnabled`, which the warning reads, was measured reporting `true` with lifecycle `resumed` on a Chrome page that was hidden and had produced one frame in two seconds. Bring the page to front (CDP `Page.bringToFront`) and run the session again.

---

<a name="examples"></a>
## Examples

### 1. Read the ranking after a scroll

```bash
dart run fluttersdk_dusk dusk:perf_end --json | jq '.blockAttribution[:5]'
```

### 2. Human summary at a terminal

```bash
dart run fluttersdk_dusk dusk:perf_end
```

```
✓ Performance session closed: 45 frames, worst build 20.0ms. Pass --json for the full attribution.
```

---

<a name="see-also"></a>
## See also

- [dusk:perf_begin](dusk-perf-begin.md): opens the session and records the liveness baseline.
- [Frame production](../reference/frame-production.md): the backgrounded-tab failure mode the refusal exists for.
- [dusk:screenshot](dusk-screenshot.md): confirm visually that the screen you measured is the screen you meant.
