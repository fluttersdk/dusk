// Smoke test for the dusk example menu app. Replaces the default
// flutter create counter test because lib/main.dart now ships a
// scenario-menu playground (not a counter app).

import 'package:example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home menu renders every scenario tile', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const DuskExampleApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Dusk Example'), findsOneWidget);
    expect(find.text('Buttons'), findsOneWidget);
    expect(find.text('Inputs'), findsOneWidget);
    expect(find.text('Scroll'), findsOneWidget);
    expect(find.text('Modals'), findsOneWidget);
    expect(find.text('Drawer'), findsOneWidget);
    expect(find.text('Forms'), findsOneWidget);
  });
}
