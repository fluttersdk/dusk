---
applyTo: '**'
---
# Commands Subsystem

## Class shape

Every CLI command lives in its own file under `lib/src/commands/tapir_<verb>_command.dart` and extends `DowelCommand` from `dowel`:

```dart
final class TapirTapCommand extends DowelCommand {
  TapirTapCommand();

  @override
  String get name => 'tapir:tap';

  @override
  String get description => 'Tap a widget by ref token.';

  @override
  DowelBoot get boot => DowelBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption('ref', mandatory: true);
    parser.addFlag('checkStable', defaultsTo: true);
    parser.addFlag('checkReceivesEvents', defaultsTo: true);
    parser.addFlag('includeSnapshot', defaultsTo: true);
  }

  @override
  Future<int> handle(DowelContext ctx) async {
    final ref = ctx.results['ref'] as String;
    // 1. Validate args.
    // 2. Call the VM Service extension.
    final response = await ctx.callExtension('ext.tapir.tap', {
      'ref': ref,
      'checkStable': ctx.results['checkStable'].toString(),
      'checkReceivesEvents': ctx.results['checkReceivesEvents'].toString(),
      'includeSnapshot': ctx.results['includeSnapshot'].toString(),
    });
    // 3. Format output.
    ctx.stdout.writeln(response);
    return 0;
  }
}
```

## Boot modes

- `DowelBoot.connected` (29 commands): requires a running app's VM Service URI from `~/.dowel/state.json`. Used for every `ext.tapir.*` route.
- `DowelBoot.none` (3 commands): runs without a VM Service. Used for `tapir:install` (writes `lib/main.dart`), `tapir:doctor` (filesystem + env preflight), `tapir:resize` and `tapir:device` (Chrome DevTools Protocol from a non-Flutter Dart context).

Three commands use the `dowel:tapir:*` substrate prefix instead of `ext.tapir.*`: `tapir:hot_reload_and_snap` (in-isolate self-reload would deadlock; routes through the substrate dispatcher to write `r\n` to the flutter run FIFO and tail-poll the log), `tapir:resize` and `tapir:device` (drive CDP via `lib/src/cdp/cdp_client.dart`).

## Argument conventions

- `--ref=<eN|qN>` for any command that targets a single widget. Always required.
- `--checkStable` / `--no-checkStable`: actionability-gate stability opt-out (default true).
- `--checkReceivesEvents` / `--no-checkReceivesEvents`: actionability-gate hit-test opt-out (default true).
- `--includeSnapshot` / `--no-includeSnapshot`: append a post-action snapshot to the response payload (default true for actions, false for pure-read commands).
- `--timeout=<ms>` for any wait command. Default 5000.
- `--format=<jpeg|png>` for `tapir:screenshot`. JPEG q70 is the default (40-120 KB typical).

Snake_case option names match the VM Service extension param keys 1:1; the command does no key translation.

## Output

`stdout` receives the success payload (JSON-encoded). Errors go to `stderr` via `ctx.stderr.writeln(...)`. The command's exit code is 0 on success, non-zero on failure (the dowel substrate translates this into the shell exit code).

Commands that call an extension and receive a `TapirErrorEnvelope` should pretty-print the `reason` substring first, then the full JSON, then exit non-zero. This keeps both human readers and downstream agents productive.

## Registration

The 32 commands are registered in order at `lib/src/tapir_dowel_provider.dart:64-120` inside `commands()`. The 31 MCP descriptors live at `lib/src/tapir_dowel_provider.dart:123-1434` inside `mcpTools()`. `tapir_evaluate` is intentionally MCP-only (no CLI mirror) because `magic_tinker` owns the connected REPL surface; never duplicate it under `tapir:`.

## MCP tool descriptor format

Every entry in `mcpTools()` is a const `McpToolDescriptor`. The description follows the Claude Code canonical shape: imperative opening sentence (survives 2 KB truncation), one context paragraph, a `Usage:` bullet list. `inputSchema` is JSON Schema 2020-12 with `"type": "object"`, `properties`, `required`, and `additionalProperties: false`:

```dart
const McpToolDescriptor(
  name: 'tapir_tap',
  description: '''
Tap a widget by ref token from a prior tapir_snap call.

Synthesizes a Down + 50ms + Up pointer sequence at the widget's center.
Routes through the 6-step actionability gate before dispatching.

Usage:
- Call tapir_snap first to mint ref tokens.
- Pass ref="e7" (snapshot-frozen) or ref="q3" (re-resolvable query handle).
- Set checkStable=false to skip the 2-frame stability check on flaky animations.
''',
  extensionMethod: 'ext.tapir.tap',
  inputSchema: { ... },
);
```

Names follow `tapir_<verb>` snake_case (max 128 chars per MCP spec; we stay well under). The 6 alpha-1 names (`tapir_snap`, `tapir_tap`, `tapir_screenshot`, `tapir_hover`, `tapir_drag`, `tapir_type`) and their `extensionMethod` strings are FROZEN; renames break pinned agent prompts.

## Adding a new command

1. Create `lib/src/commands/tapir_<verb>_command.dart`. Match the class shape above.
2. Add a matching VM Service handler (see `.claude/rules/extensions.md`) unless the command routes through `dowel:tapir:*` substrate.
3. Append the command to `TapirDowelProvider.commands()` at `lib/src/tapir_dowel_provider.dart:64`.
4. Append a const `McpToolDescriptor` to `mcpTools()` (skip when the command is intentionally CLI-only).
5. Add a unit test at `test/src/commands/tapir_<verb>_command_test.dart`. Extend `test/tapir_dowel_provider_mcp_tools_test.dart` to bump the expected `commands().length` and `mcpTools().length` assertions and to cover the new descriptor's `name` + `extensionMethod`.
6. Update docs per `.claude/rules/docs.md`.
