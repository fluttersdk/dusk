import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/dusk_plugin.dart';
import 'package:fluttersdk_dusk/src/extensions/ext_perf.dart';
import 'package:fluttersdk_dusk/src/extensions/ext_semantics_hold.dart';

/// The root semantics node of whichever pipeline owner hosts the tree.
///
/// Walks from `rootPipelineOwner` rather than reading the deprecated
/// `RendererBinding.pipelineOwner`: under the test harness the widget tree
/// sits under a child owner, the same reason ext_snapshot walks children.
SemanticsNode? _rootSemanticsNode() {
  SemanticsNode? found;
  void visit(PipelineOwner owner) {
    found ??= owner.semanticsOwner?.rootSemanticsNode;
    owner.visitChildren(visit);
  }

  visit(RendererBinding.instance.rootPipelineOwner);
  return found;
}

Map<String, dynamic> _result(ServiceExtensionResponse response) =>
    jsonDecode(response.result!) as Map<String, dynamic>;

Future<void> _openTimingSession() async {
  final ServiceExtensionResponse begin = await duskPerfBeginHandler(
    'ext.dusk.perf_begin',
    <String, String>{'mode': 'timing'},
  );
  expect(begin.result, isNotNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    // Never leave a handle for the next test: the harness asserts every
    // SemanticsHandle is disposed when a testWidgets body ends.
    DuskPlugin.resetSemanticsForTesting();
    resetPerfSessionForTesting();
  });

  group('ext.dusk.semantics_hold', () {
    // semanticsEnabled: false, or the harness holds a handle of its own and
    // the tree never goes away.
    testWidgets(
        'release then acquire plus one pumped frame brings the root semantics '
        'node back',
        semanticsEnabled: false, (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('held'))),
      );
      DuskPlugin.acquireSemantics();
      await tester.pump();
      expect(_rootSemanticsNode(), isNotNull, reason: 'baseline: held on');

      // 1. Release inside an open session: the tree goes away.
      await _openTimingSession();
      final ServiceExtensionResponse released = await duskSemanticsHoldHandler(
        'ext.dusk.semantics_hold',
        <String, String>{'action': 'release'},
      );
      expect(_result(released)['released'], isTrue);
      expect(_result(released)['semanticsEnabled'], isFalse);
      expect(_result(released)['heldByPlatform'], isFalse);
      expect(DuskPlugin.semanticsReleased, isTrue);
      await tester.pump();
      expect(_rootSemanticsNode(), isNull);

      // 2. Acquire, and the handler awaits the frame that rebuilds the tree.
      final Future<ServiceExtensionResponse> acquiring =
          duskSemanticsHoldHandler(
        'ext.dusk.semantics_hold',
        <String, String>{'action': 'acquire'},
      );
      await tester.pump();
      final Map<String, dynamic> acquired = _result(await acquiring);

      expect(acquired['acquired'], isTrue);
      expect(DuskPlugin.semanticsReleased, isFalse);
      expect(
        _rootSemanticsNode(),
        isNotNull,
        reason: 'the acquire must restore the tree after one frame',
      );

      // Inside the body: the harness checks for live handles before any
      // tearDown runs.
      DuskPlugin.resetSemanticsForTesting();
    });

    // What Flutter web does to every real app: the engine turns semantics on
    // at the first semantics update and never back off, so the platform
    // holds a handle of its own and dusk's release cannot end the tree.
    testWidgets(
        'a release while the platform holds semantics on says it stayed on '
        'and who holds it',
        semanticsEnabled: false, (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('held'))),
      );
      DuskPlugin.acquireSemantics();
      tester.binding.platformDispatcher.semanticsEnabledTestValue = true;
      await _openTimingSession();

      final Map<String, dynamic> released = _result(
        await duskSemanticsHoldHandler(
          'ext.dusk.semantics_hold',
          <String, String>{'action': 'release'},
        ),
      );

      expect(released['released'], isTrue);
      expect(released['semanticsEnabled'], isTrue);
      expect(released['heldByPlatform'], isTrue);

      // Inside the body: the platform's handle is the binding's, dropped
      // when the test value is cleared, and the harness checks handles
      // before any tearDown runs.
      tester.binding.platformDispatcher.clearSemanticsEnabledTestValue();
      DuskPlugin.resetSemanticsForTesting();
    });

    test('release outside an open perf session is refused', () async {
      final ServiceExtensionResponse response = await duskSemanticsHoldHandler(
        'ext.dusk.semantics_hold',
        <String, String>{'action': 'release'},
      );

      expect(response.result, isNull);
      expect(response.errorDetail, contains('perf session'));
      expect(DuskPlugin.semanticsReleased, isFalse);
    });

    test('an unknown or missing action is an invalid-params error', () async {
      final ServiceExtensionResponse missing = await duskSemanticsHoldHandler(
        'ext.dusk.semantics_hold',
        <String, String>{},
      );
      final ServiceExtensionResponse unknown = await duskSemanticsHoldHandler(
        'ext.dusk.semantics_hold',
        <String, String>{'action': 'toggle'},
      );

      expect(missing.errorCode, ServiceExtensionResponse.invalidParams);
      expect(unknown.errorDetail, contains('toggle'));
    });
  });
}
