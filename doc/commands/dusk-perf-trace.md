# dusk:perf_trace

Write the last closed perf session as a Chrome Trace JSON file and print only its path. The file opens as is in [ui.perfetto.dev](https://ui.perfetto.dev) and `chrome://tracing`.

---

## Synopsis

```
dart run fluttersdk_dusk dusk:perf_trace --out=<file> [--token=<perf-1>]
```

`dusk:perf_trace` requires a running session (`CommandBoot.connected`) and calls `ext.dusk.perf_trace`. The trace runs to thousands of events, which is why it goes to a file: the path is all an agent needs to hand on.

| Flag | Default | Meaning |
|------|---------|---------|
| `--out` | required | The file to write. Parent directories are created. |
| `--token` | none | The session's `sessionToken`. Only the most recent closed session is kept; a token naming any other is refused. |

The file carries `traceEvents`, `displayTimeUnit` and `otherData` (the session token, its window and the event counts). What goes into it, and why the frames must be exported before the next `perf_begin`, is on [the perf trace page](../reference/perf-trace.md).

| Exit code | Meaning |
|-----------|---------|
| `0` | Written; stdout is the absolute path. |
| `1` | `--out` missing. |
| non-zero | The extension refused: no closed session, a stale token, or a session still open. |

## See also

- [dusk:perf_run](dusk-perf-run.md), [dusk:perf_end](dusk-perf-end.md).
