# tapir:perf_trace

Write the last closed perf session as a Chrome Trace JSON file and print only its path.

The file opens as is in [ui.perfetto.dev](https://ui.perfetto.dev) and `chrome://tracing`.

- [Synopsis](#synopsis)
- [Related Documentation](#related-documentation)

<a name="synopsis"></a>
## Synopsis

```
dart run tapir tapir:perf_trace --out=<file> [--token=<perf-1>]
```

`tapir:perf_trace` requires a running session (`CommandBoot.connected`) and calls `ext.tapir.perf_trace`. The trace runs to thousands of events, which is why it goes to a file: the path is all an agent needs to hand on.

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

<a name="related-documentation"></a>
## Related Documentation

- [tapir:perf_run](tapir-perf-run.md), [tapir:perf_end](tapir-perf-end.md).
