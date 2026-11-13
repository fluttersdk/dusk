import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:dowel/dowel.dart';

import '../ref_registry.dart';
import '../utils/tapir_exceptions.dart';
import '../utils/tapir_register.dart';
import '../utils/tapir_response.dart';
import '../utils/error_envelope.dart';
import '../utils/frame_sync.dart';
import '../utils/perf_interaction.dart';
import 'ext_pointer.dart' show resolveRefForAction;
import 'ext_snapshot.dart' show snapshotForAction;
import 'ext_text_input.dart'
    show
        TextFieldTarget,
        aiTestClearHandler,
        aiTestTypeHandler,
        refuseNonTextRef,
        resolveTextFieldTarget;

const String kTapirFillMcpName = 'tapir_fill';
const String kTapirFillMcpExtension = 'ext.tapir.fill';

/// Registers the `ext.tapir.fill` VM Service extension.
///
/// Idempotent: [registerExtensionIdempotent] swallows the [ArgumentError]
/// thrown on hot-restart duplicate registration. Call once from
/// [registerAllTapirExtensions].
void registerFillExtension() {
  registerTapirExtension(kTapirFillMcpExtension, aiTestFillHandler);
}

/// Handler for `ext.tapir.fill`: the one-call "focus + clear + type + settle"
/// composition that replaces the manual dance agents otherwise re-discover.
///
/// Resolves the field once ([resolveTextFieldTarget]) and hands it to the
/// clear and type handlers, so both write the same editable and the
/// controller-write and snapshot semantics are never re-implemented. A ref
/// whose node is a non-text control is refused before anything is touched
/// ([refuseNonTextRef]). The actionability gate is carried by the `type` step
/// (the actual mutation), so the gate gates the write, not the focus/clear:
/// 1. The resolved field's focus node takes keyboard focus.
/// 2. [aiTestClearHandler] empties the backing [TextEditingController].
/// 3. [aiTestTypeHandler] runs the actionability gate, then sets [params]['text']
///    via `userUpdateTextEditingValue` (so `onChanged` fires and form validators
///    run), awaits two frames and reads the settled value back.
///
/// Stale-retry: the ref is re-resolved up front via [resolveRefForAction]
/// before each attempt. A `q<N>` handle whose stored predicates transiently
/// miss (mid-rebuild) throws [TapirStaleHandleException]; the handler retries
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
/// - `snapshot` (optional, `full` | `diff` | `none`): overrides
///   `includeSnapshot`; see [snapshotForAction]. The clear and type steps run
///   with no snapshot of their own, so a `diff` is against the snapshot taken
///   before the fill.
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
          'ext.tapir.fill: missing required param "ref"',
          TapirErrorEnvelope.missingParam('ref'),
        ),
      );
    }
    if (!params.containsKey('text')) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.tapir.fill: missing required param "text"',
          TapirErrorEnvelope.missingParam('text'),
        ),
      );
    }

    // 1. Run the resolve + focus + clear + type sequence once. On a stale
    //    handle retry the whole sequence a single time; the second pass
    //    re-resolves the ref against the now-settled tree before the steps.
    //    One interaction spans both passes: the focus, clear and type steps
    //    join it rather than opening three.
    final developer.ServiceExtensionResponse? outcome =
        await runPerfInteraction(
      'fill',
      ref,
      () async => await _attemptFill(params) ?? await _attemptFill(params),
    );
    if (outcome == null) {
      // Two consecutive stale resolutions: the handle is genuinely gone.
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.tapir.fill: ref "$ref" went stale during fill (retried once)',
          TapirErrorEnvelope.stale(ref),
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
      // The type step read the value back off the live controller; carry
      // that verdict up rather than restating `filled: true`, which only
      // says the sequence ran.
      if (typed['effect'] != null) 'effect': typed['effect'],
    };
    try {
      payload.addAll(await snapshotForAction(params));
    } catch (e) {
      developer.log(
        '[tapir] ext.tapir.fill: post-fill snapshot build swallowed '
        'for ref "$ref": $e',
        name: 'tapir',
      );
    }
    return tapirResult(payload);
  } catch (e, stackTrace) {
    developer.log(
      '[tapir] ext.tapir.fill error: $e\n$stackTrace',
      name: 'tapir',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), TapirErrorEnvelope.unexpected()),
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
  final RefEntry? entry;
  try {
    entry = resolveRefForAction(ref);
  } on TapirStaleHandleException {
    return null;
  }
  if (entry == null) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.tapir.fill: ref "$ref" not found in registry',
        TapirErrorEnvelope.notFound(
          ref: ref,
          candidates: collectSnapshotCandidates(),
        ),
      ),
    );
  }

  // 1. Refuse a non-text control before anything is touched, then resolve
  //    the field ONCE. Clear and type each ranking the tree on their own
  //    is how a dropdown ref came to wipe and rewrite the nearest field.
  final developer.ServiceExtensionResponse? refusal = refuseNonTextRef(
    verb: 'fill',
    ref: ref,
    entry: entry,
  );
  if (refusal != null) return refusal;
  final TextFieldTarget? target = resolveTextFieldTarget(
    entry: entry,
    element: entry.element,
  );
  if (target == null) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(
        'ext.tapir.fill: no EditableText under ref "$ref"',
        TapirErrorEnvelope.unexpected(widgetPath: ref),
      ),
    );
  }

  final Map<String, String> stepParams = <String, String>{
    'ref': ref,
    'includeSnapshot': 'false',
    if (params.containsKey('checkStable'))
      'checkStable': params['checkStable']!,
    if (params.containsKey('checkReceivesEvents'))
      'checkReceivesEvents': params['checkReceivesEvents']!,
  };

  // 2. Focus the resolved field itself. The focus verb walks the ref's
  //    element, which for a snapshot-minted ref is the app root, so it would
  //    focus the first field on the form.
  target.state.widget.focusNode.requestFocus();
  await awaitFrameOrTimeout();

  // 3. Clear the existing value so the type below is a replace, not an append.
  final developer.ServiceExtensionResponse clear = await aiTestClearHandler(
    'ext.tapir.clear',
    stepParams,
    target: target,
  );
  if (clear.errorCode != null) return clear;
  await awaitFrameOrTimeout();

  // 4. Type the new value. The gated type handler awaits two frames itself.
  return aiTestTypeHandler(
    'ext.tapir.type',
    <String, String>{
      ...stepParams,
      'text': params['text']!,
    },
    target: target,
  );
}
