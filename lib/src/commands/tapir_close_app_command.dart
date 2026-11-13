import 'package:dowel/dowel.dart';

import 'frame_warning_output.dart';
import 'json_output.dart';

/// `dowel tapir:close_app` — gracefully close the running app. Mirrors
/// the `tapir_close_app` MCP tool surface. The handler dispatches
/// `SystemNavigator.pop()` (mobile / desktop) or the equivalent web
/// shutdown, then returns the confirmation envelope BEFORE the OS
/// actually terminates the isolate.
class TapirCloseAppCommand extends DowelCommand {
  @override
  String get name => 'tapir:close_app';

  @override
  String get description =>
      'Gracefully close the running app via SystemNavigator.pop().';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    addJsonFlag(parser);
  }

  @override
  Future<int> handle(DowelContext ctx) async {
    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.tapir.close_app',
      const <String, String>{},
    );
    reportFrameWarning(ctx, response);
    emitEnvelope(
      ctx,
      response,
      () => ctx.output.success('Close signal sent to the running app'),
    );
    return 0;
  }
}
