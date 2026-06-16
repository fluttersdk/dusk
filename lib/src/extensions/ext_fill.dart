import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:fluttersdk_artisan/artisan.dart';

import '../ref_registry.dart';
import '../utils/dusk_exceptions.dart';
import '../utils/error_envelope.dart';
import 'ext_focus.dart' show aiTestFocusHandler;
import 'ext_pointer.dart' show resolveRefForAction;
import 'ext_snapshot.dart' show duskSnapBuild;
import 'ext_text_input.dart' show aiTestClearHandler, aiTestTypeHandler;

const String kDuskFillMcpName = 'dusk_fill';
const String kDuskFillMcpExtension = 'ext.dusk.fill';

/// Registers the `ext.dusk.fill` VM Service extension.
///
/// Idempotent: [registerExtensionIdempotent] swallows the [ArgumentError]
/// thrown on hot-restart duplicate registration. Call once from
/// [registerAllDuskExtensions].
void registerFillExtension() {
  registerExtensionIdempotent(kDuskFillMcpExtension, aiTestFillHandler);
}

/// Parses the optional `'true' | 'false'` flag [params] field [name],
/// returning [defaultValue] when missing or empty. Mirrors the helper in
/// `ext_pointer.dart`; kept local so the file is self-contained.
bool _parseBoolFlag(
  Map<String, String> params,
  String name, {
  required bool defaultValue,
}) {
  final String? raw = params[name];
  if (raw == null || raw.isEmpty) return defaultValue;
  return raw != 'false' && raw != '0';
}

/// Handler for `ext.dusk.fill`: the one-call "focus + clear + type + settle"
/// composition that replaces the manual dance agents otherwise re-discover.
///
/// Composes the three existing handlers verbatim so IME-focus, controller-write,
/// and snapshot semantics are never re-implemented. The actionability gate is
/// carried by the `type` step (the actual mutation); `focus`/`clear` do not run
/// `ensureActionable`, so the gate gates the write, not the focus/clear:
/// 1. [aiTestFocusHandler] grants keyboard focus on the resolved field.
/// 2. [aiTestClearHandler] empties the backing [TextEditingController].
/// 3. [aiTestTypeHandler] runs the actionability gate, then sets [params]['text']
///    via `userUpdateTextEditingValue` (so `onChanged` fires and form validators
///    run) and awaits two frames.
///
/// Stale-retry: the ref is re-resolved up front via [resolveRefForAction]
/// before each attempt. A `q<N>` handle whose stored predicates transiently
/// miss (mid-rebuild) throws [DuskStaleHandleException]; the handler retries
/// the whole resolve + focus + clear + type sequence ONCE so the second pass
/// re-walks the now-settled tree. A second stale outcome propagates a typed
/// `stale` envelope so the agent re-snaps or re-finds.
///
/// Params:
/// - `ref` (required): `e<N>` / `q<N>` token of the target text field.
/// - `text` (required): the value to set (empty string clears the field).
/// - `checkStable` / `checkReceivesEvents` (optional, default `'true'`):
///   actionability-gate opt-outs threaded into the type step.
/// - `includeSnapshot` (optional, default `'true'`): when `'false'`, skip the
///   post-fill accessibility snapshot.
///
/// Response (success, default):
/// ```json
/// { "ref": "e3", "text": "typed value", "filled": true, "snapshot": "<yaml>" }
/// ```
Future<developer.ServiceExtensionResponse> aiTestFillHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    final String? ref = params['ref'];
    if (ref == null || ref.isEmpty) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.fill: missing required param "ref"',
          DuskErrorEnvelope.missingParam('ref'),
        ),
      );
    }
    if (!params.containsKey('text')) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.fill: missing required param "text"',
          DuskErrorEnvelope.missingParam('text'),
        ),
      );
    }

    // 1. Run the resolve + focus + clear + type sequence once. On a stale
    //    handle retry the whole sequence a single time; the second pass
    //    re-resolves the ref against the now-settled tree before the steps.
    developer.ServiceExtensionResponse? outcome = await _attemptFill(params);
    outcome ??= await _attemptFill(params);
    if (outcome == null) {
      // Two consecutive stale resolutions: the handle is genuinely gone.
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.fill: ref "$ref" went stale during fill (retried once)',
          DuskErrorEnvelope.stale(ref),
        ),
      );
    }

    // 2. Any non-stale failure (gate, not-found, IME) propagates verbatim so
    //    the agent sees the original sub-step envelope.
    if (outcome.errorCode != null) {
      return outcome;
    }

    // 3. Decode the type step's payload (carries `text`) and surface the
    //    fill-shaped success envelope. Append the post-fill snapshot unless
    //    opted out; the type step already awaited two frames so the tree is
    //    settled.
    final Map<String, dynamic> typed =
        jsonDecode(outcome.result!) as Map<String, dynamic>;
    final Map<String, dynamic> payload = <String, dynamic>{
      'ref': ref,
      'text': typed['text'] ?? params['text'],
      'filled': true,
    };
    if (_parseBoolFlag(params, 'includeSnapshot', defaultValue: true)) {
      try {
        final Map<String, dynamic> snap = await duskSnapBuild();
        payload['snapshot'] = snap['snapshot'];
      } catch (e) {
        developer.log(
          '[fluttersdk_dusk] ext.dusk.fill: post-fill snapshot build swallowed '
          'for ref "$ref": $e',
          name: 'fluttersdk_dusk',
        );
      }
    }
    return developer.ServiceExtensionResponse.result(jsonEncode(payload));
  } catch (e, stackTrace) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.fill error: $e\n$stackTrace',
      name: 'dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), DuskErrorEnvelope.unexpected()),
    );
  }
}

/// Runs one resolve + focus + clear + type pass over the composed gated
/// handlers.
///
/// Returns `null` when the ref resolves stale (so the caller can retry once),
/// the first failing sub-response when any gated step errors (so its envelope
/// is preserved verbatim), or the successful type response (carrying the
/// `text` payload) on success. Focus / clear sub-responses run for their side
/// effects with `includeSnapshot: 'false'`; only the final composed payload
/// carries the accessibility tree.
Future<developer.ServiceExtensionResponse?> _attemptFill(
  Map<String, String> params,
) async {
  final String ref = params['ref']!;

  // Re-resolve up front so a transiently-missing q-handle surfaces as a
  // retriable stale (null) rather than an opaque sub-handler failure.
  try {
    final RefEntry? entry = resolveRefForAction(ref);
    if (entry == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.fill: ref "$ref" not found in registry',
          DuskErrorEnvelope.notFound(
            ref: ref,
            candidates: collectSnapshotCandidates(),
          ),
        ),
      );
    }
  } on DuskStaleHandleException {
    return null;
  }

  final Map<String, String> stepParams = <String, String>{
    'ref': ref,
    'includeSnapshot': 'false',
    if (params.containsKey('checkStable'))
      'checkStable': params['checkStable']!,
    if (params.containsKey('checkReceivesEvents'))
      'checkReceivesEvents': params['checkReceivesEvents']!,
  };

  // 1. Focus the field. A not-found / gate failure short-circuits here.
  final developer.ServiceExtensionResponse focus =
      await aiTestFocusHandler('ext.dusk.focus', stepParams);
  if (focus.errorCode != null) return focus;
  await WidgetsBinding.instance.endOfFrame;

  // 2. Clear the existing value so the type below is a replace, not an append.
  final developer.ServiceExtensionResponse clear =
      await aiTestClearHandler('ext.dusk.clear', stepParams);
  if (clear.errorCode != null) return clear;
  await WidgetsBinding.instance.endOfFrame;

  // 3. Type the new value. The gated type handler awaits two frames itself.
  return aiTestTypeHandler('ext.dusk.type', <String, String>{
    ...stepParams,
    'text': params['text']!,
  });
}
