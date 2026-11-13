# tapir:run

Run several tapir verbs against the running app in one call. Every step is a verb line, so an agent that already knows its next three moves (tap a button, fill a field, read the result) spends one round trip instead of three, and gets one summary line per step instead of three full outputs.

`tapir:run` runs each step through the verb's own command class, so a step accepts exactly the options the standalone command accepts. The steps share the one VM Service connection of the call.

- [Synopsis](#synopsis)
- [Step grammar](#step-grammar)
- [Output](#output)
- [Exit codes](#exit-codes)
- [MCP form](#mcp-form)
- [Working with refs](#working-with-refs)
- [Examples](#examples)
- [Related Documentation](#related-documentation)

<a name="synopsis"></a>
## Synopsis

```
dart run tapir tapir:run [--continue] "<step>" ["<step>" ...]
```

`tapir:run` requires a running Flutter session (`CommandBoot.connected`). Each step is one positional argument, so quote it. With no step it prints `No steps given` and exits `1`.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--continue` | flag | `false` | Run every step even after one fails, and exit with the first non-zero code. Without it the batch stops at the first failing step. |

---

<a name="step-grammar"></a>
## Step grammar

A step is a verb followed by the options of that verb, for example `tap --ref=e5` or `fill --ref=q1 --text="a b"`.

- The line is split the way a POSIX shell would: whitespace separates tokens, single quotes keep everything literal, double quotes keep whitespace and honour `\"` and `\\`, and a backslash outside quotes escapes the next character. An unterminated quote or a trailing backslash fails that step.
- A bare verb gets the `tapir:` prefix (`tap` means `tapir:tap`). A name with a colon is used as given.
- The tokens after the verb are parsed by the verb's own argument parser, so a mistyped option fails that step with the parser's message.

Three kinds of step are rejected, each as a failed step with exit `1`:

- `tapir:run` inside a `tapir:run`.
- A verb that does not exist (`unknown verb tapir:tapp`).
- A verb that does not run on the connected app: any command that does not boot connected, such as `tapir:resize`, `tapir:device`, `tapir:install`, `tapir:doctor`, `tapir:perf_campaign` and `tapir:perf_compare`. Call those on their own.

A step that ends or restarts the app (`tapir:close_app`, `tapir:perf_run`) is accepted, but every later step then talks to a dead connection and fails, so make it the last step.

A step that fails does so with the verb's own exit code (`tap` with no `--ref` returns `1` from its own check) and a verb that throws exits `3`; the batch carries on only with `--continue`.

---

<a name="output"></a>
## Output

One summary line per step, then the last step's output:

```
[1/3] tap --ref=e8 ok: Tapped e8
[2/3] fill --ref=q1 --text="a b" ok: Filled q1
[3/3] snap --grep Total ok
- text "Total: 42"
```

- The text after `ok:` is the first non-empty output line of the step, cut to 120 characters (`...` marks the cut). The rest of a step's output stays out of your context.
- The last step's full output follows the summary, because it is the state you act on next; its own summary line carries no digest, so the first output line is not printed twice. A step that produced no output prints only its summary line.
- A failing step prints `[N/M] <step> failed (exit C)` followed by its whole output, then the batch stops, or goes on with `--continue`.
- A step's stderr lines (the frame-production banner, the `tapPointOutsideOwner` warning) are captured into its output with an `[ERROR]` prefix, so a warning is not lost.
- When the batch fails, the last line, on stderr, is `step N failed (exit C): <step>` for the first failing step.

---

<a name="exit-codes"></a>
## Exit codes

| Exit code | Meaning |
|-----------|---------|
| `0` | Every step exited `0`. |
| `1` | No steps were given; or the first failing step failed on its grammar (nested run, unknown verb, not a connected verb, bad option, bad quoting) or returned `1` itself. |
| `3` | The first failing step threw (for example a VM Service error). |
| `75` | The first failing step ran before `ext.tapir.*` was registered; retry once the app has booted. |
| other | The exit code of the first failing step. |

Without `--continue` the batch ends at that step. With it, every step runs and the exit code is still the first non-zero one.

---

<a name="mcp-form"></a>
## MCP form

The `tapir_run` tool takes the same steps as a list and routes through `dowel:tapir:run` (the seventh substrate-routed tool).

```json
{
  "name": "tapir_run",
  "arguments": {
    "steps": ["tap --ref=e5", "fill --ref=q1 --text=\"a b\"", "snap --grep Total"],
    "continue": false
  }
}
```

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `steps` | array<string> | yes | Verb lines, run in order, without the `tapir:` prefix. |
| `continue` | boolean | no | Keep running after a failing step (default `false`). |

The response is the same text the CLI prints.

---

<a name="working-with-refs"></a>
## Working with refs

`eN` refs are scoped to one snapshot, and a batch cannot read a snapshot it has not taken yet. So:

- Use refs you already hold from a snapshot taken before the call.
- Between steps that change the screen, prefer a `q<N>` handle (`tapir:find`), `--text` or `--key`, which survive a rebuild, over an `eN` ref the first step may invalidate.
- End the batch with `snap` (or a `--snapshot=diff` action) and read the new refs from its output.
- Add `--snapshot=diff` to the last action step to see only what the batch changed; see [tapir:tap](tapir-tap.md).

---

<a name="examples"></a>
## Examples

### 1. Fill a form and read the result

```bash
dart run tapir tapir:run \
  "fill --ref=q1 --text=alice@example.com" \
  "fill --ref=q2 --text=hunter2" \
  "tap --ref=q3" \
  "snap --interactiveOnly"
```

### 2. Keep going past a failure

```bash
dart run tapir tapir:run --continue "tap --ref=e5" "press_key --key=Escape" "snap"
```

All three steps run. The exit code is the first failing step's, or `0`.

---

<a name="related-documentation"></a>
## Related Documentation

- [Commands index](index.md): every verb a step may name.
- [tapir:snap](tapir-snap.md): the usual last step.
- [tapir:tap](tapir-tap.md): `--snapshot=diff` for a cheap read of what a step changed.
- [MCP tool reference](../mcp/tool-reference.md#tapir_run): the `tapir_run` schema.
