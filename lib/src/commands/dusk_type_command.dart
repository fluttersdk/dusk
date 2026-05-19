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
    parser.addOption(
      'ref',
      help: 'Snapshot ref token (e.g. e1).',
      mandatory: true,
    );
    parser.addOption(
      'text',
      help: 'Text to type into the focused widget.',
      mandatory: true,
    );
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

    await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.type',
      {'ref': ref, 'text': text},
    );
    ctx.output.success('Typed into $ref');
    return 0;
  }
}
