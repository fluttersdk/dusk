import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:reset_overlays`: return the app to a known clean screen by
/// dismissing every modal, pressing Escape, and tapping a Cancel/Dismiss
/// affordance as a fallback. Idempotent: a no-op when nothing is open. Routes
/// through `ext.dusk.reset_overlays`.
class DuskResetOverlaysCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:reset_overlays';

  @override
  String get description =>
      'Reset overlays: dismiss modals + Escape + Cancel-tap fallback '
      '(idempotent).';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.reset_overlays',
    );
    ctx.output.writeln(jsonEncode(response));
    return 0;
  }
}
