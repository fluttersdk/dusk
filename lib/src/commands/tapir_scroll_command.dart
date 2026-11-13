import 'dart:convert';

import 'package:dowel/dowel.dart';

import 'frame_warning_output.dart';
import 'json_output.dart';
import 'web_visibility.dart';

/// `dowel tapir:scroll --ref=<eN> [--dy=<px>] [--dx=<px>] [--intoView]`
/// — scroll inside a scrollable widget by ref token.
class TapirScrollCommand extends DowelCommand {
  @override
  String get name => 'tapir:scroll';

  @override
  String get description =>
      'Scroll inside a scrollable widget by ref token from a prior tapir:snap.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    addJsonFlag(parser);
    parser.addOption(
      'ref',
      help: 'Snapshot ref token of the scrollable (e.g. e1).',
      mandatory: true,
    );
    parser.addOption(
      'dy',
      help: 'Vertical delta in logical pixels (negative = up).',
    );
    parser.addOption(
      'dx',
      help: 'Horizontal delta in logical pixels (negative = left).',
    );
    parser.addOption(
      'direction',
      allowed: ['up', 'down', 'left', 'right'],
      help:
          'Convenience scroll direction; paired with --pixels (default 300). '
          'Ignored when --dy or --dx is given.',
    );
    parser.addOption(
      'pixels',
      help: 'Magnitude of the --direction scroll in logical pixels.',
    );
    parser.addFlag(
      'intoView',
      help: 'Scroll until the ref widget is visible.',
      defaultsTo: false,
    );
    parser.addFlag(
      'includeSnapshot',
      help: 'Embed the post-scroll snapshot in the response.',
      defaultsTo: false,
    );
    parser.addOption(
      'snapshot',
      allowed: <String>['full', 'diff', 'none'],
      help:
          'Print the post-scroll snapshot after the summary: the whole '
          'tree, only the lines changed since the last snapshot, or nothing. '
          'Overrides --includeSnapshot.',
    );
  }

  @override
  Future<int> handle(DowelContext ctx) async {
    final ref = ctx.input.option('ref') as String?;
    if (ref == null || ref.isEmpty) {
      ctx.output.error(
        'Missing --ref=<eN>. Run tapir:snap first to obtain refs.',
      );
      return 1;
    }

    final params = <String, dynamic>{'ref': ref};

    // The extension resolves the delta: explicit --dy / --dx win, and
    // --direction / --pixels is the shorthand it turns into a signed delta, so
    // the CLI and the MCP tool read the same four keys the same way.
    for (final key in const ['dy', 'dx', 'direction', 'pixels']) {
      final value = ctx.input.option(key) as String?;
      if (value != null) params[key] = value;
    }

    final intoView = ctx.input.option('intoView');
    if (intoView != null && intoView != false) {
      params['intoView'] = intoView.toString();
    }
    final snapshotMode = ctx.input.option('snapshot') as String?;
    final includeSnapshot =
        snapshotMode == null &&
        ((ctx.input.option('includeSnapshot') as bool?) ?? false);
    if (snapshotMode != null) {
      params['snapshot'] = snapshotMode;
    } else {
      params['includeSnapshot'] = includeSnapshot.toString();
    }

    final response = await callExtensionVisible(
      ctx,
      'ext.tapir.scroll',
      params,
    );
    reportFrameWarning(ctx, response);
    if (includeSnapshot || wantsJson(ctx)) {
      ctx.output.writeln(jsonEncode(response));
      return 0;
    }

    final effect = response['effect'] as Map<String, dynamic>?;
    if (effect?['changed'] == false) {
      ctx.output.warning(
        'Scrolled $ref (nothing moved: not scrollable, or already at the '
        'edge)',
      );
    } else {
      ctx.output.success('Scrolled $ref');
    }
    final snapshot = response['snapshot'] as String?;
    if (snapshot != null) ctx.output.writeln(snapshot);
    return 0;
  }
}
