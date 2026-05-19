import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:blur` — clear keyboard focus from whatever currently holds it.
class DuskBlurCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:blur';

  @override
  String get description =>
      'Remove keyboard focus from the currently-focused widget.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addFlag('includeSnapshot',
        help: 'Embed the post-blur snapshot in the response.',
        defaultsTo: false);
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final includeSnapshot =
        (ctx.input.option('includeSnapshot') as bool?) ?? false;
    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.blur',
      {'includeSnapshot': includeSnapshot.toString()},
    );
    if (includeSnapshot) {
      ctx.output.writeln(jsonEncode(response));
    } else {
      ctx.output.success('Blurred');
    }
    return 0;
  }
}
