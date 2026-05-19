import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:hover --ref=<eN>` — hover the pointer over a widget by ref token.
class DuskHoverCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:hover';

  @override
  String get description =>
      'Hover the pointer over a widget by ref token (from prior dusk:snap).';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'ref',
      help: 'Snapshot ref token (e.g. e1).',
      mandatory: true,
    );
    parser.addFlag('includeSnapshot',
        help: 'Embed the post-hover snapshot in the response.',
        defaultsTo: false);
    parser.addFlag('checkStable',
        help: 'Run the Stable (2-frame rect-unchanged) actionability gate.',
        defaultsTo: true);
    parser.addFlag('checkReceivesEvents',
        help: 'Run the Receives-Events (front-most hit-test) gate.',
        defaultsTo: true);
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final ref = ctx.input.option('ref') as String?;
    if (ref == null || ref.isEmpty) {
      ctx.output.error(
        'Missing --ref=<eN>. Run dusk:snap first to obtain refs.',
      );
      return 1;
    }
    final includeSnapshot =
        (ctx.input.option('includeSnapshot') as bool?) ?? false;
    final checkStable = (ctx.input.option('checkStable') as bool?) ?? true;
    final checkReceivesEvents =
        (ctx.input.option('checkReceivesEvents') as bool?) ?? true;

    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.hover',
      {
        'ref': ref,
        'includeSnapshot': includeSnapshot.toString(),
        'checkStable': checkStable.toString(),
        'checkReceivesEvents': checkReceivesEvents.toString(),
      },
    );
    if (includeSnapshot) {
      ctx.output.writeln(jsonEncode(response));
    } else {
      ctx.output.success('Hovered $ref');
    }
    return 0;
  }
}
