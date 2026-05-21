# Dusk MCP Overview

`fluttersdk_dusk` does not ship its own MCP server. It plugs into the substrate MCP server
hosted by [`fluttersdk_artisan`](https://fluttersdk.com/artisan/mcp/overview) by exporting an
`ArtisanServiceProvider` (`DuskArtisanProvider`) that contributes 31 MCP tool descriptors.
When the consumer registers the provider in `bin/artisan.dart` (or via the auto-discovered
`lib/app/_plugins.g.dart` barrel), the substrate MCP server picks up the dusk tools at
`initialize` time and surfaces them alongside its own 10 substrate tools, so the AI client
sees a single unified catalog.

<a name="toc"></a>

- [Substrate MCP server, dusk tool descriptors](#substrate-and-descriptors)
- [The 31 dusk tools](#tool-catalog)
- [Dispatch surfaces: `ext.dusk.*` vs. `artisan:dusk:*`](#dispatch-surfaces)
- [Lifecycle: state file, lazy reconnect, snap-act loop](#lifecycle)
- [Related](#related)

---

<a name="substrate-and-descriptors"></a>

## Substrate MCP server, dusk tool descriptors

The substrate MCP server lives inside `fluttersdk_artisan`. The binary `dart run
fluttersdk_artisan:mcp` speaks stdio JSON-RPC, reads `~/.artisan/state.json` to find the
running Flutter app's VM Service URI, and collects every registered provider's
`mcpTools()` list at boot. `DuskArtisanProvider.mcpTools()` returns 31 `McpToolDescriptor`
instances; the substrate server registers each as a regular MCP tool and dispatches calls
through the descriptor's declared `extensionMethod`. No additional server process is
launched for dusk; one MCP endpoint, one server, plugin-extensible.

This means every `.mcp.json` snippet that wires the substrate MCP server already gives the
AI client access to the dusk tools. There is no separate `fluttersdk_dusk:mcp` binary to
add, no second `cwd` to configure. See [setup.md](setup.md) for the per-client install
matrix.

---

<a name="tool-catalog"></a>

## The 31 dusk tools

`DuskArtisanProvider.mcpTools()` returns the following 31 descriptors. The list is sorted
alphabetically; each link jumps to the per-tool entry in [tool-reference.md](tool-reference.md).

| Tool | Purpose |
|---|---|
| [`dusk_blur`](tool-reference.md#dusk_blur) | Clear keyboard focus from whatever currently holds it. |
| [`dusk_clear`](tool-reference.md#dusk_clear) | Empty the `TextEditingController` of a resolved text field. |
| [`dusk_close_app`](tool-reference.md#dusk_close_app) | Request a graceful shutdown via `SystemNavigator.pop()`. |
| [`dusk_console`](tool-reference.md#dusk_console) | Read recent log entries from the telescope store. |
| [`dusk_dblclick`](tool-reference.md#dusk_dblclick) | Double-click a widget by ref. |
| [`dusk_device_profile`](tool-reference.md#dusk_device_profile) | Emulate a named device profile via CDP. |
| [`dusk_dismiss_modals`](tool-reference.md#dusk_dismiss_modals) | Pop every modal route above the first persistent route. |
| [`dusk_drag`](tool-reference.md#dusk_drag) | Drag from one widget to another by ref. |
| [`dusk_evaluate`](tool-reference.md#dusk_evaluate) | Evaluate a Dart expression in the running isolate. |
| [`dusk_exceptions`](tool-reference.md#dusk_exceptions) | Read recent exceptions from the telescope store. |
| [`dusk_find`](tool-reference.md#dusk_find) | Mint a re-resolvable `q<N>` handle by text / label / key. |
| [`dusk_focus`](tool-reference.md#dusk_focus) | Request keyboard focus on a widget by ref. |
| [`dusk_get_routes`](tool-reference.md#dusk_get_routes) | List route paths declared by the running router. |
| [`dusk_hot_reload_and_snap`](tool-reference.md#dusk_hot_reload_and_snap) | Hot reload, snap, screenshot, exceptions in one round-trip. |
| [`dusk_hover`](tool-reference.md#dusk_hover) | Hover a mouse cursor over a widget by ref. |
| [`dusk_navigate`](tool-reference.md#dusk_navigate) | Navigate to a route path. |
| [`dusk_navigate_back`](tool-reference.md#dusk_navigate_back) | Pop the top route off the navigator stack. |
| [`dusk_observe`](tool-reference.md#dusk_observe) | Structured candidate list of interactive widgets (Stagehand pattern). |
| [`dusk_press_key`](tool-reference.md#dusk_press_key) | Press a hardware key with optional modifiers. |
| [`dusk_resize_viewport`](tool-reference.md#dusk_resize_viewport) | Resize the web viewport via CDP. |
| [`dusk_right_click`](tool-reference.md#dusk_right_click) | Fire a right (secondary mouse) click. |
| [`dusk_screenshot`](tool-reference.md#dusk_screenshot) | Capture a screenshot of the running app. |
| [`dusk_scroll`](tool-reference.md#dusk_scroll) | Scroll a Scrollable widget by ref. |
| [`dusk_select_option`](tool-reference.md#dusk_select_option) | Select an option in a DropdownButton. |
| [`dusk_set_checkbox`](tool-reference.md#dusk_set_checkbox) | Read + conditionally toggle a Checkbox / Switch. |
| [`dusk_snap`](tool-reference.md#dusk_snap) | Capture a YAML Semantics snapshot with `e<N>` refs. |
| [`dusk_tap`](tool-reference.md#dusk_tap) | Tap a widget by ref. |
| [`dusk_triple_click`](tool-reference.md#dusk_triple_click) | Fire three primary clicks (~100ms apart). |
| [`dusk_type`](tool-reference.md#dusk_type) | Type text into a TextField by ref. |
| [`dusk_wait_for`](tool-reference.md#dusk_wait_for) | Wait until a UI condition is satisfied. |
| [`dusk_wait_for_network_idle`](tool-reference.md#dusk_wait_for_network_idle) | Wait for zero in-flight HTTP requests. |

Tool names are frozen: the `dusk_<verb>` shape is part of the alpha-2 cross-repo contract.
Renames break agent prompts and pinned consumer scripts.

---

<a name="dispatch-surfaces"></a>

## Dispatch surfaces: `ext.dusk.*` vs. `artisan:dusk:*`

The substrate MCP server inspects each descriptor's `extensionMethod` field to choose a
dispatch path. Dusk uses two:

- **`ext.dusk.*` (28 tools).** The default path. The MCP server calls
  `VmServiceClient.callServiceExtension(method, args)` against the running Flutter app's VM
  Service. The handler runs inside the app isolate and returns a `ServiceExtensionResponse`.
  This is the standard pattern; every action / inspection tool uses it.
- **`artisan:dusk:*` (3 tools).** Dispatched in-process by the MCP server via the artisan
  registry, executing the matching CLI command (`dusk:hot_reload_and_snap`,
  `dusk:resize`, `dusk:device`). These three tools cannot run inside the app isolate:
  `dusk_hot_reload_and_snap` triggers `vm.reloadSources` against the very isolate that would
  be servicing the call (deadlock), and `dusk_resize_viewport` /
  `dusk_device_profile` drive Chrome DevTools Protocol on the host's Chromium subprocess.
  The substrate routes them through the CLI command instead so the orchestration runs
  outside the target isolate.

Both paths return MCP `CallToolResult` content; the agent sees no difference at the JSON-RPC
layer. The split exists purely so the same tool catalog can mix in-isolate VM Service calls
and out-of-isolate CLI drivers without a second binary.

---

<a name="lifecycle"></a>

## Lifecycle: state file, lazy reconnect, snap-act loop

Dusk inherits the substrate's lifecycle. The MCP server stays online even when no Flutter
app is running: `~/.artisan/state.json` may be absent at `initialize` time, and the server
still registers every tool descriptor. The first `tools/call` against a `dusk_*` tool
triggers a lazy reconnect: the MCP server reads `state.json`, opens a WebSocket to the VM
Service URI, and dispatches the call. Subsequent calls reuse the cached connection.

The canonical agent loop:

```
dusk_snap          ->  capture Semantics tree, read refs
dusk_find / read   ->  identify the target widget
dusk_tap / type /  ->  drive an action against the ref
  scroll / drag
dusk_wait_for /    ->  bridge async UI transitions
  wait_for_network_idle
dusk_snap          ->  observe the new state, loop
```

The `e<N>` refs from `dusk_snap` are frozen at snap time; re-snap after any navigation,
modal open/close, or significant rebuild. `q<N>` refs from `dusk_find` re-resolve on every
action call so they survive rebuilds as long as the predicates still match.

---

<a name="related"></a>

## Related

- [setup.md](setup.md): per-client install matrix (Claude Code, Cursor, Windsurf, VS Code,
  etc.) plus the reconnect ritual after editing `.mcp.json` or `.artisan/mcp.json`.
- [tool-reference.md](tool-reference.md): per-tool input schema, return shape, and example
  JSON-RPC payload for every dusk tool.
- [Substrate MCP overview](https://fluttersdk.com/artisan/mcp/overview): the underlying
  artisan MCP server that hosts the dusk tools.
