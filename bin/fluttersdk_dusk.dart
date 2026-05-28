import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';

// Direct import (not the package barrel) so this entrypoint stays Flutter-free.
// The barrel re-exports DuskPlugin + gesture drivers, which transitively pull in
// `dart:ui` (RendererBinding, GestureBinding). `dart run fluttersdk_dusk`
// runs on the plain Dart VM; touching `dart:ui` from this binary would break
// CLI invocation outside `flutter run`.
import 'package:fluttersdk_dusk/src/cli_args.dart';
import 'package:fluttersdk_dusk/src/dusk_artisan_provider.dart';

/// `dart run fluttersdk_dusk <cmd>` ; dusk-flavoured artisan wrapper.
///
/// Proxies the full artisan command surface (start / stop / status / doctor /
/// logs / restart / reload / hot-restart / tinker / make:* / mcp:* /
/// plugin:* / consumer:scaffold / etc.) AND registers
/// [DuskArtisanProvider] so the 3 dusk CLI commands
/// (`dusk:snap`, `dusk:tap`, `dusk:screenshot`) plus the 6
/// `dusk_*` MCP tools surface in the same `list` output.
///
/// When forwarding `mcp:install`, [injectInvocationForMcpInstall] appends
/// `--invocation=fluttersdk_dusk` so the substrate writes the correct
/// `dart run fluttersdk_dusk mcp:serve` entry into `.mcp.json`.
///
/// When forwarding `mcp:serve`, [collectMcpTools] is forced `true` so that
/// all 31 `dusk_*` MCP tools surface alongside the substrate `artisan_*` tools.
///
/// Run from any consumer directory that has `fluttersdk_dusk` in its
/// pubspec as a dependency.
Future<void> main(List<String> args) async {
  final injected = injectInvocationForMcpInstall(args, 'fluttersdk_dusk');
  final firstNonFlag = injected.firstWhere(
    (a) => !a.startsWith('-'),
    orElse: () => '',
  );
  final isMcpServe = firstNonFlag == 'mcp:serve';

  exit(
    await runArtisan(
      injected,
      baseProviders: [DuskArtisanProvider()],
      collectMcpTools: isMcpServe,
      delegateToConsumer: false,
    ),
  );
}
