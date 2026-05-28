/// Args massagers for the dusk CLI wrapper.
///
/// Pure functions (no IO, no Flutter dependencies) so the bin entrypoint
/// stays Flutter-free and the logic is unit-testable.
library;

/// Returns [args] with `--invocation=<invocation>` appended when:
///   - the first non-flag arg is exactly `mcp:install`, AND
///   - [args] does NOT already contain a user-supplied `--invocation` (either
///     `--invocation=<value>` or the whitespace form `--invocation <value>`).
///
/// Otherwise returns [args] unchanged.
///
/// Reason: surfaces plugin invocation context to the substrate's `.mcp.json`
/// writer at `mcp_install_command.dart:127-141` (the new three-branch payload
/// decision; bug 1 fix). When fastcli is absent, the substrate writes
/// `dart run <invocation> mcp:serve` instead of the legacy `:dispatcher`
/// fallback.
List<String> injectInvocationForMcpInstall(
  List<String> args,
  String invocation,
) {
  // 1. Find the first non-flag arg.
  final firstNonFlag = args.firstWhere(
    (a) => !a.startsWith('-'),
    orElse: () => '',
  );
  if (firstNonFlag != 'mcp:install') return args;

  // 2. Honor user-supplied --invocation (either equal-form or whitespace form).
  final hasOverride = args.any(
    (a) => a.startsWith('--invocation=') || a == '--invocation',
  );
  if (hasOverride) return args;

  // 3. Inject the canonical invocation flag.
  return [...args, '--invocation=$invocation'];
}
