import 'dart:developer' as developer;

import 'package:flutter/rendering.dart';
import 'package:fluttersdk_artisan/artisan.dart';

import '../dusk_plugin.dart';
import '../utils/dusk_response.dart';
import '../utils/error_envelope.dart';
import '../utils/frame_sync.dart';
import 'ext_perf.dart' show perfSessionOpen;

/// Registers `ext.dusk.semantics_hold`. Idempotent via
/// [registerExtensionIdempotent]; call once from `registerAllDuskExtensions()`.
void registerSemanticsHoldExtension() {
  registerExtensionIdempotent(
    'ext.dusk.semantics_hold',
    duskSemanticsHoldHandler,
  );
}

/// Handler for `ext.dusk.semantics_hold`: releases or re-acquires the
/// semantics handle dusk keeps for the whole process.
///
/// That handle makes the framework build the semantics tree on every frame,
/// so every dusk-driven measurement carries its cost. `dusk:perf_run
/// --semantics-pass` releases it for one timed window to measure the app
/// without it, and re-acquires it before `perf_end`.
///
/// Params (all string-valued):
/// - `action` (required): `release` or `acquire`.
///
/// `release` is refused unless a perf session is open, so the handle can only
/// be dropped inside a timed window. `acquire` always runs and awaits one
/// frame (bounded by [awaitFrameOrTimeout]) so the tree exists again when it
/// answers.
///
/// Response JSON:
/// ```json
/// {"action": "release", "released": true, "semanticsEnabled": false}
/// {"action": "acquire", "acquired": true, "semanticsEnabled": true,
///  "treeReady": true}
/// ```
///
/// While released, a target cannot be resolved through the tree: resolve
/// rects first and dispatch `ext.dusk.tap` / `ext.dusk.drag` by coordinates.
Future<developer.ServiceExtensionResponse> duskSemanticsHoldHandler(
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
            'ext.dusk.semantics_hold: release is only allowed inside an open '
            'perf session, the timed window it exists for. Call '
            'ext.dusk.perf_begin first, and acquire before ext.dusk.perf_end.',
            DuskErrorEnvelope.unexpected(),
          ),
        );
      }
      final bool released = DuskPlugin.releaseSemantics();
      return duskResult(<String, dynamic>{
        'action': action,
        'released': released,
        'semanticsEnabled': SemanticsBinding.instance.semanticsEnabled,
      });
    case 'acquire':
      final bool acquired = DuskPlugin.acquireSemantics();
      await awaitFrameOrTimeout();
      return duskResult(<String, dynamic>{
        'action': action,
        'acquired': acquired,
        'semanticsEnabled': SemanticsBinding.instance.semanticsEnabled,
        'treeReady': _treeReady(),
      });
    default:
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        wrapErrorDetail(
          'ext.dusk.semantics_hold: action "$action" is not one of release, '
          'acquire.',
          DuskErrorEnvelope.missingParam('action'),
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
