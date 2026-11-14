import 'dart:convert';

import 'package:dowel/dowel.dart';

import 'frame_warning_output.dart';

/// `dowel tapir:exceptions [--limit=<n>] [--since=<iso8601>]` -- read recent
/// exception entries from the running app.
///
/// Wraps the `ext.tapir.exceptions` VM Service extension, which reads tapir's
/// own buffer of non-fatal `FlutterError`s (filled by `TapirPlugin.install()`)
/// and merges `CrumbsStore.recentExceptions(...)` when `crumbs` is wired
/// (host sets `recentExceptionsReader`).
///
/// When `--since` is provided, only exceptions whose `time` is strictly after
/// the given ISO8601 timestamp are returned. This allows agents to compute
/// true before/after deltas for an action without a stateful reset.
class TapirExceptionsCommand extends DowelCommand {
  @override
  String get name => 'tapir:exceptions';

  @override
  String get description =>
      'Read recent exception entries from tapir\'s FlutterError capture, '
      'plus crumbs when it is wired.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'limit',
      help: 'Maximum number of exception entries to return (default 20).',
      defaultsTo: '20',
    );
    parser.addOption(
      'since',
      help:
          'ISO8601 timestamp. When set, only exceptions strictly after '
          'this time are returned (e.g. 2024-01-01T10:00:00.000Z).',
    );
    parser.addFlag(
      'clear',
      help:
          'Empty the in-package capture buffer AFTER returning the current '
          'entries, so the next read is a clean per-route delta.',
      defaultsTo: false,
    );
  }

  @override
  Future<int> handle(DowelContext ctx) async {
    final String? limit = ctx.input.option('limit') as String?;
    final String? since = ctx.input.option('since') as String?;

    final params = <String, dynamic>{};
    if (limit != null && limit.isNotEmpty) {
      params['limit'] = limit;
    }
    if (since != null && since.isNotEmpty) {
      params['since'] = since;
    }
    if ((ctx.input.option('clear') as bool?) ?? false) {
      params['clear'] = 'true';
    }

    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.tapir.exceptions',
      params,
    );
    reportFrameWarning(ctx, response);
    ctx.output.writeln(jsonEncode(response));
    return 0;
  }
}
