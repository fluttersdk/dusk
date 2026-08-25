# dusk:perf_begin

Open a performance measurement session around an interaction you are about to drive. `dusk:perf_begin` switches Flutter's build profiling on, zeroes the frame buffer and the wind counters, and records the liveness baseline that `dusk:perf_end` judges the run against. Nothing is measured until you call it, and the instrumentation costs real time, so keep every session tight: begin, drive one interaction, end.

---

## Table of contents

- [Synopsis](#synopsis)
- [What it turns on](#what-it-turns-on)
- [Returns](#returns)
- [Examples](#examples)
- [See also](#see-also)

---

<a name="synopsis"></a>
## Synopsis

```
dart run fluttersdk_dusk dusk:perf_begin [--phases] [--json]
```

`dusk:perf_begin` requires a running Flutter session (`CommandBoot.connected`) and calls `ext.dusk.perf_begin`.

| Flag | Default | Meaning |
|------|---------|---------|
| `--phases` | `false` | Also profile layout and paint, not just builds. The span volume multiplies, so reach for it when builds alone did not explain the cost. |
| `--json` | `false` | Print the raw envelope instead of the one-line summary. |

---

<a name="what-it-turns-on"></a>
## What it turns on

1. `FlutterTimeline.debugCollectionEnabled` first. Both `startSync` and `finishSync` check that flag, so enabling the build flags ahead of it would push a finish with no matching start.
2. `debugProfileBuildsEnabled` and `debugProfileBuildsEnabledUserWidgets`, from `package:flutter/widgets.dart`.
3. With `--phases`, `debugProfileLayoutsEnabled` and `debugProfilePaintsEnabled`, from `package:flutter/rendering.dart`. Two libraries, one session.
4. The session-begin hook the host wired: it zeroes wind's counters, turns wind's counting ON, and clears telescope's frame buffer. Without the hook (no `magic_devtools` in the app) those sections come back empty and the frame summary reports zero frames.

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
  "phases": true,
  "livenessBaseline": 412,
  "restartedPreviousSession": false
}
```

- `sessionToken` names the session in the matching `dusk:perf_end` payload.
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
{"sessionToken":"perf-2","phases":true,"livenessBaseline":412,"restartedPreviousSession":false}
```

---

<a name="see-also"></a>
## See also

- [dusk:perf_end](dusk-perf-end.md): closes the session, reports the attribution, restores every flag.
- [Frame production](../reference/frame-production.md): why a backgrounded tab measures nothing, and the refusal that says so.
- [dusk:snap](dusk-snap.md): confirm the surface you mean to measure is actually on screen first.
