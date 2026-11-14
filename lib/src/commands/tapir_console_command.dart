import 'dart:convert';

import 'package:dowel/dowel.dart';

import 'frame_warning_output.dart';

/// `dowel tapir:console [--limit=<n>] [--minLevel=<level>]` — read recent
/// log entries from the running app's crumbs store.
///
/// Wraps the `ext.tapir.console` VM Service extension. The Dart-side reader
/// reads through `CrumbsStore.recentLogs(...)` when
/// `crumbs` is wired (host sets `recentLogsReader`); otherwise
/// an empty list is returned (missing-crumbs graceful path).
class TapirConsoleCommand extends DowelCommand {
  @override
  String get name => 'tapir:console';

  @override
  String get description =>
      'Read recent log entries from the running app\'s crumbs store.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'limit',
      help: 'Maximum number of log entries to return (default 50).',
      defaultsTo: '50',
    );
    parser.addOption(
      'minLevel',
      help: 'Minimum severity level to include (e.g. WARNING, ERROR).',
    );
  }

  @override
  Future<int> handle(DowelContext ctx) async {
    final String? limit = ctx.input.option('limit') as String?;
    final String? minLevel = ctx.input.option('minLevel') as String?;

    final params = <String, dynamic>{};
    if (limit != null && limit.isNotEmpty) {
      params['limit'] = limit;
    }
    if (minLevel != null && minLevel.isNotEmpty) {
      params['minLevel'] = minLevel;
    }

    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.tapir.console',
      params,
    );
    reportFrameWarning(ctx, response);
    ctx.output.writeln(jsonEncode(response));
    return 0;
  }
}
