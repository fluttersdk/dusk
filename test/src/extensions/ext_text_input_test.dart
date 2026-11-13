import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/extensions/ext_find.dart';
import 'package:tapir/src/extensions/ext_snapshot.dart';
import 'package:tapir/src/extensions/ext_text_input.dart';
import 'package:tapir/src/ref_registry.dart';
import 'package:tapir/src/utils/error_envelope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ext_text_input', () {
    group('pressKey', () {
      // -----------------------------------------------------------------------
      // Test (a): Envelope shape on valid input
      // -----------------------------------------------------------------------

      test(
        '(a) returns normally when key is "Enter"',
        () async {
          expect(
            () => pressKey(key: 'Enter'),
            returnsNormally,
          );
        },
      );

      test(
        '(a) returns normally when key is "Tab"',
        () async {
          expect(
            () => pressKey(key: 'Tab'),
            returnsNormally,
          );
        },
      );

      test(
        '(a) returns normally when key is "Escape"',
        () async {
          expect(
            () => pressKey(key: 'Escape'),
            returnsNormally,
          );
        },
      );

      test(
        '(a) returns normally when key is "ArrowUp"',
        () async {
          expect(
            () => pressKey(key: 'ArrowUp'),
            returnsNormally,
          );
        },
      );

      test(
        '(a) returns normally when key is "Backspace"',
        () async {
          expect(
            () => pressKey(key: 'Backspace'),
            returnsNormally,
          );
        },
      );

      // -----------------------------------------------------------------------
      // Test (b): Modifier combo dispatch
      // -----------------------------------------------------------------------

      test(
        '(b) accepts modifiers parameter without throwing',
        () async {
          expect(
            () => pressKey(key: 'Enter', modifiers: ['ctrl']),
            returnsNormally,
          );
        },
      );

      test(
        '(b) accepts multiple modifiers without throwing',
        () async {
          expect(
            () => pressKey(key: 'Enter', modifiers: ['ctrl', 'shift']),
            returnsNormally,
          );
        },
      );

      test(
        '(b) modifiers parameter defaults to empty list',
        () async {
          expect(
            () => pressKey(key: 'Enter'),
            returnsNormally,
          );
        },
      );

      // -----------------------------------------------------------------------
      // Test (d): The key reaches the focus tree, as a real press does
      // -----------------------------------------------------------------------

      testWidgets(
        '(d) a focused widget hears an arrow key through Focus.onKeyEvent',
        (WidgetTester tester) async {
          final List<KeyEvent> heard = <KeyEvent>[];
          await tester.pumpWidget(_KeyListener(heard: heard));

          await pressKey(key: 'ArrowDown');

          expect(
            heard.map((KeyEvent e) => (e.runtimeType, e.logicalKey)),
            <(Type, LogicalKeyboardKey)>[
              (KeyDownEvent, LogicalKeyboardKey.arrowDown),
              (KeyUpEvent, LogicalKeyboardKey.arrowDown),
            ],
          );
          expect(heard.first.physicalKey, PhysicalKeyboardKey.arrowDown);
        },
      );

      testWidgets(
        '(d) a single letter is pressed with its own keys and character',
        (WidgetTester tester) async {
          final List<KeyEvent> heard = <KeyEvent>[];
          await tester.pumpWidget(_KeyListener(heard: heard));

          await pressKey(key: 'G');

          expect(heard.first.logicalKey, LogicalKeyboardKey.keyG);
          expect(heard.first.physicalKey, PhysicalKeyboardKey.keyG);
          expect(heard.first.character, 'g');
          expect(heard.last, isA<KeyUpEvent>());
        },
      );

      testWidgets(
        '(d) a digit is pressed with its own keys',
        (WidgetTester tester) async {
          final List<KeyEvent> heard = <KeyEvent>[];
          await tester.pumpWidget(_KeyListener(heard: heard));

          await pressKey(key: '0');
          await pressKey(key: '7');

          expect(
            heard.whereType<KeyDownEvent>().map((KeyEvent e) => e.physicalKey),
            <PhysicalKeyboardKey>[
              PhysicalKeyboardKey.digit0,
              PhysicalKeyboardKey.digit7,
            ],
          );
          expect(
            heard.whereType<KeyDownEvent>().map((KeyEvent e) => e.logicalKey),
            <LogicalKeyboardKey>[
              LogicalKeyboardKey.digit0,
              LogicalKeyboardKey.digit7,
            ],
          );
        },
      );

      testWidgets(
        '(d) a press leaves no key held',
        (WidgetTester tester) async {
          await tester.pumpWidget(_KeyListener(heard: <KeyEvent>[]));

          await pressKey(key: 'm');

          expect(HardwareKeyboard.instance.physicalKeysPressed, isEmpty);
        },
      );

      // -----------------------------------------------------------------------
      // Test (c): Bad-input rejection
      // -----------------------------------------------------------------------

      test(
        '(c) throws ArgumentError for a character outside letters and digits',
        () async {
          expect(
            () => pressKey(key: '%'),
            throwsA(isA<ArgumentError>()),
          );
        },
      );

      test(
        '(c) throws ArgumentError when key is unknown',
        () async {
          expect(
            () => pressKey(key: 'InvalidKeyName'),
            throwsA(isA<ArgumentError>()),
          );
        },
      );

      test(
        '(c) ArgumentError message includes the unknown key name',
        () async {
          expect(
            () => pressKey(key: 'BadKey'),
            throwsA(
              isA<ArgumentError>().having(
                (e) => e.message,
                'message',
                contains('BadKey'),
              ),
            ),
          );
        },
      );

      test(
        '(c) ArgumentError message includes list of supported keys',
        () async {
          expect(
            () => pressKey(key: 'UnknownKey'),
            throwsA(
              isA<ArgumentError>().having(
                (e) => e.message,
                'message',
                contains('Supported keys'),
              ),
            ),
          );
        },
      );

      test(
        '(c) throws ArgumentError when key is empty string',
        () async {
          expect(
            () => pressKey(key: ''),
            throwsA(isA<ArgumentError>()),
          );
        },
      );

      // -----------------------------------------------------------------------
      // Test (d): Missing-required-param rejection (handler level)
      // -----------------------------------------------------------------------

      test(
        '(d) aiTestPressKeyHandler returns error when key is missing',
        () async {
          final response =
              await aiTestPressKeyHandler('ext.tapir.press_key', {});
          expect(response.result, isNull);
        },
      );

      test(
        '(d) aiTestPressKeyHandler error mentions missing key param',
        () async {
          final response =
              await aiTestPressKeyHandler('ext.tapir.press_key', {});
          expect(response.errorDetail ?? '', contains('key'));
        },
      );

      test(
        '(d) aiTestPressKeyHandler returns error when key is empty',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.tapir.press_key',
            {'key': ''},
          );
          expect(response.result, isNull);
        },
      );

      test(
        '(d) aiTestPressKeyHandler succeeds when key is valid',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.tapir.press_key',
            {'key': 'Enter'},
          );
          final resultStr = response.result;
          expect(resultStr, isNotNull);
          expect(
            () => jsonDecode(resultStr!),
            returnsNormally,
          );
        },
      );

      test(
        '(d) aiTestPressKeyHandler success response is valid JSON for Tab',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.tapir.press_key',
            {'key': 'Tab'},
          );
          expect(
            () => jsonDecode(response.result ?? ''),
            returnsNormally,
          );
        },
      );

      test(
        '(d) aiTestPressKeyHandler success response contains ok:true',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.tapir.press_key',
            {'key': 'Escape'},
          );
          final decoded = jsonDecode(response.result ?? '{}');
          expect(decoded['ok'], equals(true));
        },
      );

      test(
        '(d) aiTestPressKeyHandler accepts case-insensitive --key=TAB',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.tapir.press_key',
            {'key': 'TAB'},
          );
          final resultStr = response.result;
          expect(resultStr, isNotNull,
              reason: 'TAB (uppercase) should fold to Tab via _lookupKey');
          final decoded = jsonDecode(resultStr!);
          expect(decoded['ok'], equals(true));
        },
      );

      test(
        '(d) aiTestPressKeyHandler accepts case-insensitive --key=enter',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.tapir.press_key',
            {'key': 'enter'},
          );
          final resultStr = response.result;
          expect(resultStr, isNotNull,
              reason: 'enter (lowercase) should fold to Enter via _lookupKey');
          final decoded = jsonDecode(resultStr!);
          expect(decoded['ok'], equals(true));
        },
      );

      test(
        '(d) aiTestPressKeyHandler rejects unknown key (no case-folding match)',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.tapir.press_key',
            {'key': 'NoSuchKey'},
          );
          expect(response.result, isNull);
          expect(response.errorDetail ?? '', contains('unknown key'));
        },
      );

      test(
        '(d) aiTestPressKeyHandler success response echoes the key',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.tapir.press_key',
            {'key': 'Enter'},
          );
          final decoded = jsonDecode(response.result ?? '{}');
          expect(decoded['key'], equals('Enter'));
        },
      );

      // -----------------------------------------------------------------------
      // Test (e): Idempotent registration
      // -----------------------------------------------------------------------

      test(
        '(e) registerTextInputExtensions can be called multiple times',
        () async {
          expect(
            () {
              registerTextInputExtensions();
              registerTextInputExtensions();
            },
            returnsNormally,
          );
        },
      );

      test(
        '(e) calling registerTextInputExtensions twice does not throw',
        () async {
          expect(
            () {
              registerTextInputExtensions();
              registerTextInputExtensions();
            },
            returnsNormally,
          );
        },
      );

      test(
        '(e) handler is still available after second registerTextInputExtensions',
        () async {
          registerTextInputExtensions();
          registerTextInputExtensions();
          final response = await aiTestPressKeyHandler(
            'ext.tapir.press_key',
            {'key': 'Enter'},
          );
          expect(response.result, isNotNull);
        },
      );
    });

    group('aiTestPressKeyHandler modifier parsing', () {
      // -----------------------------------------------------------------------
      // Test modifier parameter parsing (additional handler-level tests)
      // -----------------------------------------------------------------------

      test(
        'parses comma-separated modifiers from params',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.tapir.press_key',
            {
              'key': 'Enter',
              'modifiers': 'ctrl,shift',
            },
          );
          expect(response.result, isNotNull);
          final decoded = jsonDecode(response.result!);
          expect(decoded['ok'], equals(true));
        },
      );

      test(
        'handles whitespace in modifier list',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.tapir.press_key',
            {
              'key': 'Tab',
              'modifiers': 'ctrl, shift, alt',
            },
          );
          expect(response.result, isNotNull);
        },
      );

      test(
        'ignores empty modifier strings from split',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.tapir.press_key',
            {
              'key': 'Enter',
              'modifiers': 'ctrl,,shift',
            },
          );
          expect(response.result, isNotNull);
        },
      );

      test(
        'handles null modifiers param gracefully',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.tapir.press_key',
            {'key': 'Tab'},
          );
          expect(response.result, isNotNull);
        },
      );

      for (final String modifiers in <String>[
        '["control","shift"]',
        'control,shift',
      ]) {
        test(
          'holds control and shift while the key is pressed for $modifiers',
          () async {
            final List<(bool, bool)> heldOnKey = <(bool, bool)>[];
            bool handler(KeyEvent event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.keyS) {
                heldOnKey.add((
                  HardwareKeyboard.instance.isControlPressed,
                  HardwareKeyboard.instance.isShiftPressed,
                ));
              }

              return false;
            }

            HardwareKeyboard.instance.addHandler(handler);
            addTearDown(() => HardwareKeyboard.instance.removeHandler(handler));

            final response = await aiTestPressKeyHandler(
              'ext.tapir.press_key',
              <String, String>{
                'key': 'S',
                'modifiers': modifiers,
              },
            );

            expect(response.result, isNotNull);
            expect(heldOnKey, <(bool, bool)>[
              (true, true),
            ]);
            expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);
          },
        );
      }

      test(
        'returns an error naming an unknown modifier and presses nothing',
        () async {
          final List<KeyEvent> heard = <KeyEvent>[];
          bool handler(KeyEvent event) {
            heard.add(event);

            return false;
          }

          HardwareKeyboard.instance.addHandler(handler);
          addTearDown(() => HardwareKeyboard.instance.removeHandler(handler));

          final response = await aiTestPressKeyHandler(
            'ext.tapir.press_key',
            <String, String>{
              'key': 'Enter',
              'modifiers': 'shift,hyper',
            },
          );

          expect(response.result, isNull);
          expect(response.errorDetail ?? '', contains('unknown modifier'));
          expect(response.errorDetail ?? '', contains('hyper'));
          expect(heard, isEmpty);
        },
      );

      test('the same modifier named twice is pressed once', () async {
        final List<KeyEvent> heard = <KeyEvent>[];
        bool handler(KeyEvent event) {
          heard.add(event);

          return false;
        }

        HardwareKeyboard.instance.addHandler(handler);
        addTearDown(() => HardwareKeyboard.instance.removeHandler(handler));

        final response = await aiTestPressKeyHandler(
          'ext.tapir.press_key',
          <String, String>{
            'key': 'g',
            'modifiers': 'ctrl,control,shift,shift',
            'includeSnapshot': 'false',
          },
        );

        expect(response.errorDetail, isNull);
        expect(
          heard.whereType<KeyDownEvent>().map((e) => e.logicalKey).toList(),
          equals(<LogicalKeyboardKey>[
            LogicalKeyboardKey.controlLeft,
            LogicalKeyboardKey.shiftLeft,
            LogicalKeyboardKey.keyG,
          ]),
        );
        expect(HardwareKeyboard.instance.physicalKeysPressed, isEmpty);
      });

      testWidgets(
        'a Shift+Tab shortcut fires on Tab with shift held, and not on a '
        'plain Tab',
        (WidgetTester tester) async {
          final List<KeyEvent> heard = <KeyEvent>[];
          int fired = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(
                      LogicalKeyboardKey.tab,
                      shift: true,
                    ): () => fired++,
                  },
                  child: Focus(
                    autofocus: true,
                    onKeyEvent: (FocusNode node, KeyEvent event) {
                      heard.add(event);

                      return KeyEventResult.ignored;
                    },
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          );

          Future<void> press(Map<String, String> params) async {
            final future = aiTestPressKeyHandler(
              'ext.tapir.press_key',
              <String, String>{
                ...params,
                'includeSnapshot': 'false',
              },
            );
            bool done = false;
            unawaited(future.whenComplete(() => done = true));
            // Pumps with a duration so the handler's frame waits complete
            // whichever frame they land on.
            for (int i = 0; i < 20 && !done; i++) {
              await tester.pump(const Duration(milliseconds: 50));
            }
            final response = await future;
            expect(response.result, isNotNull);
          }

          await press(<String, String>{
            'key': 'Tab',
            'modifiers': 'shift',
          });

          expect(fired, 1);
          expect(
            heard.whereType<KeyDownEvent>().map((KeyEvent e) => e.logicalKey),
            contains(LogicalKeyboardKey.tab),
          );

          await press(<String, String>{
            'key': 'Tab',
          });

          expect(fired, 1);
          expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);
        },
      );

      test(
        'returns error when key is invalid despite valid modifiers',
        () async {
          final response = await aiTestPressKeyHandler(
            'ext.tapir.press_key',
            {
              'key': 'BadKey',
              'modifiers': 'ctrl',
            },
          );
          expect(response.result, isNull);
        },
      );
    });

    group('aiTestTypeHandler actionability gate', () {
      setUp(RefRegistry.resetForTesting);

      // -----------------------------------------------------------------------
      // (d) Zero-rect entry → type fails with descriptive actionability error
      // -----------------------------------------------------------------------

      testWidgets(
        '(d) zero-rect ref returns "zero rect" actionability error',
        (WidgetTester tester) async {
          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: Center(child: TextField()),
              ),
            ),
          );

          final Element element = tester.element(find.byType(TextField));
          final String ref = RefRegistry.registerForTesting(
            rect: const Rect.fromLTWH(10, 10, 0, 40),
            element: element,
            groupId: 'g',
            isTextField: true,
          );

          final response = await aiTestTypeHandler(
            'ext.tapir.type',
            <String, String>{'ref': ref, 'text': 'hello'},
          );

          expect(response.result, isNull);
          expect(
            response.errorDetail ?? '',
            contains('Widget ref=$ref is not actionable: zero rect'),
          );
        },
      );

      testWidgets(
        '(d) off-viewport ref returns "off-viewport" actionability error',
        (WidgetTester tester) async {
          tester.view.physicalSize = const Size(800, 600);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: Center(child: TextField()),
              ),
            ),
          );

          final Element element = tester.element(find.byType(TextField));
          final String ref = RefRegistry.registerForTesting(
            rect: const Rect.fromLTWH(5000, 5000, 80, 40),
            element: element,
            groupId: 'g',
            isTextField: true,
          );

          final response = await aiTestTypeHandler(
            'ext.tapir.type',
            <String, String>{'ref': ref, 'text': 'world'},
          );

          expect(response.result, isNull);
          expect(
            response.errorDetail ?? '',
            allOf(
              contains('Widget ref=$ref is not actionable'),
              contains('off-viewport'),
            ),
          );
        },
      );

      // -----------------------------------------------------------------------
      // Success path — actionable RefRegistry entry passes the gate and types
      // -----------------------------------------------------------------------

      testWidgets(
        'actionable ref types text into the field and returns ok envelope',
        (WidgetTester tester) async {
          tester.view.physicalSize = const Size(800, 600);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final TextEditingController controller = TextEditingController();
          addTearDown(controller.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(child: TextField(controller: controller)),
              ),
            ),
          );

          final Element element = tester.element(find.byType(TextField));
          final String ref = RefRegistry.registerForTesting(
            rect: const Rect.fromLTWH(100, 100, 200, 40),
            element: element,
            groupId: 'g',
            isTextField: true,
          );

          // Handler awaits two endOfFrame ticks; pump alongside so frames
          // advance under fake-async. Stable + receives-events gates
          // opt-out: registerForTesting mints a synthetic rect that does
          // not align with the live TextField geometry.
          final future = aiTestTypeHandler(
            'ext.tapir.type',
            <String, String>{
              'ref': ref,
              'text': 'typed',
              'checkStable': 'false',
              'checkReceivesEvents': 'false',
            },
          );
          await tester.pump();
          await tester.pump();
          final response = await future;

          expect(response.result, isNotNull);
          final Map<String, dynamic> decoded =
              jsonDecode(response.result!) as Map<String, dynamic>;
          expect(decoded['text'], equals('typed'));
          expect(controller.text, equals('typed'));
        },
      );

      // -----------------------------------------------------------------------
      // Rect-based selection: a SemanticsNode-minted ref carries the app-root
      // element, so a descendant-first walk resolves field #1. typeIntoElement
      // must select the field whose rect matches targetRect instead, so a
      // multi-field form writes the field the agent actually targeted.
      // -----------------------------------------------------------------------

      testWidgets(
        '(rect) writes the field matching targetRect, not the first editable',
        (WidgetTester tester) async {
          final TextEditingController email = TextEditingController();
          final TextEditingController password = TextEditingController();
          addTearDown(email.dispose);
          addTearDown(password.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Column(
                  children: <Widget>[
                    TextField(controller: email),
                    TextField(controller: password),
                  ],
                ),
              ),
            ),
          );

          // The SECOND (password) field is the agent's target.
          final Rect target = tester.getRect(find.byType(EditableText).at(1));

          // element = app root (the SemanticsNode-minted-ref shape); a plain
          // descendant-first walk would land on field #1 (email). The rect
          // routes the write to the targeted field instead.
          await typeIntoElement(
            element: WidgetsBinding.instance.rootElement!,
            text: 'secret',
            targetRect: target,
          );
          await tester.pump();
          await tester.pump();

          expect(password.text, equals('secret'));
          expect(email.text, isEmpty);
        },
      );

      testWidgets(
        '(rect) skips an identical field on a route covered by the target',
        (WidgetTester tester) async {
          // Two instances of one screen stacked on the navigator (a login
          // route pushed over a redirected login route): the covered one is
          // kept alive and laid out at the same rect, so it ties on overlap
          // and, visited first, used to win. The write then landed in a form
          // nobody could see while the read-back still said `verified`.
          final TextEditingController covered = TextEditingController();
          final TextEditingController visible = TextEditingController();
          addTearDown(covered.dispose);
          addTearDown(visible.dispose);

          final GlobalKey<NavigatorState> navigator =
              GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              home: Scaffold(body: TextField(controller: covered)),
            ),
          );
          // No transition, as go_router's `NoTransitionPage` (what magic builds
          // on web): the covered page keeps its exact rect. A zoom or slide
          // transition would leave it displaced and hide the tie.
          navigator.currentState!.push(
            PageRouteBuilder<void>(
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (_, __, ___) =>
                  Scaffold(body: TextField(controller: visible)),
            ),
          );
          await tester.pumpAndSettle();

          final Rect target = tester.getRect(find.byType(EditableText));

          await typeIntoElement(
            element: WidgetsBinding.instance.rootElement!,
            text: 'demo@uptizm.test',
            targetRect: target,
          );
          await tester.pump();

          expect(visible.text, equals('demo@uptizm.test'));
          expect(covered.text, isEmpty);
        },
      );

      testWidgets(
        '(rect) a visible form under muted tickers still targets by rect',
        (WidgetTester tester) async {
          // An app may mute tickers over a visible subtree on purpose. The
          // covered-route filter must not leave such a form with no candidate,
          // which would send every write to its first field.
          final TextEditingController email = TextEditingController();
          final TextEditingController password = TextEditingController();
          addTearDown(email.dispose);
          addTearDown(password.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: TickerMode(
                  enabled: false,
                  child: Column(
                    children: <Widget>[
                      TextField(controller: email),
                      TextField(controller: password),
                    ],
                  ),
                ),
              ),
            ),
          );

          final Rect target = tester.getRect(find.byType(EditableText).at(1));
          await typeIntoElement(
            element: WidgetsBinding.instance.rootElement!,
            text: 'secret',
            targetRect: target,
          );
          await tester.pump();

          expect(password.text, equals('secret'));
          expect(email.text, isEmpty);
        },
      );

      testWidgets(
        '(rect) a label target on a pushed lookalike never reaches the '
        'covered field',
        (WidgetTester tester) async {
          // A handle found by label text carries the LABEL's rect. On a screen
          // pushed over a lookalike, that rect can overlap the covered route's
          // field and no visible one; the visible field must still win.
          final TextEditingController covered = TextEditingController();
          final TextEditingController visible = TextEditingController();
          addTearDown(covered.dispose);
          addTearDown(visible.dispose);

          final GlobalKey<NavigatorState> navigator =
              GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              home: Scaffold(
                body: Column(
                  children: <Widget>[
                    const SizedBox(height: 112),
                    TextField(controller: covered),
                  ],
                ),
              ),
            ),
          );
          navigator.currentState!.push(
            PageRouteBuilder<void>(
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (_, __, ___) => Scaffold(
                body: Column(
                  children: <Widget>[
                    // The label sits level with the covered field and well
                    // above the visible one, so its rect overlaps only the
                    // field nobody can see.
                    const SizedBox(height: 120),
                    const Text('Name'),
                    const SizedBox(height: 100),
                    TextField(controller: visible),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final Rect label = tester.getRect(find.text('Name'));
          final Rect visibleRect = tester.getRect(find.byType(EditableText));
          expect(label.overlaps(visibleRect), isFalse);
          await typeIntoElement(
            element: WidgetsBinding.instance.rootElement!,
            text: 'x',
            targetRect: label,
          );
          await tester.pump();

          expect(visible.text, equals('x'));
          expect(covered.text, isEmpty);
        },
      );

      testWidgets(
        '(rect) an enabled TickerMode inside a covered route is still muted',
        (WidgetTester tester) async {
          // Hero re-enables tickers under its own TickerMode; the covered
          // route's disabling ancestor still wins, as it does in Flutter.
          final TextEditingController covered = TextEditingController();
          final TextEditingController visible = TextEditingController();
          addTearDown(covered.dispose);
          addTearDown(visible.dispose);

          final GlobalKey<NavigatorState> navigator =
              GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              home: Scaffold(
                body: TickerMode(
                  enabled: true,
                  child: TextField(controller: covered),
                ),
              ),
            ),
          );
          navigator.currentState!.push(
            PageRouteBuilder<void>(
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (_, __, ___) =>
                  Scaffold(body: TextField(controller: visible)),
            ),
          );
          await tester.pumpAndSettle();

          await typeIntoElement(
            element: WidgetsBinding.instance.rootElement!,
            text: 'y',
            targetRect: tester.getRect(find.byType(EditableText)),
          );
          await tester.pump();

          expect(visible.text, equals('y'));
          expect(covered.text, isEmpty);
        },
      );

      testWidgets(
        '(no rect) a lone muted field is still written',
        (WidgetTester tester) async {
          // The rect-less fallback's second pass: with every field muted, the
          // first one is the answer rather than none at all.
          final TextEditingController only = TextEditingController();
          addTearDown(only.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: TickerMode(
                  enabled: false,
                  child: TextField(controller: only),
                ),
              ),
            ),
          );

          await typeIntoElement(
            element: WidgetsBinding.instance.rootElement!,
            text: 'z',
          );
          await tester.pump();

          expect(only.text, equals('z'));
        },
      );

      testWidgets(
        '(no rect) the fallback skips a field on a covered route',
        (WidgetTester tester) async {
          final TextEditingController covered = TextEditingController();
          final TextEditingController visible = TextEditingController();
          addTearDown(covered.dispose);
          addTearDown(visible.dispose);

          final GlobalKey<NavigatorState> navigator =
              GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              home: Scaffold(body: TextField(controller: covered)),
            ),
          );
          navigator.currentState!.push(
            PageRouteBuilder<void>(
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (_, __, ___) =>
                  Scaffold(body: TextField(controller: visible)),
            ),
          );
          await tester.pumpAndSettle();

          await typeIntoElement(
            element: WidgetsBinding.instance.rootElement!,
            text: 'typed',
          );
          await tester.pump();

          expect(visible.text, equals('typed'));
          expect(covered.text, isEmpty);
        },
      );

      testWidgets(
        '(rect) clear empties the field matching targetRect, not the first',
        (WidgetTester tester) async {
          tester.view.physicalSize = const Size(800, 600);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final TextEditingController email = TextEditingController(
            text: 'a@b.com',
          );
          final TextEditingController password = TextEditingController(
            text: 'secret',
          );
          addTearDown(email.dispose);
          addTearDown(password.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Column(
                  children: <Widget>[
                    TextField(controller: email),
                    TextField(controller: password),
                  ],
                ),
              ),
            ),
          );

          // Target the SECOND (password) field by its rect, but register the
          // ref against the app root (the SemanticsNode-minted-ref shape) so a
          // plain descendant-first walk would clear field #1 (email) instead.
          final Rect target = tester.getRect(find.byType(EditableText).at(1));
          final String ref = RefRegistry.registerForTesting(
            rect: target,
            element: WidgetsBinding.instance.rootElement!,
            groupId: 'g',
            isTextField: true,
          );

          final future = aiTestClearHandler(
            'ext.tapir.clear',
            <String, String>{
              'ref': ref,
              'checkStable': 'false',
              'checkReceivesEvents': 'false',
            },
          );
          await tester.pump();
          await tester.pump();
          await future;

          // The rect routed the clear to the targeted (password) field; the
          // first editable (email) is untouched.
          expect(password.text, isEmpty);
          expect(email.text, equals('a@b.com'));
        },
      );

      testWidgets(
        '(rect) clear via a q-ref derives the target from the node render rect',
        (WidgetTester tester) async {
          tester.view.physicalSize = const Size(800, 600);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          RefRegistry.resetForTesting();

          final TextEditingController controller = TextEditingController(
            text: 'clear-me',
          );
          addTearDown(controller.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: Semantics(
                    label: 'search-field',
                    child: TextField(controller: controller),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          // A q-ref (unlike registerForTesting) carries the matched
          // SemanticsNode, so clear resolves the target rect from the node's own
          // render object via _localToGlobalRectForNode instead of a stored
          // rect. This is the real find -> clear path.
          final findResponse = await extTapirFindHandler(
            'ext.tapir.find',
            <String, String>{'semanticsLabel': 'search-field'},
          );
          final String qRef = (jsonDecode(findResponse.result!)
              as Map<String, dynamic>)['ref'] as String;
          expect(qRef, startsWith('q'));

          final future = aiTestClearHandler(
            'ext.tapir.clear',
            <String, String>{
              'ref': qRef,
              'checkStable': 'false',
              'checkReceivesEvents': 'false',
            },
          );
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump();
          await tester.pump();
          await future;

          expect(controller.text, isEmpty);
        },
      );
    });

    group('ext.tapir.press_key registration', () {
      // -----------------------------------------------------------------------
      // Test registration state (no duplicate handler).
      //
      // Uses testWidgets so the handler's post-Step-3.2 endOfFrame awaits
      // can settle. A bare test() would hang once any prior testWidgets
      // has initialised the WidgetsBinding rootElement.
      // -----------------------------------------------------------------------

      testWidgets(
        'ext.tapir.press_key is registered after registerTextInputExtensions',
        (WidgetTester tester) async {
          await tester.pumpWidget(const MaterialApp(home: Scaffold()));
          registerTextInputExtensions();
          // If registration fails, it would throw; succeeding here validates
          // that the registration succeeded previously.
          final future = aiTestPressKeyHandler(
            'ext.tapir.press_key',
            <String, String>{'key': 'Enter'},
          );
          await tester.pump();
          await tester.pump();
          final response = await future;
          expect(response.result, isNotNull);
        },
      );
    });
  });

  group('text verbs on a ref that is not a text field', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    testWidgets(
      'type on a dropdown ref is refused and no field changes',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        final TextEditingController name = TextEditingController(text: 'Ada');
        addTearDown(name.dispose);
        await tester.pumpWidget(_DropdownForm(name: name));

        final String ref = _registerNodeRef(
          tester,
          find.byType(DropdownButton<String>),
        );
        final response = await _drive(
          tester,
          aiTestTypeHandler('ext.tapir.type', _quietParams(ref, text: 'Bob')),
        );

        expect(response.result, isNull);
        expect(
          parseMessageFromErrorDetail(response.errorDetail ?? ''),
          contains('ref $ref is a button, not a text field'),
        );
        expect(name.text, equals('Ada'));
        semantics.dispose();
      },
    );

    testWidgets(
      'clear on a dropdown ref is refused and leaves the Name field alone',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        final TextEditingController name = TextEditingController(text: 'Ada');
        addTearDown(name.dispose);
        await tester.pumpWidget(_DropdownForm(name: name));

        final String ref = _registerNodeRef(
          tester,
          find.byType(DropdownButton<String>),
        );
        final response = await _drive(
          tester,
          aiTestClearHandler('ext.tapir.clear', _quietParams(ref)),
        );

        expect(response.result, isNull);
        expect(response.errorDetail ?? '', contains('not a text field'));
        expect(name.text, equals('Ada'));
        semantics.dispose();
      },
    );

    testWidgets(
      'type on a label ref writes the adjacent field and reports nearest',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        final TextEditingController name = TextEditingController();
        addTearDown(name.dispose);
        await tester.pumpWidget(_LabelledForm(name: name));

        final Finder label = find.text('Full name');
        expect(
          tester.getRect(label).overlaps(
                tester.getRect(find.byType(EditableText)),
              ),
          isFalse,
        );
        final String ref = _registerNodeRef(tester, label);
        final response = await _drive(
          tester,
          aiTestTypeHandler('ext.tapir.type', _quietParams(ref, text: 'Ada')),
        );

        expect(name.text, equals('Ada'));
        final Map<String, dynamic> effect = _effectOf(response);
        expect(effect['verified'], isTrue);
        final Map<String, dynamic> target =
            effect['target'] as Map<String, dynamic>;
        expect(target['matchKind'], equals('nearest'));
        final Rect field = tester.getRect(find.byType(EditableText));
        expect(
          target['rect'],
          equals(<String, dynamic>{
            'x': field.left,
            'y': field.top,
            'width': field.width,
            'height': field.height,
          }),
        );
        semantics.dispose();
      },
    );

    testWidgets(
      'type on a field ref reports the overlapping field as its target',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        final TextEditingController name = TextEditingController();
        addTearDown(name.dispose);
        await tester.pumpWidget(_LabelledForm(name: name));

        final String ref = _registerNodeRef(tester, find.byType(TextField));
        final response = await _drive(
          tester,
          aiTestTypeHandler('ext.tapir.type', _quietParams(ref, text: 'Ada')),
        );

        final Map<String, dynamic> target =
            _effectOf(response)['target'] as Map<String, dynamic>;
        expect(target['matchKind'], equals('overlap'));
        expect(target['label'], equals('Name'));
        semantics.dispose();
      },
    );

    testWidgets(
      'type on a checkbox ref is refused as a checkbox',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        final TextEditingController name = TextEditingController(text: 'Ada');
        addTearDown(name.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  TextField(controller: name),
                  Checkbox(value: false, onChanged: (_) {}),
                ],
              ),
            ),
          ),
        );

        final String ref = _registerNodeRef(tester, find.byType(Checkbox));
        final response = await _drive(
          tester,
          aiTestTypeHandler('ext.tapir.type', _quietParams(ref, text: 'Bob')),
        );

        expect(response.result, isNull);
        expect(
          response.errorDetail ?? '',
          contains('ref $ref is a checkbox, not a text field'),
        );
        expect(name.text, equals('Ada'));
        semantics.dispose();
      },
    );

    testWidgets(
      'type with no rect reports the element walk as its target',
      (WidgetTester tester) async {
        final TextEditingController name = TextEditingController();
        addTearDown(name.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: TextField(controller: name)),
          ),
        );
        TestRefRegistry.inject('e700', tester.element(find.byType(TextField)));
        addTearDown(TestRefRegistry.clear);

        final response = await _drive(
          tester,
          aiTestTypeHandler(
            'ext.tapir.type',
            _quietParams('e700', text: 'walked'),
          ),
        );

        expect(name.text, equals('walked'));
        expect(
          (_effectOf(response)['target'] as Map<String, dynamic>)['matchKind'],
          equals('element'),
        );
      },
    );
  });

  group('aiTestTypeHandler settled value', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    testWidgets(
      'a field that reverts on the next frame reports verified:false',
      (WidgetTester tester) async {
        final TextEditingController controller = TextEditingController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: _RevertingField(controller: controller)),
          ),
        );

        final String ref = RefRegistry.registerForTesting(
          rect: tester.getRect(find.byType(TextField)),
          element: tester.element(find.byType(TextField)),
          groupId: 'g',
          isTextField: true,
        );
        final response = await _drive(
          tester,
          aiTestTypeHandler('ext.tapir.type', _quietParams(ref, text: 'abc')),
        );

        final Map<String, dynamic> effect = _effectOf(response);
        expect(effect['verified'], isFalse);
        expect(effect['value'], equals(''));
        expect(controller.text, isEmpty);
      },
    );

    testWidgets(
      'a digits-only field rejecting letters reports verified:false',
      (WidgetTester tester) async {
        final TextEditingController controller = TextEditingController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TextField(
                controller: controller,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
            ),
          ),
        );

        final String ref = RefRegistry.registerForTesting(
          rect: tester.getRect(find.byType(TextField)),
          element: tester.element(find.byType(TextField)),
          groupId: 'g',
          isTextField: true,
        );
        final response = await _drive(
          tester,
          aiTestTypeHandler('ext.tapir.type', _quietParams(ref, text: 'abc')),
        );

        final Map<String, dynamic> effect = _effectOf(response);
        expect(effect['verified'], isFalse);
        expect(effect['value'], equals(''));
        expect(
          (effect['target'] as Map<String, dynamic>)['matchKind'],
          equals('overlap'),
        );
      },
    );
  });

  group('TestRefRegistry', () {
    testWidgets('inject + lookup roundtrip, clear empties the table',
        (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final element = tester.element(find.byType(SizedBox));
      TestRefRegistry.inject('e42', element);
      expect(TestRefRegistry.lookup('e42'), equals(element));
      TestRefRegistry.clear();
      expect(TestRefRegistry.lookup('e42'), isNull);
    });

    test('lookup returns null for unknown ref', () {
      expect(TestRefRegistry.lookup('e9999'), isNull);
    });
  });

  group('typeIntoElement error paths', () {
    testWidgets('throws ArgumentError when no EditableText is in the subtree',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('plain'))),
      );
      final element = tester.element(find.byType(Scaffold));

      expect(
        () => typeIntoElement(element: element, text: 'hello'),
        throwsArgumentError,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Step 3.2 — snapshot-in-action-response (type + press_key handlers).
  // ---------------------------------------------------------------------------

  group('aiTestTypeHandler snapshot-in-response', () {
    setUp(RefRegistry.resetForTesting);

    testWidgets(
      'embeds snapshot field in success response by default',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final TextEditingController controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: TextField(controller: controller)),
            ),
          ),
        );

        final Element element = tester.element(find.byType(TextField));
        final String ref = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(100, 100, 200, 40),
          element: element,
          groupId: 'g',
          isTextField: true,
        );

        final future = aiTestTypeHandler(
          'ext.tapir.type',
          <String, String>{
            'ref': ref,
            'text': 'snap-type',
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
        );
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['text'], equals('snap-type'));
        expect(decoded['snapshot'], isA<String>());
      },
    );

    testWidgets(
      'omits snapshot when includeSnapshot is false',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final TextEditingController controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: TextField(controller: controller)),
            ),
          ),
        );

        final Element element = tester.element(find.byType(TextField));
        final String ref = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(100, 100, 200, 40),
          element: element,
          groupId: 'g',
          isTextField: true,
        );

        final future = aiTestTypeHandler(
          'ext.tapir.type',
          <String, String>{
            'ref': ref,
            'text': 'no-snap-type',
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
            'includeSnapshot': 'false',
          },
        );
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded.containsKey('snapshot'), isFalse);
      },
    );

    testWidgets(
      'snapshot YAML reflects the post-type tree',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final TextEditingController controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: TextField(controller: controller)),
            ),
          ),
        );

        final Element element = tester.element(find.byType(TextField));
        final String ref = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(100, 100, 200, 40),
          element: element,
          groupId: 'g',
          isTextField: true,
        );

        final future = aiTestTypeHandler(
          'ext.tapir.type',
          <String, String>{
            'ref': ref,
            'text': 'snap-type-content',
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
        );
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        // The TextField's textbox role is the marker emitted by
        // tapirSnapBuild for editable nodes.
        expect(decoded['snapshot'] as String, contains('textbox'));
      },
    );

    testWidgets(
      'snapshot=diff answers the field line the type changed',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        resetSnapshotBaselineForTesting();
        addTearDown(resetSnapshotBaselineForTesting);

        final TextEditingController controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: TextField(controller: controller)),
            ),
          ),
        );
        await tapirSnapBuild();

        final Element element = tester.element(find.byType(TextField));
        final String ref = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(100, 100, 200, 40),
          element: element,
          groupId: 'g',
          isTextField: true,
        );

        final future = aiTestTypeHandler(
          'ext.tapir.type',
          <String, String>{
            'ref': ref,
            'text': 'diff-typed',
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
            'snapshot': 'diff',
          },
        );
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['snapshotMode'], 'diff');
        final List<String> lines = (decoded['snapshot'] as String).split('\n');
        expect(
          lines.where((String l) => l.startsWith('+ ')),
          contains(contains('"diff-typed"')),
        );
        expect(lines.last, endsWith('lines changed)'));
      },
    );
  });

  group('aiTestPressKeyHandler snapshot-in-response', () {
    testWidgets(
      'embeds snapshot field in success response by default',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('presskey-snap'))),
          ),
        );

        final future = aiTestPressKeyHandler(
          'ext.tapir.press_key',
          <String, String>{'key': 'Enter'},
        );
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(decoded['key'], equals('Enter'));
        expect(decoded['snapshot'], isA<String>());
      },
    );

    testWidgets(
      'omits snapshot when includeSnapshot is false',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('presskey-nosnap'))),
          ),
        );

        final future = aiTestPressKeyHandler(
          'ext.tapir.press_key',
          <String, String>{
            'key': 'Tab',
            'includeSnapshot': 'false',
          },
        );
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded.containsKey('snapshot'), isFalse);
      },
    );

    testWidgets(
      'snapshot YAML reflects the post-key tree contents',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(child: Text('presskey-content-marker')),
            ),
          ),
        );

        final future = aiTestPressKeyHandler(
          'ext.tapir.press_key',
          <String, String>{'key': 'Escape'},
        );
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(
            decoded['snapshot'] as String, contains('presskey-content-marker'));
      },
    );

    testWidgets(
      'snapshot=diff on a key that changed nothing reports zero lines',
      (WidgetTester tester) async {
        resetSnapshotBaselineForTesting();
        addTearDown(resetSnapshotBaselineForTesting);
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('presskey-diff'))),
          ),
        );
        await tapirSnapBuild();

        final future = aiTestPressKeyHandler(
          'ext.tapir.press_key',
          <String, String>{'key': 'Escape', 'snapshot': 'diff'},
        );
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['snapshotMode'], 'diff');
        expect(decoded['snapshot'],
            matches(RegExp(r'^\(0 of \d+ lines changed\)$')));
      },
    );
  });

  group('aiTestTypeHandler param + error paths', () {
    test('missing ref returns missing-param error', () async {
      final response = await aiTestTypeHandler(
        'ext.tapir.type',
        const <String, String>{'text': 'hello'},
      );
      expect(response.result, isNull);
      expect(
        parseMessageFromErrorDetail(response.errorDetail ?? ''),
        contains('missing required param "ref"'),
      );
    });

    test('empty ref returns missing-param error', () async {
      final response = await aiTestTypeHandler(
        'ext.tapir.type',
        const <String, String>{'ref': '', 'text': 'hello'},
      );
      expect(response.result, isNull);
      expect(
        parseMessageFromErrorDetail(response.errorDetail ?? ''),
        contains('missing required param "ref"'),
      );
    });

    test('unknown ref returns not-found error', () async {
      final response = await aiTestTypeHandler(
        'ext.tapir.type',
        const <String, String>{'ref': 'e9999', 'text': 'hello'},
      );
      expect(response.result, isNull);
      expect(
        response.errorDetail ?? '',
        contains('not found in registry'),
      );
    });
  });

  // =========================================================================
  // aiTestClearHandler error paths — covers the early-exit branches inside
  // `aiTestClearHandler` (missing ref, unknown ref) so coverage on
  // `ext_text_input.dart` lines 514-545 increases without needing a real
  // EditableText widget setup.
  // =========================================================================
  group('aiTestClearHandler error paths', () {
    test('missing ref returns missing_param error envelope', () async {
      final response = await aiTestClearHandler(
        'ext.tapir.clear',
        const <String, String>{},
      );
      expect(response.result, isNull);
      expect(response.errorDetail ?? '', contains('missing required param'));
      expect(response.errorDetail ?? '', contains('ref'));
    });

    test('empty ref string returns missing_param error envelope', () async {
      final response = await aiTestClearHandler(
        'ext.tapir.clear',
        const <String, String>{'ref': ''},
      );
      expect(response.result, isNull);
      expect(response.errorDetail ?? '', contains('missing required param'));
    });

    test('unknown ref returns not-found error envelope', () async {
      final response = await aiTestClearHandler(
        'ext.tapir.clear',
        const <String, String>{'ref': 'e9999'},
      );
      expect(response.result, isNull);
      expect(
        response.errorDetail ?? '',
        contains('not found in registry'),
      );
    });
  });
}

/// Gate opt-outs for a test-minted ref, whose rect is not re-validated.
Map<String, String> _quietParams(String ref, {String? text}) =>
    <String, String>{
      'ref': ref,
      if (text != null) 'text': text,
      'checkStable': 'false',
      'checkReceivesEvents': 'false',
      'includeSnapshot': 'false',
    };

/// Registers an `e<N>` ref the way a snapshot mints one from a semantics
/// node: the node and its rect, carried by the app-root element.
String _registerNodeRef(WidgetTester tester, Finder finder) =>
    RefRegistry.register(
      rect: tester.getRect(finder),
      element: WidgetsBinding.instance.rootElement!,
      groupId: 'g',
      isTextField: false,
      node: tester.getSemantics(finder),
    );

/// Pumps frames until [pending] completes, so a handler's frame waits land.
Future<developer.ServiceExtensionResponse> _drive(
  WidgetTester tester,
  Future<developer.ServiceExtensionResponse> pending,
) async {
  bool done = false;
  unawaited(pending.whenComplete(() => done = true));
  for (int i = 0; i < 20 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }

  return pending;
}

Map<String, dynamic> _effectOf(developer.ServiceExtensionResponse response) {
  expect(response.result, isNotNull, reason: response.errorDetail);
  final Map<String, dynamic> decoded =
      jsonDecode(response.result!) as Map<String, dynamic>;

  return decoded['effect'] as Map<String, dynamic>;
}

/// A Name field above a dropdown, the F-23 shape: the dropdown's rect overlaps
/// no editable, so the nearest one used to be written instead.
class _DropdownForm extends StatelessWidget {
  const _DropdownForm({required this.name});

  final TextEditingController name;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: <Widget>[
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 40),
            DropdownButton<String>(
              value: 'apple',
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(value: 'apple', child: Text('Apple')),
                DropdownMenuItem<String>(value: 'pear', child: Text('Pear')),
              ],
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    );
  }
}

/// A static label above a field it does not overlap, the handle shape a find
/// by label text returns.
class _LabelledForm extends StatelessWidget {
  const _LabelledForm({required this.name});

  final TextEditingController name;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: <Widget>[
            Semantics(container: true, child: const Text('Full name')),
            const SizedBox(height: 24),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A field whose owner resets it a frame after every write, the shape of a
/// formatter or an echo that refuses the value asynchronously.
class _RevertingField extends StatefulWidget {
  const _RevertingField({required this.controller});

  final TextEditingController controller;

  @override
  State<_RevertingField> createState() => _RevertingFieldState();
}

class _RevertingFieldState extends State<_RevertingField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_revert);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_revert);
    super.dispose();
  }

  void _revert() {
    if (widget.controller.text.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) =>
      TextField(controller: widget.controller);
}

/// A focused [Focus] that records every key event it hears, which is what a
/// real keyboard press reaches and a [HardwareKeyboard]-only dispatch does not.
class _KeyListener extends StatelessWidget {
  const _KeyListener({required this.heard});

  final List<KeyEvent> heard;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Focus(
        autofocus: true,
        onKeyEvent: (FocusNode node, KeyEvent event) {
          heard.add(event);

          return KeyEventResult.handled;
        },
        child: const SizedBox.expand(),
      ),
    );
  }
}
