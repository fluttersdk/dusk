library;

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_navigation.dart';

/// Tests for the navigation extensions (Step 6 of fluttersdk-dusk-alpha-2 plan).
///
/// Covers:
/// 1. `extDuskNavigateHandler` — route param validation + success envelope.
/// 2. `extDuskNavigateBackHandler` — always-success pop path.
/// 3. `extDuskGetRoutesHandler` — returns location + title keys.
/// 4. `registerNavigationExtensions()` — idempotent registration without throw.
///
/// ## Async pattern for handlers that await endOfFrame
///
/// Handlers that call `WidgetsBinding.instance.endOfFrame` internally need the
/// fake-timer dance inside `testWidgets`:
///
/// ```dart
/// final future = extDuskNavigateHandler(...);
/// await tester.pump();
/// await tester.pump();
/// final response = await future;
/// ```
void main() {
  // ---------------------------------------------------------------------------
  // buildNavigateResponse
  // ---------------------------------------------------------------------------

  group('buildNavigateResponse', () {
    test('returns navigated=true and the supplied route', () {
      final Map<String, dynamic> result = buildNavigateResponse('/dashboard');

      expect(result['navigated'], isTrue);
      expect(result['route'], equals('/dashboard'));
    });

    test('encodes to valid JSON with correct fields', () {
      final Map<String, dynamic> result =
          buildNavigateResponse('/monitors/abc');
      final String json = jsonEncode(result);
      final Map<String, dynamic> decoded =
          jsonDecode(json) as Map<String, dynamic>;

      expect(decoded['navigated'], isTrue);
      expect(decoded['route'], equals('/monitors/abc'));
    });

    test('preserves arbitrary route strings verbatim', () {
      final Map<String, dynamic> result =
          buildNavigateResponse('/monitors/123/metrics');

      expect(result['route'], equals('/monitors/123/metrics'));
    });

    test('always returns exactly two keys', () {
      final Map<String, dynamic> result = buildNavigateResponse('/foo');

      expect(result.keys, containsAll(<String>['navigated', 'route']));
      expect(result, hasLength(2));
    });
  });

  // ---------------------------------------------------------------------------
  // buildNavigateBackResponse
  // ---------------------------------------------------------------------------

  group('buildNavigateBackResponse', () {
    test('returns navigatedBack=true', () {
      final Map<String, dynamic> result = buildNavigateBackResponse();

      expect(result['navigatedBack'], isTrue);
    });

    test('encodes to valid JSON', () {
      final Map<String, dynamic> result = buildNavigateBackResponse();
      final String json = jsonEncode(result);
      final Map<String, dynamic> decoded =
          jsonDecode(json) as Map<String, dynamic>;

      expect(decoded['navigatedBack'], isTrue);
    });

    test('returns exactly one key', () {
      final Map<String, dynamic> result = buildNavigateBackResponse();

      expect(result, hasLength(1));
    });

    test('navigatedBack value is a bool (not a string)', () {
      final Map<String, dynamic> result = buildNavigateBackResponse();

      expect(result['navigatedBack'], isA<bool>());
    });
  });

  // ---------------------------------------------------------------------------
  // buildGetRoutesResponse
  // ---------------------------------------------------------------------------

  group('buildGetRoutesResponse', () {
    test('includes location and title keys', () {
      final Map<String, dynamic> result = buildGetRoutesResponse();

      expect(result, containsPair('location', anything));
      expect(result, containsPair('title', anything));
    });

    test('location and title are strings', () {
      final Map<String, dynamic> result = buildGetRoutesResponse();

      expect(result['location'], isA<String>());
      expect(result['title'], isA<String>());
    });

    test('encodes to valid JSON', () {
      final Map<String, dynamic> result = buildGetRoutesResponse();
      final String json = jsonEncode(result);
      final Map<String, dynamic> decoded =
          jsonDecode(json) as Map<String, dynamic>;

      expect(decoded, containsPair('location', anything));
      expect(decoded, containsPair('title', anything));
    });

    test('returns exactly two keys', () {
      final Map<String, dynamic> result = buildGetRoutesResponse();

      expect(result, hasLength(2));
    });
  });

  // ---------------------------------------------------------------------------
  // extDuskNavigateHandler
  // ---------------------------------------------------------------------------

  group('extDuskNavigateHandler', () {
    test('returns extensionError when route param is missing', () async {
      final developer.ServiceExtensionResponse response =
          await extDuskNavigateHandler(
        'ext.dusk.navigate',
        <String, String>{},
      );

      expect(
        response.errorCode,
        equals(developer.ServiceExtensionResponse.extensionError),
        reason: 'Missing route must return extensionError',
      );
    });

    test('returns extensionError when route param is empty string', () async {
      final developer.ServiceExtensionResponse response =
          await extDuskNavigateHandler(
        'ext.dusk.navigate',
        <String, String>{'route': ''},
      );

      expect(
        response.errorCode,
        equals(developer.ServiceExtensionResponse.extensionError),
        reason: 'Empty route must return extensionError',
      );
    });

    testWidgets('returns result envelope with navigated=true on valid route',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // 1. Pump a two-route MaterialApp so the Navigator has a real stack.
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/',
          routes: <String, WidgetBuilder>{
            '/': (BuildContext context) => const Scaffold(
                  body: Text('Home'),
                ),
            '/settings': (BuildContext context) => const Scaffold(
                  body: Text('Settings'),
                ),
          },
        ),
      );

      // 2. Drive the handler; endOfFrame completes after tester.pump().
      final Future<developer.ServiceExtensionResponse> future =
          extDuskNavigateHandler(
        'ext.dusk.navigate',
        <String, String>{'route': '/settings'},
      );
      await tester.pump();
      await tester.pump();
      final developer.ServiceExtensionResponse response = await future;

      // 3. Expect a valid result payload.
      expect(response.result, isNotNull);
      final Map<String, dynamic> body =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(body['navigated'], isTrue);
      expect(body['route'], equals('/settings'));
    });

    test('returns a ServiceExtensionResponse instance', () async {
      final developer.ServiceExtensionResponse response =
          await extDuskNavigateHandler(
        'ext.dusk.navigate',
        <String, String>{},
      );

      expect(response, isA<developer.ServiceExtensionResponse>());
    });
  });

  // ---------------------------------------------------------------------------
  // extDuskNavigateBackHandler
  // ---------------------------------------------------------------------------

  group('extDuskNavigateBackHandler', () {
    // All tests in this group use testWidgets because the handler awaits
    // WidgetsBinding.instance.endOfFrame, which requires a frame scheduler.
    // In a plain test() the frame never fires and the future never resolves.

    testWidgets('returns a ServiceExtensionResponse instance',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      final Future<developer.ServiceExtensionResponse> future =
          extDuskNavigateBackHandler(
        'ext.dusk.navigate_back',
        <String, String>{},
      );
      await tester.pump();
      await tester.pump();
      final developer.ServiceExtensionResponse response = await future;
      expect(response, isA<developer.ServiceExtensionResponse>());
    });

    testWidgets('returns result envelope with navigatedBack=true',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // 1. Pump a two-route app and push a second route so we can pop.
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/',
          routes: <String, WidgetBuilder>{
            '/': (BuildContext context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => Navigator.of(context).pushNamed('/second'),
                    child: const Text('Go'),
                  ),
                ),
            '/second': (BuildContext context) => const Scaffold(
                  body: Text('Second'),
                ),
          },
        ),
      );

      // 2. Navigate to the second route.
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      // 3. Drive the back handler.
      final Future<developer.ServiceExtensionResponse> future =
          extDuskNavigateBackHandler(
        'ext.dusk.navigate_back',
        <String, String>{},
      );
      await tester.pump();
      await tester.pump();
      final developer.ServiceExtensionResponse response = await future;

      expect(response.result, isNotNull);
      final Map<String, dynamic> body =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(body['navigatedBack'], isTrue);
    });

    testWidgets('does not require any params (handles empty map)',
        (WidgetTester tester) async {
      // Pump a minimal app so the frame scheduler is running.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      final Future<developer.ServiceExtensionResponse> future =
          extDuskNavigateBackHandler(
        'ext.dusk.navigate_back',
        <String, String>{},
      );
      await tester.pump();
      await tester.pump();
      final developer.ServiceExtensionResponse response = await future;
      expect(response, isNotNull);
    });

    testWidgets('result encodes to valid JSON', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      final Future<developer.ServiceExtensionResponse> future =
          extDuskNavigateBackHandler(
        'ext.dusk.navigate_back',
        <String, String>{},
      );
      await tester.pump();
      await tester.pump();
      final developer.ServiceExtensionResponse response = await future;

      // result is non-null; the payload must be valid JSON.
      expect(response.result, isNotNull);
      expect(() => jsonDecode(response.result!), returnsNormally);
    });
  });

  // ---------------------------------------------------------------------------
  // extDuskGetRoutesHandler
  // ---------------------------------------------------------------------------

  group('extDuskGetRoutesHandler', () {
    test('returns a ServiceExtensionResponse instance', () async {
      final developer.ServiceExtensionResponse response =
          await extDuskGetRoutesHandler(
        'ext.dusk.get_routes',
        <String, String>{},
      );

      expect(response, isA<developer.ServiceExtensionResponse>());
    });

    test('result contains location and title keys', () async {
      final developer.ServiceExtensionResponse response =
          await extDuskGetRoutesHandler(
        'ext.dusk.get_routes',
        <String, String>{},
      );

      expect(response.result, isNotNull);
      final Map<String, dynamic> body =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(body, containsPair('location', anything));
      expect(body, containsPair('title', anything));
    });

    test('location and title are strings in the JSON envelope', () async {
      final developer.ServiceExtensionResponse response =
          await extDuskGetRoutesHandler(
        'ext.dusk.get_routes',
        <String, String>{},
      );

      expect(response.result, isNotNull);
      final Map<String, dynamic> body =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(body['location'], isA<String>());
      expect(body['title'], isA<String>());
    });

    test('does not require any params (handles empty map)', () async {
      final developer.ServiceExtensionResponse response =
          await extDuskGetRoutesHandler(
        'ext.dusk.get_routes',
        <String, String>{},
      );

      expect(response, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // registerNavigationExtensions
  // ---------------------------------------------------------------------------

  group('registerNavigationExtensions', () {
    test('registers all 3 extensions without throwing', () {
      // registerExtensionIdempotent swallows ArgumentError on duplicate
      // registration — calling twice must not throw.
      expect(registerNavigationExtensions, returnsNormally);
      expect(registerNavigationExtensions, returnsNormally);
    });

    test('can be called multiple times safely (hot-restart idempotency)', () {
      // Three calls must all succeed with no exception.
      registerNavigationExtensions();
      registerNavigationExtensions();
      registerNavigationExtensions();
    });
  });
}
