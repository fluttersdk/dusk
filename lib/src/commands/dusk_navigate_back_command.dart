import 'package:fluttersdk_artisan/artisan.dart';

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
  Future<int> handle(ArtisanContext ctx) async {
    await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.navigate_back',
      const <String, String>{},
    );
    ctx.output.success('Popped current route');
    return 0;
  }
}
