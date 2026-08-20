import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

import 'frame_warning_output.dart';
import 'json_output.dart';

/// `artisan dusk:navigate_back` — pop the topmost route off the active
/// Navigator. Mirrors the `dusk_navigate_back` MCP tool surface.
class DuskNavigateBackCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:navigate_back';

  @override
  String get description =>
      'Pop the topmost route off the active Navigator (mirrors browser back).';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    addJsonFlag(parser);
    parser.addFlag('includeSnapshot',
        help: 'Embed the post-pop snapshot in the response.',
        defaultsTo: false);
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final includeSnapshot =
        (ctx.input.option('includeSnapshot') as bool?) ?? false;
    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.navigate_back',
      {'includeSnapshot': includeSnapshot.toString()},
    );
    reportFrameWarning(ctx, response);
    if (includeSnapshot) {
      ctx.output.writeln(jsonEncode(response));
    } else {
      emitEnvelope(
          ctx, response, () => ctx.output.success('Popped current route'));
    }
    return 0;
  }
}
