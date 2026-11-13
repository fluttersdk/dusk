import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// A modifier key [deliverKeyPress] can hold across a press, as its left-hand
/// key: the logical and physical halves pair, because the keyboard state
/// releases a key by its physical half.
enum KeyModifier {
  control(LogicalKeyboardKey.controlLeft, PhysicalKeyboardKey.controlLeft),
  shift(LogicalKeyboardKey.shiftLeft, PhysicalKeyboardKey.shiftLeft),
  alt(LogicalKeyboardKey.altLeft, PhysicalKeyboardKey.altLeft),
  meta(LogicalKeyboardKey.metaLeft, PhysicalKeyboardKey.metaLeft);

  const KeyModifier(this.logical, this.physical);

  final LogicalKeyboardKey logical;

  final PhysicalKeyboardKey physical;
}

/// Presses a key down and lets it up again, the way a keyboard does.
///
/// Both halves enter through the binding's `onKeyData`, the handler the
/// platform delivers real key data to, so they reach [HardwareKeyboard] AND
/// the focus tree, where `Focus.onKeyEvent` and `Shortcuts` listen. Handing
/// them to [HardwareKeyboard.handleKeyEvent] directly reaches only the
/// keyboard's global handlers, and no focused widget ever hears the key. They
/// are marked synthesized, which is what makes the binding dispatch each at
/// once rather than hold it for a raw event that never follows.
///
/// Two limits come with the route. A real key whose raw message has not
/// arrived yet holds both halves back until the next real key. And on an
/// embedder that sends only raw key messages (none of Flutter's own; a third
/// party such as flutter-tizen may), a press made before the first real key
/// fixes the binding's transit mode to key data, so `handleRawKeyMessage`
/// never attaches its converter and the app's real keys stop reaching
/// [HardwareKeyboard] and the focus tree until it restarts; made after the
/// first real key, the press asserts in a debug build and is dropped in a
/// release one. Do not drive such an embedder with this helper.
///
/// [character] rides on the down half only, as a real press carries it; a
/// text field takes its text from the text input channel, not from here.
///
/// [modifiers] go down in order before the key and come up in reverse after
/// it, so a `Shortcuts` binding that matches modifiers exactly sees them held
/// when the key goes down. They come up even when delivering the key throws.
///
/// Throws [StateError] when the binding has no key data handler; nothing is
/// pressed then.
void deliverKeyPress({
  required LogicalKeyboardKey logical,
  required PhysicalKeyboardKey physical,
  String? character,
  List<KeyModifier> modifiers = const <KeyModifier>[],
}) {
  final ui.KeyDataCallback? deliver =
      ServicesBinding.instance.platformDispatcher.onKeyData;

  if (deliver == null) {
    throw StateError(
      '[tapir] the binding has no key data handler to deliver '
      '${logical.debugName ?? logical.keyLabel} to',
    );
  }

  final Duration now = Duration(
    microseconds: DateTime.now().microsecondsSinceEpoch,
  );
  final Duration later = now + const Duration(milliseconds: 16);

  ui.KeyData half(
    ui.KeyEventType type,
    Duration timeStamp, {
    required LogicalKeyboardKey logical,
    required PhysicalKeyboardKey physical,
    String? character,
  }) => ui.KeyData(
    timeStamp: timeStamp,
    type: type,
    physical: physical.usbHidUsage,
    logical: logical.keyId,
    character: type == ui.KeyEventType.down ? character : null,
    synthesized: true,
  );

  // A modifier counts as held only once its down half went through, so the
  // release below never lets up a key the keyboard state never saw go down.
  final List<KeyModifier> held = <KeyModifier>[];

  try {
    for (final KeyModifier modifier in modifiers) {
      deliver(
        half(
          ui.KeyEventType.down,
          now,
          logical: modifier.logical,
          physical: modifier.physical,
        ),
      );
      held.add(modifier);
    }

    deliver(
      half(
        ui.KeyEventType.down,
        now,
        logical: logical,
        physical: physical,
        character: character,
      ),
    );
    deliver(
      half(ui.KeyEventType.up, later, logical: logical, physical: physical),
    );
  } finally {
    // A modifier left down would ride on every later key the app hears, real
    // or synthesized, until a real press of it comes along.
    for (final KeyModifier modifier in held.reversed) {
      deliver(
        half(
          ui.KeyEventType.up,
          later,
          logical: modifier.logical,
          physical: modifier.physical,
        ),
      );
    }
  }
}
