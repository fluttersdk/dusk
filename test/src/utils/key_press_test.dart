import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/utils/key_press.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('deliverKeyPress', () {
    test(
        'throws a StateError naming the key when the binding has no key data '
        'handler', () {
      final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;
      final saved = dispatcher.onKeyData;
      dispatcher.onKeyData = null;
      addTearDown(() => dispatcher.onKeyData = saved);

      expect(
        () => deliverKeyPress(
          logical: LogicalKeyboardKey.escape,
          physical: PhysicalKeyboardKey.escape,
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('Escape'),
          ),
        ),
      );
    });

    test('presses down then up, the character on the down half only', () {
      final List<KeyEvent> heard = <KeyEvent>[];
      bool handler(KeyEvent event) {
        heard.add(event);

        return false;
      }

      HardwareKeyboard.instance.addHandler(handler);
      addTearDown(() => HardwareKeyboard.instance.removeHandler(handler));

      deliverKeyPress(
        logical: LogicalKeyboardKey.keyG,
        physical: PhysicalKeyboardKey.keyG,
        character: 'g',
      );

      expect(heard.map((KeyEvent e) => e.runtimeType), <Type>[
        KeyDownEvent,
        KeyUpEvent,
      ]);
      expect(heard.first.character, 'g');
      expect(heard.last.character, isNull);
    });

    test(
        'holds the modifiers while the key is delivered and releases them '
        'afterwards, in reverse', () {
      final List<(Type, LogicalKeyboardKey)> heard =
          <(Type, LogicalKeyboardKey)>[];
      bool? shiftHeldOnKey;
      bool? controlHeldOnKey;
      bool handler(KeyEvent event) {
        heard.add((event.runtimeType, event.logicalKey));
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyG) {
          shiftHeldOnKey = HardwareKeyboard.instance.isShiftPressed;
          controlHeldOnKey = HardwareKeyboard.instance.isControlPressed;
        }

        return false;
      }

      HardwareKeyboard.instance.addHandler(handler);
      addTearDown(() => HardwareKeyboard.instance.removeHandler(handler));

      deliverKeyPress(
        logical: LogicalKeyboardKey.keyG,
        physical: PhysicalKeyboardKey.keyG,
        modifiers: <KeyModifier>[
          KeyModifier.control,
          KeyModifier.shift,
        ],
      );

      expect(shiftHeldOnKey, isTrue);
      expect(controlHeldOnKey, isTrue);
      expect(heard, <(Type, LogicalKeyboardKey)>[
        (KeyDownEvent, LogicalKeyboardKey.controlLeft),
        (KeyDownEvent, LogicalKeyboardKey.shiftLeft),
        (KeyDownEvent, LogicalKeyboardKey.keyG),
        (KeyUpEvent, LogicalKeyboardKey.keyG),
        (KeyUpEvent, LogicalKeyboardKey.shiftLeft),
        (KeyUpEvent, LogicalKeyboardKey.controlLeft),
      ]);
      expect(HardwareKeyboard.instance.isShiftPressed, isFalse);
      expect(HardwareKeyboard.instance.isControlPressed, isFalse);
    });

    test('releases the modifiers even when the key delivery throws', () {
      final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;
      final ui.KeyDataCallback saved = dispatcher.onKeyData!;
      dispatcher.onKeyData = (ui.KeyData data) {
        if (data.logical == LogicalKeyboardKey.keyG.keyId &&
            data.type == ui.KeyEventType.down) {
          throw StateError('key delivery failed');
        }

        return saved(data);
      };
      addTearDown(() => dispatcher.onKeyData = saved);

      expect(
        () => deliverKeyPress(
          logical: LogicalKeyboardKey.keyG,
          physical: PhysicalKeyboardKey.keyG,
          modifiers: <KeyModifier>[
            KeyModifier.shift,
          ],
        ),
        throwsStateError,
      );
      expect(HardwareKeyboard.instance.isShiftPressed, isFalse);
      expect(HardwareKeyboard.instance.physicalKeysPressed, isEmpty);
    });
  });
}
