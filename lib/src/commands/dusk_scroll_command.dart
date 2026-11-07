import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

import 'frame_warning_output.dart';
import 'json_output.dart';
import 'web_visibility.dart';

/// `artisan dusk:scroll --ref=<eN> [--dy=<px>] [--dx=<px>] [--intoView]`
/// — scroll inside a scrollable widget by ref token.
class DuskScrollCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:scroll';

  @override
  String get description =>
      'Scroll inside a scrollable widget by ref token from a prior dusk:snap.';

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
      help: 'Convenience scroll direction; paired with --pixels. '
          'Translates to --dy / --dx under the hood.',
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
    parser.addFlag('includeSnapshot',
        help: 'Embed the post-scroll snapshot in the response.',
        defaultsTo: false);
    parser.addOption(
      'snapshot',
      allowed: <String>['full', 'diff', 'none'],
      help: 'Print the post-scroll snapshot after the summary: the whole '
          'tree, only the lines changed since the last snapshot, or nothing. '
          'Overrides --includeSnapshot.',
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final ref = ctx.input.option('ref') as String?;
    if (ref == null || ref.isEmpty) {
      ctx.output.error(
        'Missing --ref=<eN>. Run dusk:snap first to obtain refs.',
      );
      return 1;
    }

    final params = <String, dynamic>{'ref': ref};

    // Resolve scroll delta: explicit --dy/--dx win; --direction/--pixels
    // is the agent-friendly shorthand that maps onto a signed --dy or --dx
    // depending on the chosen direction. Both forms may coexist; the
    // direction/pixels pair only fires when --dy / --dx are absent.
    String? dy = ctx.input.option('dy') as String?;
    String? dx = ctx.input.option('dx') as String?;
    if (dy == null && dx == null) {
      final dir = ctx.input.option('direction') as String?;
      final px = ctx.input.option('pixels') as String?;
      if (dir != null && px != null) {
        final magnitude = double.tryParse(px) ?? 0;
        switch (dir) {
          case 'down':
            dy = magnitude.toString();
            break;
          case 'up':
            dy = (-magnitude).toString();
            break;
          case 'right':
            dx = magnitude.toString();
            break;
          case 'left':
            dx = (-magnitude).toString();
            break;
        }
      }
    }
    if (dy != null) params['dy'] = dy;
    if (dx != null) params['dx'] = dx;

    final intoView = ctx.input.option('intoView');
    if (intoView != null && intoView != false) {
      params['intoView'] = intoView.toString();
    }
    final snapshotMode = ctx.input.option('snapshot') as String?;
    final includeSnapshot = snapshotMode == null &&
        ((ctx.input.option('includeSnapshot') as bool?) ?? false);
    if (snapshotMode != null) {
      params['snapshot'] = snapshotMode;
    } else {
      params['includeSnapshot'] = includeSnapshot.toString();
    }

    final response = await callExtensionVisible(ctx, 'ext.dusk.scroll', params);
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
