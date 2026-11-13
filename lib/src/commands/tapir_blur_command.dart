import 'dart:convert';

import 'package:dowel/dowel.dart';

import 'frame_warning_output.dart';
import 'json_output.dart';

/// `dowel tapir:blur` — clear keyboard focus from whatever currently holds it.
class TapirBlurCommand extends DowelCommand {
  @override
  String get name => 'tapir:blur';

  @override
  String get description =>
      'Remove keyboard focus from the currently-focused widget.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    addJsonFlag(parser);
    parser.addFlag('includeSnapshot',
        help: 'Embed the post-blur snapshot in the response.',
        defaultsTo: false);
  }

  @override
  Future<int> handle(DowelContext ctx) async {
    final includeSnapshot =
        (ctx.input.option('includeSnapshot') as bool?) ?? false;
    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.tapir.blur',
      {'includeSnapshot': includeSnapshot.toString()},
    );
    reportFrameWarning(ctx, response);
    if (includeSnapshot) {
      ctx.output.writeln(jsonEncode(response));
    } else {
      emitEnvelope(ctx, response, () => ctx.output.success('Blurred'));
    }
    return 0;
  }
}
