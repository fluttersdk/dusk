# tapir:doctor

Verify the `tapir` runtime and the consumer-side wiring health in a single pass.

`tapir:doctor` reads the consumer's filesystem and the dowel session state file, and, when a session is recorded, asks the running app over the VM Service (`ext.tapir.boot_id`) for what only the app can report: whether tapir registered, whether the Semantics tree is on and how many snapshot enrichers it holds. It runs the checks below in order, each emitting one row via the `DowelOutput` facade (a coloured `✓` / `⚠` / `✗` / `ℹ` symbol in TTY mode, plain text under buffered or null output).

- [Synopsis](#synopsis)
- [Arguments](#arguments)
- [Returns](#returns)
- [The checks](#the-checks)
- [Examples](#examples)
- [Related Documentation](#related-documentation)

<a name="synopsis"></a>
## Synopsis

```
dart run tapir tapir:doctor
```

`tapir:doctor` accepts no positional arguments and no flags. It runs the checks below against the cwd and exits with a status code derived from the single ERROR-class check (the Semantics tree row).

`CommandBoot.none`: the dispatcher opens no VM Service connection for it, so the command runs before `dowel start`. With no session recorded, the three rows that need the app (2 to 4) print `Skipped (no running app; start one with `dowel start`)` and the command completes cleanly. When the recorded app does not answer within five seconds, the same rows print `Skipped (the running app did not answer: <reason>)`.

---

<a name="arguments"></a>
## Arguments

`tapir:doctor` takes no options. Its probes read the session state file, `lib/main.dart`, the files under the project root that a previous install may have left, and the running app; nothing on the command line changes them.

---

<a name="returns"></a>
## Returns

`tapir:doctor` returns an integer exit code via `Future<int>`:

| Exit code | Meaning |
|-----------|---------|
| `0` | The ERROR-class row passed or was skipped. WARN and INFO rows do not fail the doctor, and neither does a missing session or an app that did not answer. |
| `1` | The Semantics-tree row (check 4) failed, in one of two ways: the app answered but registers no `ext.tapir.*` extension (it never calls `TapirPlugin.install()`, or it was built with `--dart-define=TAPIR_DISABLE=1`), or it answered that its Semantics tree is off. This is the only ERROR-class check. |

No structured JSON envelope is emitted; the output is row-per-check via `DowelOutput.success` / `warning` / `error` / `info`.

---

<a name="the-checks"></a>
## The checks

### 1. Hot-restart staleness

Reads the session's `state.json`, locates the live Chrome PID via `captureChromePid`, and compares Chrome's `ps -o lstart=` start time against `state.json.startedAt`. Drift over 30 s means a hot-restart spawned a fresh Chrome after the CLI wrote `state.json`; the cached isolate id will be stale, so the check WARNs and asks the operator to restart the CLI. Downgrades to an INFO "Skipped" row when no state.json exists, no Chrome can be found, or the lstart probe fails (POSIX-only).

### 2. TAPIR_DISABLE

Asks the running app, not the doctor process: a define passed to `flutter run` or `dart run tapir start` is invisible to the CLI, so the row reads the answer of `ext.tapir.boot_id`. When the app answers, the row says `not set in the running app (ext.tapir.* live)`. When the app runs but registers no `ext.tapir.*` extension, the row WARNs: `the running app registers no ext.tapir.* extension; it was built with --dart-define=TAPIR_DISABLE=1, or it never calls TapirPlugin.install()`. That answer is asked again once, after a second, because a hot restart drops every extension until tapir registers them again; only the second one counts. With no session, or an app that did not answer, the row is an INFO skip.

### 3. Snapshot enrichers

Prints the number of `TapirSnapshotEnricher` instances the running app registered, as the app counts them (`TapirPlugin.enrichers`): `enrichers registered: N`. Zero prints `enrichers are opt-in; none registered`, for example because the consumer did not install `MagicTapirIntegration`. Wind metadata flows through the neutral `WindDebugRegistry` bridge (see [Wind integration](../plugins/wind-integration.md)), so a wind-only app still shows a `wind:` block per ref even when this count is zero. INFO, never fails: enrichers are opt-in. When the answer carries no count (an app whose tapir predates the key, or an app that registers no tapir at all) the row prints `Skipped (the running app's tapir predates this check; upgrade it)`.

### 4. Semantics tree forced on (ERROR-class)

Reports the Semantics state the running app answered with. The only check that can fail the doctor (exit code `1`):

- `enabled in the running app`: passes.
- `Semantics tree not forced on in the running app; refs cannot resolve (a perf semantics pass left it released, or the handle was disposed). Hot restart the app.`: ERROR, exit `1`.
- `Semantics tree not forced on; TapirPlugin.install has not run in the running app`: ERROR, exit `1`. The app answered with no `ext.tapir.*` extension at all.
- An INFO skip when there is no session, the app did not answer, or its tapir does not send the state yet.

### 5. Magic-init detection (INFO-only)

Reads `lib/main.dart` and reports one of these states:

- `Magic-stack detected, integration wired`: both `Magic.init(` and `MagicTapirIntegration.install` are present.
- `Magic detected but MagicTapirIntegration missing; wire it with tapir:install`: `Magic.init(` is present, the integration is not, and the resolved `magic_devtools` ships `lib/tapir.dart`.
- `Magic detected, but the installed magic_devtools has no tapir integration yet; upgrade it to a release built on tapir, then rerun tapir:install`: the resolved `magic_devtools` has no `lib/tapir.dart`, so there is no class to wire yet.
- `Magic detected, but no magic_devtools resolved; add a release built on tapir to dev_dependencies, run flutter pub get, then rerun tapir:install`: `.dart_tool/package_config.json` names no `magic_devtools`.
- `vanilla Flutter detected`: no `Magic.init(` anchor.

The `magic_devtools` check reads the nearest `.dart_tool/package_config.json` at or above the working directory (the workspace root's for a pub workspace member; an unreadable or invalid one reads as unresolved and never stops the doctor), the same check `tapir:install` makes before it writes the Magic lines.

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

### 8. fluttersdk_dusk leftovers

Looks in the project root for what an install of tapir's predecessor left behind and `tapir:install` also reports (see [Migrating from fluttersdk_dusk](../getting-started/migrating-from-fluttersdk-dusk.md)). A clean project prints `fluttersdk_dusk leftovers: none found`. Otherwise the row WARNs, one line per finding, then the commands to run:

```
⚠ fluttersdk_dusk leftovers: found
  - bin/dispatcher.dart (imports fluttersdk_artisan): delete it
  - bin/fsa: delete it
  - lib/app/commands/_index.g.dart: delete it
  - lib/app/commands/deploy_command.dart (uses Artisan* classes): port it to the Dowel* classes
  - .mcp.json: delete the "fluttersdk" server entry
Then run `dart run dowel install`, `dart run dowel commands:refresh` and `dart run tapir tapir:install`.
```

Each line appears only when its file is there. It never fails the doctor.

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
✓ TAPIR_DISABLE: not set in the running app (ext.tapir.* live)
✓ snapshot enrichers: enrichers registered: 2
✓ Semantics tree forced on: enabled in the running app
 ℹ Magic-init detection: Magic-stack detected, integration wired
✓ Session ownership: state.json describes this project
 ℹ CDP session: Skipped (no cdpPort recorded; start with --cdp-port=N to enable tapir:resize_viewport, tapir:device_profile and clipped web screenshots)
✓ fluttersdk_dusk leftovers: none found
```

Exit code: `0`.

### 2. Pre-flight before the app is started

```bash
dart run tapir tapir:doctor
```

Expected output (illustrative):

```
 ℹ hot-restart staleness: Skipped (no Chrome attached)
 ℹ TAPIR_DISABLE: Skipped (no running app; start one with `dowel start`)
 ℹ snapshot enrichers: Skipped (no running app; start one with `dowel start`)
 ℹ Semantics tree forced on: Skipped (no running app; start one with `dowel start`)
 ℹ Magic-init detection: vanilla Flutter detected
 ℹ Session ownership: Skipped (no projectRoot in state.json)
 ℹ CDP session: Skipped (no cdpPort recorded; start with --cdp-port=N to enable tapir:resize_viewport, tapir:device_profile and clipped web screenshots)
✓ fluttersdk_dusk leftovers: none found
```

Exit code: `0`. Only the Semantics tree row can fail the doctor; WARN and INFO rows do not.

### 3. The app never ran `TapirPlugin.install()`

With a session recorded, the doctor asks the app. An app that answers but has no `ext.tapir.*` extension fails the check:

```
⚠ TAPIR_DISABLE: the running app registers no ext.tapir.* extension; it was built with --dart-define=TAPIR_DISABLE=1, or it never calls TapirPlugin.install()
 ℹ snapshot enrichers: Skipped (the running app's tapir predates this check; upgrade it)
✗ Semantics tree forced on: Semantics tree not forced on; TapirPlugin.install has not run in the running app
```

An app with no tapir has no enricher count to send, so that row shows its generic skip; ignore it here. The Semantics row ERRORs and the exit code is `1`. Run `tapir:install` (or wire the call by hand) and restart the app.

---

<a name="related-documentation"></a>
## Related Documentation

- [tapir:install](tapir-install.md): the bootstrap command. Re-run `tapir:install` when check 5 reports missing integration glue.
- [Migrating from fluttersdk_dusk](../getting-started/migrating-from-fluttersdk-dusk.md): what check 8 reports and how to clear it.
- [Reference: Actionability gate](../reference/actionability-gate.md): the runtime gate that snapshot consumers rely on; not checked by the doctor today.
- [Getting Started: Installation](../getting-started/installation.md): full bring-up walkthrough; the doctor is the verification step.
