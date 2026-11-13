import 'dart:convert';

import 'package:dowel/dowel.dart';

import 'frame_warning_output.dart';

/// `dowel tapir:get_routes`: print where the running app is as JSON
/// (`uri` from the mounted Router, `location` from the root Navigator's top
/// page, `title`). It does not list declared routes. Mirrors the
/// `tapir_get_routes` MCP tool surface.
class TapirGetRoutesCommand extends DowelCommand {
  @override
  String get name => 'tapir:get_routes';

  @override
  String get description =>
      'Print the app\'s current location (Router uri, top page name, title) '
      'as JSON.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  Future<int> handle(DowelContext ctx) async {
    final result = await ctx.callExtension<Map<String, dynamic>>(
      'ext.tapir.get_routes',
      const <String, String>{},
    );
    reportFrameWarning(ctx, result);
    ctx.output.writeln(const JsonEncoder.withIndent('  ').convert(result));
    return 0;
  }
}
