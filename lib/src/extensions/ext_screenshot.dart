import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img_lib;

import '../ref_registry.dart';

import '../dusk_plugin.dart';
import 'package:fluttersdk_artisan/artisan.dart';

/// Registers the `ext.dusk.screenshot` VM Service extension.
///
/// The extension captures the current app frame as a JPEG (default, q70) or
/// PNG image and returns a base64-encoded payload with size metadata. The
/// JPEG default keeps payloads in the 40-120 KB range; PNG is opt-in for
/// lossless use cases (e.g., pixel-exact test assertions).
///
/// Call this from the Wave 3 aggregator (`registerAllAiTestExtensions`) — it
/// is a no-op per extension name on repeated calls via
/// [registerExtensionIdempotent].
void registerScreenshotExtension() {
  registerExtensionIdempotent(
    'ext.dusk.screenshot',
    screenshotHandler,
  );
}

/// Handler for `ext.dusk.screenshot`.
///
/// Accepted parameters:
///
/// | Name      | Type   | Default  | Notes                                          |
/// |-----------|--------|----------|------------------------------------------------|
/// | `ref`     | String | absent   | If absent, captures the app-root viewport.     |
/// | `rect`    | String | absent   | `x,y,w,h` logical px sub-rect of the ref.      |
/// | `format`  | String | `'jpeg'` | `'png'` for lossless, `'jpeg'` for q70.        |
/// | `quality` | int    | 70       | JPEG quality 1-100 (ignored for PNG).          |
///
/// `rect` is interpreted in logical pixels relative to the ref's
/// `RenderObject` origin (top-left of the widget's paint bounds). It only
/// has meaning when `ref` is also supplied; `rect` without `ref` is treated
/// as a hard error so silent misuse cannot ship through.
///
/// Returns JSON:
/// ```json
/// { "format": "jpeg", "base64": "<base64>", "width": 2880, "height": 1800 }
/// ```
Future<developer.ServiceExtensionResponse> screenshotHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    final String format = params['format'] ?? 'jpeg';
    final int quality = int.tryParse(params['quality'] ?? '') ?? 70;
    final String? ref = params['ref'];
    final String? rectParam = params['rect'];

    // 1. Parse the optional sub-rect ahead of any rendering work — a
    //    malformed rect string is a hard caller error and must short-circuit
    //    BEFORE we open the heavy capture path.
    final Rect? subRect = _parseSubRect(rectParam);
    if (rectParam != null && rectParam.isNotEmpty && subRect == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        'ext.dusk.screenshot: malformed rect "$rectParam". '
        'Expected "x,y,w,h" with four non-negative numbers.',
      );
    }

    // 2. Resolve the capture target: the OffsetLayer to rasterise PLUS the
    //    bounds (in layer-local coordinates) to rasterise out of it. The
    //    target shape is uniform across all three modes (no ref, ref only,
    //    ref + rect); only how we derive the bounds differs.
    final _CaptureTarget target = _resolveCaptureTarget(
      ref: (ref != null && ref.isNotEmpty) ? ref : null,
      subRect: subRect,
    );

    // 3. Rasterise. toImage asserts !debugNeedsPaint — safe because the
    //    extension only fires after a frame has painted; in tests the
    //    caller pumps once before invoking us.
    final ui.Image img = await target.layer.toImage(
      target.bounds,
      pixelRatio: 2.0,
    );
    final int width = img.width;
    final int height = img.height;

    final String base64Payload;
    try {
      // 4. Encode to the requested format and base64-encode the byte stream.
      if (format == 'png') {
        // 4a. PNG path: lossless, larger payload (~300-800 KB for a full HD
        //     screen at 2x). Use only when pixel-exact output is required.
        final ByteData? byteData =
            await img.toByteData(format: ui.ImageByteFormat.png);

        if (byteData == null) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            'toByteData returned null for PNG format',
          );
        }

        base64Payload = base64Encode(byteData.buffer.asUint8List());
      } else {
        // 4b. JPEG path (default): lossy q70 encode via the `image` package.
        //     Steps: toImage() → PNG bytes → decodePng → encodeJpg. This keeps
        //     payloads in the 40-120 KB range for typical app screens.
        final ByteData? pngByteData =
            await img.toByteData(format: ui.ImageByteFormat.png);

        if (pngByteData == null) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            'toByteData returned null for intermediate PNG (JPEG path)',
          );
        }

        final Uint8List pngBytes = pngByteData.buffer.asUint8List();
        final Uint8List jpegBytes = encodeToJpeg(pngBytes, quality: quality);
        base64Payload = base64Encode(jpegBytes);
      }
    } finally {
      img.dispose();
    }

    // 5. Return the payload with format, encoded bytes, and dimensions.
    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, dynamic>{
        'format': format == 'png' ? 'png' : 'jpeg',
        'base64': base64Payload,
        'width': width,
        'height': height,
      }),
    );
  } catch (e, stackTrace) {
    developer.log(
      '[ai-test-v3] ext.dusk.screenshot error: $e\n$stackTrace',
      name: 'ai-test',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      e.toString(),
    );
  }
}

/// The two things [screenshotHandler] needs to call
/// [OffsetLayer.toImage]: the layer to rasterise and the layer-local rect
/// to rasterise out of it.
class _CaptureTarget {
  const _CaptureTarget({required this.layer, required this.bounds});

  final OffsetLayer layer;
  final Rect bounds;
}

/// Parses a `x,y,w,h` logical-px rect string. Returns `null` for any input
/// shape this contract does not accept (wrong component count, non-numeric
/// parts, negative width/height). The handler turns a `null` return into a
/// hard error response, so this stays a pure parser.
Rect? _parseSubRect(String? raw) {
  if (raw == null || raw.isEmpty) return null;

  final List<String> parts = raw.split(',');
  if (parts.length != 4) return null;

  final double? x = double.tryParse(parts[0].trim());
  final double? y = double.tryParse(parts[1].trim());
  final double? w = double.tryParse(parts[2].trim());
  final double? h = double.tryParse(parts[3].trim());

  if (x == null || y == null || w == null || h == null) return null;
  if (w <= 0 || h <= 0) return null;
  if (x < 0 || y < 0) return null;

  return Rect.fromLTWH(x, y, w, h);
}

/// Resolves the [OffsetLayer] + bounds pair to feed [OffsetLayer.toImage].
///
/// Three modes, distinguished by the input:
///
/// 1. `ref == null && subRect == null` — full viewport. Walks the render
///    tree from the app root, finds the nearest `isRepaintBoundary` render
///    object (typically [RenderView] in tests, an explicit RepaintBoundary
///    in production once the host wraps the root), and rasterises its full
///    paint bounds.
/// 2. `ref != null && subRect == null` — capture the ref's render-object
///    region. Walks up from the ref's render object for an
///    `isRepaintBoundary` ancestor; computes the ref's paint bounds
///    transformed into that ancestor's coordinate space.
/// 3. `ref != null && subRect != null` — capture a sub-rect within the
///    ref's bounds. Identical to mode 2 except the source rect is the
///    caller-supplied [subRect] (in ref-local logical px) instead of the
///    ref's full paint bounds.
///
/// Throws [StateError] when the render tree is not in a captureable state
/// (no root element, ref unknown, ref carries no live render object, or
/// no `isRepaintBoundary` ancestor exists — the last is a structural
/// impossibility once the framework attaches a RenderView, kept as a
/// belt-and-braces guard).
_CaptureTarget _resolveCaptureTarget({
  required String? ref,
  required Rect? subRect,
}) {
  // 1. Determine the starting render object — the leaf whose paint bounds
  //    define the capture region. For ref-less calls this is the app root;
  //    for ref calls it is the registered widget's RenderObject.
  final RenderObject startRO =
      (ref == null) ? _resolveRootRenderObject() : _resolveRefRenderObject(ref);

  // 2. Find the nearest ancestor (or self) flagged isRepaintBoundary. Any
  //    such RenderObject has an OffsetLayer attached (TransformLayer for
  //    RenderView and OffsetLayer for RenderRepaintBoundary both qualify
  //    — TransformLayer extends OffsetLayer).
  final RenderObject boundaryRO = _findRepaintBoundaryAncestor(startRO);
  final Layer? boundaryLayer = boundaryRO.debugLayer;
  if (boundaryLayer is! OffsetLayer) {
    throw StateError(
      'ext.dusk.screenshot: repaint-boundary ancestor has no OffsetLayer '
      '(layer runtime type: ${boundaryLayer?.runtimeType}). The frame may '
      'not have composited yet — re-pump and retry.',
    );
  }

  // 3. Compute the rect (in boundaryRO's local coordinate space) we want
  //    rasterised. The shape depends on whether the caller passed ref/rect.
  late final Rect bounds;
  if (ref == null) {
    // 3a. Full viewport — boundaryRO IS the root we walked from, so just
    //     use its paint bounds.
    bounds = boundaryRO.paintBounds;
  } else {
    // 3b. Ref-scoped capture. Source rect lives in startRO's local space:
    //     either the whole paint bounds (mode 2) or the caller's sub-rect
    //     (mode 3). Transform that rect into boundaryRO's coordinate space
    //     so OffsetLayer.toImage extracts the right pixels.
    final Rect sourceRect = subRect ?? startRO.paintBounds;
    final Matrix4 transform = startRO.getTransformTo(boundaryRO);
    bounds = MatrixUtils.transformRect(transform, sourceRect);
  }

  return _CaptureTarget(layer: boundaryLayer, bounds: bounds);
}

/// Walks up from [start] (including [start] itself) and returns the first
/// render object whose `isRepaintBoundary` is `true`. Throws [StateError]
/// when no such ancestor exists, which is structurally impossible once the
/// framework attaches a RenderView — kept as a belt-and-braces guard.
RenderObject _findRepaintBoundaryAncestor(RenderObject start) {
  RenderObject? cursor = start;
  while (cursor != null) {
    if (cursor.isRepaintBoundary) return cursor;
    cursor = cursor.parent;
  }
  throw StateError(
    'ext.dusk.screenshot: no repaint-boundary ancestor reachable from '
    '$start. The render tree is detached or has not composited yet.',
  );
}

/// Resolves the root render object for a ref-less capture.
///
/// Preference order:
///
/// 1. [DuskPlugin.rootRepaintBoundaryKey] when its `currentContext`
///    resolves — the host explicitly wrapped its root with the plugin's
///    GlobalKey (legacy V3.0 layout).
/// 2. The render object of [WidgetsBinding.instance.rootElement] — typically
///    the framework's [RenderView]. `RenderView.isRepaintBoundary` is
///    `true`, so the ancestor walk in [_findRepaintBoundaryAncestor] stops
///    immediately and we capture the full viewport.
///
/// Throws [StateError] when neither path resolves (plugin not installed
/// AND no root element — install() was called before runApp() or the
/// binding is not initialised).
RenderObject _resolveRootRenderObject() {
  // 1. Prefer the explicit GlobalKey wrap when present. Skipped silently
  //    when the key has no currentContext — the V3.1 default no longer
  //    wraps with this key (avoids GlobalKey-vs-MagicApplication lifecycle
  //    assertions). The fallback path is the standard route post-V3.1.
  final BuildContext? keyedCtx =
      DuskPlugin.rootRepaintBoundaryKey.currentContext;
  if (keyedCtx != null) {
    final RenderObject? keyedRO = keyedCtx.findRenderObject();
    if (keyedRO != null) return keyedRO;
  }

  // 2. Fall back to the root element's render object (RenderView). Always
  //    isRepaintBoundary, so the ancestor walk resolves to RenderView
  //    itself. This is the path the regression-guard test exercises.
  final Element? rootEl = WidgetsBinding.instance.rootElement;
  if (rootEl == null) {
    throw StateError(
      'ext.dusk.screenshot: no root element — was DuskPlugin.install '
      'called after runApp()?',
    );
  }
  final RenderObject? rootRO = rootEl.renderObject;
  if (rootRO == null) {
    throw StateError(
      'ext.dusk.screenshot: root element has no render object attached. '
      'The first frame has not painted yet.',
    );
  }
  return rootRO;
}

/// Resolves the render object backing a ref. Throws [StateError] when the
/// ref is unknown to [RefRegistry] OR the registered entry carries no live
/// render object (snapshot did not capture this node from the render tree).
RenderObject _resolveRefRenderObject(String ref) {
  final RefEntry? entry = RefRegistry.lookup(ref);
  if (entry == null) {
    throw StateError(
      'ext.dusk.screenshot: ref "$ref" not found in RefRegistry. '
      'Call ext.dusk.snapshot first to register refs, or omit ref to '
      'capture the root viewport.',
    );
  }

  // Prefer the explicit renderObject the snapshot enriched the entry with;
  // fall back to the element's current renderObject for synthetic entries
  // minted by find_by_* helpers (which often skip the renderObject field).
  final RenderObject? ro =
      entry.renderObject ?? entry.element.findRenderObject();
  if (ro == null) {
    throw StateError(
      'ext.dusk.screenshot: ref "$ref" resolved to an entry with no live '
      'render object. The widget may have unmounted between snapshot and '
      'screenshot — re-snapshot and retry.',
    );
  }
  return ro;
}

/// Encodes PNG [bytes] to JPEG at the given [quality] using the `image`
/// package (v4.x, pure-Dart, cross-platform, no platform channels).
///
/// Steps:
/// 1. Decode the PNG bytes via [img_lib.decodePng] into the package's
///    intermediate [img_lib.Image] representation.
/// 2. Re-encode via [img_lib.encodeJpg] at the requested [quality].
///
/// Throws [ArgumentError] when [bytes] is not valid PNG data or [quality] is
/// outside 1-100.
///
/// Exposed as a top-level function (not private) so the test suite can
/// validate the exact same encode chain as the VM extension handler.
Uint8List encodeToJpeg(Uint8List bytes, {required int quality}) {
  if (quality < 1 || quality > 100) {
    throw ArgumentError.value(
      quality,
      'quality',
      'JPEG quality must be in the range 1-100',
    );
  }

  // 1. Decode PNG into the image package's intermediate representation.
  final img_lib.Image? decoded = img_lib.decodePng(bytes);
  if (decoded == null) {
    throw ArgumentError('encodeToJpeg: input bytes are not valid PNG data');
  }

  // 2. Encode to JPEG at the requested quality. encodeJpg returns a List<int>
  //    which we convert to Uint8List for typed binary handling downstream.
  return Uint8List.fromList(img_lib.encodeJpg(decoded, quality: quality));
}
