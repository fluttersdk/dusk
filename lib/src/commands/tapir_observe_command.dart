import 'dart:convert';

import 'package:dowel/dowel.dart';

import 'frame_warning_output.dart';
import 'web_visibility.dart';

/// `dowel tapir:observe [--intent=<hint>] [--roles=<csv>] [--limit=<n>]
/// [--includeEnrichers=<true|false|full>]` — return a structured candidate
/// list of every interactive widget on screen.
///
/// Wraps the `ext.tapir.observe` VM Service extension. Each candidate is
/// minted as a `q<N>` re-resolvable query handle (Playwright Locator
/// pattern); follow-up tapir_tap / tapir_type / tapir_drag calls re-walk the
/// live Semantics tree on every action, so the ref survives intermediate
/// widget rebuilds.
///
/// No LLM is invoked server-side; the agent reads the candidate list and
/// decides which refs to act on. The CLI surface is mostly for debugging —
/// the MCP descriptor is the primary surface for agent integrations.
class TapirObserveCommand extends DowelCommand {
  @override
  String get name => 'tapir:observe';

  @override
  String get description =>
      'Return a structured candidate list of every interactive widget on '
      'screen (Stagehand observe-once-act-many; no server-side LLM).';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'intent',
      help:
          'Free-form caller hint describing what the agent is looking for '
          '(echoed back; not used server-side).',
    );
    parser.addOption(
      'roles',
      help:
          'Comma-separated role filter (e.g. button,textbox). Omit for '
          'every role.',
    );
    parser.addOption(
      'limit',
      help: 'Maximum number of candidates to return (default 50).',
      defaultsTo: '50',
    );
    parser.addOption(
      'includeEnrichers',
      help:
          'One of true (default: a subset), false (none), full (every '
          'enricher field).',
      defaultsTo: 'true',
    );
  }

  @override
  Future<int> handle(DowelContext ctx) async {
    final String? intent = ctx.input.option('intent') as String?;
    final String? roles = ctx.input.option('roles') as String?;
    final String? limit = ctx.input.option('limit') as String?;
    final String? includeEnrichers =
        ctx.input.option('includeEnrichers') as String?;

    final params = <String, dynamic>{};
    if (intent != null && intent.isNotEmpty) {
      params['intent'] = intent;
    }
    if (roles != null && roles.isNotEmpty) {
      params['roles'] = roles;
    }
    if (limit != null && limit.isNotEmpty) {
      params['limit'] = limit;
    }
    if (includeEnrichers != null && includeEnrichers.isNotEmpty) {
      params['includeEnrichers'] = includeEnrichers;
    }

    final response = await callExtensionVisible(
      ctx,
      'ext.tapir.observe',
      params,
      retry: true,
    );
    reportFrameWarning(ctx, response);
    ctx.output.writeln(jsonEncode(response));
    return 0;
  }
}
