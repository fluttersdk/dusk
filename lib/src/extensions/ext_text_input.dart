import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../ref_registry.dart';
import '../utils/actionability_gate.dart';
import '../utils/dusk_exceptions.dart';
import '../utils/dusk_response.dart';
import '../utils/effect_report.dart';
import '../utils/error_envelope.dart';
import '../utils/frame_sync.dart';
import '../utils/perf_interaction.dart';
import 'ext_pointer.dart';
import 'ext_snapshot.dart' show duskSnapBuild;
import 'package:fluttersdk_artisan/artisan.dart';

/// Parses the optional `'true' | 'false'` flag [params] field [name],
/// returning [defaultValue] when missing or empty. Mirrors the helper in
/// `ext_pointer.dart` — kept local to keep this file self-contained.
bool _parseBoolFlag(
  Map<String, String> params,
  String name, {
  required bool defaultValue,
}) {
  final String? raw = params[name];
  if (raw == null || raw.isEmpty) return defaultValue;
  return raw != 'false' && raw != '0';
}

/// Builds the post-action snapshot YAML and appends it under the
/// `snapshot` key of [payload], unless [params] sets
/// `includeSnapshot: 'false'`. See `ext_pointer.dart` for the rationale.
Future<void> _appendSnapshotIfRequested(
  Map<String, dynamic> payload,
  Map<String, String> params,
) async {
  if (!_parseBoolFlag(params, 'includeSnapshot', defaultValue: true)) {
    return;
  }
  final Map<String, dynamic> snap = await duskSnapBuild();
  payload['snapshot'] = snap['snapshot'];
}

// ---------------------------------------------------------------------------
// Logical key lookup table
// ---------------------------------------------------------------------------

/// A key as a real press carries it: both halves of its identity, and the
/// text it types, if it types any.
typedef _Key = ({
  LogicalKeyboardKey logical,
  PhysicalKeyboardKey physical,
  String? character,
});

/// Resolves an agent-facing key name to the key a real press would carry, or
/// null when it names nothing.
///
/// A name in [_kKeyMap] matches case-insensitively, since agents call
/// `dusk:press_key --key=TAB` or `--key=enter` and the canonical names are
/// PascalCase. A single letter or digit is the key that types it: `G` and `g`
/// both press the G key and type `g`, so a shortcut bound to a letter can be
/// driven. Anything else is refused rather than guessed at.
_Key? _lookupKey(String input) {
  final _Key? direct = _kKeyMap[input];
  if (direct != null) return direct;

  final String lowered = input.toLowerCase();
  for (final MapEntry<String, _Key> entry in _kKeyMap.entries) {
    if (entry.key.toLowerCase() == lowered) return entry.value;
  }

  return _characterKey(lowered);
}

/// The key that types [character], for one lowercase ASCII letter or digit;
/// null for anything else.
///
/// The physical side is the USB HID usage the platform would report: letters
/// run from `0x00070004` (A), digits from `0x0007001e` (1) to `0x00070027`
/// (0). The logical side of a printable key is its own code point.
_Key? _characterKey(String character) {
  if (character.length != 1) return null;

  final int unit = character.codeUnitAt(0);
  final int? usage = switch (unit) {
    >= 0x61 && <= 0x7a => 0x00070004 + unit - 0x61,
    0x30 => 0x00070027,
    >= 0x31 && <= 0x39 => 0x0007001e + unit - 0x31,
    _ => null,
  };

  if (usage == null) return null;

  return (
    logical: LogicalKeyboardKey(unit),
    physical: PhysicalKeyboardKey(usage),
    character: character,
  );
}

/// Maps agent-facing key name strings to the keys a real press carries.
///
/// The table covers the named keys LLM agents commonly target during form
/// navigation (Tab, Enter, Escape) and list navigation (arrows); a single
/// letter or digit is resolved by [_characterKey] instead. Unknown names
/// cause [pressKey] to throw [ArgumentError] rather than silently emitting a
/// no-op, which surfaces misconfigured agent payloads immediately.
const Map<String, _Key> _kKeyMap = <String, _Key>{
  'Enter': (
    logical: LogicalKeyboardKey.enter,
    physical: PhysicalKeyboardKey.enter,
    character: null,
  ),
  'Tab': (
    logical: LogicalKeyboardKey.tab,
    physical: PhysicalKeyboardKey.tab,
    character: null,
  ),
  'Escape': (
    logical: LogicalKeyboardKey.escape,
    physical: PhysicalKeyboardKey.escape,
    character: null,
  ),
  'Backspace': (
    logical: LogicalKeyboardKey.backspace,
    physical: PhysicalKeyboardKey.backspace,
    character: null,
  ),
  'Delete': (
    logical: LogicalKeyboardKey.delete,
    physical: PhysicalKeyboardKey.delete,
    character: null,
  ),
  'Space': (
    logical: LogicalKeyboardKey.space,
    physical: PhysicalKeyboardKey.space,
    character: ' ',
  ),
  'ArrowUp': (
    logical: LogicalKeyboardKey.arrowUp,
    physical: PhysicalKeyboardKey.arrowUp,
    character: null,
  ),
  'ArrowDown': (
    logical: LogicalKeyboardKey.arrowDown,
    physical: PhysicalKeyboardKey.arrowDown,
    character: null,
  ),
  'ArrowLeft': (
    logical: LogicalKeyboardKey.arrowLeft,
    physical: PhysicalKeyboardKey.arrowLeft,
    character: null,
  ),
  'ArrowRight': (
    logical: LogicalKeyboardKey.arrowRight,
    physical: PhysicalKeyboardKey.arrowRight,
    character: null,
  ),
  'Home': (
    logical: LogicalKeyboardKey.home,
    physical: PhysicalKeyboardKey.home,
    character: null,
  ),
  'End': (
    logical: LogicalKeyboardKey.end,
    physical: PhysicalKeyboardKey.end,
    character: null,
  ),
  'PageUp': (
    logical: LogicalKeyboardKey.pageUp,
    physical: PhysicalKeyboardKey.pageUp,
    character: null,
  ),
  'PageDown': (
    logical: LogicalKeyboardKey.pageDown,
    physical: PhysicalKeyboardKey.pageDown,
    character: null,
  ),
  'F1': (
    logical: LogicalKeyboardKey.f1,
    physical: PhysicalKeyboardKey.f1,
    character: null,
  ),
  'F2': (
    logical: LogicalKeyboardKey.f2,
    physical: PhysicalKeyboardKey.f2,
    character: null,
  ),
  'F3': (
    logical: LogicalKeyboardKey.f3,
    physical: PhysicalKeyboardKey.f3,
    character: null,
  ),
  'F4': (
    logical: LogicalKeyboardKey.f4,
    physical: PhysicalKeyboardKey.f4,
    character: null,
  ),
  'F5': (
    logical: LogicalKeyboardKey.f5,
    physical: PhysicalKeyboardKey.f5,
    character: null,
  ),
  'F6': (
    logical: LogicalKeyboardKey.f6,
    physical: PhysicalKeyboardKey.f6,
    character: null,
  ),
  'F7': (
    logical: LogicalKeyboardKey.f7,
    physical: PhysicalKeyboardKey.f7,
    character: null,
  ),
  'F8': (
    logical: LogicalKeyboardKey.f8,
    physical: PhysicalKeyboardKey.f8,
    character: null,
  ),
  'F9': (
    logical: LogicalKeyboardKey.f9,
    physical: PhysicalKeyboardKey.f9,
    character: null,
  ),
  'F10': (
    logical: LogicalKeyboardKey.f10,
    physical: PhysicalKeyboardKey.f10,
    character: null,
  ),
  'F11': (
    logical: LogicalKeyboardKey.f11,
    physical: PhysicalKeyboardKey.f11,
    character: null,
  ),
  'F12': (
    logical: LogicalKeyboardKey.f12,
    physical: PhysicalKeyboardKey.f12,
    character: null,
  ),
};

// ---------------------------------------------------------------------------
// TestRefRegistry — test-only injection point
// ---------------------------------------------------------------------------

/// In-test registry that allows test code to inject an [Element] for a given
/// ref string so that [aiTestTypeHandler] can resolve it without a live
/// [RefRegistry] (which lands in Step 6, a parallel step).
///
/// This class is only instantiated during testing. Production code routes
/// through the real [RefRegistry] from Step 6. The test-only surface is
/// kept minimal: [inject] / [clear].
@visibleForTesting
class TestRefRegistry {
  TestRefRegistry._();

  static final Map<String, Element> _entries = <String, Element>{};

  /// Injects [element] under [ref] for the duration of a single test.
  ///
  /// Call [clear] in an `addTearDown` callback to avoid leaking across tests.
  static void inject(String ref, Element element) => _entries[ref] = element;

  /// Removes all injected entries. Call from `addTearDown`.
  static void clear() => _entries.clear();

  /// Resolves a ref to its [Element], or `null` when the ref is unknown.
  static Element? lookup(String ref) => _entries[ref];
}

// ---------------------------------------------------------------------------
// Internal helpers — @visibleForTesting so tests drive them directly
// ---------------------------------------------------------------------------

/// Sets [text] into the [EditableText] backed by [element].
///
/// Steps:
/// 1. Locate the [EditableTextState] from [element] via descendant walk when
///    [element] is a parent widget (e.g. TextField) that hosts an EditableText.
/// 2. Call [EditableTextState.requestKeyboard] to focus the field so that the
///    engine's IME state stays coherent after the mutation.
/// 3. Primary path: read [EditableText.controller] from the state's widget and
///    set [TextEditingController.value] directly (confirmed by spike: PASS).
/// 4. Fallback path: if the controller is inaccessible (e.g. custom subclass
///    with a private controller), send a platform message on the
///    `flutter/textinput` channel using [TextInputClient.updateEditingState].
///
/// Frame awaiting is the caller's responsibility. In widget tests, call
/// `tester.pump()` after this function returns. In the production VM Service
/// handler ([aiTestTypeHandler]), two [WidgetsBinding.instance.endOfFrame]
/// awaits are performed before returning the response.
@visibleForTesting
Future<String?> typeIntoElement({
  required Element element,
  required String text,
  Rect? targetRect,
}) async {
  // 1. Resolve the EditableTextState. A ref minted from a SemanticsNode carries
  //    the app-root element (see ext_find `_entryFromSemanticsNode`), so a plain
  //    descendant-first walk from it returns the FIRST EditableText in the tree,
  //    sending every type/fill on a multi-field form to field #1. When the ref's
  //    on-screen rect is known, select the editable whose global rect matches it
  //    so the correct, visible field is written; fall back to the element walk.
  final EditableTextState? state =
      (targetRect != null ? _findEditableTextStateByRect(targetRect) : null) ??
          _resolveEditableTextState(element);
  if (state == null) {
    throw ArgumentError(
      '[fluttersdk_dusk] typeIntoElement: no EditableText found in or under '
      'element $element',
    );
  }

  // 2. Focus the field so the engine IME state is coherent after mutation.
  state.requestKeyboard();

  // 3. Primary path — emulate user input via Flutter's official user-input
  //    API. `userUpdateTextEditingValue` updates the controller AND fires the
  //    EditableText.onChanged / TextField.onChanged listeners, which is the
  //    path Wind WFormInput (and any parent in controlled-via-onChanged
  //    pattern) depends on. Naive `controller.value = ...` setter only
  //    notifies ValueListenable subscribers — Wind's parent onChanged stays
  //    silent and form-data backing controllers receive the empty initial
  //    value, causing 422 "required" validation failures on submit.
  //
  //    Source: EditableTextState.userUpdateTextEditingValue is the canonical
  //    pathway TextField + EditableText invoke when the user types a key.
  final TextEditingValue newValue = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

  bool injected = false;
  try {
    state.userUpdateTextEditingValue(newValue, SelectionChangedCause.keyboard);
    injected = true;
  } catch (e) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.type: userUpdateTextEditingValue threw $e; '
      'falling back to controller.value setter',
      name: 'fluttersdk_dusk',
    );
  }

  if (!injected) {
    // 3b. Fallback when userUpdateTextEditingValue is unavailable (older
    //     Flutter) — set the controller directly. May leave parent listeners
    //     unfired; only used as a defensive last resort.
    final TextEditingController? controller = _extractController(state);
    if (controller != null) {
      controller.value = newValue;
      injected = true;
    }
  }

  if (!injected) {
    // 4. Fallback path — platform message when controller is inaccessible.
    //    SystemChannels.textInput.setEditingState is a confirmed NO-OP outside
    //    test binding (Flutter #87990 / wave-1-spike finding 5). Instead, call
    //    handlePlatformMessage on the 'flutter/textinput' channel directly so
    //    the engine receives the update through the internal message path.
    developer.log(
      '[fluttersdk_dusk] ext.dusk.type: primary path unavailable, using '
      'platform-message fallback',
      name: 'fluttersdk_dusk',
    );

    final ByteData? encodedMessage = const JSONMessageCodec().encodeMessage(
      <String, dynamic>{
        'method': 'TextInputClient.updateEditingState',
        'args': <dynamic>[
          -1,
          <String, dynamic>{
            'text': text,
            'selectionBase': text.length,
            'selectionExtent': text.length,
            'selectionAffinity': 'TextAffinity.downstream',
            'selectionIsDirectional': false,
            'composingBase': -1,
            'composingExtent': -1,
          },
        ],
      },
    );

    if (encodedMessage != null) {
      ServicesBinding.instance.channelBuffers.push(
        'flutter/textinput',
        encodedMessage,
        (_) {},
      );
    }
  }

  // 5. Read the value back off the live state rather than echoing [text].
  //    An input formatter or a keyboard type can filter the write, and the
  //    caller has no way to tell that from a clean success otherwise.
  return state.textEditingValue.text;
}

/// Presses [key] down and lets it up again, the way a keyboard does.
///
/// Both events enter through the binding's `onKeyData`, the handler the
/// platform delivers real key data to, so they reach [HardwareKeyboard] AND
/// the focus tree, where `Focus.onKeyEvent` and `Shortcuts` listen. Handing
/// them to [HardwareKeyboard.handleKeyEvent] directly reaches only the
/// keyboard's global handlers and no focused widget ever hears the key. They
/// are marked synthesized, which is what makes the binding dispatch each at
/// once rather than hold it for a raw event that never follows.
///
/// [key] is a name from the supported table (Enter, Tab, Escape, ArrowDown,
/// ...) or a single letter or digit. Throws [ArgumentError] for anything else,
/// which surfaces misconfigured agent payloads immediately rather than
/// silently emitting a no-op, and [StateError] when the binding has no key
/// data handler to deliver to.
///
/// The [modifiers] parameter is accepted by the public handler but not yet
/// wired to synthesized modifier keys; it is reserved for future use.
@visibleForTesting
Future<void> pressKey({
  required String key,
  List<String> modifiers = const <String>[],
}) async {
  final _Key? resolved = _lookupKey(key);
  if (resolved == null) {
    throw ArgumentError(
      '[fluttersdk_dusk] ext.dusk.press_key: unknown key "$key". '
      'Supported keys: ${_kKeyMap.keys.join(', ')}, or one letter or digit',
    );
  }

  final ui.KeyDataCallback? deliver =
      ServicesBinding.instance.platformDispatcher.onKeyData;
  if (deliver == null) {
    throw StateError(
      '[fluttersdk_dusk] ext.dusk.press_key: the binding has no key data '
      'handler to deliver "$key" to',
    );
  }

  final Duration now = Duration(
    microseconds: DateTime.now().microsecondsSinceEpoch,
  );

  deliver(_keyData(resolved, ui.KeyEventType.down, now));
  deliver(
    _keyData(
      resolved,
      ui.KeyEventType.up,
      now + const Duration(milliseconds: 16),
    ),
  );
}

/// [key] as the platform reports one half of a press; only the down half
/// types its character.
ui.KeyData _keyData(_Key key, ui.KeyEventType type, Duration timeStamp) {
  return ui.KeyData(
    timeStamp: timeStamp,
    type: type,
    physical: key.physical.usbHidUsage,
    logical: key.logical.keyId,
    character: type == ui.KeyEventType.down ? key.character : null,
    synthesized: true,
  );
}

// ---------------------------------------------------------------------------
// VM Service extension handlers
// ---------------------------------------------------------------------------

/// Handler for the `ext.dusk.type` VM Service extension.
///
/// Params (all string-valued as per [developer.ServiceExtensionHandler]):
/// - `ref` (required): a ref string (`eN`) from a prior snapshot response;
///   resolved to an [Element] via [RefRegistry] (Step 6) or [TestRefRegistry]
///   during tests.
/// - `text` (required): the text value to set on the field.
/// - `checkStable` / `checkReceivesEvents` (optional, default `'true'`):
///   Playwright actionability opt-outs. Set to `'false'` in tests with
///   synthetic [RefEntry] rects so the gate does not trip on geometry
///   mismatch.
/// - `includeSnapshot` (optional, default `'true'`): when `'false'`, skip
///   embedding the post-action accessibility snapshot in the response.
///
/// Response (success, default):
/// ```json
/// { "text": "typed value", "snapshot": "<yaml>" }
/// ```
Future<developer.ServiceExtensionResponse> aiTestTypeHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    final String? ref = params['ref'];
    final String text = params['text'] ?? '';

    if (ref == null || ref.isEmpty) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          '[fluttersdk_dusk] ext.dusk.type: missing required param "ref"',
          DuskErrorEnvelope.missingParam('ref'),
        ),
      );
    }

    // 1. Resolve via the production registry first so the actionability gate
    //    (Step 15) can run with a real RefEntry. q-shape refs re-execute the
    //    stored Semantics query against the live tree (Step 16); e-shape
    //    refs go through [RefRegistry.lookup]. The TestRefRegistry path is
    //    only consulted when the production registry has no entry; tests
    //    that need to exercise the gate must register through
    //    [RefRegistry.registerForTesting] instead of [TestRefRegistry.inject].
    final RefEntry? entry;
    try {
      entry = resolveRefForAction(ref);
    } on DuskStaleHandleException catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(e.message, DuskErrorEnvelope.stale(ref)),
      );
    }
    // Null when no entry resolved, so no gate ran and there is nothing to
    // report. `fill` delegates here, which is the verb whose silent clean
    // pass motivated the block in the first place.
    ActionabilityReport? gate;
    if (entry != null) {
      // Step 3.1: stable + receives-events gates default on; opt-out via
      // params for tests with synthetic rect.
      final bool checkStable =
          _parseBoolFlag(params, 'checkStable', defaultValue: true);
      final bool checkReceivesEvents =
          _parseBoolFlag(params, 'checkReceivesEvents', defaultValue: true);
      try {
        gate = await ensureActionable(
          entry,
          ref: ref,
          checkStable: checkStable,
          checkReceivesEvents: checkReceivesEvents,
        );
      } on DuskActionabilityException catch (e) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          wrapErrorDetail(
            e.message,
            DuskErrorEnvelope.fromActionabilityReason(e.ref, e.reason),
          ),
        );
      }
    }

    final Element? element = entry?.element ?? TestRefRegistry.lookup(ref);
    if (element == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          '[fluttersdk_dusk] ext.dusk.type: ref "$ref" not found in registry',
          DuskErrorEnvelope.notFound(
            ref: ref,
            candidates: collectSnapshotCandidates(),
          ),
        ),
      );
    }

    final String? written = await runPerfInteraction(
      'type',
      ref,
      () => typeIntoElement(
        element: element,
        text: text,
        targetRect: _localToGlobalRectForNode(entry?.node) ?? entry?.rect,
      ),
    );

    // Wait two frames so ValueListenableBuilder listeners rebuild and paint
    // before the MCP client reads state (per Stage 3 mandate: every mutating
    // extension awaits endOfFrame before returning).
    await awaitFramesOrTimeout(2);

    // 2. Report what the field HOLDS, not what it was handed. `text` stays
    //    for callers that read it, but `effect.value` is the one read back
    //    off the live controller, and `effect.verified` is false when a
    //    formatter or keyboard type filtered the write.
    final Map<String, dynamic> payload = <String, dynamic>{
      'text': text,
      'effect': textEffect(expected: text, actual: written),
    };
    if (gate != null) stampChecks(payload, gate);

    // 3. Embed post-action snapshot (opt-out via includeSnapshot:'false').
    //    Snapshot-build noise must NOT convert a successful type into an
    //    error envelope: the text has already landed in the controller.
    try {
      await _appendSnapshotIfRequested(payload, params);
    } catch (e) {
      developer.log(
        '[fluttersdk_dusk] ext.dusk.type: post-dispatch snapshot build swallowed '
        'for ref "$ref": $e',
        name: 'fluttersdk_dusk',
      );
    }

    return duskResult(payload);
  } catch (e, stackTrace) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.type error: $e\n$stackTrace',
      name: 'fluttersdk_dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), DuskErrorEnvelope.unexpected()),
    );
  }
}

/// Handler for the `ext.dusk.press_key` VM Service extension.
///
/// Params:
/// - `key` (required): key name string from the supported lookup table
///   (Enter, Tab, Escape, ArrowUp, ArrowDown, etc.).
/// - `modifiers` (optional): comma-separated modifier names; accepted but
///   not yet applied to the dispatched event (reserved for future use).
/// - `includeSnapshot` (optional, default `'true'`): when `'false'`, skip
///   embedding the post-action accessibility snapshot in the response.
///
/// Response (success, default):
/// ```json
/// { "ok": true, "key": "Enter", "snapshot": "<yaml>" }
/// ```
Future<developer.ServiceExtensionResponse> aiTestPressKeyHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    final String? key = params['key'];
    if (key == null || key.isEmpty) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          '[fluttersdk_dusk] ext.dusk.press_key: missing required param "key"',
          DuskErrorEnvelope.missingParam('key'),
        ),
      );
    }

    final List<String> modifiers = params['modifiers']
            ?.split(',')
            .map((String s) => s.trim())
            .where((String s) => s.isNotEmpty)
            .toList() ??
        <String>[];

    await runPerfInteraction<void>(
      'press_key',
      key,
      () => pressKey(key: key, modifiers: modifiers),
    );

    // Wait two frames before snapshotting so any rebuild triggered by the
    // key (e.g. Tab moving focus, Enter submitting a form) lands in the
    // post-action accessibility tree. Pre-Step-3.2 this handler skipped
    // the endOfFrame await entirely — research flagged the shortfall.
    // Guard on rootElement: when no widget tree is mounted (headless /
    // bare `test()` contexts) the endOfFrame future never completes
    // without a frame scheduler, so we skip the awaits and the snapshot
    // embed below. Mirrors the same guard in ext_navigation.dart.
    if (WidgetsBinding.instance.rootElement != null) {
      await awaitFramesOrTimeout(2);
    }

    final Map<String, dynamic> payload = <String, dynamic>{
      'ok': true,
      'key': key,
    };
    // Snapshot build needs a live widget tree; in headless test contexts
    // (plain `test()` with no `pumpWidget`) the walk produces an empty
    // YAML and we omit the embed so the existing back-compat shape
    // `{ok, key}` survives verbatim.
    if (WidgetsBinding.instance.rootElement != null) {
      try {
        await _appendSnapshotIfRequested(payload, params);
      } catch (e) {
        developer.log(
          '[fluttersdk_dusk] ext.dusk.press_key: post-dispatch snapshot build '
          'swallowed for key "$key": $e',
          name: 'fluttersdk_dusk',
        );
      }
    }

    return duskResult(payload);
  } catch (e, stackTrace) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.press_key error: $e\n$stackTrace',
      name: 'fluttersdk_dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), DuskErrorEnvelope.unexpected()),
    );
  }
}

// ---------------------------------------------------------------------------
// Self-registration entry point
// ---------------------------------------------------------------------------

/// Registers `ext.dusk.type` and `ext.dusk.press_key` as VM Service
/// extensions.
///
/// Idempotent: each registration routes through [registerExtensionIdempotent],
/// which catches the [ArgumentError] thrown by [developer.registerExtension]
/// on duplicate registration (hot-restart safety — per V3 plan Stage 3 D12).
///
/// Called from `extensions.dart#registerAllAiTestExtensions()` once the Step
/// 14b aggregator lands. May also be called standalone in tests.
void registerTextInputExtensions() {
  registerExtensionIdempotent('ext.dusk.type', aiTestTypeHandler);
  registerExtensionIdempotent('ext.dusk.press_key', aiTestPressKeyHandler);
  registerExtensionIdempotent('ext.dusk.clear', aiTestClearHandler);
}

/// Handler for `ext.dusk.clear` — empties the [TextEditingController] backing
/// the resolved text field. Playwright parity: `locator.clear()`.
///
/// Reuses [_resolveEditableTextState] + [_extractController] helpers so the
/// behavior matches [aiTestTypeHandler]'s text-write path. Returns the
/// post-clear value (empty string) plus an optional snapshot.
Future<developer.ServiceExtensionResponse> aiTestClearHandler(
  String method,
  Map<String, String> params,
) async {
  try {
    final String? ref = params['ref'];
    if (ref == null || ref.isEmpty) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.clear: missing required param "ref"',
          DuskErrorEnvelope.missingParam('ref'),
        ),
      );
    }
    final RefEntry? entry;
    try {
      entry = resolveRefForAction(ref);
    } on DuskStaleHandleException catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(e.message, DuskErrorEnvelope.stale(ref)),
      );
    }
    final Element? element = entry?.element ?? TestRefRegistry.lookup(ref);
    if (element == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.clear: ref "$ref" not found in registry',
          DuskErrorEnvelope.notFound(
            ref: ref,
            candidates: collectSnapshotCandidates(),
          ),
        ),
      );
    }
    final Rect? clearRect =
        _localToGlobalRectForNode(entry?.node) ?? entry?.rect;
    final EditableTextState? state =
        (clearRect != null ? _findEditableTextStateByRect(clearRect) : null) ??
            _resolveEditableTextState(element);
    if (state == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.clear: no EditableText under ref "$ref"',
          DuskErrorEnvelope.unexpected(),
        ),
      );
    }
    final TextEditingController? controller = _extractController(state);
    if (controller == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.dusk.clear: could not resolve TextEditingController',
          DuskErrorEnvelope.unexpected(),
        ),
      );
    }
    await runPerfInteraction<void>('clear', ref, () async {
      controller.clear();
    });
    await awaitFrameOrTimeout();
    // Read the controller back rather than asserting the clear worked. A
    // field whose parent rewrites the value on change lands back where it
    // was, and `text: ''` alone would report that as a clean clear.
    final Map<String, dynamic> payload = <String, dynamic>{
      'ref': ref,
      'text': '',
      'effect': textEffect(expected: '', actual: controller.text),
    };
    if (_parseBoolFlag(params, 'includeSnapshot', defaultValue: false)) {
      final snap = await duskSnapBuild();
      payload['snapshot'] = snap['snapshot'];
    }
    return duskResult(payload);
  } catch (e, stackTrace) {
    developer.log(
      '[fluttersdk_dusk] ext.dusk.clear error: $e\n$stackTrace',
      name: 'dusk',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), DuskErrorEnvelope.unexpected()),
    );
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Walks the element subtree rooted at [element] to find the first
/// [EditableTextState].
///
/// This handles both the case where [element] IS the [EditableText]'s element
/// and the case where it is a parent (e.g. [TextField]) that hosts the
/// [EditableText] as a descendant.
EditableTextState? _resolveEditableTextState(Element element) =>
    _firstEditableTextState(element, skipMuted: true) ??
    _firstEditableTextState(element, skipMuted: false);

/// The first [EditableTextState] at or under [element], skipping fields under
/// muted tickers when [skipMuted] is set (see [_isUnderMutedTickers]).
EditableTextState? _firstEditableTextState(
  Element element, {
  required bool skipMuted,
}) {
  // Direct hit: the element itself is the EditableText element.
  if (element is StatefulElement &&
      element.state is EditableTextState &&
      !(skipMuted && _isUnderMutedTickers(element))) {
    return element.state as EditableTextState;
  }

  // Descendant walk: dig one level into children to find an EditableText.
  EditableTextState? found;
  element.visitChildren((Element child) {
    if (found != null) return;
    found = _firstEditableTextState(child, skipMuted: skipMuted);
  });
  return found;
}

/// Selects the [EditableTextState] whose on-screen rect best matches
/// [targetRect] (the global rect of the ref the agent targeted).
///
/// Walks every [EditableText] from the app root and prefers the one whose rect
/// OVERLAPS [targetRect] by the largest area, falling back to the editable
/// nearest the target's center when none overlaps. Overlap-area ranking (not
/// center-containment) is used because a field's editable sits inside the
/// field's larger semantics rect, which also spans its label / decoration, so
/// a center-containment test mis-fires. This routes a `type`/`clear`/`fill` to
/// the field the agent actually targeted rather than the first editable in the
/// tree, and prefers the visible on-screen editable over any zero-sized
/// off-stage accessibility proxy (whose empty rect is skipped).
EditableTextState? _findEditableTextStateByRect(Rect targetRect) {
  // Any unmuted field beats every muted one, overlap or not. A covered route's
  // field overlapping a target that no visible field overlaps (a label handle
  // on a screen pushed over a lookalike) must still lose to the visible field,
  // and ranking a muted overlap above an unmuted nearest reopened exactly that.
  // The muted pass runs only when nothing unmuted exists, which is the app that
  // mutes a visible form on purpose; with an unmuted field elsewhere on screen
  // that app gets the unmuted one, a gap left open because nothing in the
  // ecosystem mutes a visible subtree and closing it needs a hit test, which
  // this package already documents as unreliable on web debug builds.
  final live = _rankEditableTextStates(targetRect, skipMuted: true);
  if (live.overlap != null || live.nearest != null) {
    return live.overlap ?? live.nearest;
  }

  final all = _rankEditableTextStates(targetRect, skipMuted: false);
  return all.overlap ?? all.nearest;
}

/// One ranking pass for [_findEditableTextStateByRect], skipping fields under
/// muted tickers when [skipMuted] is set.
///
/// Two passes rather than one filter: a covered route is the common reason a
/// field sits under muted tickers, but an app may mute a VISIBLE subtree on
/// purpose, and there the filter alone would leave no candidate and send every
/// write to the first field in the tree.
({EditableTextState? overlap, EditableTextState? nearest})
    _rankEditableTextStates(
  Rect targetRect, {
  required bool skipMuted,
}) {
  final Element? root = WidgetsBinding.instance.rootElement;
  if (root == null) return (overlap: null, nearest: null);
  final Offset target = targetRect.center;
  // Prefer the editable whose rect OVERLAPS the target the most (a field's own
  // editable sits inside the field's semantics rect, which also spans its label
  // / decoration, so center-containment mis-fires; overlap area does not). Fall
  // back to nearest-center only when nothing overlaps.
  EditableTextState? bestOverlap;
  double bestOverlapArea = 0;
  EditableTextState? nearest;
  double nearestDist = double.infinity;

  void visit(Element element) {
    if (element is StatefulElement &&
        element.state is EditableTextState &&
        !(skipMuted && _isUnderMutedTickers(element))) {
      final RenderObject? renderObject = element.renderObject;
      if (renderObject is RenderBox &&
          renderObject.attached &&
          renderObject.hasSize &&
          !renderObject.size.isEmpty) {
        final Rect rect =
            renderObject.localToGlobal(Offset.zero) & renderObject.size;
        final Rect overlap = rect.intersect(targetRect);
        final double area = (overlap.width > 0 && overlap.height > 0)
            ? overlap.width * overlap.height
            : 0;
        if (area > bestOverlapArea) {
          bestOverlapArea = area;
          bestOverlap = element.state as EditableTextState;
        } else if (bestOverlapArea == 0) {
          final double dist = (rect.center - target).distanceSquared;
          if (dist < nearestDist) {
            nearestDist = dist;
            nearest = element.state as EditableTextState;
          }
        }
      }
    }
    element.visitChildElements(visit);
  }

  root.visitChildElements(visit);
  return (overlap: bestOverlap, nearest: nearest);
}

/// Whether [element] sits under a `TickerMode(enabled: false)`.
///
/// A route covered by an opaque one is kept alive and laid out at its old
/// rect, so a second instance of the same screen (a login pushed over a
/// redirected login) ties with the visible field on overlap and, visited
/// first, used to win: the write landed in a form nobody could see while the
/// read-back still verified. `Overlay` wraps exactly those entries in a muted
/// `TickerMode`, which is the signal read here.
///
/// An ancestor walk rather than `TickerMode.of`, which would subscribe the
/// field to ticker changes from outside build, or `getValuesNotifier`, which
/// needs Flutter 3.35, above what this package resolves against.
bool _isUnderMutedTickers(Element element) {
  bool muted = false;
  element.visitAncestorElements((Element ancestor) {
    final Widget widget = ancestor.widget;
    if (widget is TickerMode && !widget.enabled) {
      muted = true;
      return false;
    }
    return true;
  });
  return muted;
}

/// The global rect of the render object that contributes [node] to the
/// semantics tree, in the SAME `localToGlobal` space as the editable rects that
/// [_findEditableTextStateByRect] computes.
///
/// The ref's stored rect comes from `ext_find` walking the semantics-ancestor
/// transforms, which on web does not always land in the render tree's
/// `localToGlobal` space; deriving the target from the node's own render object
/// keeps the two comparable so overlap-matching selects the right field.
Rect? _localToGlobalRectForNode(SemanticsNode? node) {
  if (node == null) return null;
  final Element? root = WidgetsBinding.instance.rootElement;
  if (root == null) return null;
  Rect? result;
  void visit(Element element) {
    if (result != null) return;
    final RenderObject? renderObject = element.renderObject;
    if (renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize &&
        identical(renderObject.debugSemantics, node)) {
      result = renderObject.localToGlobal(Offset.zero) & renderObject.size;
      return;
    }
    element.visitChildElements(visit);
  }

  root.visitChildElements(visit);
  return result;
}

/// Extracts the [TextEditingController] from an [EditableTextState] using the
/// public [EditableText.controller] accessor available on the state's widget.
///
/// Returns `null` when the controller cannot be obtained (e.g. a subclass
/// overrides the widget property in an unexpected way), triggering the
/// platform-message fallback path in [typeIntoElement].
TextEditingController? _extractController(EditableTextState state) {
  try {
    return state.widget.controller;
  } catch (_) {
    return null;
  }
}
