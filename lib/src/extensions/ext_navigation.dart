import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fluttersdk_artisan/artisan.dart';

import '../utils/error_envelope.dart';
import 'ext_modal_router.dart';
import 'ext_snapshot.dart' show duskSnapBuild;

/// Parses the optional `'true' | 'false'` flag [params] field [name],
/// returning [defaultValue] when missing or empty.
bool _parseBoolFlag(
  Map<String, String> params,
  String name, {
  required bool defaultValue,
}) {
  final String? raw = params[name];
  if (raw == null || raw.isEmpty) return defaultValue;
  return raw != 'false' && raw != '0';
}

/// Builds the post-action snapshot YAML and appends it under the
/// `snapshot` key of [payload], unless [params] sets
/// `includeSnapshot: 'false'`.
Future<void> _appendSnapshotIfRequested(
  Map<String, dynamic> payload,
  Map<String, String> params,
) async {
  if (!_parseBoolFlag(params, 'includeSnapshot', defaultValue: true)) {
    return;
  }
  final Map<String, dynamic> snap = await duskSnapBuild();
  payload['snapshot'] = snap['snapshot'];
}

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

/// Walks the active widget tree for the first [Router] and polls its
/// `routeInformationProvider.value.uri` until the path component starts
/// with [requested]; returns the matching URI string on success, `null`
/// when [timeoutMs] elapses without a match. Polling is generous on the
/// FIRST tick so the common case (router applied the URL within one
/// frame) returns immediately.
Future<String?> _observeActivePathUntil({
  required String requested,
  required int pollIntervalMs,
  required int timeoutMs,
}) async {
  final Uri requestedUri = Uri.parse(requested);
  final String requestedPath =
      requestedUri.path.isEmpty ? '/' : requestedUri.path;
  final Stopwatch sw = Stopwatch()..start();
  while (sw.elapsedMilliseconds <= timeoutMs) {
    final String? observed = _readActiveRouterUri();
    if (observed != null) {
      final Uri observedUri = Uri.tryParse(observed) ?? Uri();
      final String observedPath =
          observedUri.path.isEmpty ? '/' : observedUri.path;
      if (observedPath == requestedPath ||
          observedPath.startsWith('$requestedPath/')) {
        return observed;
      }
    }
    await Future<void>.delayed(Duration(milliseconds: pollIntervalMs));
  }
  return null;
}

/// Returns the URI string the first [Router] widget reports as its
/// current location, or `null` when no Router is mounted. Reaches into
/// `Router.routeInformationProvider` via `Router.maybeOf(context)` for
/// every Router under the root element; the first one with a non-null
/// provider wins.
String? _readActiveRouterUri() {
  final Element? root = WidgetsBinding.instance.rootElement;
  if (root == null) return null;
  String? found;
  void visit(Element element) {
    if (found != null) return;
    final Widget widget = element.widget;
    if (widget is Router) {
      final RouteInformationProvider? provider =
          widget.routeInformationProvider;
      final Uri? uri = provider?.value.uri;
      if (uri != null) {
        found = uri.toString();
        return;
      }
    }
    element.visitChildren(visit);
  }

  root.visitChildren(visit);
  return found;
}

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
/// - `includeSnapshot` (optional, default `'true'`): when `'false'`, skip
///   embedding the post-navigation accessibility snapshot in the response.
///
/// On success (default):
/// `{ "navigated": true, "route": "/dashboard", "snapshot": "<yaml>" }`.
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
        wrapErrorDetail(
          'ext.dusk.navigate: missing required param "route"',
          DuskErrorEnvelope.missingParam('route'),
        ),
      );
    }

    // 2. Dismiss open modal overlays so navigation is unobstructed.
    await dismissAllModals();

    // 3. Push the route. Try Navigator 1.0 (pushNamed via onGenerateRoute)
    //    first; on failure (typically Navigator.onGenerateRoute is null
    //    because the app uses a Router-based stack like go_router / auto_route),
    //    fall back to the platform-channel route-information broadcast which
    //    every Router-backed delegate listens to.
    final Element? root = WidgetsBinding.instance.rootElement;
    bool pushed = false;
    if (root != null) {
      final NavigatorState? navigator = _findNavigator(root);
      if (navigator != null) {
        try {
          await navigator.pushNamed(route);
          pushed = true;
        } catch (e) {
          // Navigator.onGenerateRoute null (go_router stack). Fall through to
          // the cross-router platform channel below.
          developer.log(
            '[fluttersdk_dusk] extDuskNavigateHandler: Navigator.pushNamed '
            'failed for "$route" ($e); falling back to '
            'SystemNavigator.routeInformationUpdated.',
            name: 'dusk',
          );
        }
      }
    }
    if (!pushed) {
      // Router-based (go_router, auto_route, Navigator 2.0): broadcast a
      // route-information update. Every Router widget's
      // routeInformationProvider picks this up via the system message bus,
      // which then calls routerDelegate.setNewRoutePath.
      SystemNavigator.routeInformationUpdated(uri: Uri.parse(route));
    }

    // 4. Settle two frame ticks before returning so MCP snapshot calls that
    //    immediately follow see the post-navigation widget tree. Guard on
    //    rootElement: in headless / test contexts with no widget tree the
    //    endOfFrame future never completes without a frame scheduler.
    if (WidgetsBinding.instance.rootElement != null) {
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
    }

    // 4b. Verify post-navigate URL actually matches what we asked. Some
    //    Router setups silently drop unknown routes; we previously always
    //    returned `navigated:true` regardless of outcome. Poll the active
    //    Router's routeInformationProvider for up to 300ms; the active
    //    URI MUST start with the requested route's path (Routes with
    //    query params or redirect targets append, but the prefix is the
    //    minimum honest contract). If the URL never matches, return
    //    `navigated:false` plus the observed URI so the agent can branch.
    final String? activeUri = await _observeActivePathUntil(
      requested: route,
      pollIntervalMs: 50,
      timeoutMs: 300,
    );
    final bool actuallyNavigated = activeUri != null;

    // 5. Embed post-action snapshot (opt-out via includeSnapshot:'false')
    //    + return confirmation so the MCP tool can assert navigation
    //    happened. Snapshot-build failures must not convert a successful
    //    push into an error envelope.
    final Map<String, dynamic> payload = actuallyNavigated
        ? buildNavigateResponse(route)
        : <String, dynamic>{
            'navigated': false,
            'route': route,
            'reason': 'router did not honor the new route; observed URI did not '
                'change. Route may be unregistered or guarded by a redirect.',
          };
    try {
      await _appendSnapshotIfRequested(payload, params);
    } catch (e) {
      developer.log(
        '[fluttersdk_dusk] extDuskNavigateHandler: post-dispatch snapshot '
        'build swallowed for route "$route": $e',
        name: 'dusk',
      );
    }
    return developer.ServiceExtensionResponse.result(jsonEncode(payload));
  } catch (e, stackTrace) {
    developer.log(
      '[fluttersdk_dusk] extDuskNavigateHandler error: $e\n$stackTrace',
      name: 'dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), DuskErrorEnvelope.unexpected()),
    );
  }
}

/// Handler for `ext.dusk.navigate_back`.
///
/// Params:
/// - `includeSnapshot` (optional, default `'true'`): when `'false'`, skip
///   embedding the post-pop accessibility snapshot in the response.
///
/// On success (default):
/// `{ "navigatedBack": true, "snapshot": "<yaml>" }`.
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

    // 4. Embed post-action snapshot (opt-out via includeSnapshot:'false')
    //    + return confirmation.
    final Map<String, dynamic> payload = buildNavigateBackResponse();
    try {
      await _appendSnapshotIfRequested(payload, params);
    } catch (e) {
      developer.log(
        '[fluttersdk_dusk] extDuskNavigateBackHandler: post-dispatch '
        'snapshot build swallowed: $e',
        name: 'dusk',
      );
    }
    return developer.ServiceExtensionResponse.result(jsonEncode(payload));
  } catch (e, stackTrace) {
    developer.log(
      '[fluttersdk_dusk] extDuskNavigateBackHandler error: $e\n$stackTrace',
      name: 'dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), DuskErrorEnvelope.unexpected()),
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
      wrapErrorDetail(e.toString(), DuskErrorEnvelope.unexpected()),
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
