import 'dart:developer' as developer;

import 'package:dowel/dowel.dart';

import '../tapir_plugin.dart';
import '../utils/tapir_register.dart';
import '../utils/tapir_response.dart';

/// Registers `ext.tapir.boot_id`. Idempotent via
/// [registerExtensionIdempotent]; `registerAllTapirExtensions()` calls it LAST,
/// so an answer proves every other `ext.tapir.*` is registered too.
void registerBootExtension() {
  registerTapirExtension(
    'ext.tapir.boot_id',
    tapirBootIdHandler,
    ensureFrames: false,
  );
}

/// Handler for `ext.tapir.boot_id`: the id [TapirPlugin.install] minted for
/// this run of `main()`.
///
/// `tapir:perf_run` reads it before a hot restart and waits for a different
/// one after, which is how it knows the app came back. The isolate id cannot
/// tell: DWDS keeps isolate `"1"` across a web hot restart. Internal to the
/// runner; no CLI command or MCP tool wraps it.
///
/// Response JSON:
/// ```json
/// {"bootId": "m1x2y3z4-1a2b3c"}
/// ```
Future<developer.ServiceExtensionResponse> tapirBootIdHandler(
  String method,
  Map<String, String> params,
) async {
  return tapirResult(<String, dynamic>{'bootId': TapirPlugin.bootId});
}
