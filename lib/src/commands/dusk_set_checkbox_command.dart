import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:set_checkbox --ref=<ref> --value=<true|false>` — set the
/// checked state of a Checkbox or Switch widget identified by a snapshot ref.
///
/// Wraps the `ext.dusk.set_checkbox` VM Service extension which reads the
/// widget's current checked state via a Semantics/element walk, then either
/// taps to toggle (when the current value differs from [value]) or returns
/// an idempotent success (when they already match).
class DuskSetCheckboxCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:set_checkbox';

  @override
  String get description =>
      'Set the checked state of a Checkbox or Switch widget by ref.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'ref',
      help: 'Widget ref token from a prior dusk:snap call (e.g. e5).',
    );
    parser.addOption(
      'value',
      help: 'Target checked state: "true" or "false".',
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final String? ref = ctx.input.option('ref') as String?;
    final String? value = ctx.input.option('value') as String?;

    if (ref == null || ref.isEmpty) {
      ctx.output.error('Provide --ref with a widget ref token (e.g. e5).');
      return 1;
    }
    if (value == null || value.isEmpty) {
      ctx.output.error('Provide --value as "true" or "false".');
      return 1;
    }

    final params = <String, dynamic>{
      'ref': ref,
      'value': value,
    };

    await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.set_checkbox',
      params,
    );
    ctx.output.success('Checkbox $ref set to $value');
    return 0;
  }
}
