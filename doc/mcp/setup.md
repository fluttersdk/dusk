# Tapir MCP Setup

Setting up the tapir MCP tools means writing the `.mcp.json` entry of the `dowel` MCP server and registering `TapirDowelProvider`.

The tapir tools ride on the substrate MCP server shipped inside
[`dowel`](https://anilcancakir.com/dowel/docs/mcp/setup). Install the substrate, register
`TapirDowelProvider`, and every `tapir_*` tool surfaces automatically.

```bash
dart run tapir mcp:install
```

- [Prerequisites](#prerequisites)
- [Automated install (recommended)](#automated-install-recommended)
- [Canonical `.mcp.json` entry](#canonical-mcpjson-entry)
- [Fallback invocations](#fallback-invocations)
- [Per-client install](#per-client-install)
- [Reconnect ritual](#reconnect-ritual)
- [Troubleshooting](#troubleshooting)
- [Related Documentation](#related-documentation)

<a name="prerequisites"></a>
## Prerequisites

Before wiring any client config:

1. The consumer's `pubspec.yaml` depends on `dowel` and `tapir`.
2. The consumer's `bin/dispatcher.dart` (the generated scaffold from `dart run tapir install`)
   picks `TapirDowelProvider` up from the `lib/app/_plugins.g.dart` barrel, which
   `dart run tapir plugin:install tapir` fills and `dart run tapir plugins:refresh`
   regenerates. `dart run tapir tapir:install` runs both for you.
3. `dart run tapir list` shows the tapir commands (`tapir:snap`, `tapir:tap`,
   etc.). When they are missing, the provider is not registered.

The MCP server stays online with zero apps running. Plugin tool calls lazy-reconnect to the
VM Service URI recorded in the project's dowel session file
(`~/.dowel/sessions/<hash>/state.json`) on first call.

<a name="automated-install-recommended"></a>
## Automated install (recommended)

`dowel` ships a built-in MCP installer that writes the canonical `.mcp.json`
entry for you. Once tapir is in `pubspec.yaml` and the provider is registered, the same
single command wires Claude Code, Cursor, Windsurf, and any other client that
reads `.mcp.json` at the project root:

```bash
dart run tapir mcp:install
```

The installer is idempotent: pre-existing entries are preserved and the `dowel` key is
replaced in-place on re-run. Override the target path per client:

```bash
# Cursor (per-project)
dart run tapir mcp:install --path .cursor/mcp.json
```

To remove the entry later:

```bash
dart run tapir mcp:uninstall
```

<a name="canonical-mcpjson-entry"></a>
## Canonical `.mcp.json` entry

When writing the file by hand (or wiring a client whose path is not yet covered by
`mcp:install --path`):

```json
{
  "mcpServers": {
    "dowel": {
      "command": "dart",
      "args": ["run", "tapir", "mcp:serve"],
      "cwd": "."
    }
  }
}
```

The `cwd` field must point at the project root (the directory that contains the consumer's
`pubspec.yaml`). `dart run tapir mcp:serve` starts the substrate's MCP server with
`TapirDowelProvider` already registered, so the tapir descriptors ride on it.

<a name="fallback-invocations"></a>
## Fallback invocations

`mcp:install` picks the `.mcp.json` command/args payload based on the consumer's scaffold state. Three precedence levels, highest first:

1. **`./bin/dowel mcp:serve`**: when the fastcli scaffold is present and the platform is POSIX. Fastest startup (a pre-compiled binary). This is the default after `dart run tapir tapir:install`.

   ```json
   { "command": "./bin/dowel", "args": ["mcp:serve"], "cwd": "." }
   ```

2. **`dart run tapir mcp:serve`**: when fastcli is absent (Windows or scaffold skipped). Auto-selected: the tapir wrapper injects `--invocation=tapir` before forwarding `mcp:install` to the substrate, so the correct payload is written without any manual intervention. About 3s startup per call. This path surfaces every `tapir_*` tool without a scaffold, because the wrapper forces `collectMcpTools: true` when dispatching `mcp:serve`.

   ```json
   { "command": "dart", "args": ["run", "tapir", "mcp:serve"], "cwd": "." }
   ```

3. **`dart run :dispatcher mcp:serve`**: fallback when `mcp:install` runs without a plugin invocation hint (for example `dart run dowel mcp:install`, which skips the tapir wrapper). Prefer level 2 for tapir consumers; this form boots without tapir plugin tools unless the generated dispatcher already registers the provider.

Trade-off: the fastcli path (level 1) requires the `./bin/dowel` AOT binary to be pre-compiled and present on the file system, but offers the fastest MCP server startup. The `dart run` path (level 2) works everywhere Dart is on PATH with no pre-compilation, at the cost of about 3s cold-start per agent session.

<a name="per-client-install"></a>
## Per-client install

| Client | Config path | After edit |
|:---|:---|:---|
| Claude Code | `.mcp.json` (project) or `~/.claude.json` (user) | `/mcp reconnect dowel` |
| Cursor | `.cursor/mcp.json` (project) or `~/.cursor/mcp.json` (user) | Auto-reload |
| VS Code | `code --add-mcp '{"name":"dowel","type":"stdio","command":"dart","args":["run","tapir","mcp:serve"]}'` | Reload window |
| Continue | `.continue/config.json` `mcpServers` block | Restart Continue panel |
| Windsurf | Windsurf MCP settings panel | Reload Cascade panel |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) / `%APPDATA%\Claude\claude_desktop_config.json` (Windows) | Fully quit + relaunch (close-window != quit) |

For Claude Code via CLI:

```bash
claude mcp add dowel -- dart run tapir mcp:serve
# or project-scoped:
claude mcp add --scope project dowel -- dart run tapir mcp:serve
```

<a name="reconnect-ritual"></a>
## Reconnect ritual

Claude Code, Continue, and Windsurf do NOT auto-reconnect when `.mcp.json` or
`.dowel/mcp.json` (the visibility filter) changes. After every edit:

- **Claude Code:** run `/mcp reconnect dowel` in the chat. The slash command
  re-initialises only the named server; other MCP entries stay connected.
- **VS Code / Continue:** reload the editor window or restart the panel.
- **Windsurf:** reload the Cascade panel.
- **Cursor:** picks up changes on its own; no manual action needed.

The substrate MCP server stays online during a reconnect; the client simply re-runs
`initialize` and reads the refreshed tool catalogue.

<a name="troubleshooting"></a>
## Troubleshooting

**The server is online but no app is running.** This is normal. The substrate MCP server
starts without requiring the session file. Every `tapir_*` tool call returns an
actionable error (`No Flutter app detected`) until you run `dart run tapir start`. Once the
session file exists the next tool call lazy-reconnects.

**`tapir_*` tools missing from the catalogue.** The provider is not registered with the
executable `.mcp.json` starts. Check that executable, not the wrapper: when `.mcp.json`
starts `./bin/dowel`, run `./bin/dowel list`, because `dart run tapir list` registers
`TapirDowelProvider` itself and shows the `tapir:*` block even when the scaffolded
`./bin/dowel` lacks the provider (for example after a failed Phase 2 of `tapir:install`).
When the block is missing, run `dart run tapir plugin:install tapir`, then
`./bin/dowel list` again. `dart run tapir plugins:refresh` regenerates the
`lib/app/_plugins.g.dart` auto-discovery barrel. When `.mcp.json` starts
`dart run tapir mcp:serve`, `dart run tapir list` is the right check.

**Lazy-reconnect on first `tools/call` is slow (~1s).** Expected; the substrate opens a
WebSocket to the VM Service URI on demand. Subsequent calls reuse the cached connection.

**Tool visibility filter.** Hide a tool surface without uninstalling: edit
`.dowel/mcp.json` to add the tool name under `tools.deny`. Deny always wins over allow.
Run the reconnect ritual after editing.

<a name="related-documentation"></a>
## Related Documentation

- [overview.md](overview.md): tool catalogue, dispatch surfaces (`ext.tapir.*` vs.
  `dowel:tapir:*`), lifecycle.
- [tool-reference.md](tool-reference.md): per-tool input schema and example payloads.
- [Substrate MCP setup](https://anilcancakir.com/dowel/docs/mcp/setup): the full per-client
  install matrix for the underlying server.
