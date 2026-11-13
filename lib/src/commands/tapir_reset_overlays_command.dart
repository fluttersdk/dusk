import 'dart:convert';

import 'package:dowel/dowel.dart';

import 'frame_warning_output.dart';

/// `dowel tapir:reset_overlays`: return the app to a known clean screen by
/// dismissing every modal, pressing Escape, and tapping a Cancel/Dismiss
/// affordance as a fallback. Idempotent: a no-op when nothing is open. Routes
/// through `ext.tapir.reset_overlays`.
class TapirResetOverlaysCommand extends DowelCommand {
  @override
  String get name => 'tapir:reset_overlays';

  @override
  String get description =>
      'Reset overlays: dismiss modals + Escape + Cancel-tap fallback '
      '(idempotent).';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  Future<int> handle(DowelContext ctx) async {
    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.tapir.reset_overlays',
    );
    reportFrameWarning(ctx, response);
    ctx.output.writeln(jsonEncode(response));
    return 0;
  }
}
