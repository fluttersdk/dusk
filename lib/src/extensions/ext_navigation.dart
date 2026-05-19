import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import 'package:fluttersdk_artisan/artisan.dart';

import 'ext_modal_router.dart';

/// Registers the navigation VM Service extensions for fluttersdk_dusk.
///
/// Three extensions are registered:
///
/// | Extension                 | Description                                      |
/// |---------------------------|--------------------------------------------------|
/// | `ext.dusk.navigate`       | Navigate to a route by pushing onto the stack.   |
/// | `ext.dusk.navigate_back`  | Pop the current route off the navigation stack.  |
/// | `ext.dusk.get_routes`     | Return current router location + page title.     |
///
/// Each registration goes through [registerExtensionIdempotent] so hot-restart
/// duplicate-registration [ArgumentError]s are swallowed safely.
///
/// This function is intentionally self-contained: it wires its own handlers
/// via [registerExtensionIdempotent] and does NOT touch
/// `register_dusk_extensions.dart` — Step 13 owns the aggregator wire-up.
///
/// Framework-agnostic: no hard dependency on `magic`. Router resolution falls
/// back to the [NavigatorState] found via a depth-first walk of the element
/// tree using [WidgetsBinding.instance.rootElement].
void registerNavigationExtensions() {
  registerExtensionIdempotent('ext.dusk.navigate', extDuskNavigateHandler);
  registerExtensionIdempotent(
    'ext.dusk.navigate_back',
    extDuskNavigateBackHandler,
  );
  registerExtensionIdempotent(
    'ext.dusk.get_routes',
    extDuskGetRoutesHandler,
  );
}

// ---------------------------------------------------------------------------
// Response builders (exported @visibleForTesting so unit tests can assert
// on the map shape independently of the handler + WidgetsBinding machinery)
// ---------------------------------------------------------------------------

/// Builds the success payload for `ext.dusk.navigate`.
///
/// Returns a map with:
/// - `navigated`: always `true`
/// - `route`: the requested route path
@visibleForTesting
Map<String, dynamic> buildNavigateResponse(String route) => <String, dynamic>{
      'navigated': true,
      'route': route,
    };

/// Builds the success payload for `ext.dusk.navigate_back`.
///
/// Returns a map with:
/// - `navigatedBack`: always `true`
@visibleForTesting
Map<String, dynamic> buildNavigateBackResponse() =>
    <String, dynamic>{'navigatedBack': true};

/// Builds the success payload for `ext.dusk.get_routes`.
///
/// Returns a map with:
/// - `location`: current Navigator location string (empty when no Navigator
///   is active — this is the framework-agnostic fallback; Step 17 wires in
///   MagicRouter-aware location detection).
/// - `title`: current window title from [WidgetsBinding.instance.title] when
///   available, otherwise empty string.
@visibleForTesting
Map<String, dynamic> buildGetRoutesResponse() => <String, dynamic>{
      'location': _currentLocation(),
      'title': _currentTitle(),
    };

// ---------------------------------------------------------------------------
// VM Service extension handlers
// ---------------------------------------------------------------------------

/// Handler for `ext.dusk.navigate`.
///
/// Params:
/// - `route` (required): path to navigate to (e.g. `/dashboard`).
///
/// On success: `{ "navigated": true, "route": "/dashboard" }`.
/// On missing or empty `route` param: returns an extension error response.
///
/// Steps:
/// 1. Validate the `route` param — missing or blank is a hard caller error.
/// 2. Dismiss any open modal routes so the new page renders cleanly.
/// 3. Push the route via the framework Navigator located by tree-walk.
/// 4. Wait for two endOfFrame ticks so the post-navigation tree settles.
/// 5. Return the confirmation envelope.
Future<developer.ServiceExtensionResponse> extDuskNavigateHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    // 1. Validate the required route param.
    final String? route = params['route'];
    if (route == null || route.isEmpty) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        'ext.dusk.navigate: missing required param "route"',
      );
    }

    // 2. Dismiss open modal overlays so navigation is unobstructed.
    await dismissAllModals();

    // 3. Find the Navigator via tree walk and push the route.
    final Element? root = WidgetsBinding.instance.rootElement;
    if (root != null) {
      final NavigatorState? navigator = _findNavigator(root);
      navigator?.pushNamed(route);
    }

    // 4. Settle two frame ticks before returning so MCP snapshot calls that
    //    immediately follow see the post-navigation widget tree. Guard on
    //    rootElement: in headless / test contexts with no widget tree the
    //    endOfFrame future never completes without a frame scheduler.
    if (WidgetsBinding.instance.rootElement != null) {
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
    }

    // 5. Return confirmation so the MCP tool can assert navigation happened.
    return developer.ServiceExtensionResponse.result(
      jsonEncode(buildNavigateResponse(route)),
    );
  } catch (e, stackTrace) {
    developer.log(
      '[fluttersdk_dusk] extDuskNavigateHandler error: $e\n$stackTrace',
      name: 'dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      e.toString(),
    );
  }
}

/// Handler for `ext.dusk.navigate_back`.
///
/// Params: none.
///
/// On success: `{ "navigatedBack": true }`.
///
/// Steps:
/// 1. Find the [NavigatorState] via a depth-first tree walk.
/// 2. Pop if the Navigator can pop; otherwise silently no-op (bottom of stack).
/// 3. Wait for two endOfFrame ticks so the post-pop tree settles.
/// 4. Return the confirmation envelope.
Future<developer.ServiceExtensionResponse> extDuskNavigateBackHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    // 1. Walk the tree for the active Navigator.
    final Element? root = WidgetsBinding.instance.rootElement;
    if (root != null) {
      final NavigatorState? navigator = _findNavigator(root);
      if (navigator != null && navigator.canPop()) {
        // 2. Pop the top route.
        navigator.pop();
      }
    }

    // 3. Settle frame ticks. Guard on rootElement: in headless / test contexts
    //    with no widget tree the endOfFrame future never completes without a
    //    frame scheduler.
    if (WidgetsBinding.instance.rootElement != null) {
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
    }

    // 4. Return confirmation.
    return developer.ServiceExtensionResponse.result(
      jsonEncode(buildNavigateBackResponse()),
    );
  } catch (e, stackTrace) {
    developer.log(
      '[fluttersdk_dusk] extDuskNavigateBackHandler error: $e\n$stackTrace',
      name: 'dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      e.toString(),
    );
  }
}

/// Handler for `ext.dusk.get_routes`.
///
/// Params: none.
///
/// On success: `{ "location": "/current/path", "title": "Page Title" }`.
///
/// The `location` field is derived from the active Navigator's current route
/// name (framework-agnostic). Step 17 (Wave 3) wires in MagicRouter-aware
/// location detection; for now an empty string is returned when no named
/// route is on the stack.
Future<developer.ServiceExtensionResponse> extDuskGetRoutesHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    return developer.ServiceExtensionResponse.result(
      jsonEncode(buildGetRoutesResponse()),
    );
  } catch (e, stackTrace) {
    developer.log(
      '[fluttersdk_dusk] extDuskGetRoutesHandler error: $e\n$stackTrace',
      name: 'dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      jsonEncode(<String, String>{
        'error': e.toString(),
        'stackTrace': stackTrace.toString(),
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Walks the element tree depth-first from [root] and returns the first
/// [NavigatorState] found.
///
/// [Navigator.maybeOf] requires a context that is already a descendant of the
/// target Navigator, which is not available from the binding root. Walking the
/// tree directly finds the Navigator regardless of nesting depth.
NavigatorState? _findNavigator(Element root) {
  NavigatorState? found;

  void visit(Element element) {
    if (found != null) return;
    if (element is StatefulElement && element.state is NavigatorState) {
      found = element.state as NavigatorState;
      return;
    }
    element.visitChildren(visit);
  }

  visit(root);
  return found;
}

/// Returns the active route name from the Navigator stack, or an empty string
/// when no Navigator is active or the current route is unnamed.
///
/// Framework-agnostic: no `magic` dependency. Step 17 adds MagicRouter-aware
/// location detection on top of this fallback.
String _currentLocation() {
  final Element? root = WidgetsBinding.instance.rootElement;
  if (root == null) return '';

  final NavigatorState? navigator = _findNavigator(root);
  if (navigator == null) return '';

  String location = '';
  navigator.popUntil((Route<dynamic> route) {
    location = route.settings.name ?? '';
    return true; // peek only — stop immediately.
  });
  return location;
}

/// Returns the current window/page title.
///
/// Reads [WidgetsBinding.instance.platformDispatcher.defaultRouteName] as a
/// heuristic when no richer title source is available. Returns empty string on
/// any failure so the response is always a valid string.
String _currentTitle() {
  try {
    // WidgetsBinding.instance.title is not a public API; use the platform
    // dispatcher's defaultRouteName as a lightweight location hint.
    // Step 17 replaces this with MagicRoute.currentTitle integration.
    return WidgetsBinding.instance.platformDispatcher.defaultRouteName == '/'
        ? ''
        : WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  } catch (_) {
    return '';
  }
}
