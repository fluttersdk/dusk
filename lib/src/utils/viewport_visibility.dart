import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/gestures.dart' show HitTestEntry, HitTestTarget;
import 'package:flutter/rendering.dart';

/// True when [globalRect] lies entirely outside a viewport of [viewportSize]
/// anchored at the origin, in logical pixels.
///
/// A rect that only touches an edge is outside. A rect with no area is never
/// reported outside: it carries no position claim, and callers that care
/// about zero-size nodes already read it from the rect itself.
bool isRectOutsideViewport(Rect globalRect, Size viewportSize) {
  if (globalRect.isEmpty) return false;
  return !globalRect.overlaps(Offset.zero & viewportSize);
}

/// What a hit test at a target's point established.
enum HitVerdict {
  /// The path holds the target or one of its descendants.
  reached,

  /// The path is empty or its topmost entry is the root render view: the
  /// platform swallowed the probe (routine in Flutter Web's debug build), so
  /// nothing can be said either way.
  platformOnly,

  /// The topmost entry is an ancestor of the target: a container claiming a
  /// point the target has no hit surface at. A pointer lands on the container,
  /// yet nothing is painted above the target.
  ancestorOnly,

  /// The topmost entry is outside the target's ancestry: a sibling subtree
  /// painted above it, which is always hit before any shared ancestor.
  covered,
}

/// The outcome of [probeHitAt].
@immutable
final class HitProbe {
  /// Builds a probe outcome.
  const HitProbe({required this.verdict, this.top});

  /// What the hit test established.
  final HitVerdict verdict;

  /// The topmost hit-test entry, null only when the path was empty.
  final HitTestTarget? top;
}

/// Hit-tests [point] in view [viewId] and classifies the path against
/// [target].
///
/// The caller supplies the point and the view: the actionability gate probes
/// the live rect in the element's own view, the snapshot and observe probe the
/// captured rect in the implicit view. Reaching the target wins over every
/// other reading, so a root render view on top only counts when the target is
/// absent from the path.
HitProbe probeHitAt({
  required RenderObject target,
  required Offset point,
  required int viewId,
}) {
  final BoxHitTestResult result = BoxHitTestResult();
  RendererBinding.instance.hitTestInView(result, point, viewId);
  final List<HitTestTarget> path = result.path
      .map((HitTestEntry<HitTestTarget> entry) => entry.target)
      .toList(growable: false);
  final HitTestTarget? top = path.firstOrNull;

  final bool reachesTarget = path.any(
    (HitTestTarget hit) =>
        hit is RenderObject && _isSelfOrDescendant(hit, target),
  );
  if (reachesTarget) {
    return HitProbe(verdict: HitVerdict.reached, top: top);
  }

  // The suffix covers `RenderView` and the web debug build's private
  // `_ReusableRenderView` without importing the latter.
  if (top == null || top.runtimeType.toString().endsWith('RenderView')) {
    return HitProbe(verdict: HitVerdict.platformOnly, top: top);
  }

  if (top is RenderObject && _isSelfOrDescendant(target, top)) {
    return HitProbe(verdict: HitVerdict.ancestorOnly, top: top);
  }
  return HitProbe(verdict: HitVerdict.covered, top: top);
}

bool _isSelfOrDescendant(RenderObject node, RenderObject root) {
  RenderObject? current = node;
  while (current != null) {
    if (identical(current, root)) return true;
    current = current.parent;
  }
  return false;
}
