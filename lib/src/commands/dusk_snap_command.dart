import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

import 'frame_warning_output.dart';

/// `artisan dusk:snap` — captures Semantics tree YAML from the running app.
class DuskSnapCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:snap';

  @override
  String get description =>
      'Capture Semantics tree YAML of the running Flutter app with [ref=eN] tokens.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption('depth', help: 'Optional max tree depth.');
    parser.addFlag(
      'includeEnrichers',
      help: 'Emit Magic + Wind enricher fragments under each ref entry. '
          'Default off (Playwright-style minimal snapshot).',
      defaultsTo: false,
    );
    parser.addOption(
      'within',
      help: 'Scope the walk to one subtree: the e<N> ref of the region to '
          'read. Use it when a label repeats across the shell (a sidebar '
          'item and the page it opens usually share one).',
    );
    parser.addFlag(
      'interactiveOnly',
      help: 'Emit only nodes that carry a ref; drop the plain text lines.',
      defaultsTo: false,
    );
    parser.addOption(
      'grep',
      help: 'Emit only nodes whose label or value matches this regular '
          'expression, plus the ancestors that lead to them.',
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final params = <String, dynamic>{};
    final depth = ctx.input.option('depth');
    if (depth != null) params['depth'] = depth;
    final includeEnrichers =
        (ctx.input.option('includeEnrichers') as bool?) ?? false;
    params['includeEnrichers'] = includeEnrichers.toString();
    final within = ctx.input.option('within') as String?;
    if (within != null && within.isNotEmpty) params['within'] = within;
    final interactiveOnly =
        (ctx.input.option('interactiveOnly') as bool?) ?? false;
    if (interactiveOnly) params['interactiveOnly'] = 'true';
    final grep = ctx.input.option('grep') as String?;
    if (grep != null && grep.isNotEmpty) params['grep'] = grep;
    final result = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.snap',
      params,
    );
    reportFrameWarning(ctx, result);
    // Surface captured render/build FlutterErrors so a silently-broken widget
    // (e.g. a ParentDataWidget misuse that makes a button render but ignore
    // taps) is impossible to miss. This is a diagnostic, not snapshot payload,
    // so it goes to stderr via ctx.output.error: stdout stays the pure snapshot
    // for tooling that captures only the snapshot text. Full detail lives in
    // dusk:exceptions (CLI) / dusk_exceptions (MCP).
    final renderErrors = result['renderErrors'] as Map<String, dynamic>?;
    if (renderErrors != null) {
      final count = renderErrors['count'];
      ctx.output.error('⚠ $count render error(s) captured on this screen '
          '(run dusk:exceptions / dusk_exceptions for full detail):');
      final recent = renderErrors['recent'] as List<dynamic>? ?? const [];
      for (final e in recent) {
        final entry = e as Map<String, dynamic>;
        ctx.output.error('  - ${entry['type']}: ${entry['message']}');
      }
    }

    final snapshot = result['snapshot'] as String? ?? jsonEncode(result);
    ctx.output.writeln(snapshot);
    return 0;
  }
}
