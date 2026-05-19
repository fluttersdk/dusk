import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:fluttersdk_artisan/artisan.dart';

import '../utils/error_envelope.dart';

/// Signature for the function that performs the actual app-close operation.
///
/// Defaults to [defaultCloseApp]. Tests override [closeAppImpl] with a stub
/// to prevent real system navigation during test runs.
@visibleForTesting
typedef CloseAppFn = Future<void> Function();

/// Active close implementation. Override in tests to stub without closing.
///
/// Defaults to [defaultCloseApp], which calls [SystemNavigator.pop] on mobile
/// and `window.close()` on web. Both are no-ops in the Dart test environment
/// when running under `flutter test` (no real platform channel or window).
@visibleForTesting
CloseAppFn closeAppImpl = defaultCloseApp;

/// Default close implementation: mobile uses [SystemNavigator.pop], web
/// feature-detects [kIsWeb] and calls `window.close()` via the platform
/// channel. Both paths fire asynchronously; the agent receives
/// `{"closed": true}` before the OS actually terminates the app.
@visibleForTesting
Future<void> defaultCloseApp() async {
  if (kIsWeb) {
    // Web path: close the browser tab/window. The JS call returns immediately;
    // browsers may silently ignore it unless the page was opened by script.
    await SystemChannels.platform.invokeMethod<void>('SystemNavigator.pop');
  } else {
    // Mobile / desktop path: pop the system navigator (exits the Flutter app).
    await SystemNavigator.pop();
  }
}

/// Registers the `ext.dusk.close_app` VM Service extension.
///
/// Delegates to [registerExtensionIdempotent] so hot-restart is safe: the VM
/// extension table persists across hot-restart; duplicate registration silently
/// no-ops. Step 13 wires this into the [registerAllDuskExtensions] aggregator.
void registerCloseAppExtension() {
  registerExtensionIdempotent('ext.dusk.close_app', extDuskCloseAppHandler);
}

/// Handler for `ext.dusk.close_app`.
///
/// Accepts no required parameters. Returns `{"closed": true}` immediately
/// before the actual close fires so the agent sees confirmation regardless of
/// platform timing. The close operation itself runs via [closeAppImpl], which
/// defaults to [defaultCloseApp] and can be swapped out in tests.
///
/// Return envelope:
/// ```json
/// { "closed": true }
/// ```
Future<developer.ServiceExtensionResponse> extDuskCloseAppHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    // 1. Schedule the close implementation. We await here so any synchronous
    //    portion completes, but the actual platform channel/JS close fires
    //    asynchronously from the OS perspective.
    await closeAppImpl();

    // 2. Return confirmation immediately. The agent reads this before the OS
    //    terminates the isolate, giving it a chance to record the outcome.
    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, dynamic>{
        'closed': true,
      }),
    );
  } catch (e, stackTrace) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.close_app error: $e\n$stackTrace',
      name: 'dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), DuskErrorEnvelope.unexpected()),
    );
  }
}
