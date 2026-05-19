# fluttersdk_dusk example

Minimal counter app that installs `DuskPlugin` and exercises the full
`ext.dusk.*` VM Service surface. Use this to verify the dusk driver
integrates cleanly before wiring it into a production app.

## Running

```bash
# Web (recommended for agent-driven E2E)
flutter run -d chrome

# macOS desktop
flutter run -d macos
```

## What DuskPlugin surfaces

`DuskPlugin.install()` registers the following VM Service extensions:

| Extension | Purpose |
|---|---|
| `ext.dusk.snapshot` | Semantics YAML tree dump (find by label / key / type) |
| `ext.dusk.tap` | Pointer-down + pointer-up at a widget coordinate |
| `ext.dusk.type` | Inject text into the focused `TextField` |
| `ext.dusk.scroll` | Programmatic scroll by delta |
| `ext.dusk.screenshot` | PNG frame capture |
| `ext.dusk.waitFor` | Poll until a widget matching a selector appears |
| `ext.dusk.find` | Single-shot widget finder (label / key / type) |
| `ext.dusk.navigate` | Push a named route |
| `ext.dusk.closeApp` | Graceful app close for CI teardown |

## artisan CLI commands

After `dart run artisan start`, the dusk commands are available:

```bash
dart run artisan dusk:snap        # capture Semantics YAML snapshot
dart run artisan dusk:tap         # tap a widget by label
dart run artisan dusk:screenshot  # save PNG of current frame
```

## MCP tools (LLM agent access)

```bash
dart run fluttersdk_artisan:mcp
```

Exposes the same surface as CLI commands as JSON-RPC tools consumable
by an AI agent connected via the MCP server.

## kDebugMode gate

`DuskPlugin.install()` is wrapped in `if (kDebugMode)` so the entire
driver branch is tree-shaken in release builds (dart2js + dart2native AOT).
