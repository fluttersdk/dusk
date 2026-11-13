# Installation

- [Requirements](#requirements)
- [Add the package](#add-the-package)
- [Wire TapirPlugin](#wire-tapirplugin)
- [Optional integrations](#optional-integrations)
- [Wire MCP tools](#wire-mcp-tools)
- [Verify installation](#verify-installation)

Getting `tapir` running requires adding the package, calling
`TapirPlugin.install()` inside a `!kReleaseMode` guard in your app's `main.dart`, and
(optionally) wiring the MCP server so your AI client can reach the tapir tools.

<a name="requirements"></a>
## Requirements

`tapir` is a Flutter package. It requires a Flutter app target for the
VM Service extensions to register against. Pure-Dart environments are not supported.

| Dependency | Minimum | Recommended |
|:-----------|:--------|:------------|
| Dart       | `>= 3.4.0` | `3.6.0+` |
| Flutter    | `>= 3.22.0` | `3.27.0+` |
| dowel | `^0.0.20` | latest |

Install `dowel` first if it is not already in your project. It provides
the MCP server, the CLI framework, and the `registerExtensionIdempotent` helper that
tapir uses internally for hot-restart safety.

```bash
dart pub add dowel
```

<a name="add-the-package"></a>
## Add the package

Add `tapir` using the Flutter CLI:

```bash
flutter pub add tapir
```

Alternatively, add it manually to `pubspec.yaml`:

```yaml
dependencies:
  tapir: ^0.0.23
```

Then fetch dependencies:

```bash
flutter pub get
```

<a name="wire-tapirplugin"></a>
## Wire TapirPlugin

The recommended path is the CLI installer. From your project root, run:

```bash
dart run tapir tapir:install
```

This patches your `lib/main.dart` automatically: it adds the `kReleaseMode` import, wraps `TapirPlugin.install()` in a `!kReleaseMode` guard, injects `WidgetsFlutterBinding.ensureInitialized()` when missing, and detects Magic-stack apps so `MagicTapirIntegration.install()` lands AFTER `Magic.init(...)`. The command is idempotent; re-running it is safe. See [`tapir:install`](../commands/tapir-install.md) for the full sub-step list and the anchor strings the injector searches for.

### Manual wiring (when you'd rather edit `main.dart` yourself)

Skip the CLI installer and edit `lib/main.dart` directly. Call `TapirPlugin.install()` inside a `!kReleaseMode` guard, after `WidgetsFlutterBinding.ensureInitialized()` and before `runApp()`. The guard is mandatory: release builds tree-shake the entire subsystem, so tapir never ships to end users. It is `!kReleaseMode` rather than `kDebugMode` so a profile build carries tapir too, which is the build `tapir:perf_run` measures; an app wired under `kDebugMode` keeps working in debug, and `tapir:install` leaves that block alone, but it registers no `ext.tapir.*` in a profile build until the guard is changed by hand.

```dart
import 'package:flutter/foundation.dart';
import 'package:tapir/tapir.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kReleaseMode) {
    TapirPlugin.install();
  }

  runApp(const MyApp());
}
```

`TapirPlugin.install()` is idempotent: calling it more than once (for example during hot restart) is safe and registers each VM Service extension only once.

<a name="optional-integrations"></a>
## Optional integrations

Call additional `install()` methods inside the same `!kReleaseMode` block to enrich
snapshots with framework-specific metadata. Both integrations are independent; install
either, both, or neither depending on your stack.

| Integration | Package | Enrichment |
|:------------|:--------|:-----------|
| `MagicTapirIntegration.install()` | `magic_devtools` | MagicForm field values, validation state, named route per node. |
| `Wind.installDebugResolver()` (in `package:wind_kit/wind_kit.dart`) | `wind_kit` >= alpha-10 | Wind state surfaces through the neutral `WindDebugRegistry` bridge; tapir emits the 6 core fields (breakpoint, brightness, platform, states, bgColor, textColor) automatically without enricher registration. |

```dart
import 'package:magic_devtools/tapir.dart'; // magic_devtools only
// ...
if (!kReleaseMode) {
  TapirPlugin.install();
  MagicTapirIntegration.install(); // magic-stack only (from magic_devtools)
  Wind.installDebugResolver();    // wind UI only (alpha-10+)
}
```

See [Magic integration](../plugins/magic-integration) and
[Wind integration](../plugins/wind-integration) for the full enricher field reference.

<a name="register-with-dowel"></a>
## Register with dowel (automatic)

`tapir:install` already handles this for you as Phase 2 of its run. Right after the `lib/main.dart` patch lands, it chains `dart run tapir install` (scaffolds `bin/dispatcher.dart` + `./bin/dowel` fastcli, ~110ms warm AOT) followed by `dart run tapir plugin:install tapir` (registers `TapirDowelProvider` and auto-purges the AOT bundle cache). Both sub-process calls skip when their idempotency markers already exist (`bin/dispatcher.dart` and `.dowel/installed/tapir.json` respectively), so re-running `tapir:install` is a fast no-op.

If the chained calls fail (no `dart` on PATH, partial pub-cache, restricted sandbox), `tapir:install` falls through with a warning and exits 0; the `lib/main.dart` patch already landed, so `dart run tapir <cmd>` still works. You can finish the setup manually:

```bash
dart run tapir install                          # only if Phase 2 was skipped
dart run tapir plugin:install tapir   # idempotent; refreshes barrels on re-run
```

After Phase 2 lands, `./bin/dowel list` shows all `tapir:*` commands and `./bin/dowel mcp:serve` exposes the 31 tapir_* tools.

The optional `mcp:install` step in the next section writes the plugin-aware `.mcp.json` payload by default. When fastcli (`./bin/dowel`) is present, the entry uses `./bin/dowel mcp:serve`; when it is absent, the wrapper's `--invocation=tapir` pass-through causes `mcp:install` to write `dart run tapir mcp:serve` instead. Either way, no manual `.mcp.json` edit is needed.

<a name="wire-mcp-tools"></a>
## Wire MCP tools

With dowel registered, expose tapir's 33 MCP tools to your AI client by writing the `.mcp.json` entry:

```bash
dart run tapir mcp:install
```

This writes (or updates) a `.mcp.json` file at the project root. Claude Code,
Cursor, and Windsurf all pick up `.mcp.json` automatically from the working directory.
The payload depends on your scaffold state:

- **fastcli present** (`./bin/dowel` exists, POSIX): writes `./bin/dowel mcp:serve` — fastest startup (~50ms warm AOT).
- **fastcli absent**: the wrapper injects `--invocation=tapir` automatically, so the entry writes `dart run tapir mcp:serve` (~3s startup, no scaffold required).

See [Fallback invocations](../mcp/setup.md#fallback-invocations) for the full precedence table.

<a name="verify-installation"></a>
## Verify installation

Start your Flutter app in debug mode on a device or browser:

```bash
flutter run -d chrome
```

Then, in a separate terminal, capture the first Semantics snapshot:

```bash
dart run tapir tapir:snap
```

A successful snap prints a YAML block beginning with `snapshot:` followed by one or
more indented widget nodes. Each node carries a `ref:` token (`e1`, `e2`, ...) that
you pass to action commands. If the command exits with an error, confirm that
`TapirPlugin.install()` is reachable in your `main.dart` and that the app is running
in debug mode (VM Service extensions do not register in profile or release builds).
