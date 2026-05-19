import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:find [--text=...] [--semanticsLabel=...] [--key=...]` —
/// mint a re-resolvable `q<N>` handle backed by the supplied predicates.
/// Mirrors the `dusk_find` MCP tool surface (Playwright Locator
/// semantics: every action call re-executes the query, so the handle
/// survives rebuilds).
class DuskFindCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:find';

  @override
  String get description =>
      'Mint a re-resolvable q-handle by text / semanticsLabel / key (Playwright Locator pattern).';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'text',
      help: 'Match the widget\'s visible text label.',
    );
    parser.addOption(
      'semanticsLabel',
      help: 'Match the widget\'s accessibility label.',
    );
    parser.addOption(
      'key',
      help: 'Match the widget\'s ValueKey identifier.',
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final params = <String, String>{};
    final text = ctx.input.option('text') as String?;
    final semanticsLabel = ctx.input.option('semanticsLabel') as String?;
    final keyValue = ctx.input.option('key') as String?;
    if (text != null && text.isNotEmpty) params['text'] = text;
    if (semanticsLabel != null && semanticsLabel.isNotEmpty) {
      params['semanticsLabel'] = semanticsLabel;
    }
    if (keyValue != null && keyValue.isNotEmpty) params['key'] = keyValue;

    if (params.isEmpty) {
      ctx.output.error(
        'Provide at least one of --text / --semanticsLabel / --key.',
      );
      return 1;
    }

    final result = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.find',
      params,
    );
    ctx.output.writeln(const JsonEncoder.withIndent('  ').convert(result));
    return 0;
  }
}
