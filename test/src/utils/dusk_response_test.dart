import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/utils/dusk_response.dart';
import 'package:fluttersdk_dusk/src/utils/frame_sync.dart';

/// Drives the app lifecycle the way the engine does, through the platform
/// channel, so `SchedulerBinding.framesEnabled` flips for real rather than by
/// reaching into a protected member.
Future<void> _setLifecycle(WidgetTester tester, AppLifecycleState state) {
  return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/lifecycle',
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
}

/// Restores frame production for the tests that run after this one.
void _restoreFrames(WidgetTester tester) {
  addTearDown(() => _setLifecycle(tester, AppLifecycleState.resumed));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('frameProductionWarning', () {
    testWidgets('is absent while the engine produces frames', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());

      expect(frameProductionWarning(), isNull);
    });

    testWidgets('reports the starved engine and the lifecycle behind it', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());
      _restoreFrames(tester);

      await _setLifecycle(tester, AppLifecycleState.hidden);

      final Map<String, dynamic>? warning = frameProductionWarning();
      expect(warning, isNotNull);
      expect(warning!['framesEnabled'], isFalse);
      expect(warning['lifecycleState'], equals('hidden'));
      expect(warning['hint'], contains('not producing frames'));
    });
  });

  group('duskResult', () {
    testWidgets('returns the payload unchanged on a healthy engine', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());

      final Map<String, dynamic> payload = <String, dynamic>{'ok': true};
      final developer.ServiceExtensionResponse response = duskResult(payload);

      final Map<String, dynamic> decoded =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(decoded, equals(<String, dynamic>{'ok': true}));
      expect(decoded.containsKey('warnings'), isFalse);
    });

    testWidgets('stamps a warnings block when frame production is off', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());
      _restoreFrames(tester);

      await _setLifecycle(tester, AppLifecycleState.hidden);

      final developer.ServiceExtensionResponse response =
          duskResult(<String, dynamic>{'ok': true});

      final Map<String, dynamic> decoded =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      final Map<String, dynamic> warnings =
          decoded['warnings'] as Map<String, dynamic>;
      expect(warnings['framesEnabled'], isFalse);
    });

    testWidgets('leaves an existing payload key alone', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());
      _restoreFrames(tester);

      await _setLifecycle(tester, AppLifecycleState.hidden);

      final developer.ServiceExtensionResponse response = duskResult(
        <String, dynamic>{'snapshot': 'tree', 'renderErrors': 2},
      );

      final Map<String, dynamic> decoded =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(decoded['snapshot'], equals('tree'));
      expect(decoded['renderErrors'], equals(2));
      expect(decoded.containsKey('warnings'), isTrue);
    });
  });
}
