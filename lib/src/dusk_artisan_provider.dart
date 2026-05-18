import 'package:fluttersdk_artisan/artisan.dart';

import 'commands/dusk_screenshot_command.dart';
import 'commands/dusk_snap_command.dart';
import 'commands/dusk_tap_command.dart';

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
/// V1 ships 3 CLI commands: dusk:snap, dusk:tap, dusk:screenshot. The
/// remaining CLI commands (type/press_key/hover/drag/scroll/select/wait/
/// navigate/dismiss/routes) follow the same pattern; deferred to V1.x.
///
/// MCP tools: 6 descriptors covering the primary gesture and input surface
/// (snap, tap, screenshot, hover, drag, type). Extensions that are BACKLOG
/// for V1 MCP (press_key, scroll, select_option, dismiss_modals) are excluded
/// per D5 of the artisan-mcp-absorption plan.
class DuskArtisanProvider extends ArtisanServiceProvider {
  @override
  String get providerName => 'fluttersdk_dusk';

  @override
  List<ArtisanCommand> commands() => <ArtisanCommand>[
        DuskSnapCommand(),
        DuskTapCommand(),
        DuskScreenshotCommand(),
      ];

  @override
  List<McpToolDescriptor> mcpTools() => const <McpToolDescriptor>[
        // 1. Snapshot: captures the Semantics tree, no required params.
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
        // 2. Tap: pointer Down+50ms+Up at the widget identified by ref.
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
        // 3. Screenshot: captures a JPEG/PNG frame, no required params.
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
        // 4. Hover: PointerHoverEvent (mouse kind) at the widget center.
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
        // 5. Drag: Down+5xMove+Up sequence from startRef to endRef.
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
        // 6. Type: sets text into a focused text field identified by ref.
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
      ];
}
