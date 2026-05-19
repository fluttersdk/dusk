import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import 'package:fluttersdk_artisan/artisan.dart';

import '../utils/error_envelope.dart';

// ---------------------------------------------------------------------------
// Self-registration entry point
// ---------------------------------------------------------------------------

/// Registers the `ext.dusk.dismiss_modals` VM Service extension.
///
/// This extension pops any modal routes (bottom sheets, dialogs, popups) that
/// are sitting above the current page route without disturbing the underlying
/// navigation stack.
///
/// Idempotent: [registerExtensionIdempotent] swallows the [ArgumentError]
/// thrown on hot-restart duplicate registration.
///
/// Call this once from [registerAllAiTestExtensions] in `extensions.dart`.
void registerModalRouterExtension() {
  registerExtensionIdempotent(
    'ext.dusk.dismiss_modals',
    aiTestDismissModalsHandler,
  );
}

// ---------------------------------------------------------------------------
// Modal-dismissal helper (exported for reuse in ext_navigation.dart)
// ---------------------------------------------------------------------------

/// Returns `true` when [route] is a modal overlay that should be dismissed.
///
/// Matches any [PopupRoute] subclass — this covers [ModalBottomSheetRoute],
/// [RawDialogRoute] (and therefore [DialogRoute] / [AlertDialog]), and
/// [PopupMenuRouteLayout]. [PopupRoute] is Flutter's canonical base class for
/// overlays that sit above page routes without forming part of the navigation
/// stack.
///
/// Does NOT match [MaterialPageRoute], [CupertinoPageRoute], or GoRouter page
/// routes — those are real navigation entries that must never be auto-popped.
bool isModalRoute(Route<dynamic> route) => route is PopupRoute;

/// Walks the element tree rooted at [root] depth-first and returns the first
/// [NavigatorState] found.
///
/// [Navigator.maybeOf] requires an element that is already a descendant of the
/// [Navigator] in question. [WidgetsBinding.instance.rootElement] sits above
/// all navigators, so `maybeOf` always returns null from there. Walking the
/// tree directly finds the [Navigator] widget regardless of nesting depth.
NavigatorState? _findNavigatorInTree(Element root) {
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

/// Dismisses all modal routes above the current page route and returns the
/// count of routes popped.
///
/// Steps:
/// 1. Walk the element tree from [WidgetsBinding.instance.rootElement] to find
///    the active [NavigatorState]. The walk is necessary because
///    [Navigator.maybeOf] requires a descendant context of the navigator, which
///    is not available from the root element.
/// 2. Loop while [NavigatorState.canPop] AND the top route is a [PopupRoute].
/// 3. After each pop, await [WidgetsBinding.instance.endOfFrame] so the route
///    stack settles before the next inspection.
/// 4. Stop at the first non-modal route to preserve the page navigation stack.
///
/// Returns the number of routes popped (0 when no modals are open or when the
/// widget tree is not yet initialised).
Future<int> dismissAllModals() async {
  // 1. Locate the root element. If the binding is not initialised yet (e.g.
  //    very early in startup) return 0 — nothing to dismiss.
  final Element? root = WidgetsBinding.instance.rootElement;
  if (root == null) return 0;

  // 2. Walk the tree to find the first NavigatorState. showModalBottomSheet
  //    and showDialog attach routes to the nearest Navigator, so we want the
  //    first (innermost) one we encounter in the depth-first walk.
  final NavigatorState? navigator = _findNavigatorInTree(root);
  if (navigator == null) return 0;

  int popped = 0;

  // 3. Pop modal routes only; stop when canPop() is false or the top route
  //    is not a PopupRoute.
  while (navigator.canPop()) {
    // Peek at the top route without consuming it: popUntil with a predicate
    // that always returns true visits only the top entry then stops.
    Route<dynamic>? topRoute;
    navigator.popUntil((Route<dynamic> route) {
      topRoute = route;
      return true; // peek only — stop immediately.
    });

    if (topRoute == null || !isModalRoute(topRoute!)) break;

    // 4. Pop the modal route.
    navigator.pop();
    popped++;

    // 5. Settle the frame before inspecting again so the next canPop()
    //    and popUntil() see the updated route stack.
    await WidgetsBinding.instance.endOfFrame;
  }

  return popped;
}

// ---------------------------------------------------------------------------
// VM Service extension handler
// ---------------------------------------------------------------------------

/// Handler for `ext.dusk.dismiss_modals`.
///
/// Params: none.
///
/// On success: `{ "popped": N }` where N is the number of modal routes removed.
/// The underlying page navigation stack is never touched.
///
/// Use this before [aiTestNavigateHandler] navigates to a new route so that
/// stuck modal sheets do not block the new page from rendering.
Future<developer.ServiceExtensionResponse> aiTestDismissModalsHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    final int popped = await dismissAllModals();

    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, dynamic>{'popped': popped}),
    );
  } catch (e, st) {
    developer.log(
      '[ai-test-v3] aiTestDismissModalsHandler error: $e\n$st',
      name: 'ai-test',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), DuskErrorEnvelope.unexpected()),
    );
  }
}
