import 'dart:ui';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import '../ref_registry.dart';
import 'dusk_exceptions.dart';

/// Guards an action tool against firing on a widget that cannot accept the
/// action.
///
/// Throws [DuskActionabilityException] when ANY of the following hold:
///
/// 1. The entry's [RefEntry.node] is non-null AND its semantics
///    `flagsCollection.isEnabled` is [Tristate.isFalse]. `Tristate.none`
///    (unknown enabled state — the default for non-interactive widgets) and
///    `Tristate.isTrue` both pass; the gate only fails when the framework
///    has explicitly marked the widget disabled.
/// 2. The entry's [RefEntry.rect] has zero width or zero height. A zero-area
///    rect cannot receive a pointer event at `rect.center` and almost always
///    indicates the widget has been collapsed or detached between snapshot
///    and action.
/// 3. The entry's [RefEntry.rect] does not intersect the current root view's
///    logical-pixel viewport. Off-screen widgets cannot be tapped without
///    scrolling first; the agent should call `dusk_scroll_to_ref` before
///    retrying.
///
/// The viewport is recomputed from
/// `WidgetsBinding.instance.platformDispatcher.views.firstOrNull` on every
/// call so window resizes between actions are honored.
///
/// When `platformDispatcher.views` is empty (test harnesses without a real
/// view, headless contexts), the off-viewport check is skipped — the
/// previous two checks still run.
///
/// [ref] is the `eN` token that resolved to [entry]; it is embedded in the
/// thrown exception's message so the agent can identify the failing widget.
void ensureActionable(RefEntry entry, {required String ref}) {
  return ensureActionableForViews(
    entry,
    ref: ref,
    views: WidgetsBinding.instance.platformDispatcher.views,
  );
}

/// Test-injection seam for [ensureActionable].
///
/// Production callers always go through [ensureActionable]; tests use this
/// entry point to exercise the "empty views" code path without monkey-
/// patching `WidgetsBinding.instance.platformDispatcher`.
@visibleForTesting
void ensureActionableForViews(
  RefEntry entry, {
  required String ref,
  required Iterable<FlutterView> views,
}) {
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
  //    the rect is off-screen and must let the action proceed.
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
  if (!rect.overlaps(viewport)) {
    throw DuskActionabilityException(
      ref: ref,
      reason: 'off-viewport (rect=$rect, viewport=$viewport)',
    );
  }
}
