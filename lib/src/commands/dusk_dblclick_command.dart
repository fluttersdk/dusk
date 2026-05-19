import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:dblclick --ref=<ref>` — fire a double-click at the widget
/// identified by a snapshot ref.
///
/// Wraps the `ext.dusk.dblclick` VM Service extension which injects two tap
/// sequences with a ~100ms inter-tap delay, matching Playwright's double-click
/// model. The 4-gate actionability check runs before both taps; the post-action
/// snapshot is captured once after the second tap completes.
class DuskDblclickCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:dblclick';

  @override
  String get description =>
      'Fire a double-click at the widget identified by a snapshot ref.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'ref',
      help: 'Widget ref token from a prior dusk:snap call (e.g. e5).',
    );
    parser.addFlag('includeSnapshot',
        help: 'Embed the post-dblclick snapshot in the response.',
        defaultsTo: false);
    parser.addFlag('checkStable',
        help: 'Run the Stable actionability gate.', defaultsTo: true);
    parser.addFlag('checkReceivesEvents',
        help: 'Run the Receives-Events actionability gate.', defaultsTo: true);
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final String? ref = ctx.input.option('ref') as String?;

    if (ref == null || ref.isEmpty) {
      ctx.output.error('Provide --ref with a widget ref token (e.g. e5).');
      return 1;
    }
    final includeSnapshot =
        (ctx.input.option('includeSnapshot') as bool?) ?? false;
    final checkStable = (ctx.input.option('checkStable') as bool?) ?? true;
    final checkReceivesEvents =
        (ctx.input.option('checkReceivesEvents') as bool?) ?? true;

    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.dblclick',
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
      ctx.output.success('Double-clicked ref $ref');
    }
    return 0;
  }
}
