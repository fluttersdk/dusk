import 'dart:convert';

import 'package:dowel/dowel.dart';

import 'frame_warning_output.dart';
import 'json_output.dart';

/// `dowel tapir:navigate_back` — pop the topmost route off the active
/// Navigator. Mirrors the `tapir_navigate_back` MCP tool surface.
class TapirNavigateBackCommand extends DowelCommand {
  @override
  String get name => 'tapir:navigate_back';

  @override
  String get description =>
      'Pop the topmost route off the active Navigator (mirrors browser back).';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    addJsonFlag(parser);
    parser.addFlag(
      'includeSnapshot',
      help: 'Embed the post-pop snapshot in the response.',
      defaultsTo: false,
    );
  }

  @override
  Future<int> handle(DowelContext ctx) async {
    final includeSnapshot =
        (ctx.input.option('includeSnapshot') as bool?) ?? false;
    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.tapir.navigate_back',
      {'includeSnapshot': includeSnapshot.toString()},
    );
    reportFrameWarning(ctx, response);
    if (includeSnapshot || wantsJson(ctx)) {
      ctx.output.writeln(jsonEncode(response));
      return 0;
    }

    if (response['popped'] == false) {
      ctx.output.warning('Nothing to pop: already at the root route');
      return 0;
    }
    ctx.output.success('Popped current route');
    return 0;
  }
}
