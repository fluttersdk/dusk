import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/extensions/ext_snapshot.dart';
import 'package:tapir/src/ref_registry.dart';
import 'package:tapir/src/utils/tap_owner.dart';

import '../../_support/merged_stage.dart';

void _useSmallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Snapshots the screen and judges [point] on the first button ref found.
Future<TapOwnerReport?> _judge(WidgetTester tester, Offset? point) async {
  final String snapshot = (await tapirSnapBuild())['snapshot'] as String;
  final String ref = RegExp(r'button "[^"]*" \[ref=(e\d+)\]')
      .firstMatch(snapshot)!
      .group(1)!;
  final RefEntry entry = RefRegistry.lookup(ref)!;
  return judgeTapPoint(
    node: entry.node!,
    element: entry.element,
    point: point ?? entry.rect.center,
    viewId: () => tester.view.viewId,
  );
}

/// A merged 300x120 boundary whose centre is empty space: no handler of its
/// own, and a labelled `Skip intro` control in the bottom-right corner.
Widget _emptyCentreBoundary() {
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
                    button: true,
                    label: 'Skip intro',
                    onTap: () {},
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

  group('judgeTapPoint() safety', () {
    testWidgets('says when the centre has a tap handler of its own', (
      WidgetTester tester,
    ) async {
      _useSmallView(tester);
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          mergedStageApp(onStageTap: () {}, onSkip: () {}),
        );

        final TapOwnerReport? report = await _judge(tester, null);

        expect(report!.centreHandled, isTrue);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('an empty centre is not a handled centre', (
      WidgetTester tester,
    ) async {
      _useSmallView(tester);
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_emptyCentreBoundary());

        final TapOwnerReport? report = await _judge(tester, null);

        expect(report!.canRetarget, isTrue);
        expect(report.centreHandled, isFalse);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('an owner below the fold is not retargeted', (
      WidgetTester tester,
    ) async {
      _useSmallView(tester);
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  height: 1400,
                  child: MergedStage(onStageTap: () {}, onSkip: () {}),
                ),
              ),
            ),
          ),
        );

        final TapOwnerReport? report = await _judge(tester, null);

        expect(report, isNotNull);
        expect(report!.ownerRect.top, greaterThan(600));
        expect(report.canRetarget, isFalse);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('the root element is never judged', (
      WidgetTester tester,
    ) async {
      _useSmallView(tester);
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          mergedStageApp(onStageTap: () {}, onSkip: () {}),
        );
        final String snapshot = (await tapirSnapBuild())['snapshot'] as String;
        final String ref = RegExp(r'\[ref=(e\d+)\]')
            .firstMatch(snapshot)!
            .group(1)!;
        final RefEntry entry = RefRegistry.lookup(ref)!;

        final TapOwnerReport? report = judgeTapPoint(
          node: entry.node!,
          element: tester.binding.rootElement!,
          point: entry.rect.center,
          viewId: () => tester.view.viewId,
        );

        expect(report, isNull);
      } finally {
        handle.dispose();
      }
    });
  });

  group('tapOwnerBounds()', () {
    testWidgets(
      'a retargetable owner is plain bounds plus the handled centre',
      (WidgetTester tester) async {
        _useSmallView(tester);
        final SemanticsHandle handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            mergedStageApp(onStageTap: () {}, onSkip: () {}),
          );
          final String snapshot =
              (await tapirSnapBuild())['snapshot'] as String;
          final String ref = RegExp(r'\[ref=(e\d+)\]')
              .firstMatch(snapshot)!
              .group(1)!;
          final RefEntry entry = RefRegistry.lookup(ref)!;

          final Map<String, Object>? bounds = tapOwnerBounds(
            node: entry.node!,
            element: entry.element,
            rect: entry.rect,
          );

          expect(bounds, <String, Object>{
            'x': 656.0,
            'y': 536.0,
            'w': 120.0,
            'h': 40.0,
            'centreHandled': true,
          });
        } finally {
          handle.dispose();
        }
      },
    );

    testWidgets('an owner a tap cannot go to says so', (
      WidgetTester tester,
    ) async {
      _useSmallView(tester);
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          mergedChoiceApp(onStageTap: () {}, onYes: () {}, onNo: () {}),
        );
        final String snapshot = (await tapirSnapBuild())['snapshot'] as String;
        final String ref = RegExp(r'\[ref=(e\d+)\]')
            .firstMatch(snapshot)!
            .group(1)!;
        final RefEntry entry = RefRegistry.lookup(ref)!;

        final Map<String, Object>? bounds = tapOwnerBounds(
          node: entry.node!,
          element: entry.element,
          rect: entry.rect,
        );

        expect(bounds, isNotNull);
        expect(bounds!['retargets'], isFalse);
      } finally {
        handle.dispose();
      }
    });
  });

  group('judgeTapPoint()', () {
    testWidgets('the labelled control wins over a full-frame handler', (
      WidgetTester tester,
    ) async {
      _useSmallView(tester);
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          mergedStageApp(onStageTap: () {}, onSkip: () {}),
        );

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
        await tester.pumpWidget(
          mergedStageApp(onStageTap: () {}, onSkip: () {}),
        );

        final TapOwnerReport? report = await _judge(
          tester,
          const Offset(700, 550),
        );

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
