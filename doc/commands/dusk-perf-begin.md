# dusk:perf_begin

Open a performance measurement session around an interaction you are about to drive. `dusk:perf_begin` zeroes the frame buffer and the wind and magic counters and records the liveness baseline that `dusk:perf_end` judges the run against. In `attribution` mode (the default) it also switches Flutter's build profiling on; in `timing` mode it touches no profiling flag at all. Nothing is measured until you call it, and the instrumentation costs real time, so keep every session tight: begin, drive one interaction, end.

---

## Table of contents

- [Synopsis](#synopsis)
- [Modes](#modes)
- [What it turns on](#what-it-turns-on)
- [Returns](#returns)
- [Examples](#examples)
- [See also](#see-also)

---

<a name="synopsis"></a>
## Synopsis

```
dart run fluttersdk_dusk dusk:perf_begin [--mode=attribution|timing] [--phases] [--json]
```

`dusk:perf_begin` requires a running Flutter session (`CommandBoot.connected`) and calls `ext.dusk.perf_begin`.

| Flag | Default | Meaning |
|------|---------|---------|
| `--mode` | `attribution` | `attribution` profiles builds for blocks, self time and counters. `timing` touches no profiling flag and reports frame timings only. |
| `--phases` | `false` | Also profile layout and paint, not just builds. The span volume multiplies, so reach for it when builds alone did not explain the cost. Rejected with `--mode=timing`. |
| `--json` | `false` | Print the raw envelope instead of the one-line summary. |

---

<a name="modes"></a>
## Modes

The profiling flags that make attribution possible inflate every duration they wrap; Flutter's own docs call the overhead significant relative to the work measured. So one session cannot both attribute and time honestly:

- **`attribution`** answers "what did this interaction spend its time on": blocks ranked by self time, counts per painted frame, wind and magic counters, insights. Rank by its milliseconds; do not quote them.
- **`timing`** answers "how long did the frames take": no flag is touched, the report carries frame timings only, and its milliseconds are the ones to compare between a before and an after.

<a name="what-it-turns-on"></a>
## What it turns on

In `timing` mode only step 4 runs; every flag is left where it was.

1. `FlutterTimeline.debugCollectionEnabled` first. Both `startSync` and `finishSync` check that flag, so enabling the build flags ahead of it would push a finish with no matching start.
2. `debugProfileBuildsEnabled` and `debugProfileBuildsEnabledUserWidgets`, from `package:flutter/widgets.dart`.
3. With `--phases`, `debugProfileLayoutsEnabled` and `debugProfilePaintsEnabled`, from `package:flutter/rendering.dart`. Two libraries, one session.
4. The session-begin hook the host wired, called with the session's mode: it zeroes wind's counters, clears telescope's frame buffer, and turns wind's counting on in `attribution` mode only (counting sits on wind's hottest path and would inflate the milliseconds `timing` mode exists to report). Without the hook (no `magic_devtools` in the app) those sections come back empty and the frame summary reports zero frames.

Each flag's prior value is saved in the session. `dusk:perf_end` restores those values rather than forcing `false`, so a host that had build profiling on for its own reasons gets it back.

---

<a name="returns"></a>
## Returns

| Exit code | Meaning |
|-----------|---------|
| `0` | Session open. |
| non-zero | VM Service handler returned an error (no running app at the recorded URI). |

**Success envelope:**

```json
{
  "sessionToken": "perf-1",
  "mode": "attribution",
  "phases": true,
  "livenessBaseline": 412,
  "restartedPreviousSession": false
}
```

- `sessionToken` names the session in the matching `dusk:perf_end` payload and is the `--token` `dusk:perf_insight` accepts.
- `mode` echoes the mode the session opened in. An unknown mode, or `--phases` with `--mode=timing`, is rejected before anything is touched.
- `livenessBaseline` is the frame-liveness counter as it read at begin. `dusk:perf_end` refuses to report when it has not moved past this.
- `restartedPreviousSession` is `true` when a session was already open. A begin restarts rather than fails, so a `perf_end` that never landed (a crash, a dropped connection) does not strand the profiling flags on; the restart restores the previous session's flags before saving the current ones.

---

<a name="examples"></a>
## Examples

### 1. Build attribution for one scroll

```bash
dart run fluttersdk_dusk dusk:perf_begin
# drive the interaction (scroll, tap, navigate)
dart run fluttersdk_dusk dusk:perf_end --json
```

### 2. Builds did not explain it, so add the phases

```bash
dart run fluttersdk_dusk dusk:perf_begin --phases --json
```

```json
{"sessionToken":"perf-2","mode":"attribution","phases":true,"livenessBaseline":412,"restartedPreviousSession":false}
```

### 3. Time the same interaction without the profiling tax

```bash
dart run fluttersdk_dusk dusk:perf_begin --mode=timing
# drive the same interaction
dart run fluttersdk_dusk dusk:perf_end --json | jq '.summary.frames'
```

---

<a name="see-also"></a>
## See also

- [dusk:perf_end](dusk-perf-end.md): closes the session, reports ranked insights, restores every flag.
- [dusk:perf_insight](dusk-perf-insight.md): the rows behind one insight.
- [Frame production](../reference/frame-production.md): why a backgrounded tab measures nothing, and the refusal that says so.
- [dusk:snap](dusk-snap.md): confirm the surface you mean to measure is actually on screen first.
