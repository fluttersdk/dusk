import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/utils/tapir_register.dart';
import 'package:tapir/src/utils/tapir_response.dart';

/// Drives the app lifecycle through the platform channel, the path the
/// engine itself uses, so `framesEnabled` flips for real.
Future<void> _setLifecycle(WidgetTester tester, AppLifecycleState state) {
  return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/lifecycle',
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
}

void _restoreFrames(WidgetTester tester) {
  addTearDown(() => _setLifecycle(tester, AppLifecycleState.resumed));
}

Future<developer.ServiceExtensionResponse> _okHandler(
  String method,
  Map<String, String> params,
) async {
  return tapirResult(<String, dynamic>{'ok': true});
}

Map<String, dynamic> _decode(developer.ServiceExtensionResponse? response) {
  return jsonDecode(response!.result!) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('wrapTapirHandler', () {
    testWidgets('returns the payload unchanged on a healthy engine', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await _setLifecycle(tester, AppLifecycleState.resumed);

      final developer.ServiceExtensionResponse? response = await tester
          .runAsync(
            () => wrapTapirHandler(_okHandler)(
              'ext.tapir.test',
              <String, String>{},
            ),
          );

      expect(_decode(response), equals(<String, dynamic>{'ok': true}));
    });

    testWidgets('wakes a hidden engine before the handler runs', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());
      _restoreFrames(tester);
      await _setLifecycle(tester, AppLifecycleState.hidden);

      bool? framesEnabledInHandler;
      Future<developer.ServiceExtensionResponse> probe(
        String method,
        Map<String, String> params,
      ) async {
        framesEnabledInHandler = SchedulerBinding.instance.framesEnabled;
        return tapirResult(<String, dynamic>{'ok': true});
      }

      final Future<developer.ServiceExtensionResponse> call = wrapTapirHandler(
        probe,
      )('ext.tapir.test', <String, String>{});
      await tester.pump();
      final developer.ServiceExtensionResponse response = await call;

      final Map<String, dynamic> decoded = _decode(response);
      expect(framesEnabledInHandler, isTrue);
      expect(decoded['ok'], isTrue);
      expect(decoded['framesForced'], isTrue);
      expect(decoded.containsKey('warnings'), isFalse);
    });

    testWidgets('keeps the warnings block when the wake produces no frame', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());
      _restoreFrames(tester);
      await _setLifecycle(tester, AppLifecycleState.hidden);

      // Real time and no pump: no frame follows the wake, the way a hidden
      // browser tab withholds requestAnimationFrame.
      final developer.ServiceExtensionResponse? response = await tester
          .runAsync(
            () => wrapTapirHandler(_okHandler)(
              'ext.tapir.test',
              <String, String>{},
            ),
          );

      final Map<String, dynamic> decoded = _decode(response);
      expect(decoded.containsKey('framesForced'), isFalse);
      expect(decoded['warnings'], isA<Map<String, dynamic>>());
    });

    testWidgets('leaves a hidden engine hidden when ensureFrames is off', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());
      _restoreFrames(tester);
      await _setLifecycle(tester, AppLifecycleState.hidden);

      final developer.ServiceExtensionResponse? response = await tester
          .runAsync(
            () => wrapTapirHandler(_okHandler, ensureFrames: false)(
              'ext.tapir.test',
              <String, String>{},
            ),
          );

      final Map<String, dynamic> decoded = _decode(response);
      expect(SchedulerBinding.instance.framesEnabled, isFalse);
      expect(
        SchedulerBinding.instance.lifecycleState,
        equals(AppLifecycleState.hidden),
      );
      expect(decoded.containsKey('framesForced'), isFalse);
      expect(decoded.containsKey('warnings'), isTrue);
    });

    testWidgets('keeps the forced flag to the call that forced', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());
      _restoreFrames(tester);
      await _setLifecycle(tester, AppLifecycleState.hidden);

      await tester.runAsync(() async {
        // Created inside runAsync: a completer from the fake-async zone only
        // delivers when the harness pumps, which nothing does here.
        final Completer<void> entered = Completer<void>();
        final Completer<void> release = Completer<void>();
        Future<developer.ServiceExtensionResponse> slow(
          String method,
          Map<String, String> params,
        ) async {
          entered.complete();
          await release.future;
          return tapirResult(<String, dynamic>{'call': 'forcing'});
        }

        final Future<developer.ServiceExtensionResponse> forcing =
            wrapTapirHandler(slow)('ext.tapir.test', <String, String>{});

        // Run the frame the wake is waiting for, so it counts as forced.
        tester.binding.handleBeginFrame(Duration.zero);
        tester.binding.handleDrawFrame();

        // The second call runs while the forcing one is parked in its
        // handler, after it has recorded that it forced.
        await entered.future;

        final developer.ServiceExtensionResponse other = await wrapTapirHandler(
          _okHandler,
          ensureFrames: false,
        )('ext.tapir.test', <String, String>{});
        release.complete();

        expect(_decode(other).containsKey('framesForced'), isFalse);
        expect(_decode(await forcing)['framesForced'], isTrue);
      });
    });
  });

  group('markRefReresolved', () {
    testWidgets('records each ref once for the call that re-resolved it', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());

      Future<developer.ServiceExtensionResponse> relocating(
        String method,
        Map<String, String> params,
      ) async {
        markRefReresolved('e3');
        markRefReresolved('e3');
        markRefReresolved('e7');
        return tapirResult(<String, dynamic>{'ok': true});
      }

      final developer.ServiceExtensionResponse? response = await tester
          .runAsync(
            () => wrapTapirHandler(relocating)(
              'ext.tapir.test',
              <String, String>{},
            ),
          );

      expect(_decode(response)['reresolved'], equals(<String>['e3', 'e7']));
    });

    testWidgets('does not leak into a call that re-resolved nothing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());

      Future<developer.ServiceExtensionResponse> relocating(
        String method,
        Map<String, String> params,
      ) async {
        markRefReresolved('e3');
        return tapirResult(<String, dynamic>{'ok': true});
      }

      final developer.ServiceExtensionResponse? first = await tester.runAsync(
        () =>
            wrapTapirHandler(relocating)('ext.tapir.test', <String, String>{}),
      );
      final developer.ServiceExtensionResponse? second = await tester.runAsync(
        () =>
            wrapTapirHandler(_okHandler)('ext.tapir.test', <String, String>{}),
      );

      expect(_decode(first)['reresolved'], equals(<String>['e3']));
      expect(_decode(second).containsKey('reresolved'), isFalse);
    });

    test('is a no-op outside a wrapped call', () {
      markRefReresolved('e1');

      expect(reresolvedRefsInCurrentCall(), isEmpty);
    });
  });

  group('registerTapirExtension', () {
    test('registers the same method twice without throwing', () {
      void register() =>
          registerTapirExtension('ext.tapir.register_test', _okHandler);

      register();
      expect(register, returnsNormally);
    });
  });
}
