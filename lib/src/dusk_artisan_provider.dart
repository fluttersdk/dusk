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
          description:
              'Capture Semantics tree YAML of the running Flutter app with'
              ' [ref=eN] tokens for subsequent action tools.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'depth': <String, dynamic>{'type': 'integer'},
            },
          },
          extensionMethod: 'ext.dusk.snap',
        ),
        // 2. Tap: pointer Down+50ms+Up at the widget identified by ref.
        McpToolDescriptor(
          name: 'dusk_tap',
          description: 'Tap a widget by ref token (from prior dusk_snap).'
              ' Triggers GestureDetector.onTap.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{'type': 'string'},
            },
            'required': <String>['ref'],
          },
          extensionMethod: 'ext.dusk.tap',
        ),
        // 3. Screenshot: captures a JPEG/PNG frame, no required params.
        McpToolDescriptor(
          name: 'dusk_screenshot',
          description:
              'Capture a JPEG/PNG screenshot of the running Flutter app.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'format': <String, dynamic>{
                'type': 'string',
                'enum': <String>['jpeg', 'png'],
              },
              'quality': <String, dynamic>{'type': 'integer'},
            },
          },
          extensionMethod: 'ext.dusk.screenshot',
        ),
        // 4. Hover: PointerHoverEvent (mouse kind) at the widget center.
        McpToolDescriptor(
          name: 'dusk_hover',
          description:
              'Hover (mouse-only) over a widget by ref token from prior dusk_snap.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{'type': 'string'},
            },
            'required': <String>['ref'],
          },
          extensionMethod: 'ext.dusk.hover',
        ),
        // 5. Drag: Down+5xMove+Up sequence from startRef to endRef.
        McpToolDescriptor(
          name: 'dusk_drag',
          description: 'Drag from one widget ref to another.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'startRef': <String, dynamic>{'type': 'string'},
              'endRef': <String, dynamic>{'type': 'string'},
            },
            'required': <String>['startRef', 'endRef'],
          },
          extensionMethod: 'ext.dusk.drag',
        ),
        // 6. Type: sets text into a focused text field identified by ref.
        McpToolDescriptor(
          name: 'dusk_type',
          description: 'Type text into a focused text field by ref.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{'type': 'string'},
              'text': <String, dynamic>{'type': 'string'},
            },
            'required': <String>['ref', 'text'],
          },
          extensionMethod: 'ext.dusk.type',
        ),
      ];
}
