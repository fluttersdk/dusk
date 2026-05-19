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
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final route = ctx.input.option('route') as String?;
    if (route == null || route.isEmpty) {
      ctx.output.error('Missing --route=<path>.');
      return 1;
    }

    await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.navigate',
      {'route': route},
    );
    ctx.output.success('Navigated to $route');
    return 0;
  }
}
