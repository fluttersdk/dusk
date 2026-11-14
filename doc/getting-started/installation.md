# Installation

Add `tapir` to a Flutter app, wire `TapirPlugin.install()` behind a `!kReleaseMode` guard, and optionally register the MCP server for your AI client.

The recommended path is one command, `dart run tapir tapir:install`, which patches `lib/main.dart` and registers the plugin with dowel; the manual route is described step by step below.

- [Quick Reference](#quick-reference)
- [Requirements](#requirements)
- [Add the package](#add-the-package)
- [Wire TapirPlugin](#wire-tapirplugin)
- [Optional integrations](#optional-integrations)
- [Register with dowel (automatic)](#register-with-dowel)
- [Wire MCP tools](#wire-mcp-tools)
- [Verify installation](#verify-installation)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

| Step | Command | Result |
|:-----|:--------|:-------|
| 1. Add the packages | `dart pub add dowel` and `flutter pub add tapir` | Both are direct dependencies. |
| 2. Wire the app | `dart run tapir tapir:install` | `lib/main.dart` gains a `!kReleaseMode` block with `TapirPlugin.install()`; dowel registers the plugin. |
| 3. Register the MCP server (optional) | `dart run tapir mcp:install` | A `.mcp.json` entry at the project root. |
| 4. Start the app | `dart run tapir start --device=chrome` | dowel records the session that every `tapir:*` command dials. |
| 5. Take a snapshot | `dart run tapir tapir:snap` | A YAML tree with `[ref=eN]` tokens. |

<a name="requirements"></a>
## Requirements

`tapir` is a Flutter package. It requires a Flutter app target for the
VM Service extensions to register against. Pure-Dart environments are not supported.

| Dependency | Minimum | Recommended |
|:-----------|:--------|:------------|
| Dart       | `^3.13.0` | latest stable |
| Flutter    | `>= 3.47.0` | latest stable |
| dowel | `^0.0.21` | latest |

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
import 'package:flutter/widgets.dart';
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
| `Wind.installDebugResolver()` (in `package:wind_kit/wind_kit.dart`) | `wind_kit` (any release that ships `Wind.installDebugResolver()`) | Wind state surfaces through the neutral `WindDebugRegistry` bridge; tapir emits the six core fields (breakpoint, brightness, platform, states, bgColor, textColor) automatically without enricher registration. |

```dart
import 'package:magic_devtools/tapir.dart'; // magic_devtools only
import 'package:wind_kit/wind_kit.dart'; // wind_kit only
// ...
if (!kReleaseMode) {
  TapirPlugin.install();
  MagicTapirIntegration.install(); // magic-stack only (from magic_devtools)
  Wind.installDebugResolver();    // wind UI only (from wind_kit)
}
```

See [Magic integration](../plugins/magic-integration.md) and
[Wind integration](../plugins/wind-integration.md) for the full enricher field reference.

<a name="register-with-dowel"></a>
## Register with dowel (automatic)

`tapir:install` already handles this for you as Phase 2 of its run. Right after the `lib/main.dart` patch lands, it chains `dart run tapir install` (scaffolds `bin/dispatcher.dart` + `./bin/dowel` fastcli, ~50ms warm AOT) followed by `dart run tapir plugin:install tapir` (registers `TapirDowelProvider` and auto-purges the AOT bundle cache). Both sub-process calls skip when their idempotency markers already exist (`bin/dispatcher.dart` and `.dowel/installed/tapir.json` respectively), so re-running `tapir:install` is a fast no-op.

If the chained calls fail (no `dart` on PATH, partial pub-cache, restricted sandbox), `tapir:install` falls through with a warning and exits 0; the `lib/main.dart` patch already landed, so `dart run tapir <cmd>` still works. You can finish the setup manually:

```bash
dart run tapir install                # only if Phase 2 was skipped
dart run tapir plugin:install tapir   # idempotent; refreshes barrels on re-run
```

After Phase 2 lands, `./bin/dowel list` shows every `tapir:*` command and `./bin/dowel mcp:serve` exposes every `tapir_*` tool.

The optional `mcp:install` step in the next section writes the plugin-aware `.mcp.json` payload by default. When fastcli (`./bin/dowel`) is present, the entry uses `./bin/dowel mcp:serve`; when it is absent, the wrapper's `--invocation=tapir` pass-through causes `mcp:install` to write `dart run tapir mcp:serve` instead. Either way, no manual `.mcp.json` edit is needed.

<a name="wire-mcp-tools"></a>
## Wire MCP tools

With dowel registered, expose the tapir MCP tools to your AI client by writing the `.mcp.json` entry:

```bash
dart run tapir mcp:install
```

This writes (or updates) a `.mcp.json` file at the project root. Claude Code,
Cursor, and Windsurf all pick up `.mcp.json` automatically from the working directory.
The payload depends on your scaffold state:

- **fastcli present** (`./bin/dowel` exists, POSIX): writes `./bin/dowel mcp:serve`, the fastest startup (~50ms warm AOT).
- **fastcli absent**: the wrapper injects `--invocation=tapir` automatically, so the entry writes `dart run tapir mcp:serve` (~3s startup, no scaffold required).

See [Fallback invocations](../mcp/setup.md#fallback-invocations) for the full precedence table.

<a name="verify-installation"></a>
## Verify installation

Start your Flutter app through dowel, so the session (the VM Service URI every `tapir:*` command dials) is recorded for this project:

```bash
dart run tapir start --device=chrome
```

Then capture the first Semantics snapshot:

```bash
dart run tapir tapir:snap
```

A successful snap prints a YAML tree of lines such as `- button "Sign in" [ref=e2]`.
Each interactive node carries a `[ref=eN]` token (`e1`, `e2`, ...) that you pass to action
commands. If the command exits with an error, confirm that `TapirPlugin.install()` is
reachable in your `main.dart` and that the app runs in a debug or profile build (a
release build tree-shakes tapir, so no `ext.tapir.*` extension registers). Stop the app with
`dart run tapir stop` when you are done.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| `TapirPlugin.install()` sits outside a `!kReleaseMode` guard. | Wrap it: `if (!kReleaseMode) { TapirPlugin.install(); }`. A `kDebugMode` guard works in debug but registers no `ext.tapir.*` in a profile build. |
| `MagicTapirIntegration.install()` runs before `Magic.init(...)`. | Call it after `Magic.init(...)`: it queries `Magic.find<X>()`, which only resolves once the container is ready. `tapir:install` places it correctly. |
| The app was started with a plain `flutter run`, and `tapir:snap` finds no app. | Start it with `dart run tapir start`, which records the session the `tapir:*` commands dial. |
| `./bin/dowel` is missing after `tapir:install`. | Phase 2 was skipped with a warning. Run `dart run tapir install` and `dart run tapir plugin:install tapir`; `dart run tapir <cmd>` works meanwhile. |
| The snapshot has no `wind:` block. | Call `Wind.installDebugResolver()` inside the same `!kReleaseMode` block (`tapir:install` does not add it), then snap with `dart run tapir tapir:snap --includeEnrichers`: enrichers are off by default, so a plain snapshot never carries the block. |
| `.mcp.json` points at the wrong launcher. | Re-run `dart run tapir mcp:install` rather than editing the file; it picks `./bin/dowel mcp:serve` or `dart run tapir mcp:serve` from the scaffold state. |

<a name="related-documentation"></a>
## Related Documentation

- [Quickstart](quickstart.md): a first snap, tap and screenshot against the bundled example app.
- [tapir:install](../commands/tapir-install.md): the sub-steps and anchor strings behind the installer.
- [MCP setup](../mcp/setup.md): wire the server into an AI client and the fallback invocations.
- [Magic integration](../plugins/magic-integration.md) and [Wind integration](../plugins/wind-integration.md): the enricher fields each integration adds.
