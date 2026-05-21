# dusk:doctor

Verify the `fluttersdk_dusk` runtime and the consumer-side wiring health in a single pure-CLI pass. `dusk:doctor` does not dial the VM Service; every check runs against the consumer's filesystem, the artisan state file (`~/.artisan/state.json`), and a small set of environment probes.

Five lightweight checks run in order, each emitting one row via the `ArtisanOutput` facade (colored `[ok]` / `[warn]` / `[error]` / `[info]` tokens in TTY mode, plain text under buffered or null output).

---

## Table of contents

- [Synopsis](#synopsis)
- [Arguments](#arguments)
- [Returns](#returns)
- [The five checks](#the-five-checks)
- [Examples](#examples)
- [See also](#see-also)

---

<a name="synopsis"></a>
## Synopsis

```
dart run fluttersdk_dusk dusk:doctor
```

`dusk:doctor` accepts no positional arguments and no flags. It runs five preflight checks against the cwd and exits with a status code derived from the single ERROR-class check (the Semantics tree probe).

`CommandBoot.none`: no VM Service connection. The command can run before `artisan start` (some checks will downgrade to "Skipped (no Chrome attached)" but the command itself completes cleanly).

---

<a name="arguments"></a>
## Arguments

`dusk:doctor` has no `addOption` or `addFlag` calls in its `configure` method. The probes are configurable via test seams (static fields on `DuskDoctorCommand`) so tests can override per-test, but no CLI surface drives them.

Test seams (for completeness; not user-facing):

| Seam | Default | Purpose |
|------|---------|---------|
| `stateFileReader` | `StateFile.read` | Reads `~/.artisan/state.json`. |
| `chromePidProbe` | `captureChromePid` | Locates the live Chrome PID under a given parent PID. |
| `processStartTimeProbe` | POSIX `ps -o lstart=` / Windows wmic | Reads a process's start time. |
| `nowProvider` | `DateTime.now` | Wall-clock source. |
| `semanticsEnabledProbe` | returns `true` | Reports whether the running app forced Semantics on. |
| `duskDisableEnvReader` | reads `DUSK_DISABLE` compile-time constant | Detects the kill-switch env-var. |
| `enrichersProbe` | returns `0` | Reports the count of registered enrichers. |
| `mainDartPathResolver` | returns `lib/main.dart` | Resolves the consumer's main file. |
| `mainDartReader` | reads bytes off disk | Returns the main.dart source. |

---

<a name="returns"></a>
## Returns

`dusk:doctor` returns an integer exit code via `Future<int>`:

| Exit code | Meaning |
|-----------|---------|
| `0` | Every check that can ERROR passed. WARN and INFO rows do not fail the doctor. |
| `1` | The Semantics-tree probe (check 4) returned false. This is the only ERROR-class check; failure indicates `DuskPlugin.install()` did not run. |

No structured JSON envelope is emitted; the output is row-per-check via `ArtisanOutput.success` / `warning` / `error` / `info`.

---

<a name="the-five-checks"></a>
## The five checks

### 1. Hot-restart staleness

Reads `~/.artisan/state.json`, locates the live Chrome PID via `captureChromePid`, and compares Chrome's `ps -o lstart=` start time against `state.json.startedAt`. Drift over 30 s means a hot-restart spawned a fresh Chrome after the CLI wrote `state.json`; the cached isolate id will be stale, so the check WARNs and asks the operator to restart the CLI. Downgrades to an INFO "Skipped" row when no state.json exists, no Chrome can be found, or the lstart probe fails (POSIX-only).

### 2. DUSK_DISABLE env-var

Reads the compile-time `--dart-define=DUSK_DISABLE=<value>` constant. Non-empty values WARN with the actual value echoed back so the operator can confirm where the kill switch came from (a stale `.env` export, a CI flag, etc.). Empty value passes silently with `[ok]`.

### 3. Enricher list non-empty

Reads the count of registered `DuskSnapshotEnricher` instances. Zero means the consumer wired `DuskPlugin.install()` but neither `MagicDuskIntegration` nor `WindDuskIntegration`; snapshots still work, just without context. WARN, never fail. Defaults to `0` in CLI context (the pure-Dart doctor cannot reach into Flutter without pulling `dart:ui`); the WARN row is the correct CLI-time outcome.

### 4. Semantics tree forced on (ERROR-class)

Reports whether `RendererBinding.instance.semanticsEnabled` is true. The only check that can fail the doctor (exit code `1`). The default probe returns `true` unconditionally because the pure-Dart CLI cannot import `package:flutter/rendering.dart` without pulling `dart:ui`; the real-runtime check belongs to a future VM-Service-attached doctor invocation.

### 5. Magic-init detection (INFO-only)

Reads `lib/main.dart` and reports one of three states:

- `Magic-stack detected, integration wired` ; both `Magic.init(` and `MagicDuskIntegration.install` are present.
- `Magic detected but MagicDuskIntegration missing` ; `Magic.init(` is present but the integration is not. Suggests re-running `dusk:install`.
- `vanilla Flutter detected` ; no `Magic.init(` anchor.

INFO only; never fails the doctor regardless of the consumer stack.

---

<a name="examples"></a>
## Examples

### 1. Healthy magic-stack app

```bash
dart run fluttersdk_dusk dusk:doctor
```

Expected output (illustrative):

```
[ok]      hot-restart staleness: no drift detected (Chrome PID 51234)
[ok]      DUSK_DISABLE env-var: unset (runtime hooks active)
[ok]      snapshot enrichers: enrichers registered: 8
[ok]      Semantics tree forced on: enabled
[info]    Magic-init detection: Magic-stack detected, integration wired
```

Exit code: `0`.

### 2. Pre-flight on a freshly-installed vanilla app

```bash
dart run fluttersdk_dusk dusk:doctor
```

Expected output (illustrative):

```
[info]    hot-restart staleness: Skipped (no Chrome attached)
[ok]      DUSK_DISABLE env-var: unset (runtime hooks active)
[warn]    snapshot enrichers: no enrichers registered; install Magic + Wind integrations for richer snapshots
[ok]      Semantics tree forced on: enabled
[info]    Magic-init detection: vanilla Flutter detected
```

Exit code: `0`. The doctor passes despite the WARN row.

### 3. Consumer forgot to run `dusk:install`

The doctor cannot directly detect missing `DuskPlugin.install()` from CLI context, but check 5 will report `Magic detected but MagicDuskIntegration missing` when the magic-stack glue is absent. Re-run `dusk:install` to fix.

---

<a name="see-also"></a>
## See also

- [dusk:install](dusk-install.md): the bootstrap command. Re-run `dusk:install` when check 5 reports missing integration glue.
- [Reference: Actionability gate](../reference/actionability-gate.md): the runtime gate that snapshot consumers rely on; not checked by the doctor today.
- [Getting Started: Installation](../getting-started/installation.md): full bring-up walkthrough; the doctor is the verification step.
