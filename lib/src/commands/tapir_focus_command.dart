import 'dart:convert';

import 'package:dowel/dowel.dart';

import 'frame_warning_output.dart';
import 'json_output.dart';

/// `dowel tapir:focus --ref=<eN>` — request keyboard focus on a widget.
class TapirFocusCommand extends DowelCommand {
  @override
  String get name => 'tapir:focus';

  @override
  String get description =>
      'Request keyboard focus on the widget identified by --ref.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    addJsonFlag(parser);
    parser.addOption('ref',
        help: 'Widget ref token (e.g. e5).', mandatory: true);
    parser.addFlag('includeSnapshot',
        help: 'Embed the post-focus snapshot in the response.',
        defaultsTo: false);
  }

  @override
  Future<int> handle(DowelContext ctx) async {
    final ref = ctx.input.option('ref') as String?;
    if (ref == null || ref.isEmpty) {
      ctx.output.error('Missing --ref=<eN>.');
      return 1;
    }
    final includeSnapshot =
        (ctx.input.option('includeSnapshot') as bool?) ?? false;
    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.tapir.focus',
      {'ref': ref, 'includeSnapshot': includeSnapshot.toString()},
    );
    reportFrameWarning(ctx, response);
    if (includeSnapshot) {
      ctx.output.writeln(jsonEncode(response));
    } else {
      emitEnvelope(ctx, response, () => ctx.output.success('Focused $ref'));
    }
    return 0;
  }
}
