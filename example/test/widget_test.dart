// Smoke test for the tapir showroom app. The plugin itself is exercised
// end-to-end against a running flutter run process (see the tapir package
// `flutter test` suite); this file just guards the showroom widget tree
// against import or build-time breakage.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('TapirShowroomApp renders the home heading', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TapirShowroomApp());
    await tester.pump();

    expect(find.text('Tapir Showroom'), findsOneWidget);
  });
}
