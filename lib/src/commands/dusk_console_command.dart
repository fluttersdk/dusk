import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:console [--limit=<n>] [--minLevel=<level>]` — read recent
/// log entries from the running app's telescope store.
///
/// Wraps the `ext.dusk.console` VM Service extension. The Dart-side reader
/// reads through `TelescopeStore.recentLogs(...)` when
/// `fluttersdk_telescope` is wired (host sets `recentLogsReader`); otherwise
/// an empty list is returned (missing-telescope graceful path).
class DuskConsoleCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:console';

  @override
  String get description =>
      'Read recent log entries from the running app\'s telescope store.';

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
  Future<int> handle(ArtisanContext ctx) async {
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
        'ext.dusk.console', params);
    ctx.output.writeln(jsonEncode(response));
    return 0;
  }
}
