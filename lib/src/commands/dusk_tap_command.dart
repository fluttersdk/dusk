import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:tap --ref=<eN>` — synthesize a tap on the element.
class DuskTapCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:tap';

  @override
  String get description => 'Tap a widget by ref token (from prior dusk:snap).';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'ref',
      help: 'Snapshot ref token (e.g. e1).',
      mandatory: true,
    );
    parser.addFlag(
      'includeSnapshot',
      help: 'Embed the post-tap snapshot YAML in the response.',
      defaultsTo: false,
    );
    parser.addFlag(
      'checkStable',
      help: 'Run the Stable (2-frame rect-unchanged) actionability gate.',
      defaultsTo: true,
    );
    parser.addFlag(
      'checkReceivesEvents',
      help: 'Run the Receives-Events (front-most hit-test) actionability gate.',
      defaultsTo: true,
    );
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
    final params = <String, String>{
      'ref': ref,
      'includeSnapshot': includeSnapshot.toString(),
      'checkStable': checkStable.toString(),
      'checkReceivesEvents': checkReceivesEvents.toString(),
    };
    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.tap',
      params,
    );
    if (includeSnapshot) {
      ctx.output.writeln(jsonEncode(response));
    } else {
      ctx.output.success('Tapped $ref');
    }
    return 0;
  }
}
