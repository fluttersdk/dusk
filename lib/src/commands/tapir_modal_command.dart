import 'package:dowel/dowel.dart';

import 'frame_warning_output.dart';

/// `dowel tapir:modal` — dismiss all open modals, bottom sheets, and dialogs.
class TapirModalCommand extends DowelCommand {
  @override
  String get name => 'tapir:modal';

  @override
  String get description =>
      'Dismiss all open modals, bottom sheets, and dialogs in the running app.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  Future<int> handle(DowelContext ctx) async {
    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.tapir.dismiss_modals',
    );
    reportFrameWarning(ctx, response);
    ctx.output.success('Modals dismissed');
    return 0;
  }
}
