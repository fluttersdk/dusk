import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

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
  registerExtensionIdempotent(
    'ext.dusk.reset_overlays',
    aiTestResetOverlaysHandler,
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

/// Walks the element tree rooted at [root] depth-first and collects ALL
/// [NavigatorState] instances found.
///
/// [Navigator.maybeOf] requires an element that is already a descendant of the
/// [Navigator] in question. [WidgetsBinding.instance.rootElement] sits above
/// all navigators, so `maybeOf` always returns null from there. Walking the
/// tree directly finds every [Navigator] widget regardless of nesting depth.
///
/// The list is returned in DFS discovery order: the root navigator (outermost)
/// appears first, nested navigators appear later. Callers that want to dismiss
/// modals innermost-first should reverse the list before processing.
List<NavigatorState> _collectNavigatorsInTree(Element root) {
  final List<NavigatorState> found = [];

  void visit(Element element) {
    if (element is StatefulElement && element.state is NavigatorState) {
      found.add(element.state as NavigatorState);
    }
    element.visitChildren(visit);
  }

  visit(root);
  return found;
}

/// Dismisses all modal routes above the current page route across ALL
/// [NavigatorState] instances in the widget tree, and returns the total count
/// of routes popped.
///
/// Steps:
/// 1. Walk the element tree from [WidgetsBinding.instance.rootElement] to
///    collect every [NavigatorState]. The walk is necessary because
///    [Navigator.maybeOf] requires a descendant context of the navigator, which
///    is not available from the root element.
/// 2. Process each navigator newest-scope-first (reversed DFS order) using
///    [NavigatorState.popUntil] with a `(r) => r is! PopupRoute` predicate.
///    This safely dismisses [ModalBottomSheetRoute] (nearest navigator, the
///    default for [showModalBottomSheet]) and [RawDialogRoute]/[DialogRoute]
///    (root navigator, the default for [showDialog]) in a single pass per
///    navigator without any inter-pop frame awaits.
/// 3. Count each [PopupRoute] popped across all navigators and return the sum.
///
/// Returns the total number of routes popped (0 when no modals are open or
/// when the widget tree is not yet initialised). The page navigation stack is
/// never touched: only [PopupRoute] subclasses are popped.
Future<int> dismissAllModals() async {
  // 1. Locate the root element. If the binding is not initialised yet (e.g.
  //    very early in startup) return 0 — nothing to dismiss.
  final Element? root = WidgetsBinding.instance.rootElement;
  if (root == null) return 0;

  // 2. Collect all NavigatorStates. Return early when none exist.
  final List<NavigatorState> navigators = _collectNavigatorsInTree(root);
  if (navigators.isEmpty) return 0;

  int popped = 0;

  // 3. Process navigators newest-scope-first (innermost first) so that a
  //    nested navigator's modals are dismissed before the root navigator's
  //    modals. The DFS walk finds the root navigator first, so reversing gives
  //    us innermost-first order.
  for (final NavigatorState navigator in navigators.reversed) {
    // Use popUntil to remove all PopupRoute entries atomically. The predicate
    // returns false (keep popping) for each PopupRoute, and true (stop) for
    // the first non-modal route. Each time the predicate receives a PopupRoute
    // it increments the counter before returning false.
    navigator.popUntil((Route<dynamic> route) {
      if (route is PopupRoute) {
        popped++;
        return false; // pop this modal route.
      }
      return true; // stop at the first page route.
    });
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
      '[fluttersdk_dusk] aiTestDismissModalsHandler error: $e\n$st',
      name: 'fluttersdk_dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), DuskErrorEnvelope.unexpected()),
    );
  }
}

// ---------------------------------------------------------------------------
// ext.dusk.reset_overlays
// ---------------------------------------------------------------------------

/// Common Cancel / Dismiss button labels tried (in order) by the
/// reset-overlays fallback tap. Matched case-insensitively against the
/// SemanticsNode label of tappable nodes.
const List<String> _kDismissLabels = <String>[
  'Cancel',
  'Dismiss',
  'Close',
  'OK',
  'Done',
];

/// Handler for `ext.dusk.reset_overlays` — the one-call "get back to a known
/// clean screen" composition that promotes the manual dismiss + Escape +
/// Cancel-tap dance into a first-class command.
///
/// Idempotent: safe to call when nothing is open (returns `popped: 0`,
/// `escaped: false`, `dismissTapped: false`). Three escalating layers run in
/// order, each a no-op when the prior already cleared the overlays:
/// 1. [dismissAllModals] pops every [PopupRoute] (dialogs, bottom sheets,
///    popups) across every navigator without touching the page stack.
/// 2. An `Escape` key press handles overlays that listen for the dismiss
///    shortcut but are NOT [PopupRoute]s (custom `OverlayEntry` panels,
///    dropdown menus closed via `Shortcuts`).
/// 3. A Cancel / Dismiss / Close / OK / Done labelled tap handles modal
///    barriers that require an explicit affordance to close. This layer fires
///    only when a [PopupRoute] is still detected after layers 1-2 (see
///    [_hasOpenOverlay]); it is deliberately not attempted for fully-custom
///    [OverlayEntry] overlays, since tapping such a label on a clean screen
///    would hit a legitimate page button.
///
/// Params: none.
///
/// Response: `{ "popped": N, "escaped": bool, "dismissTapped": bool }`.
Future<developer.ServiceExtensionResponse> aiTestResetOverlaysHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    // 1. Pop every PopupRoute. This alone clears the common cases (showDialog,
    //    showModalBottomSheet, showMenu) and is fully idempotent.
    final int popped = await dismissAllModals();
    await _settleFrame();

    // 2. Escape key — dismisses overlays driven by the dismiss shortcut that
    //    are not PopupRoutes. Best-effort: a no-op when nothing listens.
    final bool escaped = _pressEscape();
    await _settleFrame();

    // 3. Cancel / Dismiss labelled tap: the last-resort affordance for modal
    //    barriers that require an explicit button. Only attempted when a
    //    PopupRoute still persists (see [_hasOpenOverlay]) so a clean screen
    //    never has a legitimate Cancel/OK/Done button tapped by accident.
    bool dismissTapped = false;
    if (_hasOpenOverlay()) {
      dismissTapped = _tapDismissAffordance();
      await _settleFrame();
    }

    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, dynamic>{
        'popped': popped,
        'escaped': escaped,
        'dismissTapped': dismissTapped,
      }),
    );
  } catch (e, st) {
    developer.log(
      '[fluttersdk_dusk] aiTestResetOverlaysHandler error: $e\n$st',
      name: 'fluttersdk_dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), DuskErrorEnvelope.unexpected()),
    );
  }
}

/// Awaits the next frame, falling through after a short timeout when no frame
/// is scheduled (mirrors the actionability gate's frame-or-timeout guard so
/// the handler never hangs a `flutter_test` fake clock with no pending frame).
Future<void> _settleFrame() {
  return WidgetsBinding.instance.endOfFrame.timeout(
    const Duration(milliseconds: 200),
    onTimeout: () {},
  );
}

/// Dispatches an `Escape` key down + up through [HardwareKeyboard]. Returns
/// `true` when the events were dispatched (the press itself never throws);
/// `false` only when the binding rejects the synthetic event.
bool _pressEscape() {
  try {
    HardwareKeyboard.instance.handleKeyEvent(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.escape,
        logicalKey: LogicalKeyboardKey.escape,
        timeStamp: Duration.zero,
      ),
    );
    HardwareKeyboard.instance.handleKeyEvent(
      const KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.escape,
        logicalKey: LogicalKeyboardKey.escape,
        timeStamp: Duration(milliseconds: 16),
      ),
    );
    return true;
  } catch (e) {
    developer.log(
      '[fluttersdk_dusk] reset_overlays: Escape press swallowed: $e',
      name: 'fluttersdk_dusk',
    );
    return false;
  }
}

/// Returns `true` when any [PopupRoute] is still present in any navigator
/// (i.e. the dismiss layer did not fully clear it).
///
/// Detection is [PopupRoute]-based only: a fully-custom [OverlayEntry] overlay
/// with no backing [PopupRoute] is NOT detected here. Such overlays are left to
/// the Escape layer (2); the Cancel/Dismiss tap layer (3) is intentionally not
/// fired for them, because tapping a Cancel/Close/OK/Done label on an otherwise
/// clean screen would hit a legitimate page button. This is the deliberate
/// trade-off behind gating layer 3 on a precise [PopupRoute] check.
bool _hasOpenOverlay() {
  final Element? root = WidgetsBinding.instance.rootElement;
  if (root == null) return false;
  for (final NavigatorState navigator in _collectNavigatorsInTree(root)) {
    bool hasModal = false;
    navigator.popUntil((Route<dynamic> route) {
      if (route is PopupRoute) hasModal = true;
      return true; // inspect only; never pop here.
    });
    if (hasModal) return true;
  }
  return false;
}

/// Finds the first tappable Semantics node whose label matches one of
/// [_kDismissLabels] (case-insensitive) and synthesizes a tap at its center.
/// Returns `true` when a matching affordance was tapped, `false` otherwise.
bool _tapDismissAffordance() {
  final SemanticsNode? root = RendererBinding
      .instance.rootPipelineOwner.semanticsOwner?.rootSemanticsNode;
  if (root == null) return false;

  SemanticsNode? match;
  void visit(SemanticsNode node) {
    if (match != null) return;
    final SemanticsData data = node.getSemanticsData();
    final String label = data.label.trim();
    final bool tappable =
        data.flagsCollection.isButton || data.hasAction(SemanticsAction.tap);
    if (tappable && _matchesDismissLabel(label)) {
      match = node;
      return;
    }
    node.visitChildren((SemanticsNode child) {
      visit(child);
      return match == null;
    });
  }

  visit(root);
  if (match == null) return false;

  final Rect rect = match!.rect;
  final Offset center = rect.center;
  final int viewId =
      WidgetsBinding.instance.platformDispatcher.implicitView!.viewId;
  WidgetsBinding.instance.handlePointerEvent(
    PointerDownEvent(
      position: center,
      viewId: viewId,
      timeStamp: Duration.zero,
      kind: PointerDeviceKind.touch,
    ),
  );
  WidgetsBinding.instance.handlePointerEvent(
    PointerUpEvent(
      position: center,
      viewId: viewId,
      timeStamp: const Duration(milliseconds: 16),
    ),
  );
  return true;
}

/// Returns `true` when [label] equals any [_kDismissLabels] entry,
/// case-insensitively.
bool _matchesDismissLabel(String label) {
  if (label.isEmpty) return false;
  final String lowered = label.toLowerCase();
  for (final String candidate in _kDismissLabels) {
    if (candidate.toLowerCase() == lowered) return true;
  }
  return false;
}
