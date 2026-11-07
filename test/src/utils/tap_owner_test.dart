import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_snapshot.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';
import 'package:fluttersdk_dusk/src/utils/tap_owner.dart';

import '../../_support/merged_stage.dart';

void _useSmallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Snapshots the screen and judges [point] on the first button ref found.
Future<TapOwnerReport?> _judge(WidgetTester tester, Offset? point) async {
  final String snapshot = (await duskSnapBuild())['snapshot'] as String;
  final String ref =
      RegExp(r'button "[^"]*" \[ref=(e\d+)\]').firstMatch(snapshot)!.group(1)!;
  final RefEntry entry = RefRegistry.lookup(ref)!;
  return judgeTapPoint(
    node: entry.node!,
    element: entry.element,
    point: point ?? entry.rect.center,
    viewId: tester.view.viewId,
  );
}

/// A merged 300x120 boundary holding one small unlabelled tap handler in the
/// bottom-right corner.
Widget _unlabelledBoundary() {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: MergeSemantics(
          child: Container(
            width: 300,
            height: 120,
            color: const Color(0xFFE0F2F1),
            child: Stack(
              children: <Widget>[
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Semantics(
                    container: true,
                    button: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: const SizedBox(width: 72, height: 28),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(RefRegistry.resetForTesting);
  tearDown(RefRegistry.resetForTesting);

  group('judgeTapPoint()', () {
    testWidgets('the labelled control wins over a full-frame handler', (
      WidgetTester tester,
    ) async {
      _useSmallView(tester);
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await tester
            .pumpWidget(mergedStageApp(onStageTap: () {}, onSkip: () {}));

        final TapOwnerReport? report = await _judge(tester, null);

        expect(report, isNotNull);
        expect(report!.canRetarget, isTrue);
        expect(report.ownerRect, const Rect.fromLTWH(656, 536, 120, 40));
        expect(report.target, const Offset(716, 556));
      } finally {
        handle.dispose();
      }
    });

    testWidgets('a point already inside the owner is fine', (
      WidgetTester tester,
    ) async {
      _useSmallView(tester);
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await tester
            .pumpWidget(mergedStageApp(onStageTap: () {}, onSkip: () {}));

        final TapOwnerReport? report =
            await _judge(tester, const Offset(700, 550));

        expect(report, isNull);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('a node that is not a merge boundary is never judged', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Semantics(
                container: true,
                button: true,
                label: 'Save',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: const SizedBox(width: 160, height: 40),
                ),
              ),
            ),
          ),
        );

        final TapOwnerReport? report = await _judge(tester, Offset.zero);

        expect(report, isNull);
      } finally {
        handle.dispose();
      }
    });

    testWidgets(
      'with no labelled control it compares against every tap handler',
      (WidgetTester tester) async {
        _useSmallView(tester);
        final SemanticsHandle handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(_unlabelledBoundary());

          final TapOwnerReport? report = await _judge(tester, null);

          expect(report, isNotNull);
          expect(report!.ownerRect.size, const Size(72, 28));
          expect(report.canRetarget, isFalse);
        } finally {
          handle.dispose();
        }
      },
    );

    testWidgets('an owner something else is painted over is not retargeted', (
      WidgetTester tester,
    ) async {
      _useSmallView(tester);
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        // An opaque layer over the Skip intro control, outside its subtree.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: <Widget>[
                  MergedStage(onStageTap: () {}, onSkip: () {}),
                  Positioned(
                    right: 24,
                    bottom: 24,
                    child: ExcludeSemantics(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {},
                        child: const SizedBox(width: 120, height: 40),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        final TapOwnerReport? report = await _judge(tester, null);

        expect(report, isNotNull);
        expect(report!.ownerRect.size, const Size(120, 40));
        expect(report.canRetarget, isFalse);
      } finally {
        handle.dispose();
      }
    });
  });
}
