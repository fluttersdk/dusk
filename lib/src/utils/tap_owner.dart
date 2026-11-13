import 'dart:ui' show FlutterView;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'viewport_visibility.dart';

/// Why a tap at a merge boundary's centre is not a tap on its control, and
/// where the control is (#60).
@immutable
final class TapOwnerReport {
  /// Builds a report for [point], judged against the control at [ownerRect].
  const TapOwnerReport({
    required this.point,
    required this.ownerRect,
    required this.canRetarget,
    required this.centreHandled,
  });

  /// The point that was judged, in global logical pixels.
  final Offset point;

  /// The global rect of the control the point should have hit. With several
  /// candidates this is the first one found, which is a hint, not a verdict.
  final Rect ownerRect;

  /// True when exactly one labelled control owns the merged label and a hit
  /// test at its centre reaches it inside the viewport, so a pointer sent
  /// there lands on it.
  final bool canRetarget;

  /// True when [point] lies inside a tap handler of its own (a stage that
  /// pauses on any tap, a row that opens). Moving the pointer then trades one
  /// real action for another, which the caller should say out loud.
  final bool centreHandled;

  /// The point a retargeted pointer is sent to.
  Offset get target => ownerRect.center;
}

/// Judges a pointer at [point] on the merge boundary [node] (backed by
/// [element]) and returns null when nothing is wrong or nothing can be told.
///
/// A `MergeSemantics` boundary folds its controls into one node that reports
/// the boundary's own rect and the concatenated label. The absorbed controls
/// are flagged `isMergedIntoParent` and get no ref, so the render objects
/// beneath the boundary are what say where they are and what they publish. The
/// owner is the labelled control whose label is part of the node's merged
/// label; a handler that publishes no label (a stage that pauses on any tap) is
/// never the owner, which is what lets it be told apart from the control the
/// agent named. Without a labelled control the judgement falls back to every
/// control that carries a tap.
///
/// Null as well when [node] is not a merge boundary, when no control is found
/// to compare against, or when [point] already lies inside one of them.
TapOwnerReport? judgeTapPoint({
  required SemanticsNode node,
  required Element element,
  required Offset point,
  required int Function() viewId,
}) {
  if (!node.attached || !node.mergeAllDescendantsIntoThisNode) return null;
  // A query handle whose element could not be found falls back to the root,
  // and a walk from there would pick up controls from the whole app.
  if (element == WidgetsBinding.instance.rootElement) return null;

  final List<_Carrier> carriers = _carriersBelow(element);
  if (carriers.isEmpty) return null;

  final String merged = node.getSemanticsData().label;
  final List<_Carrier> owners = _distinct(
    carriers.where(
      (_Carrier c) => c.label != null && merged.contains(c.label!),
    ),
  );
  final List<_Carrier> judged = owners.isEmpty ? carriers : owners;
  if (judged.any((_Carrier c) => c.rect.contains(point))) return null;

  final _Carrier first = judged.first;
  return TapOwnerReport(
    point: point,
    ownerRect: first.rect,
    canRetarget: owners.length == 1 && _isReached(first, viewId()),
    centreHandled: carriers.any((_Carrier c) => c.rect.contains(point)),
  );
}

/// The owner of the merge boundary [node] as `{x, y, w, h}` in global logical
/// pixels, when a pointer at [rect]'s centre would miss it; null otherwise.
/// Snapshot and observe both name the control this way.
///
/// `centreHandled: true` is added when the centre has a tap handler of its own,
/// and `retargets: false` when a tap on the ref cannot go to the owner (several
/// candidates, or one that is covered or off screen); both are absent on the
/// plain case. An empty rect (a sliver reports [Rect.zero]) has no centre worth
/// judging, and without a view there is nothing to hit-test against.
Map<String, Object>? tapOwnerBounds({
  required SemanticsNode node,
  required Element element,
  required Rect rect,
}) {
  if (rect.isEmpty) return null;
  final FlutterView? view =
      WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view == null) return null;

  final TapOwnerReport? report = judgeTapPoint(
    node: node,
    element: element,
    point: rect.center,
    viewId: () => view.viewId,
  );
  if (report == null) return null;

  final Rect owner = report.ownerRect;
  return <String, Object>{
    'x': owner.left,
    'y': owner.top,
    'w': owner.width,
    'h': owner.height,
    if (report.centreHandled) 'centreHandled': true,
    if (!report.canRetarget) 'retargets': false,
  };
}

/// A pointer sent to the owner's centre must land on it: the centre has to lie
/// inside the viewport and a hit test there has to reach the owner. A control
/// with no hit surface, or one something else is painted over, gains nothing
/// from a pointer. Only a web probe may be unable to answer, and there the
/// retarget stands; on a native platform a root-only path means the point is
/// outside the window or over nothing.
bool _isReached(_Carrier owner, int viewId) {
  final FlutterView? view = WidgetsBinding.instance.platformDispatcher.view(
    id: viewId,
  );
  if (view == null ||
      isRectOutsideViewport(
        owner.rect,
        view.physicalSize / view.devicePixelRatio,
      )) {
    return false;
  }

  final HitVerdict verdict = probeHitAt(
    target: owner.render,
    point: owner.rect.center,
    viewId: viewId,
  ).verdict;
  return verdict == HitVerdict.reached ||
      (kIsWeb && verdict == HitVerdict.platformOnly);
}

/// Owners that share a rect (a `Semantics` wrapped round another) are one.
List<_Carrier> _distinct(Iterable<_Carrier> carriers) {
  final List<_Carrier> distinct = <_Carrier>[];
  for (final _Carrier carrier in carriers) {
    if (distinct.every((_Carrier seen) => seen.rect != carrier.rect)) {
      distinct.add(carrier);
    }
  }
  return distinct;
}

final class _Carrier {
  const _Carrier({required this.render, required this.rect, this.label});

  final RenderBox render;
  final Rect rect;

  /// The label the control publishes, null when it publishes none.
  final String? label;
}

/// The controls beneath [element] that carry a tap: a `Semantics` with an
/// `onTap` or a labelled button, and a `GestureDetector` with an `onTap`.
List<_Carrier> _carriersBelow(Element element) {
  final List<_Carrier> carriers = <_Carrier>[];

  void visit(Element child) {
    final RenderObject? render = child.renderObject;
    if (render is RenderBox && render.attached && render.hasSize) {
      final String? label = _labelOf(render);
      final bool carriesTap = switch (render) {
        RenderSemanticsAnnotations(:final SemanticsProperties properties) =>
          properties.onTap != null ||
              (label != null && properties.button == true),
        RenderSemanticsGestureHandler(:final onTap) => onTap != null,
        _ => false,
      };
      if (carriesTap) {
        carriers.add(
          _Carrier(
            render: render,
            rect: MatrixUtils.transformRect(
              render.getTransformTo(null),
              Offset.zero & render.size,
            ),
            label: label,
          ),
        );
      }
    }
    child.visitChildren(visit);
  }

  element.visitChildren(visit);
  return carriers;
}

String? _labelOf(RenderBox render) {
  if (render is! RenderSemanticsAnnotations) return null;
  final String? label =
      render.properties.label ?? render.properties.attributedLabel?.string;
  return label == null || label.isEmpty ? null : label;
}
