import 'dart:convert';
import 'dart:developer' as developer;

import 'tapir_register.dart';
import 'frame_sync.dart';

/// Builds the success response every `ext.tapir.*` handler returns.
///
/// One seam rather than 34 hand-written `ServiceExtensionResponse.result(
/// jsonEncode(payload))` calls, so a diagnostic that belongs on every reply
/// is added once and cannot be forgotten by the next handler.
///
/// Today that diagnostic is [frameProductionWarning]: a `warnings` key
/// appears only while the engine has stopped producing frames, which is the
/// state in which both a snapshot and an action silently lie. A healthy run
/// gets the payload back byte-for-byte unchanged.
///
/// When the registration wrapper had to wake a hidden engine for this call,
/// the payload also carries `framesForced: true`, so a caller knows the app
/// was occluded even though the result itself is fresh.
///
/// When the call relocated a stale `e<N>` ref to the control that replaced
/// it, the payload carries `reresolved: [<ref>, ...]`, so a caller knows the
/// ref it holds now names a rebuilt widget.
///
/// [payload] is stamped in place, so callers that keep a reference see the
/// same map the client receives.
developer.ServiceExtensionResponse tapirResult(Map<String, dynamic> payload) {
  if (framesForcedInCurrentCall()) {
    payload['framesForced'] = true;
  }

  final List<String> reresolved = reresolvedRefsInCurrentCall();
  if (reresolved.isNotEmpty) {
    payload['reresolved'] = reresolved;
  }

  final Map<String, dynamic>? warnings = frameProductionWarning();
  if (warnings != null) {
    payload['warnings'] = warnings;
  }

  return developer.ServiceExtensionResponse.result(jsonEncode(payload));
}
