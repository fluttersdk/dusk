# Installation

- [Requirements](#requirements)
- [Add the package](#add-the-package)
- [Wire DuskPlugin](#wire-duskplugin)
- [Optional integrations](#optional-integrations)
- [Wire MCP tools](#wire-mcp-tools)
- [Verify installation](#verify-installation)

Getting `fluttersdk_dusk` running requires adding the package, calling
`DuskPlugin.install()` inside a `kDebugMode` guard in your app's `main.dart`, and
(optionally) wiring the MCP server so your AI client can reach the dusk tools.

<a name="requirements"></a>
## Requirements

`fluttersdk_dusk` is a Flutter package. It requires a Flutter app target for the
VM Service extensions to register against. Pure-Dart environments are not supported.

| Dependency | Minimum | Recommended |
|:-----------|:--------|:------------|
| Dart       | `>= 3.4.0` | `3.6.0+` |
| Flutter    | `>= 3.22.0` | `3.27.0+` |
| fluttersdk_artisan | `^0.0.8` | latest |

Install `fluttersdk_artisan` first if it is not already in your project. It provides
the MCP server, the CLI framework, and the `registerExtensionIdempotent` helper that
dusk uses internally for hot-restart safety.

```bash
dart pub add fluttersdk_artisan
```

<a name="add-the-package"></a>
## Add the package

Add `fluttersdk_dusk` using the Flutter CLI:

```bash
flutter pub add fluttersdk_dusk
```

Alternatively, add it manually to `pubspec.yaml`:

```yaml
dependencies:
  fluttersdk_dusk: ^0.0.8
```

Then fetch dependencies:

```bash
flutter pub get
```

<a name="wire-duskplugin"></a>
## Wire DuskPlugin

The recommended path is the CLI installer. From your project root, run:

```bash
dart run fluttersdk_dusk dusk:install
```

This patches your `lib/main.dart` automatically: it adds the `kDebugMode` import, wraps `DuskPlugin.install()` in a `kDebugMode` guard, injects `WidgetsFlutterBinding.ensureInitialized()` when missing, and detects Magic-stack apps so `MagicDuskIntegration.install()` lands AFTER `Magic.init(...)`. The command is idempotent; re-running it is safe. See [`dusk:install`](../commands/dusk-install.md) for the full sub-step list and the anchor strings the injector searches for.

### Manual wiring (when you'd rather edit `main.dart` yourself)

Skip the CLI installer and edit `lib/main.dart` directly. Call `DuskPlugin.install()` inside a `kDebugMode` guard, after `WidgetsFlutterBinding.ensureInitialized()` and before `runApp()`. The guard is mandatory: release builds tree-shake the entire subsystem, so dusk never ships to end users.

```dart
import 'package:flutter/foundation.dart';
import 'package:fluttersdk_dusk/dusk.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    DuskPlugin.install();
  }

  runApp(const MyApp());
}
```

`DuskPlugin.install()` is idempotent: calling it more than once (for example during hot restart) is safe and registers each VM Service extension only once.

<a name="optional-integrations"></a>
## Optional integrations

Call additional `install()` methods inside the same `kDebugMode` block to enrich
snapshots with framework-specific metadata. Both integrations are independent; install
either, both, or neither depending on your stack.

| Integration | Package | Enrichment |
|:------------|:--------|:-----------|
| `MagicDuskIntegration.install()` | `magic_devtools` | MagicForm field values, validation state, named route per node. |
| `Wind.installDebugResolver()` (in `package:fluttersdk_wind/fluttersdk_wind.dart`) | `fluttersdk_wind` >= alpha-10 | Wind state surfaces through the neutral `WindDebugRegistry` bridge; dusk emits the 6 core fields (breakpoint, brightness, platform, states, bgColor, textColor) automatically without enricher registration. |

```dart
import 'package:magic_devtools/dusk.dart'; // magic_devtools only
// ...
if (kDebugMode) {
  DuskPlugin.install();
  MagicDuskIntegration.install(); // magic-stack only (from magic_devtools)
  Wind.installDebugResolver();    // wind UI only (alpha-10+)
}
```

See [Magic integration](../plugins/magic-integration) and
[Wind integration](../plugins/wind-integration) for the full enricher field reference.

<a name="register-with-artisan"></a>
## Register with artisan (automatic)

`dusk:install` already handles this for you as Phase 2 of its run. Right after the `lib/main.dart` patch lands, it chains `dart run fluttersdk_dusk install` (scaffolds `bin/dispatcher.dart` + `./bin/fsa` fastcli, ~110ms warm AOT) followed by `dart run fluttersdk_dusk plugin:install fluttersdk_dusk` (registers `DuskArtisanProvider` and auto-purges the AOT bundle cache). Both sub-process calls skip when their idempotency markers already exist (`bin/dispatcher.dart` and `.artisan/installed/fluttersdk_dusk.json` respectively), so re-running `dusk:install` is a fast no-op.

If the chained calls fail (no `dart` on PATH, partial pub-cache, restricted sandbox), `dusk:install` falls through with a warning and exits 0; the `lib/main.dart` patch already landed, so `dart run fluttersdk_dusk <cmd>` still works. You can finish the setup manually:

```bash
dart run fluttersdk_dusk install                          # only if Phase 2 was skipped
dart run fluttersdk_dusk plugin:install fluttersdk_dusk   # idempotent; refreshes barrels on re-run
```

After Phase 2 lands, `./bin/fsa list` shows all `dusk:*` commands and `./bin/fsa mcp:serve` exposes the 31 dusk_* tools.

The optional `mcp:install` step in the next section writes the plugin-aware `.mcp.json` payload by default. When fastcli (`./bin/fsa`) is present, the entry uses `./bin/fsa mcp:serve`; when it is absent, the wrapper's `--invocation=fluttersdk_dusk` pass-through causes `mcp:install` to write `dart run fluttersdk_dusk mcp:serve` instead. Either way, no manual `.mcp.json` edit is needed.

<a name="wire-mcp-tools"></a>
## Wire MCP tools

With artisan registered, expose dusk's 33 MCP tools to your AI client by writing the `.mcp.json` entry:

```bash
dart run fluttersdk_dusk mcp:install
```

This writes (or updates) a `.mcp.json` file at the project root. Claude Code,
Cursor, and Windsurf all pick up `.mcp.json` automatically from the working directory.
The payload depends on your scaffold state:

- **fastcli present** (`./bin/fsa` exists, POSIX): writes `./bin/fsa mcp:serve` — fastest startup (~50ms warm AOT).
- **fastcli absent**: the wrapper injects `--invocation=fluttersdk_dusk` automatically, so the entry writes `dart run fluttersdk_dusk mcp:serve` (~3s startup, no scaffold required).

See [Fallback invocations](../mcp/setup.md#fallback-invocations) for the full precedence table.

<a name="verify-installation"></a>
## Verify installation

Start your Flutter app in debug mode on a device or browser:

```bash
flutter run -d chrome
```

Then, in a separate terminal, capture the first Semantics snapshot:

```bash
dart run fluttersdk_dusk dusk:snap
```

A successful snap prints a YAML block beginning with `snapshot:` followed by one or
more indented widget nodes. Each node carries a `ref:` token (`e1`, `e2`, ...) that
you pass to action commands. If the command exits with an error, confirm that
`DuskPlugin.install()` is reachable in your `main.dart` and that the app is running
in debug mode (VM Service extensions do not register in profile or release builds).
