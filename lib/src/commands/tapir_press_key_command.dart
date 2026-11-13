import 'dart:convert';

import 'package:dowel/dowel.dart';

import 'frame_warning_output.dart';
import 'json_output.dart';
import 'web_visibility.dart';

/// `dowel tapir:press_key --key=<name|letter|digit> [--modifiers=<csv>]`:
/// press a key on the focused widget. Mirrors the
/// `tapir_press_key` MCP tool surface.
class TapirPressKeyCommand extends DowelCommand {
  @override
  String get name => 'tapir:press_key';

  @override
  String get description =>
      'Synthesise a hardware-key event on the currently focused widget.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    addJsonFlag(parser);
    parser.addOption(
      'key',
      help: 'Logical key name, e.g. Enter / Escape / ArrowDown / Tab, '
          'or one letter or digit, e.g. G / 7.',
      mandatory: true,
    );
    parser.addOption(
      'modifiers',
      help: 'Comma-separated modifiers held during the press: control '
          '(or ctrl), shift, alt, meta, e.g. control,shift.',
    );
    parser.addFlag('includeSnapshot',
        help: 'Embed the post-press snapshot in the response.',
        defaultsTo: false);
  }

  @override
  Future<int> handle(DowelContext ctx) async {
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

    final response = await callExtensionVisible(
      ctx,
      'ext.tapir.press_key',
      params,
    );
    reportFrameWarning(ctx, response);
    if (includeSnapshot) {
      ctx.output.writeln(jsonEncode(response));
    } else {
      emitEnvelope(ctx, response, () => ctx.output.success('Pressed $key'));
    }
    return 0;
  }
}
