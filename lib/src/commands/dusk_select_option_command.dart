import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:select_option --ref=<eN> --value=<string>` — pick an
/// option from a DropdownButton / PopupMenuButton. Mirrors the
/// `dusk_select_option` MCP tool surface.
class DuskSelectOptionCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:select_option';

  @override
  String get description =>
      'Select an option in a DropdownButton or PopupMenuButton by ref token.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'ref',
      help: 'Snapshot ref token of the parent dropdown / popup widget.',
      mandatory: true,
    );
    parser.addOption(
      'value',
      help: 'Option value to select (must match the item\'s value).',
      mandatory: true,
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final ref = ctx.input.option('ref') as String?;
    if (ref == null || ref.isEmpty) {
      ctx.output.error('Missing --ref=<eN>.');
      return 1;
    }
    final value = ctx.input.option('value') as String?;
    if (value == null) {
      ctx.output.error('Missing --value=<string>.');
      return 1;
    }

    await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.select_option',
      {'ref': ref, 'value': value},
    );
    ctx.output.success('Selected "$value" on $ref');
    return 0;
  }
}
