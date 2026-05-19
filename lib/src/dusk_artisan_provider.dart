import 'package:fluttersdk_artisan/artisan.dart';

import 'commands/dusk_drag_command.dart';
import 'commands/dusk_hover_command.dart';
import 'commands/dusk_install_command.dart';
import 'commands/dusk_modal_command.dart';
import 'commands/dusk_screenshot_command.dart';
import 'commands/dusk_scroll_command.dart';
import 'commands/dusk_snap_command.dart';
import 'commands/dusk_tap_command.dart';
import 'commands/dusk_type_command.dart';
import 'commands/dusk_wait_command.dart';

/// Contributes dusk:* commands and MCP tool descriptors to the artisan
/// dispatcher.
///
/// Host integration:
/// ```dart
/// // lib/config/app.dart
/// final appConfig = {
///   'artisan': {
///     'providers': [DuskArtisanProvider.new],
///   },
/// };
/// ```
///
/// Alpha-2 ships 10 CLI commands (snap / tap / screenshot from alpha-1 +
/// install + type / scroll / wait / hover / drag / modal added in Wave 2).
/// DuskDoctorCommand lands in Step 21 of the alpha-2 plan and is
/// intentionally absent here.
///
/// MCP tools: 17 descriptors. The original 6 from alpha-1 (snap / tap /
/// screenshot / hover / drag / type) are preserved verbatim; the 10 new
/// descriptors (scroll / wait_for / dismiss_modals / navigate /
/// navigate_back / get_routes / press_key / select_option / evaluate /
/// close_app) come from Wave 2's handler steps; dusk_find (Step 16) adds
/// the Playwright-Locator-style query-handle resolver as the 17th.
class DuskArtisanProvider extends ArtisanServiceProvider {
  @override
  String get providerName => 'fluttersdk_dusk';

  @override
  List<ArtisanCommand> commands() => <ArtisanCommand>[
        // Alpha-1.
        DuskSnapCommand(),
        DuskTapCommand(),
        DuskScreenshotCommand(),
        // Alpha-2 Step 11.
        DuskInstallCommand(),
        // Alpha-2 Step 12.
        DuskTypeCommand(),
        DuskScrollCommand(),
        DuskWaitCommand(),
        DuskHoverCommand(),
        DuskDragCommand(),
        DuskModalCommand(),
      ];

  @override
  List<McpToolDescriptor> mcpTools() => const <McpToolDescriptor>[
        // ---------------------------------------------------------------------
        // 1. Snapshot: captures the Semantics tree, no required params.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_snap',
          description: 'Capture a YAML snapshot of the running Flutter app\'s '
              'Semantics tree with stable `[ref=eN]` tokens.\n'
              '\n'
              'Walks the app\'s Semantics tree from the root, emits one '
              'YAML node per widget with role / label / actions / bounds, '
              'and assigns each node a stable `eN` ref. Every action tool '
              '(dusk_tap, dusk_hover, dusk_drag, dusk_type) takes one of '
              'these refs to identify its target. Call this FIRST, then '
              'pass the returned ref tokens to subsequent action calls.\n'
              '\n'
              'Usage:\n'
              '- Call before any dusk_* action tool; refs become stale '
              'after navigation, modal open/close, or significant widget '
              'tree rebuild.\n'
              '- Pass `depth: <n>` to limit tree traversal depth (default '
              'unlimited). Useful when the tree is huge and you only need '
              'the visible region.\n'
              '- Returns YAML; the model parses ref tokens out of the '
              'shape `[ref=e<N>]` next to each widget.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'depth': <String, dynamic>{
                'type': 'integer',
                'description': 'Max tree-traversal depth from the root. '
                    'Omit for full tree. Use a small number (5-10) when '
                    'snapshotting only the focused screen.',
              },
            },
          },
          extensionMethod: 'ext.dusk.snap',
        ),
        // ---------------------------------------------------------------------
        // 2. Tap: pointer Down+50ms+Up at the widget identified by ref.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_tap',
          description: 'Tap a widget by ref token from a prior dusk_snap.\n'
              '\n'
              'Synthesizes a pointer Down + 50ms hold + Up sequence at the '
              'center of the widget identified by `ref`. Triggers '
              '`GestureDetector.onTap`, `InkWell.onTap`, button onPressed, '
              'and any other gesture handler bound to that widget. For '
              'TextField widgets the tap also requests keyboard focus.\n'
              '\n'
              'Usage:\n'
              '- Call dusk_snap first to get a ref token; the ref string '
              'has shape `e<N>`.\n'
              '- Returns the ref of the tapped widget on success; errors '
              'when the ref is unknown or stale (re-snap to refresh).\n'
              '- For drag use dusk_drag; for typing use dusk_type after '
              'dusk_tap to focus the field.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Widget ref token from a prior dusk_snap '
                    'call. Shape: `e<N>` (e.g. `e5`, `e23`).',
              },
            },
            'required': <String>['ref'],
          },
          extensionMethod: 'ext.dusk.tap',
        ),
        // ---------------------------------------------------------------------
        // 3. Screenshot: captures a JPEG/PNG frame, no required params.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_screenshot',
          description: 'Capture a screenshot of the running Flutter app as a '
              'base64-encoded image.\n'
              '\n'
              'Renders the current frame to a JPEG or PNG and returns the '
              'image bytes inline so the model can see the UI directly. '
              'Useful for visual verification, UI debugging, or when '
              'Semantics tree alone is insufficient (custom paint widgets, '
              'rendered text, color regressions).\n'
              '\n'
              'Usage:\n'
              '- No required params; defaults to PNG at high quality.\n'
              '- Pass `format: "jpeg"` for smaller payload (quality '
              'configurable via `quality: <0-100>`).\n'
              '- Captures the WHOLE app surface; for region screenshots '
              'use dusk_snap to locate a widget first.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'format': <String, dynamic>{
                'type': 'string',
                'enum': <String>['jpeg', 'png'],
                'description': 'Image format. `png` (default) is lossless '
                    'but larger; `jpeg` is smaller (good for quick visual '
                    'checks where pixel-perfect detail is not needed).',
              },
              'quality': <String, dynamic>{
                'type': 'integer',
                'description': 'JPEG quality 0-100 (higher is better). '
                    'Default 80. Ignored when format is `png`.',
              },
            },
          },
          extensionMethod: 'ext.dusk.screenshot',
        ),
        // ---------------------------------------------------------------------
        // 4. Hover: PointerHoverEvent (mouse kind) at the widget center.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_hover',
          description: 'Hover a mouse cursor over a widget by ref token (mouse-'
              'only, no touch equivalent).\n'
              '\n'
              'Synthesizes a `PointerHoverEvent` of `PointerDeviceKind.'
              'mouse` at the center of the widget identified by `ref`. '
              'Triggers `MouseRegion.onEnter`, tooltip reveal, hover '
              'state changes. Web + desktop apps only; mobile devices '
              'ignore hover events.\n'
              '\n'
              'Usage:\n'
              '- Use to reveal tooltips, dropdown previews, or hover-'
              'state widgets before dusk_tap.\n'
              '- Call dusk_snap first to get a ref token.\n'
              '- No-op on touch-only devices (Android, iOS).',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Widget ref token from a prior dusk_snap '
                    'call. Shape: `e<N>`.',
              },
            },
            'required': <String>['ref'],
          },
          extensionMethod: 'ext.dusk.hover',
        ),
        // ---------------------------------------------------------------------
        // 5. Drag: Down+5xMove+Up sequence from startRef to endRef.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_drag',
          description: 'Drag from one widget to another by ref tokens.\n'
              '\n'
              'Synthesizes a pointer Down + 5x intermediate Move events + '
              'Up sequence from `startRef`\'s center to `endRef`\'s '
              'center. Use for reorder lists, slider scrubbing, drawer '
              'pulls, swipe-to-dismiss gestures.\n'
              '\n'
              'Usage:\n'
              '- Both refs come from dusk_snap; widget positions are '
              'frozen at snap time.\n'
              '- For pure-direction swipes without a target widget, use '
              'dusk_scroll (when available) or wrap a region in dusk_snap '
              'and use a phantom endRef.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'startRef': <String, dynamic>{
                'type': 'string',
                'description': 'Source widget ref token (`e<N>`). The '
                    'drag begins at this widget\'s center.',
              },
              'endRef': <String, dynamic>{
                'type': 'string',
                'description': 'Target widget ref token (`e<N>`). The '
                    'drag ends at this widget\'s center.',
              },
            },
            'required': <String>['startRef', 'endRef'],
          },
          extensionMethod: 'ext.dusk.drag',
        ),
        // ---------------------------------------------------------------------
        // 6. Type: sets text into a focused text field identified by ref.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_type',
          description: 'Type text into a TextField widget by ref token.\n'
              '\n'
              'Targets the `TextField` / `TextFormField` widget identified '
              'by `ref` and fires `userUpdateTextEditingValue` so '
              '`onChanged` callbacks fire and form validators run. Falls '
              'back to direct controller mutation when the editable cannot '
              'accept input events. Replaces existing text (does not '
              'append).\n'
              '\n'
              'Usage:\n'
              '- Call dusk_tap on the field FIRST to focus it, then '
              'dusk_type to enter text.\n'
              '- To clear a field, pass `text: ""`.\n'
              '- Submits character by character via the keyboard event '
              'pipeline; multi-line text uses `\\n` line breaks.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'TextField widget ref token (`e<N>`).',
              },
              'text': <String, dynamic>{
                'type': 'string',
                'description': 'Text to enter. Replaces existing field '
                    'content. Pass empty string to clear.',
              },
            },
            'required': <String>['ref', 'text'],
          },
          extensionMethod: 'ext.dusk.type',
        ),
        // ---------------------------------------------------------------------
        // 7. Scroll: drives a Scrollable widget identified by ref.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_scroll',
          description: 'Scroll a Scrollable widget by ref token.\n'
              '\n'
              'Drives the nearest `Scrollable` ancestor of the widget '
              'identified by `ref` to bring lazily-built children into '
              'view, page through long lists, or reveal off-screen content '
              'before a follow-up dusk_tap. Pair with dusk_snap before AND '
              'after the scroll: post-scroll refs differ from pre-scroll '
              'refs because new widgets enter the Semantics tree.\n'
              '\n'
              'Usage:\n'
              '- Pass `ref` of any widget inside (or below) the target '
              'Scrollable; the extension walks up to the nearest '
              '`Scrollable` ancestor.\n'
              '- Optional `direction` (default `down`) accepts `up`, '
              '`down`, `left`, `right`.\n'
              '- Optional `pixels` (default 300) tunes the scroll '
              'distance; pass larger values to page faster.\n'
              '- Re-snap after the scroll completes; off-screen widgets '
              'gain refs only once Flutter builds them.\n'
              '\n'
              'Example: `{ "ref": "e12", "direction": "down", "pixels": 500 }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Widget ref token (`e<N>`) inside the '
                    'target Scrollable. The extension walks up to the '
                    'nearest ancestor Scrollable.',
              },
              'direction': <String, dynamic>{
                'type': 'string',
                'enum': <String>['up', 'down', 'left', 'right'],
                'description': 'Scroll direction. Default `down`.',
              },
              'pixels': <String, dynamic>{
                'type': 'number',
                'description': 'Logical pixels to scroll. Default 300. '
                    'Larger values page faster but may overshoot.',
              },
            },
            'required': <String>['ref'],
          },
          extensionMethod: 'ext.dusk.scroll',
        ),
        // ---------------------------------------------------------------------
        // 8. Wait for: polls a condition until satisfied or the timeout
        // expires. One-of condition validated inside the handler.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_wait_for',
          description: 'Wait until a UI condition is satisfied or the timeout '
              'expires.\n'
              '\n'
              'Polls the running app at a fixed interval and returns once '
              'one of three one-of conditions is met: `text` (a Semantics '
              'node with that label exists), `textGone` (no Semantics node '
              'with that label exists), or `expression` (a Dart expression '
              'evaluated via the Tinker bridge returns truthy). Useful for '
              'bridging async UI transitions before a follow-up dusk_tap / '
              'dusk_snap.\n'
              '\n'
              'Usage:\n'
              '- Pass exactly ONE of `text`, `textGone`, `expression`; the '
              'handler errors when zero or multiple are passed.\n'
              '- Optional `timeoutMs` (default 5000) caps the wait; on '
              'timeout the call returns an error result, never silently '
              'continues.\n'
              '- Polling interval is 100 ms; the handler returns as soon '
              'as the condition flips, never blocks the full timeout.\n'
              '\n'
              'Example: `{ "text": "Welcome", "timeoutMs": 3000 }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'text': <String, dynamic>{
                'type': 'string',
                'description': 'Wait until a Semantics node with this '
                    'exact label exists. One-of: pair with neither '
                    '`textGone` nor `expression`.',
              },
              'textGone': <String, dynamic>{
                'type': 'string',
                'description': 'Wait until NO Semantics node with this '
                    'label exists. One-of: pair with neither `text` nor '
                    '`expression`.',
              },
              'expression': <String, dynamic>{
                'type': 'string',
                'description': 'Wait until this Dart expression (evaluated '
                    'via the Tinker bridge) returns a truthy value. '
                    'One-of: pair with neither `text` nor `textGone`.',
              },
              'timeoutMs': <String, dynamic>{
                'type': 'integer',
                'description': 'Wait timeout in milliseconds. Default '
                    '5000. On timeout the call returns an error, never '
                    'continues silently.',
              },
            },
          },
          extensionMethod: 'ext.dusk.wait_for',
        ),
        // ---------------------------------------------------------------------
        // 9. Dismiss modals: pops every dialog / bottom sheet / route on top
        // of the first persistent route.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_dismiss_modals',
          description: 'Pop every modal route (dialog, bottom sheet, popup) '
              'currently above the first persistent route.\n'
              '\n'
              'Walks the active Navigator stack and pops each modal route '
              'in LIFO order until only the first non-modal route remains. '
              'Useful for resetting the UI to a known state between test '
              'flows, dismissing left-over confirm dialogs, or clearing a '
              'stack of bottom sheets without per-modal taps.\n'
              '\n'
              'Usage:\n'
              '- No parameters.\n'
              '- Idempotent: safe to call when no modals are open '
              '(returns immediately with zero pops).\n'
              '- Does NOT pop the root route; the underlying screen '
              'remains.\n'
              '- For dismissing a single specific dialog, prefer dusk_tap '
              'on the dialog\'s explicit Cancel button.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
          },
          extensionMethod: 'ext.dusk.dismiss_modals',
        ),
        // ---------------------------------------------------------------------
        // 10. Navigate: pushes a named route onto the active router.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_navigate',
          description: 'Navigate the running Flutter app to a route path.\n'
              '\n'
              'Pushes the supplied route onto the active router stack. '
              'Resolves through `MagicRoute.to(...)` when the Magic '
              'framework is installed, falling back to '
              '`Navigator.of(root).pushNamed(...)` otherwise. Useful for '
              'driving the app to a specific screen before taking a '
              'snapshot or action, without traversing the UI by hand.\n'
              '\n'
              'Usage:\n'
              '- Pass `route: "/monitors/123"` (must start with `/`).\n'
              '- ALWAYS re-snapshot after navigation; refs from a prior '
              'dusk_snap are invalidated by the route change.\n'
              '- For going back use dusk_navigate_back; to list known '
              'routes use dusk_get_routes.\n'
              '\n'
              'Example: `{ "route": "/login" }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'route': <String, dynamic>{
                'type': 'string',
                'description': 'Route path to push. Must start with `/`. '
                    'Example: `/monitors/123`.',
              },
            },
            'required': <String>['route'],
          },
          extensionMethod: 'ext.dusk.navigate',
        ),
        // ---------------------------------------------------------------------
        // 11. Navigate back: pops the top route off the navigator stack.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_navigate_back',
          description: 'Pop the top route off the active navigator stack.\n'
              '\n'
              'Equivalent to pressing the system Back button: calls '
              '`MagicRoute.back()` when Magic is installed, falling back '
              'to `Navigator.of(root).pop()` otherwise. Useful for '
              'returning from a detail screen to its list without '
              'snapshotting and tapping a Back AppBar button.\n'
              '\n'
              'Usage:\n'
              '- No parameters.\n'
              '- No-op when the stack has only one route; safe to call '
              'speculatively.\n'
              '- Re-snapshot after the pop; refs from the previous screen '
              'are stale.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
          },
          extensionMethod: 'ext.dusk.navigate_back',
        ),
        // ---------------------------------------------------------------------
        // 12. Get routes: enumerates the declared routes in the active
        // router.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_get_routes',
          description: 'List the route paths declared by the running app\'s '
              'router.\n'
              '\n'
              'Walks the active `MagicRouter` (when Magic is installed) '
              'and emits every registered route path with its name and '
              'any path parameters. Useful before a dusk_navigate call '
              'when the available routes are not known upfront, or when '
              'auditing the surface area of the app.\n'
              '\n'
              'Usage:\n'
              '- No parameters.\n'
              '- Returns a list of `{ path, name }` records; static and '
              'parameterised paths are both included (parameters render '
              'as `:id`-style placeholders).\n'
              '- Returns an empty list when no Magic router is installed.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
          },
          extensionMethod: 'ext.dusk.get_routes',
        ),
        // ---------------------------------------------------------------------
        // 13. Press key: synthesises a hardware key event with optional
        // modifiers.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_press_key',
          description: 'Press a hardware key (optionally with modifiers).\n'
              '\n'
              'Synthesises a `KeyDownEvent` + `KeyUpEvent` through '
              '`ServicesBinding.instance.keyboard.handleKeyEvent` so '
              'shortcut intents, `Focus.onKeyEvent` handlers, and '
              '`CallbackShortcuts` widgets fire. Use for keyboard-driven '
              'flows that have no equivalent tap target: Escape to close, '
              'Enter to submit, arrow keys to navigate a list, Ctrl+S to '
              'save.\n'
              '\n'
              'Usage:\n'
              '- Pass `key: "Enter"` (key name from '
              '`LogicalKeyboardKey.keyLabel`). Common values: `Enter`, '
              '`Escape`, `Tab`, `ArrowDown`, `Backspace`.\n'
              '- Optional `modifiers: ["control", "shift"]` chord the '
              'key with modifier keys held during the press.\n'
              '- For text input prefer dusk_type; this tool is for '
              'shortcut keys only.\n'
              '\n'
              'Example: `{ "key": "S", "modifiers": ["control"] }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'key': <String, dynamic>{
                'type': 'string',
                'description': 'Logical key label. Examples: `Enter`, '
                    '`Escape`, `Tab`, `ArrowDown`, `S`, `Backspace`.',
              },
              'modifiers': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{
                  'type': 'string',
                  'enum': <String>['control', 'shift', 'alt', 'meta'],
                },
                'description': 'Modifier keys held during the press. '
                    'Accepts any subset of `control`, `shift`, `alt`, '
                    '`meta`.',
              },
            },
            'required': <String>['key'],
          },
          extensionMethod: 'ext.dusk.press_key',
        ),
        // ---------------------------------------------------------------------
        // 14. Select option: drives a DropdownButton / DropdownButtonFormField
        // to the matching item.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_select_option',
          description: 'Select an option in a DropdownButton by ref + value.\n'
              '\n'
              'Opens the `DropdownButton` / `DropdownButtonFormField` '
              'identified by `ref`, finds the item whose value equals '
              '`value`, and taps it. Bridges the gap between dusk_tap '
              '(which opens the menu) and a second dusk_snap+dusk_tap '
              'pair (which would otherwise be needed to pick the item).\n'
              '\n'
              'Usage:\n'
              '- Pass `ref` of the dropdown widget from a prior '
              'dusk_snap.\n'
              '- Pass `value` matching the option text or the underlying '
              'value (the handler tries label match first, then '
              '`toString()` of the underlying value).\n'
              '- Re-snap after the selection; the dropdown closes and '
              'downstream widgets may re-render.\n'
              '\n'
              'Example: `{ "ref": "e7", "value": "GET" }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Dropdown widget ref token (`e<N>`) from '
                    'a prior dusk_snap.',
              },
              'value': <String, dynamic>{
                'type': 'string',
                'description': 'Option to select. Matches against the '
                    'displayed label first, then `toString()` of the '
                    'underlying value.',
              },
            },
            'required': <String>['ref', 'value'],
          },
          extensionMethod: 'ext.dusk.select_option',
        ),
        // ---------------------------------------------------------------------
        // 15. Evaluate: runs a Dart expression through the Tinker bridge.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_evaluate',
          description:
              'Evaluate a Dart expression in the running app isolate.\n'
              '\n'
              'Forwards `expression` to the Tinker bridge '
              '(`ext.tinker.evaluate`) and returns the stringified result. '
              'Useful for inspecting controller state, asserting an '
              'invariant from the model layer, or reading a private '
              'getter that has no UI surface. Reaches anything visible '
              'to the Magic facade autocomplete (Auth, Http, Cache, '
              'controllers via `Magic.find<T>()`).\n'
              '\n'
              'Usage:\n'
              '- Pass a single Dart expression (no statements, no '
              'semicolons). Example: `Magic.find<MonitorController>().'
              'rxState.value.length`.\n'
              '- Errors when the Tinker plugin is not installed (returns '
              'an MCP error result, never crashes the app).\n'
              '- For UI assertions prefer dusk_snap; this tool is for '
              'state inspection that lives below the Semantics tree.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'expression': <String, dynamic>{
                'type': 'string',
                'description': 'Single Dart expression to evaluate. No '
                    'statements; no trailing semicolon. Example: '
                    '`Auth.user?.email`.',
              },
            },
            'required': <String>['expression'],
          },
          extensionMethod: 'ext.dusk.evaluate',
        ),
        // ---------------------------------------------------------------------
        // 16. Close app: requests a graceful shutdown of the running app.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_close_app',
          description: 'Request a graceful shutdown of the running Flutter '
              'app.\n'
              '\n'
              'Calls `SystemNavigator.pop()` which routes through the '
              'platform back-button channel. On mobile + desktop this '
              'terminates the app; on web the call is a no-op (browsers '
              'do not allow programmatic tab close). Useful at the end '
              'of a long-running E2E session when the next test run '
              'wants a clean process.\n'
              '\n'
              'Usage:\n'
              '- No parameters.\n'
              '- After calling this, the next dusk_* tool will fail '
              'because the VM Service URI is gone; restart the app '
              'before issuing further commands.\n'
              '- No-op on web; pair with manual tab close if you need a '
              'fresh browser session.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
          },
          extensionMethod: 'ext.dusk.close_app',
        ),
        // ---------------------------------------------------------------------
        // 17. Find: Playwright-Locator-style query handle. q-shape refs
        // re-execute the stored predicates on each action call.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_find',
          description:
              'Find a widget by semantic query (text / semanticsLabel / '
              'key) and return a re-resolvable handle.\n'
              '\n'
              'Mints a `q<N>` handle backed by the supplied predicates. '
              'Unlike `e<N>` refs from dusk_snap (which freeze the widget '
              'position at snap time and stale on rebuild), q-handles '
              're-execute the Semantics + Element tree walk on every '
              'subsequent dusk_tap / dusk_hover / dusk_drag / dusk_type '
              'call, so they survive widget rebuilds, route pushes, and '
              'snapshot disposal as long as the predicates still match.\n'
              '\n'
              'Usage:\n'
              '- Pass at least one of `text`, `semanticsLabel`, or `key`. '
              'When multiple are supplied they form an intersection.\n'
              '- Prefer dusk_find when the target survives re-renders '
              '(stable Text, stable accessibility label, stable Key); '
              'prefer dusk_snap+`eN` when you want a positional snapshot '
              'of the whole tree.\n'
              '- Returns `{ref: "q<N>", matched: true}` on first match, '
              'or `{ref: null, matched: false}` when no node matches.\n'
              '- When a follow-up action call finds zero live matches, '
              'the handler returns a "stale handle" error — agent must '
              're-find or re-snap, NOT retry.\n'
              '\n'
              'Example: `{ "text": "Submit" }` or `{ "key": "monitor-row-7" }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'text': <String, dynamic>{
                'type': 'string',
                'description': 'Exact match against an accessibility label '
                    'first, then against `Text.data` as fallback. Example: '
                    '`"Submit"` matches a labelled button or a visible '
                    '`Text("Submit")` widget.',
              },
              'semanticsLabel': <String, dynamic>{
                'type': 'string',
                'description': 'Exact match against `SemanticsNode.label` '
                    'ONLY (no Text fallback). Use when the visible text '
                    'differs from the accessibility label.',
              },
              'key': <String, dynamic>{
                'type': 'string',
                'description': 'Match against a widget Key. For ValueKey, '
                    'pass the inner value\'s `toString()` (e.g. '
                    '`"monitor-row-7"`); for arbitrary Keys, pass the '
                    'full `Key.toString()` value.',
              },
            },
          },
          extensionMethod: 'ext.dusk.find',
        ),
      ];
}
