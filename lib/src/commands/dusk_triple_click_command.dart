import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:triple_click --ref=<eN>` — three primary clicks with 100ms
/// inter-click delay. Playwright parity: locator.click({ clickCount: 3 }).
class DuskTripleClickCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:triple_click';

  @override
  String get description =>
      'Fire three primary clicks (~100ms apart) at the widget identified by --ref.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption('ref',
        help: 'Widget ref token (e.g. e5).', mandatory: true);
    parser.addFlag('includeSnapshot',
        help: 'Embed the post-action snapshot in the response.',
        defaultsTo: false);
    parser.addFlag('checkStable',
        help: 'Run the Stable actionability gate.', defaultsTo: true);
    parser.addFlag('checkReceivesEvents',
        help: 'Run the Receives-Events actionability gate.', defaultsTo: true);
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final ref = ctx.input.option('ref') as String?;
    if (ref == null || ref.isEmpty) {
      ctx.output.error('Missing --ref=<eN>.');
      return 1;
    }
    final includeSnapshot =
        (ctx.input.option('includeSnapshot') as bool?) ?? false;
    final checkStable = (ctx.input.option('checkStable') as bool?) ?? true;
    final checkReceivesEvents =
        (ctx.input.option('checkReceivesEvents') as bool?) ?? true;
    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.triple_click',
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
      ctx.output.success('Triple-clicked $ref');
    }
    return 0;
  }
}
