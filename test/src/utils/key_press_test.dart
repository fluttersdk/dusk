import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/utils/key_press.dart';

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
  });
}
