import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:focus --ref=<eN>` — request keyboard focus on a widget.
class DuskFocusCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:focus';

  @override
  String get description =>
      'Request keyboard focus on the widget identified by --ref.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption('ref',
        help: 'Widget ref token (e.g. e5).', mandatory: true);
    parser.addFlag('includeSnapshot',
        help: 'Embed the post-focus snapshot in the response.',
        defaultsTo: false);
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
    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.focus',
      {'ref': ref, 'includeSnapshot': includeSnapshot.toString()},
    );
    if (includeSnapshot) {
      ctx.output.writeln(jsonEncode(response));
    } else {
      ctx.output.success('Focused $ref');
    }
    return 0;
  }
}
