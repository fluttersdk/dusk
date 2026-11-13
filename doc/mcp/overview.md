# Tapir MCP Overview

`tapir` does not ship its own MCP server. It plugs into the substrate MCP server
hosted by [`dowel`](https://anilcancakir.com/dowel/docs/mcp/overview) by exporting an
`DowelServiceProvider` (`TapirDowelProvider`) that contributes 33 MCP tool descriptors.
When the consumer registers the provider in `bin/dowel.dart` (or via the auto-discovered
`lib/app/_plugins.g.dart` barrel), the substrate MCP server picks up the tapir tools at
`initialize` time and surfaces them alongside its own 10 substrate tools, so the AI client
sees a single unified catalog.

<a name="toc"></a>

- [Substrate MCP server, tapir tool descriptors](#substrate-and-descriptors)
- [The 33 tapir tools](#tool-catalog)
- [Dispatch surfaces: `ext.tapir.*` vs. `dowel:tapir:*`](#dispatch-surfaces)
- [Lifecycle: state file, lazy reconnect, snap-act loop](#lifecycle)
- [Related](#related)

---

<a name="substrate-and-descriptors"></a>

## Substrate MCP server, tapir tool descriptors

The substrate MCP server is surfaced through the tapir wrapper binary. Running `dart run tapir mcp:serve` speaks stdio JSON-RPC, reads `~/.dowel/state.json` to find the
running Flutter app's VM Service URI, and collects every registered provider's
`mcpTools()` list at boot (the wrapper forces `collectMcpTools: true` so all 33 tapir_* tools surface without needing a scaffolded fastcli binary). `TapirDowelProvider.mcpTools()` returns 33 `McpToolDescriptor`
instances; the substrate server registers each as a regular MCP tool and dispatches calls
through the descriptor's declared `extensionMethod`. No additional server process is
launched for tapir; one MCP endpoint, one server, plugin-extensible.

This means every `.mcp.json` snippet that wires the substrate MCP server already gives the
AI client access to the tapir tools. There is no separate `tapir:mcp` binary to
add, no second `cwd` to configure. See [setup.md](setup.md) for the per-client install
matrix. Running `dart run tapir mcp:serve` directly (without scaffolded fastcli) now surfaces the same 40 tools via the wrapper's automatic `collectMcpTools: true` flag.

---

<a name="tool-catalog"></a>

## The 33 tapir tools

`TapirDowelProvider.mcpTools()` returns the following 33 descriptors. The list is sorted
alphabetically; each link jumps to the per-tool entry in [tool-reference.md](tool-reference.md).

| Tool | Purpose |
|---|---|
| [`tapir_blur`](tool-reference.md#tapir_blur) | Clear keyboard focus from whatever currently holds it. |
| [`tapir_clear`](tool-reference.md#tapir_clear) | Empty the `TextEditingController` of a resolved text field. |
| [`tapir_close_app`](tool-reference.md#tapir_close_app) | Request a graceful shutdown via `SystemNavigator.pop()`. |
| [`tapir_console`](tool-reference.md#tapir_console) | Read recent log entries from the crumbs store. |
| [`tapir_dblclick`](tool-reference.md#tapir_dblclick) | Double-click a widget by ref. |
| [`tapir_device_profile`](tool-reference.md#tapir_device_profile) | Emulate a named device profile via CDP. |
| [`tapir_dismiss_modals`](tool-reference.md#tapir_dismiss_modals) | Pop every modal route above the first persistent route. |
| [`tapir_drag`](tool-reference.md#tapir_drag) | Drag from one widget to another by ref. |
| [`tapir_evaluate`](tool-reference.md#tapir_evaluate) | Evaluate a Dart expression in the running isolate. |
| [`tapir_exceptions`](tool-reference.md#tapir_exceptions) | Read recent exceptions from the crumbs store. |
| [`tapir_fill`](tool-reference.md#tapir_fill) | Focus + clear + type + settle a text field in one call (stale-retry). |
| [`tapir_find`](tool-reference.md#tapir_find) | Mint a re-resolvable `q<N>` handle by text / label / key. |
| [`tapir_focus`](tool-reference.md#tapir_focus) | Request keyboard focus on a widget by ref. |
| [`tapir_get_routes`](tool-reference.md#tapir_get_routes) | Report the mounted Router's location, the top page name and a title hint. |
| [`tapir_hot_reload_and_snap`](tool-reference.md#tapir_hot_reload_and_snap) | Hot reload, snap, screenshot, exceptions in one round-trip. |
| [`tapir_hover`](tool-reference.md#tapir_hover) | Hover a mouse cursor over a widget by ref. |
| [`tapir_navigate`](tool-reference.md#tapir_navigate) | Navigate to a route path. |
| [`tapir_navigate_back`](tool-reference.md#tapir_navigate_back) | Pop the top route off the navigator stack. |
| [`tapir_observe`](tool-reference.md#tapir_observe) | Structured candidate list of interactive widgets (Stagehand pattern). |
| [`tapir_press_key`](tool-reference.md#tapir_press_key) | Press a hardware key with optional modifiers. |
| [`tapir_reset_overlays`](tool-reference.md#tapir_reset_overlays) | Reset overlays: dismiss modals + Escape + Cancel-tap fallback (idempotent). |
| [`tapir_resize_viewport`](tool-reference.md#tapir_resize_viewport) | Resize the web viewport via CDP. |
| [`tapir_right_click`](tool-reference.md#tapir_right_click) | Fire a right (secondary mouse) click. |
| [`tapir_screenshot`](tool-reference.md#tapir_screenshot) | Capture a screenshot of the running app. |
| [`tapir_scroll`](tool-reference.md#tapir_scroll) | Scroll a Scrollable widget by ref. |
| [`tapir_select_option`](tool-reference.md#tapir_select_option) | Select an option in a DropdownButton. |
| [`tapir_set_checkbox`](tool-reference.md#tapir_set_checkbox) | Read + conditionally toggle a Checkbox / Switch. |
| [`tapir_snap`](tool-reference.md#tapir_snap) | Capture a YAML Semantics snapshot with `e<N>` refs. |
| [`tapir_tap`](tool-reference.md#tapir_tap) | Tap a widget by ref. |
| [`tapir_triple_click`](tool-reference.md#tapir_triple_click) | Fire three primary clicks (~100ms apart). |
| [`tapir_type`](tool-reference.md#tapir_type) | Type text into a TextField by ref. |
| [`tapir_wait_for`](tool-reference.md#tapir_wait_for) | Wait until a UI condition is satisfied. |
| [`tapir_wait_for_network_idle`](tool-reference.md#tapir_wait_for_network_idle) | Wait for zero in-flight HTTP requests. |

Tool names are frozen: the `tapir_<verb>` shape is part of the alpha-2 cross-repo contract.
Renames break agent prompts and pinned consumer scripts.

---

<a name="dispatch-surfaces"></a>

## Dispatch surfaces: `ext.tapir.*` vs. `dowel:tapir:*`

The substrate MCP server inspects each descriptor's `extensionMethod` field to choose a
dispatch path. Tapir uses two:

- **`ext.tapir.*` (33 tools).** The default path. The MCP server calls
  `VmServiceClient.callServiceExtension(method, args)` against the running Flutter app's VM
  Service. The handler runs inside the app isolate and returns a `ServiceExtensionResponse`.
  This is the standard pattern; every action / inspection tool uses it.
- **`dowel:tapir:*` (7 tools).** Dispatched in-process by the MCP server via the dowel
  registry, executing the matching CLI command (`tapir:hot_reload_and_snap`,
  `tapir:resize`, `tapir:device`, `tapir:perf_run`, `tapir:perf_compare`, `tapir:perf_trace`,
  `tapir:run`). The first three cannot run inside the app isolate:
  `tapir_hot_reload_and_snap` triggers `vm.reloadSources` against the very isolate that would
  be servicing the call (deadlock), and `tapir_resize_viewport` /
  `tapir_device_profile` drive Chrome DevTools Protocol on the host's Chromium subprocess.
  The substrate routes them through the CLI command instead so the orchestration runs
  outside the target isolate.

Both paths return MCP `CallToolResult` content; the agent sees no difference at the JSON-RPC
layer. The split exists purely so the same tool catalog can mix in-isolate VM Service calls
and out-of-isolate CLI drivers without a second binary.

---

<a name="lifecycle"></a>

## Lifecycle: state file, lazy reconnect, snap-act loop

Tapir inherits the substrate's lifecycle. The MCP server stays online even when no Flutter
app is running: `~/.dowel/state.json` may be absent at `initialize` time, and the server
still registers every tool descriptor. The first `tools/call` against a `tapir_*` tool
triggers a lazy reconnect: the MCP server reads `state.json`, opens a WebSocket to the VM
Service URI, and dispatches the call. Subsequent calls reuse the cached connection.

The canonical agent loop:

```
tapir_snap          ->  capture Semantics tree, read refs
tapir_find / read   ->  identify the target widget
tapir_tap / type /  ->  drive an action against the ref
  scroll / drag
tapir_wait_for /    ->  bridge async UI transitions
  wait_for_network_idle
tapir_snap          ->  observe the new state, loop
```

The `e<N>` refs from `tapir_snap` are frozen at snap time; re-snap after any navigation,
modal open/close, or significant rebuild. `q<N>` refs from `tapir_find` re-resolve on every
action call so they survive rebuilds as long as the predicates still match.

---

<a name="related"></a>

## Related

- [setup.md](setup.md): per-client install matrix (Claude Code, Cursor, Windsurf, VS Code,
  etc.) plus the reconnect ritual after editing `.mcp.json` or `.dowel/mcp.json`.
- [tool-reference.md](tool-reference.md): per-tool input schema, return shape, and example
  JSON-RPC payload for every tapir tool.
- [Substrate MCP overview](https://anilcancakir.com/dowel/docs/mcp/overview): the underlying
  dowel MCP server that hosts the tapir tools.
