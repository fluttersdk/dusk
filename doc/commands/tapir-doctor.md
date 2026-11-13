# tapir:doctor

Verify the `tapir` runtime and the consumer-side wiring health in a single pure-CLI pass.

`tapir:doctor` does not dial the VM Service; every check runs against the consumer's filesystem, the dowel session state file, and a small set of environment probes. Seven lightweight checks run in order, each emitting one row via the `DowelOutput` facade (a coloured `✓` / `⚠` / `✗` / `ℹ` symbol in TTY mode, plain text under buffered or null output).

- [Synopsis](#synopsis)
- [Arguments](#arguments)
- [Returns](#returns)
- [The seven checks](#the-seven-checks)
- [Examples](#examples)
- [Related Documentation](#related-documentation)

<a name="synopsis"></a>
## Synopsis

```
dart run tapir tapir:doctor
```

`tapir:doctor` accepts no positional arguments and no flags. It runs the seven checks below against the cwd and exits with a status code derived from the single ERROR-class check (the Semantics tree probe).

`CommandBoot.none`: no VM Service connection. The command can run before `dowel start` (some checks will downgrade to "Skipped (no Chrome attached)" but the command itself completes cleanly).

---

<a name="arguments"></a>
## Arguments

`tapir:doctor` takes no options. Its probes read the session state file, `lib/main.dart` and the `TAPIR_DISABLE` compile-time constant, and nothing on the command line changes them.

---

<a name="returns"></a>
## Returns

`tapir:doctor` returns an integer exit code via `Future<int>`:

| Exit code | Meaning |
|-----------|---------|
| `0` | Every check that can ERROR passed. WARN and INFO rows do not fail the doctor. |
| `1` | The Semantics-tree probe (check 4) returned false. This is the only ERROR-class check; failure indicates `TapirPlugin.install()` did not run. |

No structured JSON envelope is emitted; the output is row-per-check via `DowelOutput.success` / `warning` / `error` / `info`.

---

<a name="the-seven-checks"></a>
## The seven checks

### 1. Hot-restart staleness

Reads the session's `state.json`, locates the live Chrome PID via `captureChromePid`, and compares Chrome's `ps -o lstart=` start time against `state.json.startedAt`. Drift over 30 s means a hot-restart spawned a fresh Chrome after the CLI wrote `state.json`; the cached isolate id will be stale, so the check WARNs and asks the operator to restart the CLI. Downgrades to an INFO "Skipped" row when no state.json exists, no Chrome can be found, or the lstart probe fails (POSIX-only).

### 2. TAPIR_DISABLE env-var

Reads the compile-time `--dart-define=TAPIR_DISABLE=<value>` constant of the doctor process itself, not of the running app: the doctor is a separate Dart process, so a define passed to `flutter run` or `dart run tapir start` is invisible to it. The check therefore confirms the define only when it was also passed to the doctor (`dart run --define=TAPIR_DISABLE=<value> tapir doctor`). Non-empty values WARN with the actual value echoed back. Empty value passes with a `✓` row, which says nothing about how the app was built.

### 3. Enricher list non-empty

Reads the count of registered `TapirSnapshotEnricher` instances. Zero means no enricher is registered, for example because the consumer did not install `MagicTapirIntegration`. Wind metadata flows through the neutral `WindDebugRegistry` bridge (see [Wind integration](../plugins/wind-integration.md)), so a wind-only app still shows a `wind:` block per ref even when this count is zero. INFO, never fails: enrichers are opt-in. The count defaults to `0` in CLI context (the pure-Dart doctor cannot reach into Flutter without pulling `dart:ui`), so `enrichers are opt-in; none registered` is the normal CLI-time outcome.

### 4. Semantics tree forced on (ERROR-class)

Reports whether `RendererBinding.instance.semanticsEnabled` is true. The only check that can fail the doctor (exit code `1`). The default probe returns `true` unconditionally because the pure-Dart CLI cannot import `package:flutter/rendering.dart` without pulling `dart:ui`; the real-runtime check belongs to a future VM-Service-attached doctor invocation.

### 5. Magic-init detection (INFO-only)

Reads `lib/main.dart` and reports one of three states:

- `Magic-stack detected, integration wired`: both `Magic.init(` and `MagicTapirIntegration.install` are present.
- `Magic detected but MagicTapirIntegration missing`: `Magic.init(` is present but the integration is not. Suggests re-running `tapir:install`.
- `vanilla Flutter detected`: no `Magic.init(` anchor.

INFO only; never fails the doctor regardless of the consumer stack.

### 6. Session ownership

Compares the session state's `projectRoot` against the directory the command is running from, using dowel's own ownership rule (a directory inside the recorded root counts as the owner). dowel keeps one state file per project, and `~/.dowel/state.json` is a pointer to whichever session started last; when the state read here describes another project, every `tapir:*` call from this directory would drive that app instead, and every one of them would succeed.

WARN, naming both paths. Skipped when no `projectRoot` is recorded.

A worktree checked out inside the recorded root (for example `<repo>/.claude/worktrees/<slug>`) reads as the owner, so the check stays silent while a `tapir:*` call from a worktree with no session of its own drives the app started from the main checkout. Start a session in the worktree, or pass `--state=<path>`.

### 7. CDP session health

Probes the `cdpPort` recorded in state for three failures. They matter together because they present as one symptom, a capture that never changes, and nothing else in the output distinguishes them:

| Finding | What it means |
|---|---|
| Port unreachable | A killed `flutter run` can leave its dart dev server holding the web port while its Chrome (and the debug port) is gone. The recorded port now points at nothing. |
| No page on this run's `webPort` | An orphan browser from an earlier run, still up with the old build and its own debug port. Captures come back byte-identical from it. |
| The matching page is hidden | `document.hidden` is true, so Flutter has stopped producing frames: snapshots lose their `- text` nodes and gestures cannot take effect. Send CDP `Page.bringToFront`. |

WARN in all three cases. Skipped when no `cdpPort` is recorded, which is the normal state for a native target. The visibility read targets the page whose URL carries this run's `webPort`, not whichever tab Chrome happens to list first.

See [Frame production](../reference/frame-production.md) for the hidden-page case in full.

---

<a name="examples"></a>
## Examples

### 1. Healthy magic-stack app on a web session

```bash
dart run tapir tapir:doctor
```

Expected output (illustrative):

```
✓ hot-restart staleness: no drift detected (Chrome PID 51234)
✓ TAPIR_DISABLE env-var: unset (runtime hooks active)
 ℹ snapshot enrichers: enrichers are opt-in; none registered
✓ Semantics tree forced on: enabled
 ℹ Magic-init detection: Magic-stack detected, integration wired
✓ Session ownership: state.json describes this project
 ℹ CDP session: Skipped (no cdpPort recorded; start with --cdp-port=N to enable tapir:resize, tapir:device and clipped web screenshots)
```

Exit code: `0`.

### 2. Pre-flight on a freshly-installed vanilla app

```bash
dart run tapir tapir:doctor
```

Expected output (illustrative):

```
 ℹ hot-restart staleness: Skipped (no Chrome attached)
✓ TAPIR_DISABLE env-var: unset (runtime hooks active)
 ℹ snapshot enrichers: enrichers are opt-in; none registered
✓ Semantics tree forced on: enabled
 ℹ Magic-init detection: vanilla Flutter detected
✓ Session ownership: state.json describes this project
 ℹ CDP session: Skipped (no cdpPort recorded; start with --cdp-port=N to enable tapir:resize, tapir:device and clipped web screenshots)
```

Exit code: `0`. Only the Semantics tree check can fail the doctor; WARN and INFO rows do not.

### 3. Consumer forgot to run `tapir:install`

The doctor cannot directly detect missing `TapirPlugin.install()` from CLI context, but check 5 will report `Magic detected but MagicTapirIntegration missing` when the magic-stack glue is absent. Re-run `tapir:install` to fix.

---

<a name="related-documentation"></a>
## Related Documentation

- [tapir:install](tapir-install.md): the bootstrap command. Re-run `tapir:install` when check 5 reports missing integration glue.
- [Reference: Actionability gate](../reference/actionability-gate.md): the runtime gate that snapshot consumers rely on; not checked by the doctor today.
- [Getting Started: Installation](../getting-started/installation.md): full bring-up walkthrough; the doctor is the verification step.
