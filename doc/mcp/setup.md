# Dusk MCP Setup

The dusk MCP tools ride on the substrate MCP server shipped inside
[`fluttersdk_artisan`](https://fluttersdk.com/artisan/mcp/setup). Setup is therefore the
substrate's `.mcp.json` plus a one-line provider registration: install the substrate,
register `DuskArtisanProvider`, and the 33 `dusk_*` tools surface automatically.

## Prerequisites

Before wiring any client config:

1. The consumer's `pubspec.yaml` depends on `fluttersdk_artisan` and `fluttersdk_dusk`.
2. The consumer's `bin/artisan.dart` (the standard scaffold from `dart run fluttersdk_dusk install`) lists `DuskArtisanProvider` in its provider factory list,
   or relies on the auto-discovered `lib/app/_plugins.g.dart` barrel populated by
   `dart run fluttersdk_dusk plugins:refresh`.
3. `dart run fluttersdk_dusk list` shows the dusk commands (`dusk:snap`, `dusk:tap`,
   etc.). When they are missing, the provider is not registered.

The MCP server stays online with zero apps running. Plugin tool calls lazy-reconnect to the
VM Service URI recorded in `~/.artisan/state.json` on first call.

## Automated install (recommended)

`fluttersdk_artisan` ships a built-in MCP installer that writes the canonical `.mcp.json`
entry for you. Once dusk is in `pubspec.yaml` and the provider is registered, the same
single command wires Claude Code, Cursor, VS Code, Windsurf, and any other client that
reads `.mcp.json` at the project root:

```bash
dart run fluttersdk_dusk mcp:install
```

The installer is idempotent: pre-existing entries are preserved and the `fluttersdk` key is
replaced in-place on re-run. Override the target path per client:

```bash
# VS Code (per-project)
dart run fluttersdk_dusk mcp:install --path .vscode/mcp.json

# Cursor (per-project)
dart run fluttersdk_dusk mcp:install --path .cursor/mcp.json
```

To remove the entry later:

```bash
dart run fluttersdk_dusk mcp:uninstall
```

## Canonical `.mcp.json` entry

When writing the file by hand (or wiring a client whose path is not yet covered by
`mcp:install --path`):

```json
{
  "mcpServers": {
    "fluttersdk": {
      "command": "dart",
      "args": ["run", "fluttersdk_dusk", "mcp:serve"],
      "cwd": "."
    }
  }
}
```

The `cwd` field must point at the project root (the directory that contains the consumer's
`pubspec.yaml`). The server binary is the substrate's `bin/mcp.dart`; the dusk descriptors
ride on it.

## Fallback invocations

`mcp:install` picks the `.mcp.json` command/args payload based on the consumer's scaffold state. Three precedence levels, highest first:

1. **`./bin/fsa mcp:serve`** — when the fastcli scaffold is present and the platform is POSIX. Fastest startup (~50ms warm AOT). This is the default after `dart run fluttersdk_dusk dusk:install`.

   ```json
   { "command": "./bin/fsa", "args": ["mcp:serve"], "cwd": "." }
   ```

2. **`dart run fluttersdk_dusk mcp:serve`** — when fastcli is absent (Windows or scaffold skipped). Auto-selected: the dusk wrapper injects `--invocation=fluttersdk_dusk` before forwarding `mcp:install` to the substrate, so the correct payload is written without any manual intervention. ~3s startup per call. This path surfaces all 33 dusk_* tools without scaffold dependency, because the wrapper forces `collectMcpTools: true` when dispatching `mcp:serve`.

   ```json
   { "command": "dart", "args": ["run", "fluttersdk_dusk", "mcp:serve"], "cwd": "." }
   ```

3. **`dart run :dispatcher mcp:serve`** — legacy fallback when `mcp:install` is called directly through the substrate without a plugin invocation hint (e.g. a consumer that ran `dart run fluttersdk_dusk mcp:install` without going through the dusk wrapper). Prefer level 2 for dusk consumers; this form boots without dusk plugin tools unless the dispatcher is already configured.

Trade-off: the fastcli path (level 1) requires the `./bin/fsa` AOT binary to be pre-compiled and present on the file system, but offers the fastest MCP server startup. The `dart run` path (level 2) works everywhere Dart is on PATH with no pre-compilation, at the cost of ~3s cold-start per agent session.

## Per-client install

| Client | Config path | After edit |
|---|---|---|
| Claude Code | `.mcp.json` (project) or `~/.claude.json` (user) | `/mcp reconnect fluttersdk` |
| Cursor | `.cursor/mcp.json` (project) or `~/.cursor/mcp.json` (user) | Auto-reload |
| VS Code (GitHub Copilot Workspace) | `.vscode/mcp.json` with `"servers"` key + `"type": "stdio"` | Reload window |
| Continue | `.continue/config.json` `mcpServers` block | Restart Continue panel |
| Windsurf | Windsurf MCP settings panel | Reload Cascade panel |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) / `%APPDATA%\Claude\claude_desktop_config.json` (Windows) | Fully quit + relaunch (close-window != quit) |

For Claude Code via CLI:

```bash
claude mcp add fluttersdk -- dart run fluttersdk_dusk mcp:serve
# or project-scoped:
claude mcp add --scope project fluttersdk -- dart run fluttersdk_dusk mcp:serve
```

For the VS Code MCP shape (note the `"servers"` key, not `"mcpServers"`, plus the explicit
transport type):

```json
{
  "servers": {
    "fluttersdk": {
      "type": "stdio",
      "command": "dart",
      "args": ["run", "fluttersdk_dusk", "mcp:serve"],
      "cwd": "."
    }
  }
}
```

## Reconnect ritual

Claude Code, Continue, and Windsurf do NOT auto-reconnect when `.mcp.json` or
`.artisan/mcp.json` (the visibility filter) changes. After every edit:

- **Claude Code:** run `/mcp reconnect fluttersdk` in the chat. The slash command
  re-initializes only the named server; other MCP entries stay connected.
- **VS Code / Continue:** reload the editor window or restart the panel.
- **Windsurf:** reload the Cascade panel.
- **Cursor:** picks up changes on its own; no manual action needed.

The substrate MCP server stays online during a reconnect; the client simply re-runs
`initialize` and reads the refreshed tool catalog.

## Troubleshooting

**The server is online but no app is running.** This is normal. The substrate MCP server
starts without requiring `~/.artisan/state.json`. Every `dusk_*` tool call returns an
actionable error (`"VM Service unreachable: state.json missing"`) until you run `dart run fluttersdk_dusk start`. Once the state file exists the next tool call lazy-reconnects.

**`dusk_*` tools missing from the catalog.** The provider is not registered. Verify by
running `dart run fluttersdk_dusk list` and confirming the `dusk:*` command block. If
the block is empty, add `DuskArtisanProvider.new` to the consumer's `artisanProviders`
list in `bin/artisan.dart`, or run `dart run fluttersdk_dusk plugins:refresh` to
regenerate the auto-discovery barrel.

**Lazy-reconnect on first `tools/call` is slow (~1s).** Expected; the substrate opens a
WebSocket to the VM Service URI on demand. Subsequent calls reuse the cached connection.

**Tool visibility filter.** Hide a tool surface without uninstalling: edit
`.artisan/mcp.json` to add the tool name under `tools.deny`. Deny always wins over allow.
Run the reconnect ritual after editing.

## Related

- [overview.md](overview.md): tool catalog, dispatch surfaces (`ext.dusk.*` vs.
  `artisan:dusk:*`), lifecycle.
- [tool-reference.md](tool-reference.md): per-tool input schema and example payloads.
- [Substrate MCP setup](https://fluttersdk.com/artisan/mcp/setup): the full per-client
  install matrix for the underlying server.
