import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:navigate --route=<path>` — push a named route onto the
/// active Navigator. Mirrors the `dusk_navigate` MCP tool surface.
class DuskNavigateCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:navigate';

  @override
  String get description =>
      'Navigate the running app to a named route via the active Navigator.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'route',
      help: 'Route path to push, e.g. /forms.',
      mandatory: true,
    );
    parser.addFlag('includeSnapshot',
        help: 'Embed the post-navigate snapshot in the response.',
        defaultsTo: false);
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final route = ctx.input.option('route') as String?;
    if (route == null || route.isEmpty) {
      ctx.output.error('Missing --route=<path>.');
      return 1;
    }
    final includeSnapshot =
        (ctx.input.option('includeSnapshot') as bool?) ?? false;
    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.navigate',
      {'route': route, 'includeSnapshot': includeSnapshot.toString()},
    );
    if (includeSnapshot) {
      ctx.output.writeln(jsonEncode(response));
    } else {
      ctx.output.success('Navigated to $route');
    }
    return 0;
  }
}
