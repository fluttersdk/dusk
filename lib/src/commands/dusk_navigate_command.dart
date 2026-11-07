import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

import 'frame_warning_output.dart';
import 'json_output.dart';
import 'web_visibility.dart';

/// `artisan dusk:navigate --route=<path>` — push a named route onto the
/// active Navigator. Mirrors the `dusk_navigate` MCP tool surface.
class DuskNavigateCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:navigate';

  @override
  String get description =>
      'Navigate the running app to a named route via the active Navigator.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    addJsonFlag(parser);
    parser.addOption(
      'route',
      help: 'Route path to push, e.g. /forms.',
      mandatory: true,
    );
    parser.addFlag('includeSnapshot',
        help: 'Embed the post-navigate snapshot in the response.',
        defaultsTo: false);
    parser.addOption(
      'snapshot',
      allowed: <String>['full', 'diff', 'none'],
      help: 'Print the post-navigate snapshot after the summary: the whole '
          'tree, only the lines changed since the last snapshot, or nothing. '
          'Overrides --includeSnapshot.',
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final route = ctx.input.option('route') as String?;
    if (route == null || route.isEmpty) {
      ctx.output.error('Missing --route=<path>.');
      return 1;
    }
    final snapshotMode = ctx.input.option('snapshot') as String?;
    final includeSnapshot = snapshotMode == null &&
        ((ctx.input.option('includeSnapshot') as bool?) ?? false);
    final response = await callExtensionVisible(
      ctx,
      'ext.dusk.navigate',
      {
        'route': route,
        if (snapshotMode != null)
          'snapshot': snapshotMode
        else
          'includeSnapshot': includeSnapshot.toString(),
      },
    );
    reportFrameWarning(ctx, response);
    if (includeSnapshot || wantsJson(ctx)) {
      ctx.output.writeln(jsonEncode(response));
      return 0;
    }

    // `navigated: false` means the URL verify found no change. A Navigator 1.0
    // app has no Router to read a URI from, so a push that did land reports
    // the same thing: say "unconfirmed" and point at the snapshot.
    if (response['navigated'] == false) {
      final raw = response['reason'] as String? ??
          'the router did not report the new route';
      final reason = raw.endsWith('.') ? raw.substring(0, raw.length - 1) : raw;
      ctx.output.warning(
        'Navigation to $route not confirmed: $reason. A Navigator 1.0 app '
        'without a Router cannot be URL-verified; check with dusk:snap.',
      );
    } else {
      ctx.output.success('Navigated to $route');
    }
    final snapshot = response['snapshot'] as String?;
    if (snapshot != null) ctx.output.writeln(snapshot);
    return 0;
  }
}
