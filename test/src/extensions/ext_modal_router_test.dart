import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_modal_router.dart';

void main() {
  // NOTE: The original implementation awaited endOfFrame between pops, which
  // hangs the flutter_test fake-clock harness when real modal routes are open.
  //
  // The fixed implementation uses popUntil per NavigatorState with no
  // endOfFrame waits, so real modal routes CAN be tested here. Tests that open
  // a modal must call tester.pump() after dismissAllModals() to settle the
  // widget tree.

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

    testWidgets(
      'dismisses a showModalBottomSheet on the nearest navigator (popped==1)',
      (tester) async {
        // 1. Pump a minimal MaterialApp so there is a Navigator + Overlay.
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => const SizedBox(
                      height: 200,
                      child: Center(child: Text('sheet')),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );

        // 2. Open the bottom sheet (nearest navigator, useRootNavigator: false).
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('sheet'), findsOneWidget);

        // 3. Dismiss via the extension under test.
        final popped = await dismissAllModals();
        // pumpAndSettle lets the route exit animation finish and the route
        // entry be removed from the overlay. The sheet uses Duration.zero-ish
        // transitions in test mode but still needs at least one frame.
        await tester.pumpAndSettle();

        // 4. The sheet must be gone and exactly one route was popped.
        expect(popped, equals(1));
        expect(find.text('sheet'), findsNothing);
      },
    );

    testWidgets(
      'dismisses two stacked PopupRoutes on the same navigator; '
      'returns additive total (popped==2)',
      (tester) async {
        // Reproduce the multi-modal count bug: the original implementation
        // only popped one PopupRoute per call because it awaited endOfFrame
        // after each pop (which would hang in test harness) and was
        // structured as a one-at-a-time loop. The new popUntil-per-navigator
        // approach dismisses ALL PopupRoutes on each navigator atomically.
        //
        // showDialog defaults useRootNavigator: true and showModalBottomSheet
        // defaults useRootNavigator: false. In a single-navigator app both
        // land on the same navigator. We open both and verify popped==2.

        // 1. Capture the Scaffold context via a GlobalKey so we can call
        //    showDialog / showModalBottomSheet after pumpWidget returns.
        final scaffoldKey = GlobalKey<ScaffoldState>();
        late NavigatorState nav;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                nav = Navigator.of(context);
                return Scaffold(
                  key: scaffoldKey,
                  body: const Text('home'),
                );
              },
            ),
          ),
        );
        await tester.pump();

        // Resolve a context that is inside the MaterialApp so Material
        // Localizations and Navigator are available.
        final BuildContext ctx = tester.element(find.byKey(scaffoldKey));

        // 2. Push dialog (PopupRoute via showDialog -> RawDialogRoute).
        showDialog<void>(
          context: ctx,
          builder: (_) => const AlertDialog(title: Text('dialog')),
        );
        await tester.pumpAndSettle();
        expect(find.text('dialog'), findsOneWidget);

        // 3. Push bottom sheet on top of the dialog (second PopupRoute).
        showModalBottomSheet<void>(
          context: ctx,
          builder: (_) => const SizedBox(
            height: 200,
            child: Center(child: Text('sheet')),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('sheet'), findsOneWidget);

        // 4. Dismiss all modals. Both PopupRoutes must be removed.
        final popped = await dismissAllModals();
        await tester.pumpAndSettle();

        expect(popped, equals(2));
        expect(find.text('sheet'), findsNothing);
        expect(find.text('dialog'), findsNothing);

        // Home page must still be present (page route was NOT popped).
        expect(find.text('home'), findsOneWidget);
        expect(nav.canPop(), isFalse);
      },
    );
  });

  group('registerModalRouterExtension', () {
    test('runs without throwing twice in a row (hot-restart safe)', () {
      registerModalRouterExtension();
      registerModalRouterExtension();
    });
  });

  group('aiTestResetOverlaysHandler', () {
    testWidgets('idempotent: returns popped=0 when no overlays are open',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('idle'))),
      );

      // First call: nothing to dismiss. runAsync drives the handler's
      // endOfFrame.timeout settle steps against a real clock.
      final first = await tester.runAsync(() async {
        return aiTestResetOverlaysHandler(
          'ext.dusk.reset_overlays',
          const <String, String>{},
        );
      });
      expect(first!.errorCode, isNull);
      final Map<String, dynamic> firstJson =
          jsonDecode(first.result!) as Map<String, dynamic>;
      expect(firstJson['popped'], equals(0));

      // Second call on the same idle tree: identical result (idempotent).
      final second = await tester.runAsync(() async {
        return aiTestResetOverlaysHandler(
          'ext.dusk.reset_overlays',
          const <String, String>{},
        );
      });
      expect(second!.errorCode, isNull);
      final Map<String, dynamic> secondJson =
          jsonDecode(second.result!) as Map<String, dynamic>;
      expect(secondJson['popped'], equals(0));
    });

    testWidgets('dismisses an open bottom sheet and reports popped>=1',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const SizedBox(
                    height: 150,
                    child: Center(child: Text('reset-sheet')),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('reset-sheet'), findsOneWidget);

      final response = await tester.runAsync(() async {
        return aiTestResetOverlaysHandler(
          'ext.dusk.reset_overlays',
          const <String, String>{},
        );
      });
      await tester.pumpAndSettle();

      expect(response!.errorCode, isNull);
      final Map<String, dynamic> json =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(json['popped'], equals(1));
      expect(find.text('reset-sheet'), findsNothing);

      // Calling again on the now-clean tree is a no-op (idempotent).
      final again = await tester.runAsync(() async {
        return aiTestResetOverlaysHandler(
          'ext.dusk.reset_overlays',
          const <String, String>{},
        );
      });
      final Map<String, dynamic> againJson =
          jsonDecode(again!.result!) as Map<String, dynamic>;
      expect(againJson['popped'], equals(0));
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
      'no modals + navigator present → popUntil short-circuits on page route',
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
        // is NOT a PopupRoute — exercises the popUntil stop condition.
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

    testWidgets(
      'handler returns popped==1 when a bottom sheet is open',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => const SizedBox(
                      height: 150,
                      child: Center(child: Text('handler-sheet')),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('handler-sheet'), findsOneWidget);

        final response = await aiTestDismissModalsHandler(
          'ext.dusk.dismiss_modals',
          const <String, String>{},
        );
        await tester.pumpAndSettle();

        expect(response.errorCode, isNull);
        expect(response.result, contains('"popped":1'));
        expect(find.text('handler-sheet'), findsNothing);
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
