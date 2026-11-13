import 'dart:developer' as developer;

import 'package:flutter/rendering.dart';
import 'package:dowel/dowel.dart';

import '../tapir_plugin.dart';
import '../utils/tapir_register.dart';
import '../utils/tapir_response.dart';
import '../utils/error_envelope.dart';
import '../utils/frame_sync.dart';
import 'ext_perf.dart' show perfSessionOpen;

/// Registers `ext.tapir.semantics_hold`. Idempotent via
/// [registerExtensionIdempotent]; call once from `registerAllTapirExtensions()`.
void registerSemanticsHoldExtension() {
  registerTapirExtension(
    'ext.tapir.semantics_hold',
    tapirSemanticsHoldHandler,
    ensureFrames: false,
  );
}

/// Handler for `ext.tapir.semantics_hold`: releases or re-acquires the
/// semantics handle tapir keeps for the whole process.
///
/// That handle makes the framework build the semantics tree on every frame,
/// so every tapir-driven measurement carries its cost. `tapir:perf_run
/// --semantics-pass` releases it for one timed window to measure the app
/// without it, and re-acquires it after `perf_end` has closed the window, so
/// the acquire's full tree rebuild is not a frame of the session.
///
/// Params (all string-valued):
/// - `action` (required): `release` or `acquire`.
///
/// `release` is refused unless a perf session is open, so the handle can only
/// be dropped inside a timed window. `acquire` always runs and awaits one
/// frame (bounded by [awaitFrameOrTimeout]) so the tree exists again when it
/// answers.
///
/// A release does not always turn the tree off: the framework builds it while
/// any handle is held, and the platform holds one of its own whenever
/// `platformDispatcher.semanticsEnabled` is true. On Flutter web that is
/// every real app once it has sent a semantics tree (the engine turns
/// semantics on at the first update and never back off); on a native device
/// it is an accessibility service. `semanticsEnabled` says whether the tree
/// went off, `heldByPlatform` whether the platform is what kept it on.
///
/// Response JSON:
/// ```json
/// {"action": "release", "released": true, "semanticsEnabled": false,
///  "heldByPlatform": false}
/// {"action": "acquire", "acquired": true, "semanticsEnabled": true,
///  "treeReady": true}
/// ```
///
/// While released, a target cannot be resolved through the tree: resolve
/// rects first and dispatch `ext.tapir.tap` / `ext.tapir.drag` by coordinates.
Future<developer.ServiceExtensionResponse> tapirSemanticsHoldHandler(
  String method,
  Map<String, String> params,
) async {
  final String action = params['action'] ?? '';

  switch (action) {
    case 'release':
      if (!perfSessionOpen) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          wrapErrorDetail(
            'ext.tapir.semantics_hold: release is only allowed inside an open '
            'perf session, the timed window it exists for. Call '
            'ext.tapir.perf_begin first, and acquire after ext.tapir.perf_end.',
            TapirErrorEnvelope.unexpected(),
          ),
        );
      }
      final bool released = TapirPlugin.releaseSemantics();
      return tapirResult(<String, dynamic>{
        'action': action,
        'released': released,
        'semanticsEnabled': SemanticsBinding.instance.semanticsEnabled,
        'heldByPlatform':
            SemanticsBinding.instance.platformDispatcher.semanticsEnabled,
      });
    case 'acquire':
      final bool acquired = TapirPlugin.acquireSemantics();
      await awaitFrameOrTimeout();
      return tapirResult(<String, dynamic>{
        'action': action,
        'acquired': acquired,
        'semanticsEnabled': SemanticsBinding.instance.semanticsEnabled,
        'treeReady': _treeReady(),
      });
    default:
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        wrapErrorDetail(
          'ext.tapir.semantics_hold: action "$action" is not one of release, '
          'acquire.',
          TapirErrorEnvelope.missingParam('action'),
        ),
      );
  }
}

/// Whether any pipeline owner carries a root semantics node. Walks children
/// because the widget tree is usually hosted under a child owner.
bool _treeReady() {
  bool ready = false;
  void visit(PipelineOwner owner) {
    if (owner.semanticsOwner?.rootSemanticsNode != null) ready = true;
    if (!ready) owner.visitChildren(visit);
  }

  visit(RendererBinding.instance.rootPipelineOwner);
  return ready;
}
