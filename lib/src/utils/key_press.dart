import 'dart:ui' as ui;

import 'package:flutter/services.dart';

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
/// arrived yet holds both halves back until the next real key, and an
/// embedder that sends only raw key messages (none of Flutter's own; a third
/// party such as flutter-tizen may) cannot take key data at all.
///
/// [character] rides on the down half only, as a real press carries it; a
/// text field takes its text from the text input channel, not from here.
///
/// Throws [StateError] when the binding has no key data handler.
void deliverKeyPress({
  required LogicalKeyboardKey logical,
  required PhysicalKeyboardKey physical,
  String? character,
}) {
  final ui.KeyDataCallback? deliver =
      ServicesBinding.instance.platformDispatcher.onKeyData;

  if (deliver == null) {
    throw StateError(
      '[fluttersdk_dusk] the binding has no key data handler to deliver '
      '${logical.debugName ?? logical.keyLabel} to',
    );
  }

  final Duration now = Duration(
    microseconds: DateTime.now().microsecondsSinceEpoch,
  );

  ui.KeyData half(ui.KeyEventType type, Duration timeStamp) => ui.KeyData(
        timeStamp: timeStamp,
        type: type,
        physical: physical.usbHidUsage,
        logical: logical.keyId,
        character: type == ui.KeyEventType.down ? character : null,
        synthesized: true,
      );

  deliver(half(ui.KeyEventType.down, now));
  deliver(half(ui.KeyEventType.up, now + const Duration(milliseconds: 16)));
}
