# dusk:perf_compare

Judge one `dusk:perf_run` file against another: a verdict per metric and one overall, on counts per painted frame first and timing-mode milliseconds second.

---

## Table of contents

- [Synopsis](#synopsis)
- [What is compared](#what-is-compared)
- [Returns](#returns)
- [See also](#see-also)

---

<a name="synopsis"></a>
## Synopsis

```
dart run fluttersdk_dusk dusk:perf_compare <a.json> <b.json> [--json]
```

`dusk:perf_compare` reads two files and needs no running app (`CommandBoot.none`). `a` is the baseline, `b` the candidate; `--a` and `--b` name them too, which is how the MCP tool passes them.

---

<a name="what-is-compared"></a>
## What is compared

- **Counts per painted frame**, from `summary.perFrame`, are the gate. Raw counts are never compared: a run that drew 10% fewer frames reports 10% fewer of every count, which reads as an improvement and is not one. The painted-frame counts are shown as info.
- **Milliseconds**, only from `summary.timing.ms`, the medians of the `--timing` repeats. Attribution milliseconds are inflated by build profiling and never gated; without a timing pass on both sides the result says so in `timing.note`.
- **Emulator raster milliseconds** (`env.emulator`) are listed with severity `info` and never gated: an emulator's raster thread is the host GPU's, not a device's.

Every metric is one where higher is worse. Per metric:

| Change (B against A) | Verdict |
|---|---|
| inside either run's own repeat-to-repeat range (`summary.spread`) | `unchanged`: the repeats produce that much by themselves |
| at or above `error` percent | `regressed`, severity `error` |
| at or above `warn` percent | `regressed`, severity `warn` |
| at or below minus `warn` percent | `improved` |
| a metric A never recorded | `regressed`, severity `warn`, no percentage |
| otherwise | `unchanged` |

Thresholds default to warn 10% and error 25%, and come from B's scenario `thresholds` (else A's). The overall verdict is `regressed` when any gated row regressed, else `improved` when any improved, else `unchanged`.

---

<a name="returns"></a>
## Returns

The default output is a compact table: the verdict and thresholds, the painted frames of each side, then the changed rows, worst first (the first 20; `--json` has all).

```json
{
  "verdict": "regressed",
  "thresholds": {"warn": 10, "error": 25},
  "frames": {"painted": {"a": 100, "b": 90}},
  "rows": [
    {"metric": "blocks.MonitorRow", "a": 2.0, "b": 2.6, "deltaPct": 30.0,
     "verdict": "regressed", "severity": "error"},
    {"metric": "timing.rasterMs.p50", "a": 3.0, "b": 9.0, "deltaPct": 200.0,
     "verdict": "regressed", "severity": "info"}
  ],
  "unchanged": 41,
  "timing": {"gated": true}
}
```

| Exit code | Meaning |
|-----------|---------|
| `0` | No error-level regression (a warn is reported, not failed). |
| `1` | An error-level regression, a missing argument or file, or a run with no measured repeat (every one refused). |

---

<a name="see-also"></a>
## See also

- [dusk:perf_run](dusk-perf-run.md): the files this reads.
