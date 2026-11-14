import 'package:dowel/dowel.dart';

import 'frame_warning_output.dart';
import 'json_output.dart';

/// `dowel tapir:select_option --ref=<eN> --value=<string>` — pick an
/// option from a DropdownButton / PopupMenuButton. Mirrors the
/// `tapir_select_option` MCP tool surface.
class TapirSelectOptionCommand extends DowelCommand {
  @override
  String get name => 'tapir:select_option';

  @override
  String get description =>
      'Select an option in a DropdownButton or PopupMenuButton by ref token.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    addJsonFlag(parser);
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
  Future<int> handle(DowelContext ctx) async {
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

    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.tapir.select_option',
      {'ref': ref, 'value': value},
    );
    reportFrameWarning(ctx, response);
    emitEnvelope(
      ctx,
      response,
      () => ctx.output.success('Selected "$value" on $ref'),
    );
    return 0;
  }
}
