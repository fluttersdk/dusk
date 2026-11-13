import 'dart:io';

import 'package:dowel/dowel.dart';

// Direct import (not the package barrel) so this entrypoint stays Flutter-free.
// The barrel re-exports TapirPlugin + gesture drivers, which transitively pull in
// `dart:ui` (RendererBinding, GestureBinding). `dart run tapir`
// runs on the plain Dart VM; touching `dart:ui` from this binary would break
// CLI invocation outside `flutter run`.
import 'package:tapir/src/cli_args.dart';
import 'package:tapir/src/tapir_dowel_provider.dart';

/// `dart run tapir <cmd>` ; tapir-flavoured dowel wrapper.
///
/// Proxies the full dowel command surface (start / stop / status / doctor /
/// logs / restart / reload / hot-restart / tinker / make:* / mcp:* /
/// plugin:* / consumer:scaffold / etc.) AND registers
/// [TapirDowelProvider] so the 3 tapir CLI commands
/// (`tapir:snap`, `tapir:tap`, `tapir:screenshot`) plus the 6
/// `tapir_*` MCP tools surface in the same `list` output.
///
/// When forwarding `mcp:install`, [injectInvocationForMcpInstall] appends
/// `--invocation=tapir` so the substrate writes the correct
/// `dart run tapir mcp:serve` entry into `.mcp.json`.
///
/// When forwarding `mcp:serve`, [collectMcpTools] is forced `true` so that
/// all 31 `tapir_*` MCP tools surface alongside the substrate `dowel_*` tools.
///
/// Run from any consumer directory that has `tapir` in its
/// pubspec as a dependency.
Future<void> main(List<String> args) async {
  final injected = injectInvocationForMcpInstall(args, 'tapir');
  final firstNonFlag = injected.firstWhere(
    (a) => !a.startsWith('-'),
    orElse: () => '',
  );
  final isMcpServe = firstNonFlag == 'mcp:serve';

  exit(
    await runDowel(
      injected,
      baseProviders: [TapirDowelProvider()],
      collectMcpTools: isMcpServe,
      delegateToConsumer: false,
    ),
  );
}
