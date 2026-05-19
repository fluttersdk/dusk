import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:get_routes` — print the active Navigator's current route
/// state as JSON (location + title per registered route). Mirrors the
/// `dusk_get_routes` MCP tool surface.
class DuskGetRoutesCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:get_routes';

  @override
  String get description =>
      'Print the active Navigator\'s route table + current location as JSON.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final result = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.get_routes',
      const <String, String>{},
    );
    ctx.output.writeln(const JsonEncoder.withIndent('  ').convert(result));
    return 0;
  }
}
