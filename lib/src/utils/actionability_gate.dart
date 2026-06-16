import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../ref_registry.dart';
import 'dusk_exceptions.dart';

/// Guards an action tool against firing on a widget that cannot accept the
/// action.
///
/// Throws [DuskActionabilityException] when ANY of the following hold (checked
/// in this exact order; agents branch on the substring inside [reason]):
///
/// 1. **Not enabled** — the entry's [RefEntry.node] is non-null AND its
///    semantics `flagsCollection.isEnabled` is [Tristate.isFalse].
///    `Tristate.none` (unknown enabled state — the default for non-interactive
///    widgets) and `Tristate.isTrue` both pass; the gate only fails when the
///    framework has explicitly marked the widget disabled.
/// 2. **Zero rect** — the entry's [RefEntry.rect] has zero width or zero
///    height. A zero-area rect cannot receive a pointer event at
///    `rect.center` and almost always indicates the widget has been
///    collapsed or detached between snapshot and action.
/// 3. **Off-viewport** — the entry's [RefEntry.rect] does not intersect the
///    current root view's logical-pixel viewport. Off-screen widgets cannot
///    be tapped without scrolling first; the agent should call
///    `dusk_scroll_to_ref` before retrying.
/// 4. **Not stable** — the entry's bounding box (re-resolved from
///    [RefEntry.element]'s live [RenderBox]) shifted by more than 0.5
///    logical pixels on any side between two consecutive frames. Animated
///    widgets (sliding sheets, expanding tiles, page transitions) fail this
///    gate so the agent waits for the animation to settle before retrying.
///    Skipped when [checkStable] is `false`.
/// 5. **Obscured by other widget** — at `rect.center` the topmost hit-test
///    target is not [RefEntry.element]'s render object (or a descendant).
///    Overlays, modal scrims, and stacked widgets that swallow the pointer
///    fail this gate. The reason carries the obscurer's `runtimeType`.
///    Skipped when [checkReceivesEvents] is `false`.
///
/// The viewport is recomputed from
/// `WidgetsBinding.instance.platformDispatcher.views.firstOrNull` on every
/// call so window resizes between actions are honored.
///
/// When `platformDispatcher.views` is empty (test harnesses without a real
/// view, headless contexts), the off-viewport / stable / receives-events
/// checks are skipped — the first two checks still run.
///
/// [ref] is the `eN` token that resolved to [entry]; it is embedded in the
/// thrown exception's message so the agent can identify the failing widget.
///
/// [checkStable] and [checkReceivesEvents] default to `true` to match
/// Playwright's "4-gate" actionability semantics. Action handlers in
/// production never override the defaults; widget tests that fabricate
/// synthetic [RefEntry] rects (which would not match the live render-object
/// geometry) opt out by passing `false`.
Future<void> ensureActionable(
  RefEntry entry, {
  required String ref,
  bool checkStable = true,
  bool checkReceivesEvents = true,
}) {
  return ensureActionableForViews(
    entry,
    ref: ref,
    views: WidgetsBinding.instance.platformDispatcher.views,
    checkStable: checkStable,
    checkReceivesEvents: checkReceivesEvents,
  );
}

/// Test-injection seam for [ensureActionable].
///
/// Production callers always go through [ensureActionable]; tests use this
/// entry point to exercise the "empty views" code path without monkey-
/// patching `WidgetsBinding.instance.platformDispatcher`.
@visibleForTesting
Future<void> ensureActionableForViews(
  RefEntry entry, {
  required String ref,
  required Iterable<FlutterView> views,
  bool checkStable = true,
  bool checkReceivesEvents = true,
}) async {
  // 0. Defunct guard — the snapshot may have minted this ref against an
  //    Element that has since been deactivated (parent rebuild, route pop,
  //    list-item recycle). Calling findRenderObject on a defunct element
  //    throws `FlutterError: Cannot get renderObject of inactive element`
  //    which the JSON-RPC handler then propagates with a multi-kilobyte
  //    stack trace. Detect the lifecycle state up front and emit a typed
  //    stale envelope so the agent re-snaps + re-resolves.
  try {
    final RenderObject? probe = entry.element.findRenderObject();
    if (probe == null) {
      throw DuskActionabilityException(
        ref: ref,
        reason: 'defunct (element no longer attached to a render object)',
      );
    }
  } on FlutterError catch (e) {
    if (e.message.contains('inactive element') ||
        e.message.contains('_ElementLifecycle.defunct')) {
      throw DuskActionabilityException(
        ref: ref,
        reason: 'defunct (element no longer mounted)',
      );
    }
    rethrow;
  }

  // 1. Enabled check — only meaningful when a SemanticsNode was captured at
  //    registration time. Synthetic entries (e.g. find_by_text) pass through
  //    untouched. We compare against Tristate.isFalse explicitly so the
  //    common Tristate.none (no enabled flag set, e.g. plain Text) is NOT
  //    treated as a failure.
  final SemanticsNode? node = entry.node;
  if (node != null && node.flagsCollection.isEnabled == Tristate.isFalse) {
    throw DuskActionabilityException(ref: ref, reason: 'not enabled');
  }

  // 2. Zero-area rect — width OR height of zero means pointer dispatch at
  //    rect.center would land outside the widget's hit area.
  final Rect rect = entry.rect;
  if (rect.width == 0 || rect.height == 0) {
    throw DuskActionabilityException(ref: ref, reason: 'zero rect');
  }

  // 3. Off-viewport check — re-derive the logical viewport on every call so
  //    window resizes between actions are observed. When no FlutterView is
  //    attached (headless test harness, multi-view race), we cannot prove
  //    the rect is off-screen and must let the action proceed. The stable
  //    and receives-events checks also rely on a live view, so they share
  //    this early return.
  //
  //    Playwright auto-actionability: when the target rect lies outside the
  //    viewport, call RenderObject.showOnScreen which walks every Scrollable
  //    ancestor and brings the element into view, then await one frame and
  //    re-check. The gate only fails when scroll-into-view cannot place the
  //    target inside the viewport (no scrollable ancestor, or the page
  //    layout cannot accommodate the element).
  final FlutterView? view = views.isEmpty ? null : views.first;
  if (view == null) {
    return;
  }
  final Size physical = view.physicalSize;
  final double dpr = view.devicePixelRatio;
  final Rect viewport = Rect.fromLTWH(
    0,
    0,
    physical.width / dpr,
    physical.height / dpr,
  );
  Rect currentRect = rect;
  if (!currentRect.overlaps(viewport)) {
    final RenderObject? renderObject = entry.element.renderObject;
    if (renderObject != null && renderObject.attached) {
      // Only attempt scroll-into-view when a `Scrollable` ancestor exists —
      // `showOnScreen` is a no-op without one, so awaiting a frame would
      // hang in any environment that does not auto-pump (e.g. `flutter_test`
      // running off a `FakeAsync` clock). Production callers always have a
      // scrollable somewhere up the tree when the target sits below the
      // fold; widget-test fixtures rarely do.
      final bool hasScrollable =
          Scrollable.maybeOf(entry.element as BuildContext) != null;
      if (hasScrollable) {
        renderObject.showOnScreen(duration: Duration.zero);
        await _awaitFrameOrTimeout();
        final Rect? liveRect = _liveRectOf(entry.element);
        if (liveRect != null) {
          currentRect = liveRect;
        }
      }
    }
    if (!currentRect.overlaps(viewport)) {
      throw DuskActionabilityException(
        ref: ref,
        reason: 'off-viewport (rect=$currentRect, viewport=$viewport)',
      );
    }
  }

  // 4. Stable check — re-resolve the rect from the live render object after
  //    awaiting one frame. If any side has drifted by more than 0.5 logical
  //    pixels the widget is still animating; the agent should wait or
  //    re-snap rather than tap a moving target.
  //
  //    Baseline is [currentRect] (post-auto-scroll, if step 3 ran) instead of
  //    the original entry.rect — otherwise the deliberate scroll motion from
  //    step 3 would always trip this gate.
  if (checkStable) {
    await _awaitFrameOrTimeout();
    final Rect? liveRect = _liveRectOf(entry.element);
    if (liveRect != null) {
      final double delta = _maxSideDelta(currentRect, liveRect);
      if (delta > 0.5) {
        final String formatted = delta.toStringAsFixed(1);
        throw DuskActionabilityException(
          ref: ref,
          reason: 'not stable (rect changed by ${formatted}px)',
        );
      }
      currentRect = liveRect;
    }
  }

  // 5. Receives-events check — hit-test at rect.center and confirm the
  //    entry's render object (or a descendant) appears in the path. If the
  //    topmost target is anything else, a modal scrim / overlay / stacked
  //    widget is swallowing the pointer.
  if (checkReceivesEvents) {
    final RenderObject? target = entry.element.findRenderObject();
    if (target != null) {
      final BoxHitTestResult result = BoxHitTestResult();
      RendererBinding.instance
          .hitTestInView(result, currentRect.center, view.viewId);
      final List<HitTestEntry<HitTestTarget>> path =
          result.path.toList(growable: false);
      final bool targetInPath = path.any(
        (HitTestEntry<HitTestTarget> e) =>
            identical(e.target, target) || _isDescendantOf(e.target, target),
      );
      if (!targetInPath) {
        // Graceful degradation: when the hit-test path contains ONLY the
        // root render view (Flutter Web's `_ReusableRenderView` or the
        // generic `RenderView`), the platform compositor swallowed the
        // synthetic hit-test before it reached the widget layer. Treat as
        // "could not determine receivership" and let the action proceed.
        // The behavior happens routinely in Flutter Web's debug build
        // because DWDS pipes hit-tests through a snapshot view that does
        // not always mirror the live element subtree, and breaking valid
        // taps on that artifact is a worse failure mode than letting
        // pointer dispatch decide.
        final bool platformOnly =
            path.length == 1 && _isRootRenderView(path.first.target);
        if (platformOnly || path.isEmpty) {
          // proceed
        } else {
          final HitTestTarget top = path.first.target;
          final String topName = top.runtimeType.toString();
          throw DuskActionabilityException(
            ref: ref,
            reason: 'obscured by other widget (top=$topName)',
          );
        }
      }
    }
  }
}

/// Await the next `WidgetsBinding.endOfFrame` but fall through after
/// [timeout] if no frame is scheduled.
///
/// `endOfFrame` is a [Future] that completes when the next frame finishes;
/// it NEVER completes when nothing has scheduled a frame (Flutter does not
/// poll a frame clock — it only renders on demand). In `flutter_test` runs,
/// `showOnScreen` on a widget with no `Scrollable` ancestor is a no-op, so
/// the gate's `await endOfFrame` would hang the test indefinitely. The
/// timeout is large enough to cover a real production reflow (16ms at 60Hz
/// + scheduler jitter + dart2js dispatch overhead) and small enough that
/// no real user action waits more than ~one frame on the gate.
Future<void> _awaitFrameOrTimeout({
  Duration timeout = const Duration(milliseconds: 200),
}) {
  return WidgetsBinding.instance.endOfFrame.timeout(
    timeout,
    onTimeout: () {},
  );
}

/// Recognises the framework-level RenderView wrappers that legitimately
/// sit at the top of every Flutter hit-test path. The class names are
/// matched on `runtimeType` so the gate stays portable across the
/// `RenderView` (mobile + desktop) and `_ReusableRenderView` (web debug
/// build) variants without taking a hard import on the private symbol.
bool _isRootRenderView(HitTestTarget target) {
  final String name = target.runtimeType.toString();
  return name == 'RenderView' ||
      name == '_ReusableRenderView' ||
      name.endsWith('RenderView');
}

/// Re-resolves the live global-coordinate bounding rect of [entry]'s element,
/// for pointer dispatch immediately after the actionability gate passes.
///
/// Reuses [_liveRectOf] so the dispatch point matches the same live geometry
/// the gate's stable check (step 4) measured: a widget whose host rebuilt it
/// into a shifted slot between snapshot and action (footer submit buttons in
/// an `AnimatedBuilder`, the last tab in a scrollable tab bar) keeps the same
/// `Element` / `RenderObject` identity (Flutter retains both across a
/// same-type-and-key rebuild), so the live rect is valid and current.
///
/// Returns `null` when the render object is detached, missing, unsized, or
/// not a [RenderBox] (e.g. a sliver). Callers fall back to the cached
/// [RefEntry.rect] center in that case; the guard mirrors the
/// `renderObject.attached` precondition Flutter's `localToGlobal` asserts.
///
/// This helper is purely additive to the FROZEN actionability gate: it runs
/// AFTER the gate passes and BEFORE pointer dispatch, never touching the gate
/// order or any failure-reason substring.
Rect? dispatchRectOf(RefEntry entry) => _liveRectOf(entry.element);

/// Re-resolves the global-coordinate bounding rect of [element] from its
/// live [RenderBox]. Returns `null` when the element is detached, the
/// render object is missing, or the render object is not a [RenderBox]
/// (e.g. a sliver). The caller treats `null` as "cannot prove instability"
/// and lets the action proceed.
Rect? _liveRectOf(Element element) {
  final RenderObject? renderObject = element.findRenderObject();
  if (renderObject is! RenderBox) {
    return null;
  }
  if (!renderObject.attached || !renderObject.hasSize) {
    return null;
  }
  final Offset topLeft = renderObject.localToGlobal(Offset.zero);
  return topLeft & renderObject.size;
}

/// Returns the maximum absolute drift, in logical pixels, between any
/// matching side of [a] and [b]. A return value of zero means the rects
/// share all four sides; anything above 0.5 trips the stable gate.
double _maxSideDelta(Rect a, Rect b) {
  final double left = (a.left - b.left).abs();
  final double top = (a.top - b.top).abs();
  final double right = (a.right - b.right).abs();
  final double bottom = (a.bottom - b.bottom).abs();
  double max = left;
  if (top > max) {
    max = top;
  }
  if (right > max) {
    max = right;
  }
  if (bottom > max) {
    max = bottom;
  }
  return max;
}

/// Returns `true` when [target] is a render-tree descendant of [candidate].
///
/// Used by the receives-events gate to accept hit-test path entries whose
/// render object lives inside the entry's subtree: a `RenderParagraph`
/// inside a button's `SizedBox`, for example, will hit-test first but the
/// button is still "receiving the pointer" because the descendant sits
/// within the button's bounds.
///
/// Render-tree ANCESTORS of [candidate] do NOT count as "receiving the
/// pointer at the entry's rect" — only the entry itself or its descendants
/// occupy the entry's bounds. The gate intentionally excludes ancestors so
/// that an overlay sibling (which shares a Stack ancestor with the entry
/// candidate but does not contain it) trips the gate.
bool _isDescendantOf(HitTestTarget target, RenderObject candidate) {
  if (target is! RenderObject) {
    return false;
  }
  RenderObject? parent = target.parent;
  while (parent != null) {
    if (identical(parent, candidate)) {
      return true;
    }
    parent = parent.parent;
  }
  return false;
}
