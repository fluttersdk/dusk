import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_modal_router.dart';

void main() {
  // dismissAllModals awaits endOfFrame between pops, which hangs the
  // flutter_test fake-clock harness when real modal routes are open. We
  // restrict tests to the no-modal / no-navigator / handler-envelope
  // paths; multi-modal dismiss is covered by the example/ live drive
  // (dusk:modal against the /modals screen).

  group('dismissAllModals helper', () {
    testWidgets('returns 0 when binding root is unset', (tester) async {
      // Pumping no widget leaves rootElement null in some test paths;
      // dismissAllModals must short-circuit safely.
      final dismissed = await dismissAllModals();
      expect(dismissed, equals(0));
    });

    testWidgets('returns 0 when no Navigator exists in the tree',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Text('No nav'),
        ),
      );
      final dismissed = await dismissAllModals();
      expect(dismissed, equals(0));
    });
  });

  group('registerModalRouterExtension', () {
    test('runs without throwing twice in a row (hot-restart safe)', () {
      registerModalRouterExtension();
      registerModalRouterExtension();
    });
  });

  group('isModalRoute', () {
    test('returns true for a PopupRoute subclass', () {
      expect(isModalRoute(_TestPopupRoute<void>()), isTrue);
    });

    test('returns false for a MaterialPageRoute (regular page route)', () {
      final page = MaterialPageRoute<void>(
        builder: (_) => const SizedBox(),
      );
      expect(isModalRoute(page), isFalse);
    });
  });

  group('aiTestDismissModalsHandler envelope', () {
    testWidgets('returns popped=0 when no modals are open', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('idle'))),
      );

      final response = await aiTestDismissModalsHandler(
        'ext.dusk.dismiss_modals',
        const <String, String>{},
      );
      expect(response.errorCode, isNull);
      expect(response.result, contains('"popped":0'));
    });

    testWidgets(
      'no modals + navigator present → loop short-circuits via popUntil peek',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            routes: <String, WidgetBuilder>{
              '/': (_) => const Scaffold(body: Text('home')),
              '/second': (_) => const Scaffold(body: Text('second')),
            },
          ),
        );

        // Push a regular page route so canPop() is true but the top route
        // is NOT a PopupRoute — exercises the `!isModalRoute(topRoute!)` break.
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        navigator.pushNamed('/second');
        await tester.pumpAndSettle();
        expect(navigator.canPop(), isTrue);

        final response = await aiTestDismissModalsHandler(
          'ext.dusk.dismiss_modals',
          const <String, String>{},
        );
        expect(response.errorCode, isNull);
        expect(response.result, contains('"popped":0'));
      },
    );
  });
}

class _TestPopupRoute<T> extends PopupRoute<T> {
  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => false;
  @override
  String? get barrierLabel => null;
  @override
  Duration get transitionDuration => Duration.zero;
  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      const SizedBox.shrink();
}
