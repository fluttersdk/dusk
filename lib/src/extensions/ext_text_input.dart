import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../ref_registry.dart';
import '../utils/actionability_gate.dart';
import '../utils/tapir_exceptions.dart';
import '../utils/tapir_register.dart';
import '../utils/tapir_response.dart';
import '../utils/effect_report.dart';
import '../utils/error_envelope.dart';
import '../utils/frame_sync.dart';
import '../utils/key_press.dart';
import '../utils/perf_interaction.dart';
import 'ext_pointer.dart';
import 'ext_snapshot.dart' show tapirSnapBuild, snapshotForAction;
import 'package:dowel/dowel.dart';

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

// ---------------------------------------------------------------------------
// Logical key lookup table
// ---------------------------------------------------------------------------

/// A key as a real press carries it: both halves of its identity, and the
/// character it carries, if it carries one.
typedef _Key = ({
  LogicalKeyboardKey logical,
  PhysicalKeyboardKey physical,
  String? character,
});

/// Resolves an agent-facing key name to the key a real press would carry, or
/// null when it names nothing.
///
/// A name in [_kKeyMap] matches case-insensitively, since agents call
/// `tapir:press_key --key=TAB` or `--key=enter` and the canonical names are
/// PascalCase. A single letter or digit is the key that carries it: `G` and
/// `g` both press the G key with the character `g`, so a shortcut bound to a
/// letter can be driven. Anything else is refused rather than guessed at.
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
// Text-field target resolution
// ---------------------------------------------------------------------------

/// The editable a text verb writes for one ref, and how it was picked.
///
/// Resolved once per verb, so `fill`'s clear and type land on the same field
/// rather than each re-ranking the tree on its own.
@immutable
final class TextFieldTarget {
  /// Creates a target for [state], picked by [match].
  const TextFieldTarget({
    required this.state,
    required this.match,
  });

  /// The editable that is written.
  final EditableTextState state;

  /// How [state] was picked for the ref.
  final TextTargetMatch match;

  /// The `effect.target` block, read off the live field: its global rect and
  /// its semantics label. Null when the field is no longer laid out.
  Map<String, dynamic>? describe() {
    if (!state.mounted) return null;
    final RenderObject? renderObject = state.context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;

    return textTarget(
      match: match,
      label: _semanticsLabelFor(renderObject),
      rect: renderObject.localToGlobal(Offset.zero) & renderObject.size,
    );
  }
}

/// Resolves the editable a text verb on a ref writes, or null when there is
/// no editable at all.
///
/// A ref minted from a SemanticsNode carries the app-root element (see
/// ext_find `_entryFromSemanticsNode`), so a plain descendant-first walk from
/// it returns the FIRST EditableText in the tree, sending every write on a
/// multi-field form to field #1. When the ref's on-screen rect is known the
/// editable matching it is selected instead; the element walk is the fallback
/// for a ref with no rect. Run [refuseNonTextRef] first: the rect ranking
/// always finds SOME editable, which for a dropdown is the wrong one.
TextFieldTarget? resolveTextFieldTarget({
  required RefEntry? entry,
  required Element element,
}) =>
    _resolveTarget(
      element: element,
      targetRect: _localToGlobalRectForNode(entry?.node) ?? entry?.rect,
    );

/// The error a text verb answers for a ref whose node is an interactive
/// control that is not a text field, or null when the ref may be written.
///
/// Before this refusal a dropdown, checkbox or button ref overlapped no
/// editable, so the nearest field on screen was cleared and written and the
/// read-back of THAT field verified the write. Only an interactive control is
/// refused: a static-text handle (a label above its field) keeps the nearest
/// fallback, which is exactly what it is for. [verb] names the extension in
/// the message (`type`, `clear`, `fill`).
developer.ServiceExtensionResponse? refuseNonTextRef({
  required String verb,
  required String ref,
  required RefEntry? entry,
}) {
  final SemanticsNode? node = entry?.node;
  if (node == null) return null;
  final String? role = _nonTextControlRole(node);
  if (role == null) return null;

  return developer.ServiceExtensionResponse.error(
    developer.ServiceExtensionResponse.extensionError,
    wrapErrorDetail(
      '[tapir] ext.tapir.$verb: ref $ref is a $role, not a text '
      'field. Target the field itself, or use the verb for a $role '
      '(tap, select_option, set_checkbox).',
      TapirErrorEnvelope.unexpected(widgetPath: ref),
    ),
  );
}

/// The role of [node] when it is an interactive control other than a text
/// field, read off its (merged) semantics flags; null otherwise.
///
/// Flags only, no tap action: a tappable label is still a label, and the
/// nearest fallback is what a label handle needs.
String? _nonTextControlRole(SemanticsNode node) {
  final SemanticsFlags flags = node.getSemanticsData().flagsCollection;
  if (flags.isTextField) return null;
  if (flags.isChecked != CheckedState.none) {
    return flags.isInMutuallyExclusiveGroup ? 'radio' : 'checkbox';
  }
  if (flags.isToggled != Tristate.none) return 'switch';
  if (flags.isSlider) return 'slider';
  if (flags.isLink) return 'link';
  if (flags.isButton || flags.isExpanded != Tristate.none) return 'button';

  return null;
}

/// The label of the semantics node [renderObject] contributes to, climbing
/// to the node a merge folds it into; null when it has none.
String? _semanticsLabelFor(RenderObject renderObject) {
  RenderObject? current = renderObject;
  while (current != null) {
    SemanticsNode? node = current.debugSemantics;
    if (node != null) {
      while (node!.isMergedIntoParent && node.parent != null) {
        node = node.parent;
      }
      final String label = node.getSemanticsData().label;

      return label.isEmpty ? null : label;
    }
    current = current.parent;
  }

  return null;
}

/// [resolveTextFieldTarget] for an already-derived [targetRect].
TextFieldTarget? _resolveTarget({
  required Element element,
  required Rect? targetRect,
}) {
  final TextFieldTarget? byRect =
      targetRect != null ? _findEditableTextStateByRect(targetRect) : null;
  if (byRect != null) return byRect;

  final EditableTextState? walked = _resolveEditableTextState(element);
  if (walked == null) return null;

  return TextFieldTarget(state: walked, match: TextTargetMatch.element);
}

// ---------------------------------------------------------------------------
// Internal helpers — @visibleForTesting so tests drive them directly
// ---------------------------------------------------------------------------

/// Sets [text] into the [EditableText] backed by [element], selected by
/// [targetRect] when given (see [resolveTextFieldTarget]).
///
/// Returns the value the field holds straight after the write. Frame awaiting
/// is the caller's responsibility: in widget tests call `tester.pump()` after
/// this returns. Throws [ArgumentError] when there is no editable to write.
@visibleForTesting
Future<String?> typeIntoElement({
  required Element element,
  required String text,
  Rect? targetRect,
}) async {
  final TextFieldTarget? target = _resolveTarget(
    element: element,
    targetRect: targetRect,
  );

  return _writeText(_requireTarget(target, element).state, text);
}

/// [target], or the [ArgumentError] a text verb raises when none resolved.
TextFieldTarget _requireTarget(TextFieldTarget? target, Element element) {
  if (target == null) {
    throw ArgumentError(
      '[tapir] typeIntoElement: no EditableText found in or under '
      'element $element',
    );
  }

  return target;
}

/// Writes [text] into [state] the way a user edit would: focus, then
/// [EditableTextState.userUpdateTextEditingValue] (which fires `onChanged`
/// and runs the input formatters), then the controller setter and a
/// `flutter/textinput` platform message as fallbacks. Returns the value the
/// field holds straight after the write.
Future<String?> _writeText(EditableTextState state, String text) async {
  // 1. Focus the field so the engine IME state is coherent after mutation.
  state.requestKeyboard();

  // 2. Primary path — emulate user input via Flutter's official user-input
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
      '[tapir] ext.tapir.type: userUpdateTextEditingValue threw $e; '
      'falling back to controller.value setter',
      name: 'tapir',
    );
  }

  if (!injected) {
    // 3. Fallback when userUpdateTextEditingValue is unavailable (older
    //    Flutter) — set the controller directly. May leave parent listeners
    //    unfired; only used as a defensive last resort.
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
      '[tapir] ext.tapir.type: primary path unavailable, using '
      'platform-message fallback',
      name: 'tapir',
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
  //    caller has no way to tell that from a clean success otherwise. The
  //    handler reads again once frames have run, for a field that reverts.
  return state.textEditingValue.text;
}

/// Presses [key] down and lets it up again through [deliverKeyPress], so the
/// focused widget hears it as it would a real press.
///
/// [key] is a name from the supported table (Enter, Tab, Escape, ArrowDown,
/// ...) or a single letter or digit. [modifiers] are held across the press,
/// each one of `control` (or `ctrl`), `shift`, `alt`, `meta`, in any case.
/// Throws [ArgumentError] for an unknown key or modifier before anything is
/// pressed, which surfaces misconfigured agent payloads immediately rather
/// than silently emitting a no-op, and [StateError] when the binding has no
/// key data handler to deliver to.
@visibleForTesting
Future<void> pressKey({
  required String key,
  List<String> modifiers = const <String>[],
}) async {
  final _Key? resolved = _lookupKey(key);
  if (resolved == null) {
    throw ArgumentError(
      '[tapir] ext.tapir.press_key: unknown key "$key". '
      'Supported keys: ${_kKeyMap.keys.join(', ')}, or one letter or digit',
    );
  }

  deliverKeyPress(
    logical: resolved.logical,
    physical: resolved.physical,
    character: resolved.character,
    // A set: naming a modifier twice (`ctrl,control`) must not press it twice.
    modifiers: modifiers.map(_lookupModifier).toSet().toList(),
  );
}

/// Resolves an agent-facing modifier name, case-insensitively.
///
/// Throws [ArgumentError] naming [input] and the accepted names otherwise.
KeyModifier _lookupModifier(String input) {
  final KeyModifier? modifier = switch (input.toLowerCase()) {
    'control' || 'ctrl' => KeyModifier.control,
    'shift' => KeyModifier.shift,
    'alt' => KeyModifier.alt,
    'meta' => KeyModifier.meta,
    _ => null,
  };

  if (modifier == null) {
    throw ArgumentError(
      '[tapir] ext.tapir.press_key: unknown modifier "$input". '
      'Supported modifiers: control (or ctrl), shift, alt, meta',
    );
  }

  return modifier;
}

/// Splits the `modifiers` param of `ext.tapir.press_key` into names.
///
/// The CLI sends a comma-separated string (`control,shift`); the MCP schema
/// declares an array, which reaches the extension as its JSON text
/// (`["control","shift"]`), since every VM Service param is a string. A
/// malformed array throws [FormatException].
List<String> _parseModifiers(String? raw) {
  if (raw == null) return <String>[];

  final String trimmed = raw.trim();
  final Iterable<String> names = trimmed.startsWith('[')
      ? (jsonDecode(trimmed) as List<dynamic>).map((dynamic e) => '$e')
      : trimmed.split(',');

  return names
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();
}

// ---------------------------------------------------------------------------
// VM Service extension handlers
// ---------------------------------------------------------------------------

/// Handler for the `ext.tapir.type` VM Service extension.
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
/// - `snapshot` (optional, `full` | `diff` | `none`): overrides
///   `includeSnapshot`; see [snapshotForAction].
///
/// [target] is the field `fill` already resolved for the ref, so its clear
/// and its type write the same editable; a direct call resolves its own. A
/// ref whose node is a non-text control is refused (see [refuseNonTextRef]).
///
/// Response (success, default):
/// ```json
/// {
///   "text": "typed value",
///   "effect": {"kind": "text", "verified": true, "value": "typed value",
///              "target": {"matchKind": "overlap", "label": "Name", "rect": {}}},
///   "snapshot": "<yaml>"
/// }
/// ```
Future<developer.ServiceExtensionResponse> aiTestTypeHandler(
  String method,
  Map<String, String> params, {
  TextFieldTarget? target,
}) async {
  try {
    final String? ref = params['ref'];
    final String text = params['text'] ?? '';

    if (ref == null || ref.isEmpty) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          '[tapir] ext.tapir.type: missing required param "ref"',
          TapirErrorEnvelope.missingParam('ref'),
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
    } on TapirStaleHandleException catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(e.message, TapirErrorEnvelope.stale(ref)),
      );
    }
    if (target == null) {
      final developer.ServiceExtensionResponse? refusal = refuseNonTextRef(
        verb: 'type',
        ref: ref,
        entry: entry,
      );
      if (refusal != null) return refusal;
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
      } on TapirActionabilityException catch (e) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          wrapErrorDetail(
            e.message,
            TapirErrorEnvelope.fromActionabilityReason(e.ref, e.reason),
          ),
        );
      }
    }

    final Element? element = entry?.element ?? TestRefRegistry.lookup(ref);
    if (element == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          '[tapir] ext.tapir.type: ref "$ref" not found in registry',
          TapirErrorEnvelope.notFound(
            ref: ref,
            candidates: collectSnapshotCandidates(),
          ),
        ),
      );
    }

    final TextFieldTarget field = _requireTarget(
      target ?? resolveTextFieldTarget(entry: entry, element: element),
      element,
    );
    await runPerfInteraction<String?>(
      'type',
      ref,
      () => _writeText(field.state, text),
    );

    // Wait two frames so ValueListenableBuilder listeners rebuild and paint
    // before the MCP client reads state (per Stage 3 mandate: every mutating
    // extension awaits endOfFrame before returning).
    await awaitFramesOrTimeout(2);

    // 2. Report what the field HOLDS once those frames ran, not what it was
    //    handed nor what it held straight after the write: a formatter or an
    //    echo that reverts the value a frame later would otherwise verify.
    //    `text` stays for callers that read it. A field gone by then cannot
    //    be read back, so it reports null rather than the earlier read.
    final String? settled =
        field.state.mounted ? field.state.textEditingValue.text : null;
    final Map<String, dynamic> payload = <String, dynamic>{
      'text': text,
      'effect': textEffect(
        expected: text,
        actual: settled,
        target: field.describe(),
      ),
    };
    if (gate != null) stampChecks(payload, gate);

    // 3. Embed post-action snapshot (opt-out via includeSnapshot:'false').
    //    Snapshot-build noise must NOT convert a successful type into an
    //    error envelope: the text has already landed in the controller.
    try {
      payload.addAll(await snapshotForAction(params));
    } catch (e) {
      developer.log(
        '[tapir] ext.tapir.type: post-dispatch snapshot build swallowed '
        'for ref "$ref": $e',
        name: 'tapir',
      );
    }

    return tapirResult(payload);
  } catch (e, stackTrace) {
    developer.log(
      '[tapir] ext.tapir.type error: $e\n$stackTrace',
      name: 'tapir',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), TapirErrorEnvelope.unexpected()),
    );
  }
}

/// Handler for the `ext.tapir.press_key` VM Service extension.
///
/// Params:
/// - `key` (required): key name string from the supported lookup table
///   (Enter, Tab, Escape, ArrowUp, ArrowDown, etc.).
/// - `modifiers` (optional): modifier names held across the press, as a
///   comma-separated list (CLI) or a JSON array (MCP); see [pressKey].
/// - `includeSnapshot` (optional, default `'true'`): when `'false'`, skip
///   embedding the post-action accessibility snapshot in the response.
/// - `snapshot` (optional, `full` | `diff` | `none`): overrides
///   `includeSnapshot`; see [snapshotForAction].
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
          '[tapir] ext.tapir.press_key: missing required param "key"',
          TapirErrorEnvelope.missingParam('key'),
        ),
      );
    }

    final List<String> modifiers = _parseModifiers(params['modifiers']);

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
        payload.addAll(await snapshotForAction(params));
      } catch (e) {
        developer.log(
          '[tapir] ext.tapir.press_key: post-dispatch snapshot build '
          'swallowed for key "$key": $e',
          name: 'tapir',
        );
      }
    }

    return tapirResult(payload);
  } catch (e, stackTrace) {
    developer.log(
      '[tapir] ext.tapir.press_key error: $e\n$stackTrace',
      name: 'tapir',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), TapirErrorEnvelope.unexpected()),
    );
  }
}

// ---------------------------------------------------------------------------
// Self-registration entry point
// ---------------------------------------------------------------------------

/// Registers `ext.tapir.type` and `ext.tapir.press_key` as VM Service
/// extensions.
///
/// Idempotent: each registration routes through [registerExtensionIdempotent],
/// which catches the [ArgumentError] thrown by [developer.registerExtension]
/// on duplicate registration (hot-restart safety — per V3 plan Stage 3 D12).
///
/// Called from `extensions.dart#registerAllAiTestExtensions()` once the Step
/// 14b aggregator lands. May also be called standalone in tests.
void registerTextInputExtensions() {
  registerTapirExtension('ext.tapir.type', aiTestTypeHandler);
  registerTapirExtension('ext.tapir.press_key', aiTestPressKeyHandler);
  registerTapirExtension('ext.tapir.clear', aiTestClearHandler);
}

/// Handler for `ext.tapir.clear` — empties the [TextEditingController] backing
/// the resolved text field. Playwright parity: `locator.clear()`.
///
/// Resolves the field through [resolveTextFieldTarget], as
/// [aiTestTypeHandler] does, unless `fill` hands its resolved [target] in,
/// and refuses a non-text control ref the same way. Returns the post-clear
/// value read back off the controller plus an optional snapshot.
Future<developer.ServiceExtensionResponse> aiTestClearHandler(
  String method,
  Map<String, String> params, {
  TextFieldTarget? target,
}) async {
  try {
    final String? ref = params['ref'];
    if (ref == null || ref.isEmpty) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.tapir.clear: missing required param "ref"',
          TapirErrorEnvelope.missingParam('ref'),
        ),
      );
    }
    final RefEntry? entry;
    try {
      entry = resolveRefForAction(ref);
    } on TapirStaleHandleException catch (e) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(e.message, TapirErrorEnvelope.stale(ref)),
      );
    }
    if (target == null) {
      final developer.ServiceExtensionResponse? refusal = refuseNonTextRef(
        verb: 'clear',
        ref: ref,
        entry: entry,
      );
      if (refusal != null) return refusal;
    }
    final Element? element = entry?.element ?? TestRefRegistry.lookup(ref);
    if (element == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.tapir.clear: ref "$ref" not found in registry',
          TapirErrorEnvelope.notFound(
            ref: ref,
            candidates: collectSnapshotCandidates(),
          ),
        ),
      );
    }
    final TextFieldTarget? field =
        target ?? resolveTextFieldTarget(entry: entry, element: element);
    if (field == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.tapir.clear: no EditableText under ref "$ref"',
          TapirErrorEnvelope.unexpected(),
        ),
      );
    }
    final TextEditingController? controller = _extractController(field.state);
    if (controller == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        wrapErrorDetail(
          'ext.tapir.clear: could not resolve TextEditingController',
          TapirErrorEnvelope.unexpected(),
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
      'effect': textEffect(
        expected: '',
        actual: controller.text,
        target: field.describe(),
      ),
    };
    if (_parseBoolFlag(params, 'includeSnapshot', defaultValue: false)) {
      final snap = await tapirSnapBuild();
      payload['snapshot'] = snap['snapshot'];
    }
    return tapirResult(payload);
  } catch (e, stackTrace) {
    developer.log(
      '[tapir] ext.tapir.clear error: $e\n$stackTrace',
      name: 'tapir',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      wrapErrorDetail(e.toString(), TapirErrorEnvelope.unexpected()),
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
TextFieldTarget? _findEditableTextStateByRect(Rect targetRect) {
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
    return _rankedTarget(live);
  }

  return _rankedTarget(_rankEditableTextStates(targetRect, skipMuted: false));
}

/// The winner of one ranking pass, tagged with how it won.
TextFieldTarget? _rankedTarget(
  ({EditableTextState? overlap, EditableTextState? nearest}) ranked,
) {
  final EditableTextState? overlap = ranked.overlap;
  if (overlap != null) {
    return TextFieldTarget(state: overlap, match: TextTargetMatch.overlap);
  }
  final EditableTextState? nearest = ranked.nearest;
  if (nearest == null) return null;

  return TextFieldTarget(state: nearest, match: TextTargetMatch.nearest);
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
