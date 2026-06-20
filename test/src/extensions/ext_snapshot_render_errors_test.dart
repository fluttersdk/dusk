import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_dusk/src/dusk_error_capture.dart';
import 'package:fluttersdk_dusk/src/extensions/ext_snapshot.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';

/// Verifies that `duskSnapBuild` surfaces captured non-fatal render/build
/// FlutterErrors in its payload under `renderErrors`. A widget that throws at
/// build time (ParentDataWidget misuse, overflow) can render partially and stay
/// invisible in the semantics tree, so an action against it silently no-ops.
/// Embedding the error summary in every snapshot makes that impossible to miss.
void main() {
  group('duskSnapBuild renderErrors', () {
    setUp(() {
      RefRegistry.resetForTesting();
      resetCapturedExceptionsForTesting();
    });
    tearDown(() {
      RefRegistry.resetForTesting();
      resetCapturedExceptionsForTesting();
    });

    testWidgets('omits renderErrors when no FlutterError was captured',
        (tester) async {
      installErrorCapture();
      addTearDown(uninstallErrorCapture);

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: Text('clean')),
        ),
      );

      final payload = await tester.runAsync(() => duskSnapBuild());

      expect(payload!.containsKey('renderErrors'), isFalse,
          reason: 'a clean screen must not carry a renderErrors block');
      expect(payload.containsKey('snapshot'), isTrue);
    });

    testWidgets('includes a renderErrors summary when an overflow is captured',
        (tester) async {
      installErrorCapture();
      addTearDown(uninstallErrorCapture);

      // Force a RenderFlex overflow (reported via FlutterError.onError).
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
      // Consume the overflow exception so the test binding does not fail it;
      // the dusk capture buffer has already recorded it via FlutterError.onError.
      tester.takeException();

      final payload = await tester.runAsync(() => duskSnapBuild());

      expect(payload!.containsKey('renderErrors'), isTrue,
          reason: 'a screen with a captured FlutterError must report it');
      final renderErrors = payload['renderErrors'] as Map<String, dynamic>;
      expect(renderErrors['count'], greaterThanOrEqualTo(1));
      final recent = renderErrors['recent'] as List<dynamic>;
      expect(recent, isNotEmpty);
      expect((recent.first as Map<String, dynamic>)['message'] as String,
          contains('overflowed by'));
      expect(renderErrors['hint'], contains('dusk:exceptions'));
    });
  });
}
