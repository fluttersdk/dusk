import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:clear --ref=<eN>` — empty the TextEditingController under
/// the resolved ref. Playwright parity: locator.clear().
class DuskClearCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:clear';

  @override
  String get description =>
      'Empty the text content of the focused widget by ref.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption('ref',
        help: 'Widget ref token of the text field (e.g. e5).', mandatory: true);
    parser.addFlag('includeSnapshot',
        help: 'Embed the post-clear snapshot in the response.',
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
      'ext.dusk.clear',
      {'ref': ref, 'includeSnapshot': includeSnapshot.toString()},
    );
    if (includeSnapshot) {
      ctx.output.writeln(jsonEncode(response));
    } else {
      ctx.output.success('Cleared $ref');
    }
    return 0;
  }
}
