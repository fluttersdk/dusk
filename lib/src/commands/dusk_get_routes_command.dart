import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

import 'frame_warning_output.dart';

/// `artisan dusk:get_routes`: print where the running app is as JSON
/// (`uri` from the mounted Router, `location` from the root Navigator's top
/// page, `title`). It does not list declared routes. Mirrors the
/// `dusk_get_routes` MCP tool surface.
class DuskGetRoutesCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:get_routes';

  @override
  String get description =>
      'Print the app\'s current location (Router uri, top page name, title) '
      'as JSON.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final result = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.get_routes',
      const <String, String>{},
    );
    reportFrameWarning(ctx, result);
    ctx.output.writeln(const JsonEncoder.withIndent('  ').convert(result));
    return 0;
  }
}
