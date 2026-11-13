# Tapir MCP Setup

The tapir MCP tools ride on the substrate MCP server shipped inside
[`dowel`](https://anilcancakir.com/dowel/docs/mcp/setup). Setup is therefore the
substrate's `.mcp.json` plus a one-line provider registration: install the substrate,
register `TapirDowelProvider`, and the 33 `tapir_*` tools surface automatically.

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
2. The consumer's `bin/dowel.dart` (the standard scaffold from `dart run tapir install`) lists `TapirDowelProvider` in its provider factory list,
   or relies on the auto-discovered `lib/app/_plugins.g.dart` barrel populated by
   `dart run tapir plugins:refresh`.
3. `dart run tapir list` shows the tapir commands (`tapir:snap`, `tapir:tap`,
   etc.). When they are missing, the provider is not registered.

The MCP server stays online with zero apps running. Plugin tool calls lazy-reconnect to the
VM Service URI recorded in `~/.dowel/state.json` on first call.

<a name="automated-install-recommended"></a>
## Automated install (recommended)

`dowel` ships a built-in MCP installer that writes the canonical `.mcp.json`
entry for you. Once tapir is in `pubspec.yaml` and the provider is registered, the same
single command wires Claude Code, Cursor, VS Code, Windsurf, and any other client that
reads `.mcp.json` at the project root:

```bash
dart run tapir mcp:install
```

The installer is idempotent: pre-existing entries are preserved and the `dowel` key is
replaced in-place on re-run. Override the target path per client:

```bash
# VS Code (per-project)
dart run tapir mcp:install --path .vscode/mcp.json

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
`pubspec.yaml`). The server binary is the substrate's `bin/mcp.dart`; the tapir descriptors
ride on it.

<a name="fallback-invocations"></a>
## Fallback invocations

`mcp:install` picks the `.mcp.json` command/args payload based on the consumer's scaffold state. Three precedence levels, highest first:

1. **`./bin/dowel mcp:serve`** — when the fastcli scaffold is present and the platform is POSIX. Fastest startup (~50ms warm AOT). This is the default after `dart run tapir tapir:install`.

   ```json
   { "command": "./bin/dowel", "args": ["mcp:serve"], "cwd": "." }
   ```

2. **`dart run tapir mcp:serve`** — when fastcli is absent (Windows or scaffold skipped). Auto-selected: the tapir wrapper injects `--invocation=tapir` before forwarding `mcp:install` to the substrate, so the correct payload is written without any manual intervention. ~3s startup per call. This path surfaces all 40 tapir_* tools without scaffold dependency, because the wrapper forces `collectMcpTools: true` when dispatching `mcp:serve`.

   ```json
   { "command": "dart", "args": ["run", "tapir", "mcp:serve"], "cwd": "." }
   ```

3. **`dart run :dispatcher mcp:serve`** — legacy fallback when `mcp:install` is called directly through the substrate without a plugin invocation hint (e.g. a consumer that ran `dart run tapir mcp:install` without going through the tapir wrapper). Prefer level 2 for tapir consumers; this form boots without tapir plugin tools unless the dispatcher is already configured.

Trade-off: the fastcli path (level 1) requires the `./bin/dowel` AOT binary to be pre-compiled and present on the file system, but offers the fastest MCP server startup. The `dart run` path (level 2) works everywhere Dart is on PATH with no pre-compilation, at the cost of ~3s cold-start per agent session.

<a name="per-client-install"></a>
## Per-client install

| Client | Config path | After edit |
|---|---|---|
| Claude Code | `.mcp.json` (project) or `~/.claude.json` (user) | `/mcp reconnect dowel` |
| Cursor | `.cursor/mcp.json` (project) or `~/.cursor/mcp.json` (user) | Auto-reload |
| VS Code (GitHub Copilot Workspace) | `.vscode/mcp.json` with `"servers"` key + `"type": "stdio"` | Reload window |
| Continue | `.continue/config.json` `mcpServers` block | Restart Continue panel |
| Windsurf | Windsurf MCP settings panel | Reload Cascade panel |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) / `%APPDATA%\Claude\claude_desktop_config.json` (Windows) | Fully quit + relaunch (close-window != quit) |

For Claude Code via CLI:

```bash
claude mcp add dowel -- dart run tapir mcp:serve
# or project-scoped:
claude mcp add --scope project dowel -- dart run tapir mcp:serve
```

For the VS Code MCP shape (note the `"servers"` key, not `"mcpServers"`, plus the explicit
transport type):

```json
{
  "servers": {
    "dowel": {
      "type": "stdio",
      "command": "dart",
      "args": ["run", "tapir", "mcp:serve"],
      "cwd": "."
    }
  }
}
```

<a name="reconnect-ritual"></a>
## Reconnect ritual

Claude Code, Continue, and Windsurf do NOT auto-reconnect when `.mcp.json` or
`.dowel/mcp.json` (the visibility filter) changes. After every edit:

- **Claude Code:** run `/mcp reconnect dowel` in the chat. The slash command
  re-initializes only the named server; other MCP entries stay connected.
- **VS Code / Continue:** reload the editor window or restart the panel.
- **Windsurf:** reload the Cascade panel.
- **Cursor:** picks up changes on its own; no manual action needed.

The substrate MCP server stays online during a reconnect; the client simply re-runs
`initialize` and reads the refreshed tool catalog.

<a name="troubleshooting"></a>
## Troubleshooting

**The server is online but no app is running.** This is normal. The substrate MCP server
starts without requiring `~/.dowel/state.json`. Every `tapir_*` tool call returns an
actionable error (`"VM Service unreachable: state.json missing"`) until you run `dart run tapir start`. Once the state file exists the next tool call lazy-reconnects.

**`tapir_*` tools missing from the catalog.** The provider is not registered. Verify by
running `dart run tapir list` and confirming the `tapir:*` command block. If
the block is empty, add `TapirDowelProvider.new` to the consumer's `dowelProviders`
list in `bin/dowel.dart`, or run `dart run tapir plugins:refresh` to
regenerate the auto-discovery barrel.

**Lazy-reconnect on first `tools/call` is slow (~1s).** Expected; the substrate opens a
WebSocket to the VM Service URI on demand. Subsequent calls reuse the cached connection.

**Tool visibility filter.** Hide a tool surface without uninstalling: edit
`.dowel/mcp.json` to add the tool name under `tools.deny`. Deny always wins over allow.
Run the reconnect ritual after editing.

<a name="related-documentation"></a>
## Related Documentation

- [overview.md](overview.md): tool catalog, dispatch surfaces (`ext.tapir.*` vs.
  `dowel:tapir:*`), lifecycle.
- [tool-reference.md](tool-reference.md): per-tool input schema and example payloads.
- [Substrate MCP setup](https://anilcancakir.com/dowel/docs/mcp/setup): the full per-client
  install matrix for the underlying server.
