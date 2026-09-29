# dusk:perf_campaign

Run every scenario of a perf campaign on one platform, each from a cold start of the app, and summarise which passed. One command replaces the shell harness that used to boot services, start the app, log in and loop over `dusk:perf_run`: the app declares that work in a campaign YAML, and dusk runs it.

---

## Table of contents

- [Synopsis](#synopsis)
- [The campaign file](#the-campaign-file)
- [What one campaign does](#what-one-campaign-does)
- [Files and output](#files-and-output)
- [Secrets](#secrets)
- [Exit codes](#exit-codes)
- [See also](#see-also)

---

<a name="synopsis"></a>
## Synopsis

```
dart run fluttersdk_dusk dusk:perf_campaign <campaign.yaml> --platform=chrome|android|ios
    [--label=<name>] [--out=<dir>] [--only=<substring>] [--device=<id>]
    [--cdp-port=<port>] [--timing] [--semantics-pass] [--json]
```

`dusk:perf_campaign` needs no running app (`CommandBoot.none`): it starts and stops the app itself through artisan's `start` and `stop`, run in-process. It is CLI only; there is no MCP tool for it.

Rebuild a stale dispatcher before invoking it: the command runs inside the compiled dispatcher, whose staleness stamp keys only on `pubspec.lock` and the SDK, so a dusk change reached through a path override never reaches it. Run `rm -f .artisan/build.stamp` first.

| Flag | Default | Meaning |
|------|---------|---------|
| `<campaign.yaml>` / `--campaign` | required | The campaign file. |
| `--platform` | required | `chrome`, `android` or `ios`. Only scenarios whose `platforms` list it run. |
| `--label` | `run` | Names the run in every file name. `[a-z0-9_-]` only. |
| `--out` | `build/perf` | Directory the run files and `.err` files go to. |
| `--only` | none | Runs only the scenarios whose name (the run file stem, `<name>-<variant>` for a variant) contains this substring. |
| `--device` | see below | Chrome: `chrome`. Android: the emulator running `android.avd`, else the first `emulator-*` serial `adb devices` lists as ready. iOS: required, the id of a USB-connected device. |
| `--cdp-port` | `9222` | The Chrome DevTools port `artisan start --cdp-port` opens. Chrome only. |
| `--timing` | `false` | Passed to every `dusk:perf_run`. |
| `--semantics-pass` | `false` | Passed to every `dusk:perf_run`. |
| `--json` | `false` | Print only the envelope described in [files and output](#files-and-output). |

---

<a name="the-campaign-file"></a>
## The campaign file

```yaml
scenarios:                        # relative to this file; `*` in the file name only
  - scenarios/*.yaml
hooks:                            # shell strings, run verbatim, never interpolated
  before_campaign: ./tool/perf/services.sh up
  before_scenario: ./tool/perf/services.sh reset
android:
  avd: my_pixel_api35             # matched by name, launched when not running
  reverse: [8001, 8080]           # adb reverse tcp:P tcp:P each
  grant: [android.permission.POST_NOTIFICATIONS]
after_start:                      # the scenario `setup` grammar, includes and all
  - include: fragments/login.yaml
    with: {email: "${env.PERF_EMAIL}", password: "${env.PERF_PASSWORD}"}
    when: {text: Sign in, unless_text: Monitors}
retries: 1                        # extra attempts per scenario, default 1
```

- `scenarios` expands a `*` in the file name against its directory, sorted; a `*` in a directory or `**` is refused. A file with `variants` becomes one scenario per variant. Two scenarios with one name are refused, since each name is a run file.
- `hooks` run through `/bin/sh -c` in the directory the command was invoked from. `${` in a hook is refused: read a variable in the shell as `$NAME`. Each hook gets the inherited environment plus `DUSK_PERF_PLATFORM`, `DUSK_PERF_LABEL` and `DUSK_PERF_OUT`; `before_scenario` also gets `DUSK_PERF_SCENARIO`, the scenario name.
- `android` is read only with `--platform=android`. Nothing in it has a default: the AVD, the ports and the permissions are the app's.
- `after_start` runs once per cold start, before `dusk:perf_run` and so before the scenario's own `setup`. It uses the setup grammar of [dusk:perf_run](dusk-perf-run.md#fragments-parameters-and-variants), fragments, `when` guards and secrets included.

The whole file is validated before anything runs, and every problem is listed at once, each scenario file's prefixed with the file.

---

<a name="what-one-campaign-does"></a>
## What one campaign does

1. **Filter.** The scenarios whose `platforms` list `--platform` and whose name contains `--only`. When none is left the command prints `No scenario matched --only=<x> on <platform>.` (or `No scenario lists <platform>.`) and exits 1 before any hook or process runs. `--platform=ios` without `--device` and an unsafe `--label` are refused here too.
2. **`hooks.before_campaign`.** A non-zero exit stops the campaign.
3. **`flutter pub get`.** An edit to `pubspec_overrides.yaml` does not reach `.dart_tool/package_config.json` on its own.
4. **Android preparation** (`--platform=android`). adb is `$ANDROID_HOME/platform-tools/adb` when it exists, else `adb` on `PATH`: flutter drives the SDK's adb, and a second adb of another version restarts the shared server whenever either runs. With `android.avd` (and no `--device`): the serial is the ready `emulator-*` whose `adb emu avd name` is that AVD, so another emulator already running is never the one measured; when none runs it, `flutter emulators --launch <avd>` and the same match every 2 s until it appears (up to 180 s). Then `getprop sys.boot_completed` every 2 s until it reads `1` (up to 180 s). Without `android.avd` the serial is `--device` or the first ready `emulator-*`. Then `adb -s <serial> reverse tcp:P tcp:P` per `android.reverse`. With `android.grant`: `flutter build apk --profile`, `adb install -r` of the profile APK and `pm grant <applicationId> <permission>` each, the `applicationId` read from `android/app/build.gradle(.kts)`. A permission prompt on first launch sits on top of the task and swallows every later launch intent, so the grant comes before the first start. Any step that exits non-zero stops the campaign.
5. **Each scenario**, up to `retries + 1` attempts:
   1. `hooks.before_scenario`. A non-zero exit stops the campaign at this scenario.
   2. The session is read (artisan's stop deletes it), artisan `stop` runs, and the command waits until the old app's pid is gone and its ports (the web and CDP ports of a browser session, the VM Service port always) can be bound, polling every 250 ms for up to 30 s. artisan's stop signals and returns, and its start fails at once on a port still held.
   3. artisan `start`: `--device`, `--cdp-port` on Chrome, `--profile-static` on a device (a profile build).
   4. `ext.dusk.boot_id` is polled every 500 ms, for up to 180 s, until it answers: the VM Service is up before `main()` has installed dusk.
   5. `after_start`, once the app has mounted a Router (`boot_id` answers before it has one, and a login screen needs it).
   6. `dusk:perf_run <scenario> --variant --label --out --platform [--timing] [--semantics-pass]`, in-process on the same connection.

   Every scenario runs from its own cold start: on Chrome, DWDS answers `ext.dusk.*` with `0/1 responses` timeouts that compound over a long session, and a retry in the same session does not clear them. Whatever an attempt throws, or a non-zero exit from stop, start or perf_run, fails that attempt; the next attempt, and the next scenario, still run.
6. **The end.** The app is stopped once the last scenario is done, whatever happened.

---

<a name="files-and-output"></a>
## Files and output

- `<out>/<scenario>-<label>.json`: the run file `dusk:perf_run` writes.
- `<out>/<scenario>-<label>.err`: written when an attempt fails, one section per failed attempt: the failure, the stack trace of anything that is not a perf-run failure, what stop, start and perf_run printed, and, when the attempt failed while starting, a copy of the session's `flutter-dev.log`. A scenario that passes on its first attempt has none; a stale one from an earlier run is deleted when the scenario starts.
- `<out>/campaign-<label>.err`: the output of a hook, `flutter pub get` or Android step that stopped the campaign.

One line per scenario, as each finishes:

```
  monitors-list-scroll-1440  ok
  monitor-detail-390         FAILED (see /abs/build/perf/monitor-detail-390-base.err)
```

With `--json` the lines are replaced by one envelope:

```json
{"results": [
  {"scenario": "monitors-list-scroll-1440", "status": "ok", "attempts": 1,
   "runFile": "/abs/build/perf/monitors-list-scroll-1440-base.json", "errFile": null},
  {"scenario": "monitor-detail-390", "status": "failed", "attempts": 2,
   "runFile": null, "errFile": "/abs/build/perf/monitor-detail-390-base.err"}
]}
```

`errFile` is also set on an `ok` scenario whose first attempt failed.

---

<a name="secrets"></a>
## Secrets

A value read through `${env.*}` or a `secret: true` param, in `after_start` or any scenario, is a secret (see [dusk:perf_run](dusk-perf-run.md#secrets)). The campaign masks every secret, raw and JSON-encoded, as `***` in every line it prints, every `.err` it writes (hook output and the copied `flutter-dev.log` included) and the `--json` envelope. No secret is put on a command line: hooks, adb and flutter get only their literal arguments, and a hook reads what it needs from the environment it inherits.

---

<a name="exit-codes"></a>
## Exit codes

| Exit code | Meaning |
|-----------|---------|
| `0` | Every selected scenario passed. |
| `1` | A bad input or campaign file, nothing selected, a hook, `flutter pub get` or Android step that failed, or any scenario that failed every attempt. |

---

<a name="see-also"></a>
## See also

- [dusk:perf_run](dusk-perf-run.md): the scenario file, fragments and the run file.
- [dusk:perf_compare](dusk-perf-compare.md): judge one campaign's run files against another's.
