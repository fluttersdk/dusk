import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/dusk_error_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DuskErrorCapture', () {
    setUp(resetCapturedExceptionsForTesting);
    tearDown(resetCapturedExceptionsForTesting);

    group('installErrorCapture()', () {
      testWidgets(
        'captures a RenderFlex overflow as a non-fatal entry and chains the '
        'prior handler',
        (tester) async {
          // 1. Save and restore the binding-installed handler around the test.
          final FlutterExceptionHandler? prior = FlutterError.onError;
          addTearDown(() => FlutterError.onError = prior);

          // 2. Spy on the prior handler so we can assert it is still invoked.
          bool priorInvoked = false;
          FlutterError.onError = (FlutterErrorDetails details) {
            priorInvoked = true;
          };

          installErrorCapture();
          addTearDown(uninstallErrorCapture);

          // 3. Trigger a real overflow via a narrow viewport.
          tester.view.physicalSize = const Size(50, 600);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            const Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                children: <Widget>[
                  SizedBox(width: 400, height: 100),
                  SizedBox(width: 400, height: 100),
                ],
              ),
            ),
          );

          final List<Map<String, dynamic>> captured =
              recentCapturedExceptions();

          expect(captured, isNotEmpty);
          final Map<String, dynamic> entry = captured.first;
          expect(entry['message'] as String, contains('overflowed by'));
          expect(entry['type'], equals('overflow'));
          expect(entry['fatal'], isFalse);
          expect(entry['library'], equals('rendering library'));
          expect(entry['stackHead'], isA<String>());
          expect(entry['time'], isA<String>());
          expect(priorInvoked, isTrue);
        },
      );
    });

    group('uninstallErrorCapture()', () {
      test('restores the prior handler', () {
        final FlutterExceptionHandler? prior = FlutterError.onError;
        addTearDown(() => FlutterError.onError = prior);

        installErrorCapture();
        expect(FlutterError.onError, isNot(equals(prior)));

        uninstallErrorCapture();
        expect(FlutterError.onError, equals(prior));
      });

      test('re-captures the prior handler on each install', () {
        final FlutterExceptionHandler? original = FlutterError.onError;
        addTearDown(() => FlutterError.onError = original);

        void firstPrior(FlutterErrorDetails _) {}
        FlutterError.onError = firstPrior;
        installErrorCapture();
        uninstallErrorCapture();
        expect(FlutterError.onError, equals(firstPrior));

        void secondPrior(FlutterErrorDetails _) {}
        FlutterError.onError = secondPrior;
        installErrorCapture();
        uninstallErrorCapture();
        expect(FlutterError.onError, equals(secondPrior));
      });
    });

    group('recentCapturedExceptions()', () {
      test('dedupes by message + stackHead', () {
        final FlutterExceptionHandler? prior = FlutterError.onError;
        addTearDown(() => FlutterError.onError = prior);

        installErrorCapture();
        addTearDown(uninstallErrorCapture);

        final FlutterErrorDetails details = FlutterErrorDetails(
          exception: FlutterError('A RenderFlex overflowed by 100 pixels.'),
          library: 'rendering library',
          stack: StackTrace.fromString('frame#0\nframe#1\nframe#2'),
        );

        FlutterError.onError!(details);
        FlutterError.onError!(details);

        expect(recentCapturedExceptions(), hasLength(1));
      });

      test('caps the buffer at 50 entries, newest-first', () {
        final FlutterExceptionHandler? prior = FlutterError.onError;
        addTearDown(() => FlutterError.onError = prior);

        installErrorCapture();
        addTearDown(uninstallErrorCapture);

        for (int i = 0; i < 60; i++) {
          FlutterError.onError!(
            FlutterErrorDetails(
              exception: ArgumentError('error number $i'),
              library: 'test library',
              stack: StackTrace.fromString('frame for $i'),
            ),
          );
        }

        final List<Map<String, dynamic>> all =
            recentCapturedExceptions(limit: 100);
        expect(all, hasLength(50));
        // Newest-first: the last recorded error (59) is at the head.
        expect(all.first['message'] as String, contains('error number 59'));
        expect(all.last['message'] as String, contains('error number 10'));
      });

      test('honors the limit argument', () {
        final FlutterExceptionHandler? prior = FlutterError.onError;
        addTearDown(() => FlutterError.onError = prior);

        installErrorCapture();
        addTearDown(uninstallErrorCapture);

        for (int i = 0; i < 10; i++) {
          FlutterError.onError!(
            FlutterErrorDetails(
              exception: ArgumentError('error $i'),
              stack: StackTrace.fromString('frame $i'),
            ),
          );
        }

        expect(recentCapturedExceptions(limit: 3), hasLength(3));
      });
    });
  });
}
