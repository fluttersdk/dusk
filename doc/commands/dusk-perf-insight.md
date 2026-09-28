# dusk:perf_insight

Drill into one insight of the report `dusk:perf_end` last produced: its title, a summary in prose, the raw rows behind it, the estimated savings and the next step. The report stays small because these rows live here; ask for the one insight you are acting on.

---

## Table of contents

- [Synopsis](#synopsis)
- [Returns](#returns)
- [Errors](#errors)
- [Examples](#examples)
- [See also](#see-also)

---

<a name="synopsis"></a>
## Synopsis

```
dart run fluttersdk_dusk dusk:perf_insight --id=<I1> [--token=<perf-1>] [--json]
```

`dusk:perf_insight` requires a running Flutter session (`CommandBoot.connected`) and calls `ext.dusk.perf_insight`.

| Flag | Default | Meaning |
|------|---------|---------|
| `--id` | required | Insight id from the `insights[]` list `dusk:perf_end` returned. Ids are assigned before the report cuts its list, so one counted in `omitted.insights` is drillable too. |
| `--token` | none | The report's `sessionToken`. Only the most recent closed session is kept; a token naming any other is refused, which guards against reading a newer session than the report you hold. |
| `--json` | `false` | Print the raw envelope, `detail` included, instead of the human summary. |

---

<a name="returns"></a>
## Returns

| Exit code | Meaning |
|-----------|---------|
| `0` | Drill-down returned. |
| `1` | `--id` missing. |
| non-zero | The handler returned an error (see below). |

```json
{
  "sessionToken": "perf-1",
  "id": "I1",
  "severity": "warn",
  "title": "3 of 45 frames over the 16.7ms budget",
  "summary": "3 of 45 painted frames took longer than 16.7ms on their slower thread (3 over on build, 0 on raster). Their time past the budget totals 29.4ms, the most a fix to these frames alone could win back.",
  "detail": {
    "overBudgetBuild": 3,
    "overBudgetRaster": 0,
    "worstFrames": [
      {"frameNumber": 212, "buildMs": 31.2, "rasterMs": 2.1, "blocks": [{"name": "MonitorRow", "selfMs": 9.8, "count": 12}]}
    ]
  },
  "estimatedSavingsMs": 29.4,
  "nextStep": "Build-bound: drill in for the worst frames and their self-time blocks."
}
```

`detail` depends on the rule:

| Metric | `detail` |
|---|---|
| `framesOverBudget` | `overBudgetBuild`, `overBudgetRaster`, and up to 10 `worstFrames`, each with its top 5 blocks by self time |
| `framesDropped` | up to 20 `gaps` as `{after, next, missing}`, plus `gapsOmitted` |
| `blockSelfMs` | the `block` (self and inclusive ms, count, frames, share), `totalSelfMs`, and the 10 frames where it cost most |
| `blockCountPerFrame` | the `block`, `medianPerFrame`, and the 10 frames where it ran most |
| `framesUnreported` / `sourcesMissing` | the coverage map |
| `contributorErrors` | which contributor failed and how |

`estimatedSavingsMs` is `null` where no saving can be stated. Where it is stated it is an upper bound: the time past the budget, or a block's whole self time.

---

<a name="errors"></a>
## Errors

Each names what to read instead:

- No `--id`: an `invalidParams` error asking for an id from `insights[]`.
- No session has closed yet: run `dusk:perf_begin`, drive, `dusk:perf_end`.
- A stale `--token`: the error names the session that IS held.
- The last session was refused: it has no insights; rerun it with an interaction driven inside.
- An id the session never issued: the error points at the `insights[]` list of `dusk:perf_end`.

---

<a name="examples"></a>
## Examples

### 1. Open the top insight the summary line named

```bash
dart run fluttersdk_dusk dusk:perf_end
dart run fluttersdk_dusk dusk:perf_insight --id=I1
```

### 2. The worst frames as JSON

```bash
dart run fluttersdk_dusk dusk:perf_insight --id=I1 --token=perf-1 --json | jq '.detail.worstFrames'
```

---

<a name="see-also"></a>
## See also

- [dusk:perf_end](dusk-perf-end.md): the report whose ids this reads, and the rules behind each insight.
- [dusk:perf_begin](dusk-perf-begin.md): attribution versus timing mode.
