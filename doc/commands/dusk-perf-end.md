# dusk:perf_end

Close the measurement session opened by `dusk:perf_begin` and read a bounded report: frame percentiles against a stated budget, blocks ranked by self time and by count per painted frame, wind and magic counters, and ranked insights you can drill into with `dusk:perf_insight`. It also restores every profiling flag the session changed, so a session you forget to close is the one that taxes every later frame.

---

## Table of contents

- [Synopsis](#synopsis)
- [Returns](#returns)
- [Insights](#insights)
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

**Success envelope** (bounded to about 6 KB; the rows behind each insight stay behind `dusk:perf_insight`):

```json
{
  "sessionToken": "perf-1",
  "refused": false,
  "mode": "attribution",
  "env": {"platform": "macOS", "isWeb": true, "buildMode": "debug", "semanticsEnabled": true, "phases": false},
  "coverage": {"framesDrawn": 45, "framesSummarized": 45, "complete": true, "missing": []},
  "summary": {
    "durationMs": 2310.4,
    "budgetMs": 16.7,
    "frames": {
      "count": 45, "painted": 45, "dropped": 0,
      "overBudget": 3, "overBudgetBuild": 3, "overBudgetRaster": 0,
      "buildMs": {"p50": 3.1, "p90": 8.1, "p99": 31.2, "worst": 31.2},
      "rasterMs": {"p50": 1.2, "p90": 1.9, "p99": 2.4, "worst": 2.4}
    },
    "blocksBySelf": [{"name": "MonitorRow", "selfMs": 21.4, "frames": 12}],
    "blocksByCount": [{"name": "WText", "count": 540, "perFrame": 12.0}],
    "routeTransitions": [{"route": "/monitors", "ms": 118.2}]
  },
  "counters": {
    "columns": ["name", "count", "perFrame"],
    "wind": {"cacheHits": {"count": 812, "perFrame": 18.04}, "cacheSize": 64, "widgetBuilds": [["WDiv", 402, 8.93]]},
    "magic": {"controllerNotifies": [["MonitorController", 12, 0.27]]}
  },
  "insights": [
    {
      "id": "I1",
      "severity": "warn",
      "title": "3 of 45 frames over the 16.7ms budget",
      "evidence": {"metric": "framesOverBudget", "value": 3, "perFrame": 0.07, "threshold": {"budgetMs": 16.7, "errorShare": 0.1}},
      "estimatedSavingsMs": 29.4,
      "nextStep": "Build-bound: drill in for the worst frames and their self-time blocks."
    }
  ],
  "omitted": {"blocksBySelf": 212, "blocksByCount": 212, "routeTransitions": 0, "wind.widgetBuilds": 9, "insights": 0}
}
```

- `env` says where the numbers came from, read in the app: `buildMode` from `kProfileMode` / `kDebugMode`, and `semanticsEnabled`, which is `true` whenever dusk is installed because dusk holds a semantics handle for the whole process.
- `coverage` says whether the summary describes every frame the engine drew. `framesDrawn` comes from the liveness counter, which a post-frame callback increments once per frame; `framesSummarized` counts the records Flutter's `onReportTimings` delivered, and Flutter batches those. When `complete` is `false` the report describes a SUBSET and the coverage insight says so: an empty ranking then means "not reported", not "nothing was slow". `missing` names sources that were never read: `wind` (no wind perf resolver, so `counters.wind` is `null`, which is a different finding from zeros), `blocks`, `blockSelfTime`. Read this before the numbers.
- `summary.frames`: `painted` is the frames Flutter reported, `dropped` the frames missing from the `frameNumber` sequence (how a dropped scene shows on web), `count` their sum. A frame is over budget when its slower thread took longer than `budgetMs`.
- `blocksBySelf` ranks by EXCLUSIVE time. A parent's inclusive time contains its children's, so ranking by it blames the parent for the child's work. `frames` separates a block that cost 10ms once from one that cost 0.1ms in each of a hundred frames; those need opposite fixes. Both block lists keep the top 10; `omitted` counts the rest.
- `counters` are given raw and per painted frame. A breakdown keeps its top 3 as positional rows in `columns` order.
- In `timing` mode `counters` is `null` and `summary` carries `durationMs`, `budgetMs` and `frames` only.

Attribution milliseconds are inflated by the profiling that makes attribution possible. Rank by them; compare milliseconds only between `--mode=timing` sessions.

---

<a name="insights"></a>
## Insights

At most six, sorted by severity (`error`, `warn`, `info`) then `estimatedSavingsMs`. Each carries `id`, `severity`, `title`, `evidence {metric, value, perFrame, threshold}` and `nextStep`; the threshold it was judged against is always in the evidence, so a verdict can be checked rather than trusted. Ids are assigned before the sort and the cut, so an insight counted in `omitted.insights` is still drillable.

| Metric | Fires when | Severity |
|---|---|---|
| `framesOverBudget` | a frame's slower thread exceeds 16.7ms | `error` past a 0.1 share of painted frames, else `warn` |
| `framesDropped` | the `frameNumber` sequence steps by 2 or more | `error` past a 0.1 share, else `warn` |
| `blockSelfMs` | one block owns at least 0.3 of all self time and at least 1ms per painted frame | `error` past 8.35ms per frame, else `warn` |
| `blockCountPerFrame` | one block runs at least 20 times per painted frame and 10 times the median block | `warn` |
| `framesUnreported` / `sourcesMissing` | coverage is incomplete, or a source was never read | `warn`, or `info` when only wind is missing |
| `contributorErrors` | a host-contributed rule threw or returned a malformed insight | `warn` |

The host adds its own rules through `perfInsightContributors` (magic_devtools fills it with wind and magic rules). A contributor that fails costs its own insights and never the report.

---

<a name="the-refusal"></a>
## The refusal

Check `refused` before anything else.

```json
{
  "sessionToken": "perf-1",
  "refused": true,
  "mode": "attribution",
  "coverage": {"framesDrawn": 0, "livenessBaseline": 412, "livenessFinal": 412, "complete": false},
  "reason": "The liveness counter advanced by 0 between perf_begin and perf_end ..."
}
```

When the liveness counter advanced by 1 or less, the engine rendered nothing worth measuring and every metric would be a zero or a single sample that reads as "fast". The response therefore carries no metrics at all, `dusk:perf_insight` has nothing to drill into, and the command exits `1` so a shell caller cannot chain on a report that does not exist.

The ordinary cause is an idle app, not a broken one. Flutter schedules a frame only when something is dirty, so a session that opens, sleeps and closes legitimately draws nothing: drive an interaction inside the session, and aim a scroll at something that actually scrolls. The second cause is a hidden or backgrounded page, which produces exactly one frame rather than zero, which is why the threshold is `1` and not `0`.

That counter is the authority here, not the `warnings` block that may sit on the same response: `SchedulerBinding.framesEnabled`, which the warning reads, was measured reporting `true` with lifecycle `resumed` on a Chrome page that was hidden and had produced one frame in two seconds. Bring the page to front (CDP `Page.bringToFront`) and run the session again.

---

<a name="examples"></a>
## Examples

### 1. Read the insights after a scroll

```bash
dart run fluttersdk_dusk dusk:perf_end --json | jq '.insights'
```

### 2. Human summary at a terminal

```bash
dart run fluttersdk_dusk dusk:perf_end
```

```
✓ Performance session perf-1 closed (attribution): 45 painted frames, 3 over the 16.7ms budget, worst build 31.2ms. 2 insights; top [warn] I1: 3 of 45 frames over the 16.7ms budget. Drill in with dusk:perf_insight --id=I1, or pass --json for the report.
```

---

<a name="see-also"></a>
## See also

- [dusk:perf_begin](dusk-perf-begin.md): opens the session, picks the mode, records the liveness baseline.
- [dusk:perf_insight](dusk-perf-insight.md): the rows behind one insight.
- [Frame production](../reference/frame-production.md): the backgrounded-tab failure mode the refusal exists for.
