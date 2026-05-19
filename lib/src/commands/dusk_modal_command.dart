import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:modal` — dismiss all open modals, bottom sheets, and dialogs.
class DuskModalCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:modal';

  @override
  String get description =>
      'Dismiss all open modals, bottom sheets, and dialogs in the running app.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    await ctx.callExtension<Map<String, dynamic>>('ext.dusk.dismiss_modals');
    ctx.output.success('Modals dismissed');
    return 0;
  }
}
