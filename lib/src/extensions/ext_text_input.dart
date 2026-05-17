import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../ref_registry.dart';
import 'package:fluttersdk_artisan/artisan.dart';

// ---------------------------------------------------------------------------
// Logical key lookup table
// ---------------------------------------------------------------------------

/// Maps agent-facing key name strings to Flutter [LogicalKeyboardKey] values.
///
/// The lookup table covers the subset of keys that LLM agents commonly target
/// during form navigation (Tab, Enter, Escape) and list navigation (arrows).
/// Unknown keys cause [pressKey] to throw [ArgumentError] rather than silently
/// emitting a no-op, which surfaces misconfigured agent payloads immediately.
const Map<String, LogicalKeyboardKey> _kKeyMap = <String, LogicalKeyboardKey>{
  'Enter': LogicalKeyboardKey.enter,
  'Tab': LogicalKeyboardKey.tab,
  'Escape': LogicalKeyboardKey.escape,
  'Backspace': LogicalKeyboardKey.backspace,
  'Delete': LogicalKeyboardKey.delete,
  'Space': LogicalKeyboardKey.space,
  'ArrowUp': LogicalKeyboardKey.arrowUp,
  'ArrowDown': LogicalKeyboardKey.arrowDown,
  'ArrowLeft': LogicalKeyboardKey.arrowLeft,
  'ArrowRight': LogicalKeyboardKey.arrowRight,
  'Home': LogicalKeyboardKey.home,
  'End': LogicalKeyboardKey.end,
  'PageUp': LogicalKeyboardKey.pageUp,
  'PageDown': LogicalKeyboardKey.pageDown,
  'F1': LogicalKeyboardKey.f1,
  'F2': LogicalKeyboardKey.f2,
  'F3': LogicalKeyboardKey.f3,
  'F4': LogicalKeyboardKey.f4,
  'F5': LogicalKeyboardKey.f5,
  'F6': LogicalKeyboardKey.f6,
  'F7': LogicalKeyboardKey.f7,
  'F8': LogicalKeyboardKey.f8,
  'F9': LogicalKeyboardKey.f9,
  'F10': LogicalKeyboardKey.f10,
  'F11': LogicalKeyboardKey.f11,
  'F12': LogicalKeyboardKey.f12,
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
Future<void> typeIntoElement({
  required Element element,
  required String text,
}) async {
  // 1. Resolve the EditableTextState — either the element IS the EditableText,
  //    or it is an ancestor (e.g. TextField) that contains one as a descendant.
  final EditableTextState? state = _resolveEditableTextState(element);
  if (state == null) {
    throw ArgumentError(
      '[ai-test-v3] typeIntoElement: no EditableText found in or under '
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
      '[ai-test-v3] ext.dusk.type: userUpdateTextEditingValue threw $e; '
      'falling back to controller.value setter',
      name: 'ai-test',
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
      '[ai-test-v3] ext.dusk.type: primary path unavailable, using '
      'platform-message fallback',
      name: 'ai-test',
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
}

/// Resolves a [LogicalKeyboardKey] from an agent-facing [key] name string
/// and dispatches a [KeyDownEvent] followed by a [KeyUpEvent] via
/// [HardwareKeyboard.instance.handleKeyEvent].
///
/// Throws [ArgumentError] when [key] is not in the supported lookup table.
/// This surfaces misconfigured agent payloads immediately rather than silently
/// emitting a no-op.
///
/// The [modifiers] parameter is accepted by the public handler but not yet
/// wired to synthesized modifier keys; it is reserved for future use.
@visibleForTesting
Future<void> pressKey({
  required String key,
  List<String> modifiers = const <String>[],
}) async {
  final LogicalKeyboardKey? logicalKey = _kKeyMap[key];
  if (logicalKey == null) {
    throw ArgumentError(
      '[ai-test-v3] ext.dusk.press_key: unknown key "$key". '
      'Supported keys: ${_kKeyMap.keys.join(', ')}',
    );
  }

  HardwareKeyboard.instance.handleKeyEvent(
    KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.enter,
      logicalKey: logicalKey,
      timeStamp: Duration.zero,
    ),
  );

  HardwareKeyboard.instance.handleKeyEvent(
    KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.enter,
      logicalKey: logicalKey,
      timeStamp: const Duration(milliseconds: 16),
    ),
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
///
/// Response (success):
/// ```json
/// { "text": "typed value" }
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
        '[ai-test-v3] ext.dusk.type: missing required param "ref"',
      );
    }

    // Resolve the element — TestRefRegistry in tests; RefRegistry in production
    // once Step 6 lands. The test-injection path keeps this module independently
    // testable without mandating Step 6's implementation.
    final Element? element = _resolveElement(ref);
    if (element == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        '[ai-test-v3] ext.dusk.type: ref "$ref" not found in registry',
      );
    }

    await typeIntoElement(element: element, text: text);

    // Wait two frames so ValueListenableBuilder listeners rebuild and paint
    // before the MCP client reads state (per Stage 3 mandate: every mutating
    // extension awaits endOfFrame before returning).
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;

    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, dynamic>{'text': text}),
    );
  } catch (e, stackTrace) {
    developer.log(
      '[ai-test-v3] ext.dusk.type error: $e\n$stackTrace',
      name: 'ai-test',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      e.toString(),
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
///
/// Response (success):
/// ```json
/// { "ok": true, "key": "Enter" }
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
        '[ai-test-v3] ext.dusk.press_key: missing required param "key"',
      );
    }

    final List<String> modifiers = params['modifiers']
            ?.split(',')
            .map((String s) => s.trim())
            .where((String s) => s.isNotEmpty)
            .toList() ??
        <String>[];

    await pressKey(key: key, modifiers: modifiers);

    return developer.ServiceExtensionResponse.result(
      jsonEncode(<String, dynamic>{'ok': true, 'key': key}),
    );
  } catch (e, stackTrace) {
    developer.log(
      '[ai-test-v3] ext.dusk.press_key error: $e\n$stackTrace',
      name: 'ai-test',
    );
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      e.toString(),
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
EditableTextState? _resolveEditableTextState(Element element) {
  // Direct hit: the element itself is the EditableText element.
  if (element is StatefulElement && element.state is EditableTextState) {
    return element.state as EditableTextState;
  }

  // Descendant walk: dig one level into children to find an EditableText.
  EditableTextState? found;
  element.visitChildren((Element child) {
    if (found != null) return;
    found = _resolveEditableTextState(child);
  });
  return found;
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

/// Resolves an element for [ref].
///
/// During tests, [TestRefRegistry] provides an injection point so widget
/// tests can inject an [Element] without wiring a full [RefRegistry] group.
/// In production (and integration tests that call snapshot first), [RefRegistry]
/// from Step 6 is the authoritative source.
Element? _resolveElement(String ref) {
  // 1. Test injection path takes priority — returns null when not in a test.
  final Element? fromTest = TestRefRegistry.lookup(ref);
  if (fromTest != null) return fromTest;

  // 2. Production path — RefRegistry populated by the snapshot extension.
  return RefRegistry.lookup(ref)?.element;
}
