import 'package:fluttersdk_artisan/artisan.dart';

import 'commands/dusk_blur_command.dart';
import 'commands/dusk_clear_command.dart';
import 'commands/dusk_close_app_command.dart';
import 'commands/dusk_console_command.dart';
import 'commands/dusk_dblclick_command.dart';
import 'commands/dusk_device_command.dart';
import 'commands/dusk_focus_command.dart';
import 'commands/dusk_right_click_command.dart';
import 'commands/dusk_triple_click_command.dart';
import 'commands/dusk_doctor_command.dart';
import 'commands/dusk_drag_command.dart';
import 'commands/dusk_exceptions_command.dart';
import 'commands/dusk_find_command.dart';
import 'commands/dusk_get_routes_command.dart';
import 'commands/dusk_hot_reload_and_snap_command.dart';
import 'commands/dusk_hover_command.dart';
import 'commands/dusk_install_command.dart';
import 'commands/dusk_modal_command.dart';
import 'commands/dusk_navigate_back_command.dart';
import 'commands/dusk_navigate_command.dart';
import 'commands/dusk_observe_command.dart';
import 'commands/dusk_press_key_command.dart';
import 'commands/dusk_resize_command.dart';
import 'commands/dusk_screenshot_command.dart';
import 'commands/dusk_scroll_command.dart';
import 'commands/dusk_select_option_command.dart';
import 'commands/dusk_set_checkbox_command.dart';
import 'commands/dusk_snap_command.dart';
import 'commands/dusk_tap_command.dart';
import 'commands/dusk_type_command.dart';
import 'commands/dusk_wait_command.dart';
import 'commands/dusk_wait_for_network_idle_command.dart';

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
/// Alpha-2 ships 11 CLI commands (snap / tap / screenshot from alpha-1 +
/// install + type / scroll / wait / hover / drag / modal added in Wave 2 +
/// doctor added in Wave 4b Step 21).
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
        // Alpha-2 Step 12 (six standard verbs).
        DuskTypeCommand(),
        DuskScrollCommand(),
        DuskWaitCommand(),
        DuskHoverCommand(),
        DuskDragCommand(),
        DuskModalCommand(),
        // Alpha-2 Step 21.
        DuskDoctorCommand(),
        // CLI symmetry pass: every E2E-driver MCP tool has a matching
        // CLI command so the two surfaces expose identical capabilities.
        // Seven verbs land alongside their pre-existing ext.dusk.*
        // handlers + dusk_* MCP descriptors. dusk_evaluate intentionally
        // stays MCP-only: magic_tinker (the dedicated REPL package) owns
        // the actual evaluate-via-VM-Service implementation and ships
        // `tinker --eval` as the CLI surface; duplicating it under
        // `dusk:` would split the evaluate contract across two packages.
        DuskNavigateCommand(),
        DuskNavigateBackCommand(),
        DuskGetRoutesCommand(),
        DuskPressKeyCommand(),
        DuskSelectOptionCommand(),
        DuskCloseAppCommand(),
        DuskFindCommand(),
        // Step 3.4: network-idle waiter wired against
        // TelescopeStore.pendingHttpCount via pendingHttpCountReader.
        DuskWaitForNetworkIdleCommand(),
        // Step 3.5: telescope readers + double-click + checkbox setter.
        DuskConsoleCommand(),
        DuskExceptionsCommand(),
        DuskDblclickCommand(),
        DuskSetCheckboxCommand(),
        // Wave 4 Step 4.1: structured candidate list (Stagehand observe-once-
        // act-many; no server-side LLM).
        DuskObserveCommand(),
        // Wave 4 Step 4.2: fused round-trip (mcp_flutter's
        // `fmt_hot_reload_and_capture` pattern). Reload lives CLI-side
        // because an in-isolate handler cannot reload itself.
        DuskHotReloadAndSnapCommand(),
        // P4 (Playwright parity): explicit focus management + right-click +
        // triple-click + clear-text.
        DuskFocusCommand(),
        DuskBlurCommand(),
        DuskClearCommand(),
        DuskRightClickCommand(),
        DuskTripleClickCommand(),
        // Wave 4 Step 6+7 (CDP): device emulation commands.
        DuskResizeCommand(),
        DuskDeviceCommand(),
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
              'Nodes inside a currently-overflowing render ancestor carry '
              'an additive `overflow: true` sub-line (live '
              '`RenderFlex.toStringShort()` check). This is a current-state '
              'signal only; call dusk_exceptions for the full non-fatal '
              'error history including overflow details.\n'
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
              'This MCP tool always dispatches the in-isolate '
              '`ext.dusk.screenshot` extension.\n'
              '\n'
              'Web limitation: the in-isolate path can hang under '
              'CanvasKit+DWDS (the toImage() future never completes). For '
              'reliable web screenshots, run the CLI command '
              '`dusk:screenshot --output=<path>` instead: when artisan was '
              'started with `--cdp-port`, the CLI falls back to CDP '
              '`Page.captureScreenshot` for a full-viewport capture. That CDP '
              'fallback is CLI-only; it does not apply to this MCP tool.\n'
              '\n'
              'Usage:\n'
              '- No required params; defaults to JPEG at quality 70.\n'
              '- Pass `format: "png"` for a lossless (larger) payload.\n'
              '- Captures the WHOLE app surface; for region screenshots use '
              'dusk_snap to locate a widget first.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'format': <String, dynamic>{
                'type': 'string',
                'enum': <String>['jpeg', 'png'],
                'description': 'Image format. `jpeg` (default) is smaller '
                    '(good for quick visual checks); `png` is lossless but '
                    'larger (use when pixel-perfect detail matters).',
              },
              'quality': <String, dynamic>{
                'type': 'integer',
                'description': 'JPEG quality 0-100 (higher is better). '
                    'Default 70. Ignored when format is `png`.',
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
        // ---------------------------------------------------------------------
        // 18. Wait for network idle (Step 3.4). Polls
        // TelescopeStore.pendingHttpCount via the pendingHttpCountReader
        // function-pointer indirection (set by the host when telescope is
        // installed; defaults to () => 0 otherwise ; missing-telescope
        // graceful path returns matched=true immediately).
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_wait_for_network_idle',
          description: 'Wait until the running app reports zero in-flight HTTP '
              'requests for a contiguous idleMs window.\n'
              '\n'
              'Polls the host\'s in-flight HTTP counter (wired by '
              'fluttersdk_telescope\'s `MagicHttpFacadeAdapter.pendingCount` '
              'when both packages are present) every `pollIntervalMs` ms. '
              'When the counter reaches 0 a continuous-zero countdown of '
              '`idleMs` starts; any spike back to a positive count fully '
              'resets the accumulator (Playwright `waitForLoadState` '
              'network-idle semantics). On success returns '
              '`{matched: true, idleAchievedMs: <int>}`; on timeout returns '
              'a structured error envelope with `type: "timeout"` and the '
              'max in-flight count observed inside the wire `message` field.\n'
              '\n'
              'Usage:\n'
              '- No required params; sensible defaults '
              '(`timeoutMs=5000`, `idleMs=500`, `pollIntervalMs=200`).\n'
              '- Call AFTER dusk_tap / dusk_navigate / dusk_select_option to '
              'bridge async network round-trips before a follow-up dusk_snap. '
              'Replaces the `dusk_wait_for textGone=Loading...` pattern when '
              'the loading affordance is not Semantically labelled.\n'
              '- Missing-telescope graceful: when the host has not wired '
              'telescope the counter is constantly 0 and the call returns '
              'idle immediately, so callers do not need to branch on the '
              'host\'s install state.\n'
              '- `pollIntervalMs` must be >= 100ms (CPU constraint); the '
              'handler asserts this internally.\n'
              '\n'
              'Example: `{ "timeoutMs": 8000, "idleMs": 750 }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'timeoutMs': <String, dynamic>{
                'type': 'integer',
                'description': 'Maximum total wait time in milliseconds. '
                    'Default 5000.',
              },
              'idleMs': <String, dynamic>{
                'type': 'integer',
                'description': 'Contiguous-zero window the loop must observe '
                    'before declaring idle. Default 500.',
              },
              'pollIntervalMs': <String, dynamic>{
                'type': 'integer',
                'description': 'Poll cadence in milliseconds. Minimum 100; '
                    'default 200.',
              },
            },
          },
          extensionMethod: 'ext.dusk.wait_for_network_idle',
        ),
        // ---------------------------------------------------------------------
        // 19. Console: reads recent log entries from the telescope store.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_console',
          description: 'Read recent log entries from the running app\'s '
              'telescope store.\n'
              '\n'
              'Reads structured log entries recorded by the telescope HTTP '
              'adapter and log watcher when `fluttersdk_telescope` is '
              'installed and wired. When telescope is absent the call '
              'returns an empty list immediately (missing-telescope graceful '
              'path), so callers do not need to branch on install state.\n'
              '\n'
              'Usage:\n'
              '- No required params; defaults to the 50 most recent entries '
              'at any severity level.\n'
              '- Pass `limit: <n>` to cap the returned count.\n'
              '- Pass `minLevel: "WARNING"` (or `"ERROR"`) to filter by '
              'minimum severity level.\n'
              '- Each log entry contains `level`, `message`, `time`, and '
              '`logger` fields.\n'
              '- Useful for asserting that a controller logged an expected '
              'message without needing to inspect the UI tree.\n'
              '\n'
              'Example: `{ "limit": 10, "minLevel": "ERROR" }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'limit': <String, dynamic>{
                'type': 'integer',
                'description': 'Maximum number of log entries to return. '
                    'Default 50.',
              },
              'minLevel': <String, dynamic>{
                'type': 'string',
                'description': 'Minimum severity level to include. Examples: '
                    '`INFO`, `WARNING`, `ERROR`. Omit to include all levels.',
              },
            },
          },
          extensionMethod: 'ext.dusk.console',
        ),
        // ---------------------------------------------------------------------
        // 20. Exceptions: reads recent exception entries from telescope.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_exceptions',
          description: 'Read recent exceptions recorded by the running app, '
              'including non-fatal FlutterErrors.\n'
              '\n'
              'Returns the merged union of two sources: the in-package '
              'non-fatal `FlutterError.onError` capture buffer (installed '
              'by `DuskPlugin.install()`) and the telescope exception '
              'watcher (when `fluttersdk_telescope` is present). Entries '
              'are deduped by `(type, message, stackHead)`, sorted '
              'newest-first, and clipped to `limit`. RenderFlex overflow '
              'errors appear with `type: "overflow"`. Missing-telescope '
              'graceful: the in-package buffer alone ensures non-fatal '
              'errors are visible even without telescope.\n'
              '\n'
              'Usage:\n'
              '- No required params; defaults to the 20 most recent exceptions.\n'
              '- Pass `limit: <n>` to cap the returned count.\n'
              '- Each entry contains `type`, `message`, `stackHead` (first '
              '3 lines of the stack trace), `library`, `fatal`, and `time`.\n'
              '- Useful for asserting that an action did not trigger an '
              'unexpected exception, or for diagnosing overflow errors '
              'flagged in a prior dusk_snap `overflow: true` annotation.\n'
              '\n'
              'Example: `{ "limit": 5 }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'limit': <String, dynamic>{
                'type': 'integer',
                'description': 'Maximum number of exception entries to '
                    'return. Default 20.',
              },
            },
          },
          extensionMethod: 'ext.dusk.exceptions',
        ),
        // ---------------------------------------------------------------------
        // 21. Double-click: two tap sequences at ref center (~100ms apart).
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_dblclick',
          description: 'Double-click a widget by ref token from a prior '
              'dusk_snap.\n'
              '\n'
              'Synthesizes two pointer Down+50ms+Up sequences at the center '
              'of the widget identified by `ref`, with ~100ms between the '
              'two taps, matching Playwright\'s double-click model. Triggers '
              '`GestureDetector.onDoubleTap` and any double-tap handlers '
              'registered on that widget. The 4-gate actionability check '
              '(enabled, non-zero rect, in-viewport, stable) runs before the '
              'first tap; the post-action snapshot is captured once after the '
              'second tap completes.\n'
              '\n'
              'Usage:\n'
              '- Call dusk_snap first to get a ref token; the ref string '
              'has shape `e<N>` or `q<N>`.\n'
              '- For single tap use dusk_tap; for drag use dusk_drag.\n'
              '- Returns the ref of the clicked widget on success; errors '
              'when the ref is unknown, stale, or the widget fails the '
              'actionability gate.\n'
              '\n'
              'Example: `{ "ref": "e7" }`',
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
          extensionMethod: 'ext.dusk.dblclick',
        ),
        // ---------------------------------------------------------------------
        // 22. Set checkbox: read + conditionally toggle a Checkbox or Switch.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_set_checkbox',
          description: 'Set the checked state of a Checkbox or Switch widget '
              'by ref.\n'
              '\n'
              'Reads the widget\'s current checked state via an element/Semantics '
              'walk. When the current value already matches `value` the call '
              'returns an idempotent success without tapping (safe to call '
              'speculatively). When the current value differs, injects a tap '
              'at the widget\'s center to toggle it.\n'
              '\n'
              'Usage:\n'
              '- Call dusk_snap first to get a ref token for the target '
              'Checkbox or Switch widget.\n'
              '- Pass `value: "true"` to check or `value: "false"` to uncheck.\n'
              '- Returns `{ref, previousValue, value, toggled: bool}` — use '
              '`toggled` to confirm whether a tap was actually issued.\n'
              '- Re-snap after a toggle to see the updated Semantics tree.\n'
              '\n'
              'Example: `{ "ref": "e4", "value": "true" }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Checkbox or Switch widget ref token (`e<N>`) '
                    'from a prior dusk_snap.',
              },
              'value': <String, dynamic>{
                'type': 'string',
                'enum': <String>['true', 'false'],
                'description': 'Target checked state. `"true"` checks the '
                    'widget; `"false"` unchecks it.',
              },
            },
            'required': <String>['ref', 'value'],
          },
          extensionMethod: 'ext.dusk.set_checkbox',
        ),
        // ---------------------------------------------------------------------
        // 23. Observe: structured candidate list (Stagehand observe-once-
        // act-many; no server-side LLM).
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_observe',
          description:
              'Return a structured candidate list of every interactive widget '
              'on screen.\n'
              '\n'
              'Walks the live Semantics + Element tree once, finds every '
              'interactive node (buttons, text fields, links, checkboxes, '
              'dropdowns — same role detection as dusk_find), and mints a '
              're-resolvable `q<N>` ref for each candidate via the '
              'Playwright-Locator pattern. NO server-side LLM is invoked: '
              'the agent reads the candidate list and decides which refs to '
              'act on. Implements Stagehand\'s observe-once-act-many pattern '
              '(model-agnostic locked decision).\n'
              '\n'
              'Each candidate carries: `ref`, `role`, `label`, `value`, '
              '`bounds` (x/y/w/h), `isEnabled`, `isVisible`, plus a subset '
              'of per-candidate enricher fields when '
              '`includeEnrichers=true` (default: `magicFormField`, '
              '`magicRoute`, `magicGateResult`, `wind.breakpoint`, '
              '`wind.states`).\n'
              '\n'
              'Usage:\n'
              '- No required params; sensible defaults observe every role '
              'with `limit=50` and the default enricher subset.\n'
              '- Pass `intent: "<hint>"` to record what the agent is looking '
              'for (NOT used server-side; accepted purely for caller-side '
              'audit logging).\n'
              '- Pass `roles: "button,textbox"` to filter the candidate '
              'list to a comma-separated subset.\n'
              '- Pass `limit: <n>` to cap the candidate count.\n'
              '- Pass `includeEnrichers: "false"` to skip enricher fields '
              'entirely; pass `includeEnrichers: "full"` for every enricher '
              'field (incl. full `wind` block).\n'
              '- q-refs survive widget rebuilds; reuse a single observe '
              'output across many follow-up dusk_tap / dusk_type / dusk_drag '
              'calls without re-observing.\n'
              '\n'
              'Examples:\n'
              '- `{ "roles": "button", "limit": 20 }`\n'
              '- `{ "intent": "login form", "roles": "textbox,button" }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'intent': <String, dynamic>{
                'type': 'string',
                'description': 'Free-form caller hint describing what the '
                    'agent is looking for (e.g. "login form"). NOT used '
                    'server-side; echoed in audit logs only.',
              },
              'roles': <String, dynamic>{
                'type': 'string',
                'description': 'Comma-separated role filter '
                    '(e.g. `"button,textbox"`). Roles match the same '
                    'vocabulary as dusk_snap: `button`, `textbox`, `link`, '
                    '`checkbox`, `heading`, `image`. Omit for every role.',
              },
              'limit': <String, dynamic>{
                'type': 'integer',
                'description': 'Maximum number of candidates to return. '
                    'Default 50.',
              },
              'includeEnrichers': <String, dynamic>{
                'type': 'string',
                'enum': <String>['true', 'false', 'full'],
                'description': 'Toggle per-candidate enricher fields. '
                    '`"true"` (default) projects the default subset '
                    '(magicFormField, magicRoute, magicGateResult, '
                    'wind.breakpoint+states); `"false"` projects no '
                    'enricher fields; `"full"` projects every field '
                    'including all wind sub-fields.',
              },
            },
          },
          extensionMethod: 'ext.dusk.observe',
        ),
        // ---------------------------------------------------------------------
        // 24. Hot reload and snap (Step 4.2): mcp_flutter's
        // fmt_hot_reload_and_capture pattern. Triggers a VM Service hot reload
        // from outside the running isolate (a same-isolate handler would block
        // on reloadSources against itself), then bundles snapshot + screenshot
        // + recent exceptions into one response.
        //
        // extensionMethod routes through the `artisan:` substrate dispatch
        // prefix instead of `ext.dusk.*`; the MCP server executes the CLI
        // command (`dusk:hot_reload_and_snap`) in-process so the orchestration
        // can drive `vm.reloadSources` against the target isolate.
        // ---------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_hot_reload_and_snap',
          description: 'Hot reload the running Flutter app, then capture a '
              'snapshot, screenshot, and recent exceptions in one '
              'round-trip.\n'
              '\n'
              'Triggers `reloadSources` over the VM Service against the '
              'running app, waits for completion, then calls dusk_snap + '
              'dusk_screenshot + dusk_exceptions and bundles every result '
              'into a single response. Equivalent to mcp_flutter\'s '
              '`fmt_hot_reload_and_capture`; saves three round-trips when '
              'the agent needs to validate that a code change took effect.\n'
              '\n'
              'Usage:\n'
              '- No required params; sensible defaults capture the '
              'screenshot.\n'
              '- Pass `screenshot: "false"` to skip the screenshot step '
              '(useful when the agent only needs the Semantics tree).\n'
              '- On reload success the response carries `reloaded: true`, '
              '`durationMs`, `snapshot`, `screenshot` (or `screenshotError` '
              'when capture failed; the snapshot still lands), and '
              '`recentExceptions`.\n'
              '- On compile error the response carries `reloaded: false`, '
              '`durationMs`, `error` (the compile message), and '
              '`recentExceptions`. snapshot + screenshot are omitted.\n'
              '- Recent exceptions reuse dusk_exceptions wiring; missing '
              'telescope is graceful (empty list).\n'
              '\n'
              'Example: `{ "screenshot": "false" }`',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'screenshot': <String, dynamic>{
                'type': 'boolean',
                'description': 'Capture a screenshot after the reload '
                    '(default true). Pass `false` to skip the screenshot '
                    'step.',
              },
            },
          },
          extensionMethod: 'artisan:dusk:hot_reload_and_snap',
        ),
        // -------------------------------------------------------------------
        // P4 (Playwright parity): focus / blur / clear / right_click /
        // triple_click. Five short descriptors; the behavior mirrors the
        // matching Playwright Locator methods (focus, blur, clear,
        // click({button:right}), click({clickCount:3})).
        // -------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_focus',
          description: 'Request keyboard focus on the widget identified by '
              '`ref`.\n\n'
              'Playwright parity: `locator.focus()`. Walks the resolved '
              'element to find the nearest Focus ancestor and calls '
              'requestFocus(). Returns `{ref, focused: true}`.\n\n'
              'Usage:\n'
              '- `ref` (required): widget ref token from a prior dusk_snap.\n'
              '- `includeSnapshot` (default false): embed post-focus snapshot.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Widget ref token (e.g. "e5").',
              },
              'includeSnapshot': <String, dynamic>{
                'type': 'boolean',
                'description': 'Embed the post-focus snapshot (default false).',
              },
            },
            'required': <String>['ref'],
          },
          extensionMethod: 'ext.dusk.focus',
        ),
        McpToolDescriptor(
          name: 'dusk_blur',
          description: 'Clear keyboard focus from whatever currently holds it.'
              '\n\n'
              'Playwright parity: `locator.blur()` / `document.activeElement'
              '.blur()`. Returns `{blurred: true, hadFocus: bool}`.\n\n'
              'Usage:\n'
              '- No required params; blurs the primary focused node.\n'
              '- `includeSnapshot` (default false): embed post-blur snapshot.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'includeSnapshot': <String, dynamic>{
                'type': 'boolean',
                'description': 'Embed the post-blur snapshot (default false).',
              },
            },
          },
          extensionMethod: 'ext.dusk.blur',
        ),
        McpToolDescriptor(
          name: 'dusk_clear',
          description: 'Empty the TextEditingController backing the resolved '
              'text field.\n\n'
              'Playwright parity: `locator.clear()`. Walks the resolved '
              'element to find an EditableText descendant, extracts its '
              'controller, calls clear(). Returns `{ref, text: ""}`.\n\n'
              'Usage:\n'
              '- `ref` (required): widget ref of a TextField / TextFormField '
              '/ EditableText.\n'
              '- `includeSnapshot` (default false): embed post-clear snapshot.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Widget ref of the text field (e.g. "e5").',
              },
              'includeSnapshot': <String, dynamic>{
                'type': 'boolean',
                'description': 'Embed the post-clear snapshot (default false).',
              },
            },
            'required': <String>['ref'],
          },
          extensionMethod: 'ext.dusk.clear',
        ),
        McpToolDescriptor(
          name: 'dusk_right_click',
          description: 'Fire a right (secondary mouse button) click at the '
              'widget identified by `ref`.\n\n'
              'Playwright parity: `locator.click({ button: "right" })`. '
              'Useful for context menus. Runs the 5-gate actionability check '
              'before injecting the PointerDownEvent + 50ms hold + '
              'PointerUpEvent (mouse kind, kSecondaryButton).\n\n'
              'Usage:\n'
              '- `ref` (required): widget ref token.\n'
              '- `includeSnapshot` (default false): embed post-action snapshot.\n'
              '- `checkStable`/`checkReceivesEvents` (both default true): '
              'gate opt-outs.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Widget ref token (e.g. "e5").',
              },
              'includeSnapshot': <String, dynamic>{
                'type': 'boolean',
                'description':
                    'Embed the post-action snapshot (default false).',
              },
              'checkStable': <String, dynamic>{
                'type': 'boolean',
                'description':
                    'Run the Stable actionability gate (default true).',
              },
              'checkReceivesEvents': <String, dynamic>{
                'type': 'boolean',
                'description': 'Run the Receives-Events actionability gate '
                    '(default true).',
              },
            },
            'required': <String>['ref'],
          },
          extensionMethod: 'ext.dusk.right_click',
        ),
        McpToolDescriptor(
          name: 'dusk_triple_click',
          description: 'Fire three primary clicks (~100ms apart) at the '
              'widget identified by `ref`.\n\n'
              'Playwright parity: `locator.click({ clickCount: 3 })`. In '
              'Material text fields this selects an entire paragraph. Runs '
              'the 5-gate actionability check once before the first tap; '
              'subsequent taps assume the target is still actionable.\n\n'
              'Usage:\n'
              '- `ref` (required): widget ref token.\n'
              '- `includeSnapshot` (default false): embed post-action snapshot.\n'
              '- `checkStable`/`checkReceivesEvents` (both default true): '
              'gate opt-outs.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{
                'type': 'string',
                'description': 'Widget ref token (e.g. "e5").',
              },
              'includeSnapshot': <String, dynamic>{
                'type': 'boolean',
                'description':
                    'Embed the post-action snapshot (default false).',
              },
              'checkStable': <String, dynamic>{
                'type': 'boolean',
                'description':
                    'Run the Stable actionability gate (default true).',
              },
              'checkReceivesEvents': <String, dynamic>{
                'type': 'boolean',
                'description': 'Run the Receives-Events actionability gate '
                    '(default true).',
              },
            },
            'required': <String>['ref'],
          },
          extensionMethod: 'ext.dusk.triple_click',
        ),
        // -------------------------------------------------------------------
        // 25. Resize viewport: set dimensions, DPR, mobile, touch via CDP.
        // -------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_resize_viewport',
          description: 'Resize the running Flutter web app viewport via Chrome '
              'DevTools Protocol.\n'
              '\n'
              'Sets browser viewport dimensions, device pixel ratio, mobile '
              'profile, and touch emulation flags via the Emulation.* CDP '
              'methods. Allows testing responsive layouts and mobile-only UI '
              'without DevTools manual intervention. Requires artisan to have '
              'been started with --cdp-port (which pre-launches Chrome with a '
              'debug port); fail-loudly if cdpPort is not set.\n'
              '\n'
              'Usage:\n'
              '- Requires `width` (integer, CSS pixels; e.g. 375 for iPhone) '
              'and `height` (integer, CSS pixels; e.g. 812).\n'
              '- Optional `deviceScaleFactor` (number; default 1.0) simulates '
              'device DPR. Use 2.0 for Retina, 3.0 for iPhone Pro.\n'
              '- Optional `mobile` (boolean; default false) enables mobile '
              'device profile (affects text sizing, viewport meta, scrolling '
              'UX).\n'
              '- Optional `touch` (boolean; default false) enables touch event '
              'synthesis (PointerDown/Move/Up sequences).\n'
              '- Optional `reset` (boolean; default false) clears ALL viewport '
              'overrides (metrics, touch, user agent) in one call. When true, '
              'all other params are ignored.\n'
              '\n'
              'Examples:\n'
              '- `{"width": 375, "height": 812, "deviceScaleFactor": 3.0, '
              '"mobile": true, "touch": true}` (iPhone-X emulation).\n'
              '- `{"width": 1440, "height": 900, "reset": false}` (desktop '
              'viewport).\n'
              '- `{"reset": true}` (clear overrides, revert to host defaults).',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'width': <String, dynamic>{
                'type': 'integer',
                'description': 'Viewport width in CSS pixels (required). '
                    'Example: 375 for mobile, 1440 for desktop.',
              },
              'height': <String, dynamic>{
                'type': 'integer',
                'description': 'Viewport height in CSS pixels (required). '
                    'Example: 812 for mobile, 900 for desktop.',
              },
              'deviceScaleFactor': <String, dynamic>{
                'type': 'number',
                'description': 'Device pixel ratio (optional; default 1.0). '
                    'Use 2.0 for Retina, 3.0 for iPhone Pro DPR. Must be '
                    'greater than 0.',
              },
              'mobile': <String, dynamic>{
                'type': 'boolean',
                'description': 'Enable mobile device profile (optional; default '
                    'false). Affects viewport meta tag behavior, text autosizing, '
                    'and scrolling UX.',
              },
              'touch': <String, dynamic>{
                'type': 'boolean',
                'description': 'Enable touch event synthesis (optional; default '
                    'false). When true, browser fires touch events instead of '
                    'mouse events.',
              },
              'reset': <String, dynamic>{
                'type': 'boolean',
                'description': 'Clear all viewport overrides (optional; default '
                    'false). When true, metrics + touch + user agent are reset. '
                    'All other params ignored when reset is true.',
              },
            },
            'required': <String>['width', 'height'],
          },
          extensionMethod: 'artisan:dusk:resize',
        ),
        // -------------------------------------------------------------------
        // 26. Device profile: emulate a named device preset via CDP.
        // -------------------------------------------------------------------
        McpToolDescriptor(
          name: 'dusk_device_profile',
          description: 'Emulate a named device profile (viewport + DPR + touch '
              '+ user agent) via Chrome DevTools Protocol.\n'
              '\n'
              'Applies a curated device preset (iphone-x, pixel-5, ipad-pro, '
              'desktop-1440, etc.) in a single call. Each preset bundles the '
              'correct viewport dimensions, device pixel ratio, touch '
              'emulation flag, and user agent string so the app renders as it '
              'would on that actual device. Requires artisan to have been '
              'started with --cdp-port (which pre-launches Chrome with a debug '
              'port).\n'
              '\n'
              'Usage:\n'
              '- Call with `list: true` (no `preset` required) to enumerate '
              'all available device presets with dimensions.\n'
              '- Call with `preset: "<name>"` (string; no list) to apply a '
              'preset. Valid preset names: iphone-x, iphone-13, iphone-15-pro, '
              'pixel-5, pixel-8, ipad-pro-12.9, desktop-1440, desktop-1920.\n'
              '- Call with `reset: true` (optional; no preset required) to '
              'clear all overrides (metrics, touch, user agent). Equivalent to '
              'dusk_resize_viewport with reset=true.\n'
              '- When `preset` is unknown, exits with error and suggests '
              'running with `list: true` to see available options.\n'
              '\n'
              'Examples:\n'
              '- `{"preset": "iphone-x"}` (apply iPhone-X emulation).\n'
              '- `{"list": true}` (show all 8 presets).\n'
              '- `{"reset": true}` (clear overrides).',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'preset': <String, dynamic>{
                'type': 'string',
                'enum': <String>[
                  'iphone-x',
                  'iphone-13',
                  'iphone-15-pro',
                  'pixel-5',
                  'pixel-8',
                  'ipad-pro-12.9',
                  'desktop-1440',
                  'desktop-1920',
                ],
                'description': 'Device preset name (optional). One of: '
                    'iphone-x, iphone-13, iphone-15-pro, pixel-5, pixel-8, '
                    'ipad-pro-12.9, desktop-1440, desktop-1920. Omit when '
                    'using list or reset.',
              },
              'list': <String, dynamic>{
                'type': 'boolean',
                'description': 'List all available device presets (optional; '
                    'default false). When true, preset and reset are ignored.',
              },
              'reset': <String, dynamic>{
                'type': 'boolean',
                'description': 'Clear all viewport overrides (optional; default '
                    'false). When true, metrics + touch + user agent are reset. '
                    'Preset is ignored when reset is true.',
              },
            },
          },
          extensionMethod: 'artisan:dusk:device',
        ),
      ];
}
