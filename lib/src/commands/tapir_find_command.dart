import 'dart:convert';

import 'package:dowel/dowel.dart';

import 'frame_warning_output.dart';

/// `dowel tapir:find [--text=...] [--semanticsLabel=...] [--key=...]` —
/// mint a re-resolvable `q<N>` handle backed by the supplied predicates.
/// Mirrors the `tapir_find` MCP tool surface (Playwright Locator
/// semantics: every action call re-executes the query, so the handle
/// survives rebuilds).
class TapirFindCommand extends DowelCommand {
  @override
  String get name => 'tapir:find';

  @override
  String get description =>
      'Mint a re-resolvable q-handle by text / semanticsLabel / key (Playwright Locator pattern).';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'text',
      help: 'Match the widget\'s visible text label (exact match).',
    );
    parser.addOption(
      'contains',
      help: 'Match the widget\'s visible text by substring (case-sensitive). '
          'Use instead of --text when the visible label is dynamic.',
    );
    parser.addOption(
      'semanticsLabel',
      help: 'Match the widget\'s accessibility label.',
    );
    parser.addOption(
      'key',
      help: 'Match the widget\'s ValueKey identifier.',
    );
    parser.addOption(
      'within',
      help: 'Evaluate the predicates inside one subtree: the e<N> ref of '
          'the region to search. Reach for it when a label repeats across '
          'the shell, which a sidebar and the page it opens usually do.',
    );
  }

  @override
  Future<int> handle(DowelContext ctx) async {
    final params = <String, String>{};
    final text = ctx.input.option('text') as String?;
    final contains = ctx.input.option('contains') as String?;
    final semanticsLabel = ctx.input.option('semanticsLabel') as String?;
    final keyValue = ctx.input.option('key') as String?;
    if (text != null && text.isNotEmpty) params['text'] = text;
    if (contains != null && contains.isNotEmpty) params['contains'] = contains;
    if (semanticsLabel != null && semanticsLabel.isNotEmpty) {
      params['semanticsLabel'] = semanticsLabel;
    }
    if (keyValue != null && keyValue.isNotEmpty) params['key'] = keyValue;

    // Checked for emptiness BEFORE `within` joins the map: a scope is not a
    // predicate, so `--within` alone is still a usage error.
    if (params.isEmpty) {
      ctx.output.error(
        'Provide at least one of --text / --contains / --semanticsLabel / --key.',
      );
      return 1;
    }

    final within = ctx.input.option('within') as String?;
    if (within != null && within.isNotEmpty) params['within'] = within;

    final result = await ctx.callExtension<Map<String, dynamic>>(
      'ext.tapir.find',
      params,
    );
    reportFrameWarning(ctx, result);
    ctx.output.writeln(const JsonEncoder.withIndent('  ').convert(result));
    return 0;
  }
}
