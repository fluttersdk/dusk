import 'dart:developer' as developer;

import 'package:fluttersdk_artisan/artisan.dart';

import '../dusk_plugin.dart';
import '../utils/dusk_response.dart';

/// Registers `ext.dusk.boot_id`. Idempotent via
/// [registerExtensionIdempotent]; `registerAllDuskExtensions()` calls it LAST,
/// so an answer proves every other `ext.dusk.*` is registered too.
void registerBootExtension() {
  registerExtensionIdempotent('ext.dusk.boot_id', duskBootIdHandler);
}

/// Handler for `ext.dusk.boot_id`: the id [DuskPlugin.install] minted for
/// this run of `main()`.
///
/// `dusk:perf_run` reads it before a hot restart and waits for a different
/// one after, which is how it knows the app came back. The isolate id cannot
/// tell: DWDS keeps isolate `"1"` across a web hot restart. Internal to the
/// runner; no CLI command or MCP tool wraps it.
///
/// Response JSON:
/// ```json
/// {"bootId": "m1x2y3z4-1a2b3c"}
/// ```
Future<developer.ServiceExtensionResponse> duskBootIdHandler(
  String method,
  Map<String, String> params,
) async {
  return duskResult(<String, dynamic>{'bootId': DuskPlugin.bootId});
}
