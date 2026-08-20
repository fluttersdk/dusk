import 'dart:convert';
import 'dart:developer' as developer;

import 'frame_sync.dart';

/// Builds the success response every `ext.dusk.*` handler returns.
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
/// [payload] is stamped in place, so callers that keep a reference see the
/// same map the client receives.
developer.ServiceExtensionResponse duskResult(Map<String, dynamic> payload) {
  final Map<String, dynamic>? warnings = frameProductionWarning();
  if (warnings != null) {
    payload['warnings'] = warnings;
  }

  return developer.ServiceExtensionResponse.result(jsonEncode(payload));
}
