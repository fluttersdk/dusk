import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_perf.dart';
import 'package:fluttersdk_dusk/src/extensions/ext_pointer.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';
import 'package:fluttersdk_dusk/src/utils/perf_insights.dart';
import 'package:fluttersdk_dusk/src/utils/perf_interaction.dart';
import 'package:fluttersdk_dusk/src/utils/perf_readers.dart';

/// What the zone carries at the moment of the call, read the way a host in
/// another package reads it: through the public symbol, not through dusk.
PerfInteraction? _zoneHandle() =>
    Zone.current[#fluttersdk_interaction] as PerfInteraction?;

/// Opens a timing session: it flips no debug flag, which `testWidgets`
/// would otherwise report as a leaked debug variable.
Future<void> _openSession() async {
  await duskPerfBeginHandler(
    'ext.dusk.perf_begin',
    <String, String>{'mode': 'timing'},
  );
  expect(perfSessionOpen, isTrue, reason: 'the session must open');
}

/// Taps [finder] through `ext.dusk.tap`, pumping the harness the way the
/// handler's 50 ms hold and two frame awaits need.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  final String ref = RefRegistry.registerForTesting(
    rect: tester.getRect(finder),
    element: tester.element(finder),
    groupId: 'g',
    isTextField: false,
  );
  final Future<Object?> response = aiTestTapHandler(
    'ext.dusk.tap',
    <String, String>{
      'ref': ref,
      'checkStable': 'false',
      'checkReceivesEvents': 'false',
      'includeSnapshot': 'false',
    },
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
  await tester.pump();
  await response;
}

void main() {
  setUp(() {
    RefRegistry.resetForTesting();
    resetPerfInteractionsForTesting();
    framePerfReader = () => <String, Object?>{
          'frames': <Map<String, Object?>>[],
          'livenessCounter': 0,
        };
    perfSessionBeginHook = (PerfMode mode) {};
    perfSessionEndHook = () {};
  });

  tearDown(() {
    resetPerfSessionForTesting();
    RefRegistry.resetForTesting();
  });

  group('PerfInteraction', () {
    testWidgets(
        'a tapped onTap hands the open handle to its Timer and its Future, '
        'closes it at settle, and a later Timer reads it closed',
        (WidgetTester tester) async {
      PerfInteraction? fromTimer;
      PerfInteraction? fromFuture;
      PerfInteraction? fromLateTimer;
      int? closedAtWhenLateTimerFired;

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Timer(const Duration(milliseconds: 10), () {
                  fromTimer = _zoneHandle();
                });
                Future<void>(() {
                  fromFuture = _zoneHandle();
                });
                // A socket or poller opened during the tap keeps the zone for
                // good; this one fires long after the interaction settled.
                Timer(const Duration(seconds: 2), () {
                  fromLateTimer = _zoneHandle();
                  closedAtWhenLateTimerFired = fromLateTimer?.closedAtUs;
                });
              },
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      );
      await _openSession();

      await _tap(tester, find.byType(GestureDetector));

      final PerfInteraction? active = activeInteraction();
      expect(active, isNotNull, reason: 'the tap must open an interaction');
      expect(active!.verb, 'tap');
      expect(active.closedAtUs, isNull, reason: 'still settling');
      expect(fromTimer, same(active));
      expect(fromFuture, same(active));

      // Nothing schedules a frame now, so the 300 ms quiet window closes it.
      await tester.pump(const Duration(milliseconds: 500));
      expect(active.closedAtUs, isNotNull);
      expect(active.closedAtUs, greaterThanOrEqualTo(active.startUs));
      expect(activeInteraction(), isNull);

      await tester.pump(const Duration(seconds: 2));
      expect(fromLateTimer, same(active));
      expect(closedAtWhenLateTimerFired, isNotNull);

      resetPerfSessionForTesting();
    });

    testWidgets('opens nothing while no perf session is open',
        (WidgetTester tester) async {
      Object? seen = 'unset';
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => seen = Zone.current[#fluttersdk_interaction],
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      );

      await _tap(tester, find.byType(GestureDetector));

      expect(seen, isNull, reason: 'the tap ran, outside any interaction');
      expect(activeInteraction(), isNull);
      expect(perfInteractionsBetween(0, 1 << 62), isEmpty);
    });

    testWidgets('a verb dispatched inside another joins its interaction',
        (WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await _openSession();
      PerfInteraction? outer;
      PerfInteraction? inner;

      await runPerfInteraction<void>('fill', 'e1', () async {
        outer = _zoneHandle();
        await runPerfInteraction<void>('type', 'e1', () async {
          inner = _zoneHandle();
        });
      });

      expect(outer, isNotNull);
      expect(inner, same(outer), reason: "fill's type step is one gesture");
      expect(outer!.verb, 'fill');
      expect(perfInteractionsBetween(0, 1 << 62), hasLength(1));

      await tester.pump(const Duration(milliseconds: 500));
      resetPerfSessionForTesting();
    });

    testWidgets(
        'a frame-zone reader sees the open interaction through the slot',
        (WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await _openSession();
      PerfInteraction? seenInFrame;
      Object? zoneInFrame = 'unset';

      await runPerfInteraction<void>('tap', 'e1', () async {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          seenInFrame = activeInteraction();
          zoneInFrame = Zone.current[#fluttersdk_interaction];
        });
        WidgetsBinding.instance.scheduleFrame();
      });
      await tester.pump();

      expect(seenInFrame, isNotNull);
      expect(seenInFrame!.verb, 'tap');
      expect(
        zoneInFrame,
        isNull,
        reason: 'post-frame work runs in the frame zone, which is why the '
            'slot exists',
      );

      await tester.pump(const Duration(milliseconds: 500));
      resetPerfSessionForTesting();
    });

    testWidgets('an app that never stops scheduling frames is closed at 5 s',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(child: CircularProgressIndicator()),
        ),
      );
      await _openSession();

      await runPerfInteraction<void>('tap', 'e1', () async {});
      final PerfInteraction handle = activeInteraction()!;

      for (int i = 0; i < 48; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(handle.closedAtUs, isNull, reason: 'frames keep it busy');

      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(handle.closedAtUs, isNotNull, reason: 'the cap closes it');

      resetPerfSessionForTesting();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('closing the session closes an interaction still settling',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(child: CircularProgressIndicator()),
        ),
      );
      await _openSession();
      await runPerfInteraction<void>('tap', 'e1', () async {});
      final PerfInteraction handle = activeInteraction()!;

      resetPerfSessionForTesting();
      expect(activeInteraction(), isNull, reason: 'no session, no slot');
      await tester.pump(const Duration(milliseconds: 100));

      expect(handle.closedAtUs, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    test('the zone key is the public symbol a host in another library reads',
        () {
      expect(PerfInteraction.zoneKey, #fluttersdk_interaction);
      expect(PerfInteraction.zoneKey, const Symbol('fluttersdk_interaction'));
    });
  });
}
