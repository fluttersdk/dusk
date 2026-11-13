# tapir:install

One-shot bootstrap for `tapir`. Runs in two phases, both idempotent:

1. **Patch `lib/main.dart`**: inject the imports (including `import 'package:magic_devtools/tapir.dart';` when applicable), `WidgetsFlutterBinding.ensureInitialized()`, and a `!kReleaseMode`-gated `TapirPlugin.install()` block before `runApp(` (debug and profile builds carry tapir, so `tapir:perf_run` can measure a profile build; release tree-shakes it). Magic-stack apps additionally wire `MagicTapirIntegration.install()` after `Magic.init(` when `magic_devtools:` is present in `pubspec.yaml`.
2. **Chain fastcli setup** — best-effort `dart run tapir install` (scaffolds `bin/dispatcher.dart` + `./bin/dowel` AOT wrapper) + `dart run tapir plugin:install tapir` (registers `TapirDowelProvider`). Both sub-process calls are skipped when their idempotency markers already exist (`bin/dispatcher.dart` for the scaffold, `.dowel/installed/tapir.json` for the plugin record). Failures are swallowed with a warning; the Phase 1 patch always succeeds on its own, so the consumer can still drive tapir via `dart run tapir <cmd>` even when the chain skipped.

Together, the two phases mean a fresh consumer needs only:

```bash
flutter pub add tapir
dart run tapir tapir:install
```

After the second command, `./bin/dowel list` surfaces all 42 `tapir:*` commands and `./bin/dowel mcp:serve` exposes the 40 MCP tools.

- [Synopsis](#synopsis)
- [Arguments](#arguments)
- [Returns](#returns)
- [Anchor modes](#anchor-modes)
- [Examples](#examples)
- [Related Documentation](#related-documentation)

<a name="synopsis"></a>
## Synopsis

```
dart run tapir tapir:install
```

`tapir:install` accepts no positional arguments and no flags. The command reads `lib/main.dart` and `pubspec.yaml` from the current working directory and injects the runtime wiring snippets that fit the detected stack.

---

<a name="arguments"></a>
## Arguments

`tapir:install` has no `addOption` or `addFlag` calls in its `configure` method. The two side-channel inputs are environment-derived:

| Input | Source | Purpose |
|-------|--------|---------|
| `lib/main.dart` path | `TapirInstallCommand.mainDartPathResolver()` (defaults to `lib/main.dart`) | Target file for snippet injection. Test seam: override the resolver to point at a fixture. |
| `pubspec.yaml` path | `TapirInstallCommand.pubspecPathResolver()` (defaults to `pubspec.yaml`) | Inspected for `magic_devtools:` and `wind_kit:` dependency entries. Drives the conditional wiring decisions described under [Anchor modes](#anchor-modes). |

Both resolvers are public static fields so tests can override per-test without leaking files into the running test process' cwd.

---

<a name="returns"></a>
## Returns

`tapir:install` returns an integer exit code via `Future<int>`:

| Exit code | Meaning |
|-----------|---------|
| `0` | Success. `lib/main.dart` was either updated with the required snippets or already contained them. The command prints a `tapir:install complete` success line. |
| `1` | `lib/main.dart` not found at the resolved path. The command prints an error advising the operator to run `tapir:install` from a Flutter project root. |

No structured payload is emitted. Status flows through `DowelOutput.info` / `success` / `error` so it surfaces with the same `[info]` / `[ok]` / `[error]` tokens as every other dowel command.

---

<a name="anchor-modes"></a>
## Anchor modes

The injector picks one of two anchor strings depending on what `lib/main.dart` already contains:

- **Magic-stack apps** (`lib/main.dart` contains `await Magic.init(`): `TapirPlugin.install()` is wired BEFORE `Magic.init(` so the driver is live during Magic boot. When `magic_devtools:` is also a pubspec dependency or dev_dependency, `import 'package:magic_devtools/tapir.dart';` is added and `MagicTapirIntegration.install()` is injected AFTER `Magic.init()` (the integration queries `Magic.find<X>()` for the form and nav enrichers, which only resolves once the container is ready).
- **Vanilla apps** (no `Magic.init` anchor): `TapirPlugin.install()` is wired immediately before `runApp(`.

The installer does not wire Wind. When the consumer uses `wind_kit`, add `Wind.installDebugResolver()` by hand inside the same `!kReleaseMode` block as `TapirPlugin.install()`. Wind alpha-10 no longer ships a tapir-specific integration class; tapir reads wind state through the neutral `WindDebugRegistry` bridge at snap time, independent of the Magic detection, so a magic-free app with that call still gets the wind metadata block.

An app wired before the guard moved keeps its `if (kDebugMode)` block: the installer checks for the `TapirPlugin.install()` and `MagicTapirIntegration.install()` calls themselves, not for the snippet, so a re-run adds neither a second block nor an unused `kReleaseMode` import. That app works in debug but registers no `ext.tapir.*` in a profile build; change the guard to `!kReleaseMode` by hand to measure one.

The full sub-step list (from the source docblock):

1. Add the two required imports (`kReleaseMode` from `package:flutter/foundation.dart`, only when a block is about to be injected; the `package:tapir/tapir.dart` barrel).
2. Inject `WidgetsFlutterBinding.ensureInitialized()` (skip when already present) plus the `!kReleaseMode`-gated tapir block before the canonical install anchor, unless `TapirPlugin.install()` is already called.
3. When pubspec has `magic_devtools:` (dependency or dev_dependency) AND main.dart has `await Magic.init(`, inject `import 'package:magic_devtools/tapir.dart';` and `MagicTapirIntegration.install()` AFTER that call, unless it is already called.

---

<a name="examples"></a>
## Examples

### 1. Fresh install in a vanilla Flutter app

```bash
flutter create my_app
cd my_app
dart run tapir tapir:install
```

Expected output (illustrative):

```
[info]    Wiring TapirPlugin into lib/main.dart...
[ok]      tapir:install complete. Run `dart run tapir <cmd>` to invoke tapir commands.
```

Diff against `lib/main.dart`:

```dart
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:tapir/tapir.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode) {
    TapirPlugin.install();
  }
  runApp(const MyApp());
}
```

### 2. Re-running on an already-installed project

```bash
dart run tapir tapir:install
```

The injector early-returns on every duplicate snippet. The output still prints `tapir:install complete`; the file is left untouched.

### 3. Magic-stack app with wind enricher

When pubspec lists `magic_devtools:`, the post-install `lib/main.dart` looks like this, with the `Wind.installDebugResolver()` line added by hand:

```dart
import 'package:tapir/tapir.dart';
import 'package:magic_devtools/tapir.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode) {
    TapirPlugin.install();
    Wind.installDebugResolver(); // added by hand
  }
  await Magic.init(MyApp.new);
  if (!kReleaseMode) {
    MagicTapirIntegration.install(); // magic_devtools wiring
  }
}
```

---

<a name="related-documentation"></a>
## Related Documentation

- [Getting Started: Installation](../getting-started/installation.md): step-by-step walkthrough from `dart pub add` to first snapshot.
- [tapir:doctor](tapir-doctor.md): verify the post-install wiring is healthy and the running session can be reached.
- [Plugins: Magic integration](../plugins/magic-integration.md): full surface of `MagicTapirIntegration` and which enrichers it ships.
- [Plugins: Wind integration](../plugins/wind-integration.md): the six-field `wind:` block surfaced through the neutral `WindDebugRegistry` bridge in wind alpha-10.
