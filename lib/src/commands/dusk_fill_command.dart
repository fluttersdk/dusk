import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:fill --ref=<eN|qN> --text=<value>`: focus, clear, type, and
/// settle a text field in one call (replaces the manual focus + clear + type +
/// settle + stale-retry dance). Routes through `ext.dusk.fill`, which composes
/// the gated focus / clear / type handlers and retries once on a stale handle.
class DuskFillCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:fill';

  @override
  String get description =>
      'Focus, clear, and type into a text field by ref (one-call fill).';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'ref',
      help: 'Text-field ref token (e.g. e5 or q3) from a prior dusk:snap.',
      mandatory: true,
    );
    parser.addOption(
      'text',
      help: 'Value to set. Pass an empty string to clear the field.',
      mandatory: true,
    );
    parser.addFlag(
      'includeSnapshot',
      help: 'Embed the post-fill snapshot YAML in the response.',
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
        'Missing --ref=<eN|qN>. Run dusk:snap first to obtain refs.',
      );
      return 1;
    }
    final text = ctx.input.option('text') as String?;
    if (text == null) {
      ctx.output.error('Missing --text=<value>.');
      return 1;
    }
    final includeSnapshot =
        (ctx.input.option('includeSnapshot') as bool?) ?? false;
    final checkStable = (ctx.input.option('checkStable') as bool?) ?? true;
    final checkReceivesEvents =
        (ctx.input.option('checkReceivesEvents') as bool?) ?? true;
    final params = <String, String>{
      'ref': ref,
      'text': text,
      'includeSnapshot': includeSnapshot.toString(),
      'checkStable': checkStable.toString(),
      'checkReceivesEvents': checkReceivesEvents.toString(),
    };
    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.fill',
      params,
    );
    if (includeSnapshot) {
      ctx.output.writeln(jsonEncode(response));
    } else {
      ctx.output.success('Filled $ref');
    }
    return 0;
  }
}
