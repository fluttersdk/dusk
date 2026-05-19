import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:close_app` — gracefully close the running app. Mirrors
/// the `dusk_close_app` MCP tool surface. The handler dispatches
/// `SystemNavigator.pop()` (mobile / desktop) or the equivalent web
/// shutdown, then returns the confirmation envelope BEFORE the OS
/// actually terminates the isolate.
class DuskCloseAppCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:close_app';

  @override
  String get description =>
      'Gracefully close the running app via SystemNavigator.pop().';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.close_app',
      const <String, String>{},
    );
    ctx.output.success('Close signal sent to the running app');
    return 0;
  }
}
