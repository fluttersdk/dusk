import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:type --ref=<eN> --text=<string>` — type text into a focused widget.
class DuskTypeCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:type';

  @override
  String get description => 'Type text into a focused widget by ref token.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption('ref',
        help: 'Snapshot ref token (e.g. e1).', mandatory: true);
    parser.addOption('text',
        help: 'Text to type into the focused widget.', mandatory: true);
    parser.addFlag('includeSnapshot',
        help: 'Embed the post-type snapshot in the response.',
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
      ctx.output
          .error('Missing --ref=<eN>. Run dusk:snap first to obtain refs.');
      return 1;
    }
    final text = ctx.input.option('text') as String?;
    if (text == null) {
      ctx.output.error('Missing --text=<string>. Provide the text to type.');
      return 1;
    }
    final includeSnapshot =
        (ctx.input.option('includeSnapshot') as bool?) ?? false;
    final checkStable = (ctx.input.option('checkStable') as bool?) ?? true;
    final checkReceivesEvents =
        (ctx.input.option('checkReceivesEvents') as bool?) ?? true;

    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.type',
      {
        'ref': ref,
        'text': text,
        'includeSnapshot': includeSnapshot.toString(),
        'checkStable': checkStable.toString(),
        'checkReceivesEvents': checkReceivesEvents.toString(),
      },
    );
    if (includeSnapshot) {
      ctx.output.writeln(jsonEncode(response));
    } else {
      ctx.output.success('Typed into $ref');
    }
    return 0;
  }
}
