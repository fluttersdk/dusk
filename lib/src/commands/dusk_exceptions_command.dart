import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:exceptions [--limit=<n>]` — read recent exception entries
/// from the running app's telescope store.
///
/// Wraps the `ext.dusk.exceptions` VM Service extension. The Dart-side reader
/// reads through `TelescopeStore.recentExceptions(...)` when
/// `fluttersdk_telescope` is wired (host sets `recentExceptionsReader`);
/// otherwise an empty list is returned (missing-telescope graceful path).
class DuskExceptionsCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:exceptions';

  @override
  String get description =>
      'Read recent exception entries from the running app\'s telescope store.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'limit',
      help: 'Maximum number of exception entries to return (default 20).',
      defaultsTo: '20',
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final String? limit = ctx.input.option('limit') as String?;

    final params = <String, dynamic>{};
    if (limit != null && limit.isNotEmpty) {
      params['limit'] = limit;
    }

    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.exceptions',
      params,
    );
    ctx.output.writeln(jsonEncode(response));
    return 0;
  }
}
