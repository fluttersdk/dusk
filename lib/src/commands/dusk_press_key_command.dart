import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:press_key --key=<name> [--modifiers=<csv>]` — synthesise
/// a hardware-key event on the focused widget. Mirrors the
/// `dusk_press_key` MCP tool surface.
class DuskPressKeyCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:press_key';

  @override
  String get description =>
      'Synthesise a hardware-key event on the currently focused widget.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'key',
      help: 'Logical key name, e.g. Enter / Escape / ArrowDown / Tab.',
      mandatory: true,
    );
    parser.addOption(
      'modifiers',
      help: 'Comma-separated modifier list, e.g. ctrl,shift.',
    );
    parser.addFlag('includeSnapshot',
        help: 'Embed the post-press snapshot in the response.',
        defaultsTo: false);
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final key = ctx.input.option('key') as String?;
    if (key == null || key.isEmpty) {
      ctx.output.error('Missing --key=<name>.');
      return 1;
    }

    final modifiers = ctx.input.option('modifiers') as String?;
    final params = <String, String>{'key': key};
    if (modifiers != null && modifiers.isNotEmpty) {
      params['modifiers'] = modifiers;
    }

    final includeSnapshot =
        (ctx.input.option('includeSnapshot') as bool?) ?? false;
    params['includeSnapshot'] = includeSnapshot.toString();

    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.press_key',
      params,
    );
    if (includeSnapshot) {
      ctx.output.writeln(jsonEncode(response));
    } else {
      ctx.output.success('Pressed $key');
    }
    return 0;
  }
}
