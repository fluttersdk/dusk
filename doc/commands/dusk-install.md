# dusk:install

One-shot bootstrap for `fluttersdk_dusk`. Runs in two phases, both idempotent:

1. **Patch `lib/main.dart`** — inject the imports, `WidgetsFlutterBinding.ensureInitialized()`, and a `kDebugMode`-gated `DuskPlugin.install()` block before `runApp(`. Magic-stack apps additionally wire `MagicDuskIntegration.install()` after `Magic.init(`.
2. **Chain fastcli setup** — best-effort `dart run fluttersdk_artisan install` (scaffolds `bin/dispatcher.dart` + `./bin/fsa` AOT wrapper) + `dart run fluttersdk_artisan plugin:install fluttersdk_dusk` (registers `DuskArtisanProvider`). Both sub-process calls are skipped when their idempotency markers already exist (`bin/dispatcher.dart` for the scaffold, `.artisan/installed/fluttersdk_dusk.json` for the plugin record). Failures are swallowed with a warning; the Phase 1 patch always succeeds on its own, so the consumer can still drive dusk via `dart run fluttersdk_dusk <cmd>` even when the chain skipped.

Together, the two phases mean a fresh consumer needs only:

```bash
flutter pub add fluttersdk_dusk
dart run fluttersdk_dusk dusk:install
```

After the second command, `./bin/fsa list` surfaces all 32 `dusk:*` commands and `./bin/fsa mcp:serve` exposes the 31 MCP tools.

---

## Table of contents

- [Synopsis](#synopsis)
- [Arguments](#arguments)
- [Returns](#returns)
- [Anchor modes](#anchor-modes)
- [Examples](#examples)
- [See also](#see-also)

---

<a name="synopsis"></a>
## Synopsis

```
dart run fluttersdk_dusk dusk:install
```

`dusk:install` accepts no positional arguments and no flags. The command reads `lib/main.dart` and `pubspec.yaml` from the current working directory and injects the runtime wiring snippets that fit the detected stack.

---

<a name="arguments"></a>
## Arguments

`dusk:install` has no `addOption` or `addFlag` calls in its `configure` method. The two side-channel inputs are environment-derived:

| Input | Source | Purpose |
|-------|--------|---------|
| `lib/main.dart` path | `DuskInstallCommand.mainDartPathResolver()` (defaults to `lib/main.dart`) | Target file for snippet injection. Test seam: override the resolver to point at a fixture. |
| `pubspec.yaml` path | `DuskInstallCommand.pubspecPathResolver()` (defaults to `pubspec.yaml`) | Inspected for `magic:` and `fluttersdk_wind:` dependency entries. Drives the conditional wiring decisions described under [Anchor modes](#anchor-modes). |

Both resolvers are public static fields so tests can override per-test without leaking files into the running test process' cwd.

---

<a name="returns"></a>
## Returns

`dusk:install` returns an integer exit code via `Future<int>`:

| Exit code | Meaning |
|-----------|---------|
| `0` | Success. `lib/main.dart` was either updated with the required snippets or already contained them. The command prints a `dusk:install complete` success line. |
| `1` | `lib/main.dart` not found at the resolved path. The command prints an error advising the operator to run `dusk:install` from a Flutter project root. |

No structured payload is emitted. Status flows through `ArtisanOutput.info` / `success` / `error` so it surfaces with the same `[info]` / `[ok]` / `[error]` tokens as every other artisan command.

---

<a name="anchor-modes"></a>
## Anchor modes

The injector picks one of two anchor strings depending on what `lib/main.dart` already contains:

- **Magic-stack apps** (`lib/main.dart` contains `await Magic.init(`): `DuskPlugin.install()` is wired BEFORE `Magic.init(` so the driver is live during Magic boot. When `magic:` is also a pubspec dependency, `MagicDuskIntegration.install()` is also injected AFTER `Magic.init()` (the integration queries `Magic.find<X>()` for the form and nav enrichers, which only resolves once the container is ready).
- **Vanilla apps** (no `Magic.init` anchor): `DuskPlugin.install()` is wired immediately before `runApp(`.

When the consumer's pubspec lists `fluttersdk_wind:` as a top-level dependency, `Wind.installDebugResolver()` lands inside the same `kDebugMode` block as `DuskPlugin.install()`. Wind alpha-10 no longer ships a dusk-specific integration class; dusk reads wind state through the neutral `WindDebugRegistry` bridge at snap time. The Wind enricher wiring is independent of the Magic detection: a magic-free app with `fluttersdk_wind` still gets the wind metadata block.

The full sub-step list (from the source docblock):

1. Add the two required imports (`kDebugMode` from `package:flutter/foundation.dart`; the `package:fluttersdk_dusk/dusk.dart` barrel).
2. Inject `WidgetsFlutterBinding.ensureInitialized()` (skip when already present) plus the `kDebugMode`-gated dusk block before the canonical install anchor.
3. When pubspec has `magic:` AND main.dart has `await Magic.init(`, inject `MagicDuskIntegration.install()` AFTER that call.

---

<a name="examples"></a>
## Examples

### 1. Fresh install in a vanilla Flutter app

```bash
flutter create my_app
cd my_app
dart run fluttersdk_dusk dusk:install
```

Expected output (illustrative):

```
[info]    Wiring DuskPlugin into lib/main.dart...
[ok]      dusk:install complete. Run `dart run fluttersdk_dusk <cmd>` to invoke dusk commands.
```

Diff against `lib/main.dart`:

```dart
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:fluttersdk_dusk/dusk.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    DuskPlugin.install();
  }
  runApp(const MyApp());
}
```

### 2. Re-running on an already-installed project

```bash
dart run fluttersdk_dusk dusk:install
```

The injector early-returns on every duplicate snippet. The output still prints `dusk:install complete`; the file is left untouched.

### 3. Magic-stack app with wind enricher

When pubspec lists both `magic:` and `fluttersdk_wind:`, the post-install `lib/main.dart` looks like:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    DuskPlugin.install();
    Wind.installDebugResolver();
  }
  await Magic.init(MyApp.new);
  if (kDebugMode) {
    MagicDuskIntegration.install();
  }
}
```

---

<a name="see-also"></a>
## See also

- [Getting Started: Installation](../getting-started/installation.md): step-by-step walkthrough from `dart pub add` to first snapshot.
- [dusk:doctor](dusk-doctor.md): verify the post-install wiring is healthy and the running session can be reached.
- [Plugins: Magic integration](../plugins/magic-integration.md): full surface of `MagicDuskIntegration` and which enrichers it ships.
- [Plugins: Wind integration](../plugins/wind-integration.md): the six-field `wind:` block surfaced through the neutral `WindDebugRegistry` bridge in wind alpha-10.
