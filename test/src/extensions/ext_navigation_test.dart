library;

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/dusk_plugin.dart';
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

    test('returns exactly navigatedBack and popped', () {
      final Map<String, dynamic> result = buildNavigateBackResponse();

      expect(result.keys, unorderedEquals(<String>['navigatedBack', 'popped']));
    });

    test('carries popped=false for a no-op', () {
      expect(buildNavigateBackResponse(popped: false)['popped'], isFalse);
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

    test('returns location, title and uri, and nothing else', () {
      final Map<String, dynamic> result = buildGetRoutesResponse();

      expect(
        result.keys,
        unorderedEquals(<String>['location', 'title', 'uri']),
      );
    });

    test('uri is null while no Router is mounted', () {
      expect(buildGetRoutesResponse()['uri'], isNull);
    });

    testWidgets('uri is the mounted Router\'s location, not the page name',
        (WidgetTester tester) async {
      // A Router-based app names no page, so `location` reads '' while the
      // router is on /monitors: the diagnosis measured exactly that in
      // uptizm, where a post-idle route re-check compared '' with ''.
      await tester.pumpWidget(
        MaterialApp.router(routerConfig: _routerConfig('/monitors?page=2')),
      );

      final Map<String, dynamic> result = buildGetRoutesResponse();

      expect(result['uri'], '/monitors?page=2');
      expect(result['location'], '');
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

    testWidgets(
        'forwards the requested route to the registered navigate adapter',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Adapter wiring is the Magic-aware dispatch path in production:
      // host main.dart binds MagicRoute.to here. We only assert the
      // route is forwarded — the navigated=true / navigated=false
      // envelope depends on URL-verify reading the router URI, which
      // needs a real Router widget and is exercised by the uptizm-app
      // MCP smoke test (live GoRouter, both directions).
      String? routeSeenByAdapter;
      DuskPlugin.registerNavigateAdapter((String route) async {
        routeSeenByAdapter = route;
        return true;
      });
      addTearDown(() => DuskPlugin.registerNavigateAdapter(null));

      await tester
          .pumpWidget(const MaterialApp(home: Scaffold(body: Text('Home'))));

      // Spawn the handler; we only need the adapter call to land.
      // Pumping two frames lets the handler progress past its initial
      // dismissAllModals + adapter await. We don't await the full
      // handler future — the URL-verify poll past this point requires
      // a router that this test doesn't mount.
      // ignore: unawaited_futures
      extDuskNavigateHandler(
        'ext.dusk.navigate',
        <String, String>{'route': '/settings', 'includeSnapshot': 'false'},
      );
      await tester.pump();
      await tester.pump();

      expect(routeSeenByAdapter, equals('/settings'));
    });

    testWidgets('adapter is preferred over Navigator when both are available',
        (WidgetTester tester) async {
      // Regression guard for the adapter-first reorder. Constructs a widget
      // tree where BOTH a registered navigate adapter AND a pushable named
      // Navigator route exist, then asserts:
      //   (a) the adapter received the route, and
      //   (b) the Navigator did NOT push it (the target widget never mounted).
      //
      // If the reorder were reverted so Navigator fires before the adapter,
      // Navigator.pushNamed('/adapter-wins-target') would succeed, the
      // target Scaffold would mount, and find.text('adapter-wins-content')
      // would return a match, failing assertion (b).
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // 1. Mount an app with a pushable named route so Navigator COULD push.
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/',
          routes: <String, WidgetBuilder>{
            '/': (BuildContext context) =>
                const Scaffold(body: Text('adapter-wins-home')),
            '/adapter-wins-target': (BuildContext context) => const Scaffold(
                  body: Text('adapter-wins-content'),
                ),
          },
        ),
      );

      // 2. Register a recording adapter that claims the route (returns true).
      //    This is the same pattern as the existing test; the critical
      //    difference is that a named route for the same path also exists above.
      String? routeSeenByAdapter;
      DuskPlugin.registerNavigateAdapter((String route) async {
        routeSeenByAdapter = route;
        return true; // claim the route so Navigator fallback must be skipped.
      });
      addTearDown(() => DuskPlugin.registerNavigateAdapter(null));

      // 3. Drive the handler.
      // ignore: unawaited_futures
      extDuskNavigateHandler(
        'ext.dusk.navigate',
        <String, String>{
          'route': '/adapter-wins-target',
          'includeSnapshot': 'false',
        },
      );
      await tester.pump();
      await tester.pump();

      // 4a. Adapter must have received the route.
      expect(routeSeenByAdapter, equals('/adapter-wins-target'));

      // 4b. Navigator must NOT have pushed the target route: the target
      //     widget's unique content marker must be absent from the tree.
      //     A find.text that returns nothing proves Navigator.pushNamed was
      //     never called (or was called but skipped because pushed was true).
      expect(
        find.text('adapter-wins-content'),
        findsNothing,
        reason: 'Navigator must not push the route when the adapter claimed it',
      );
    });

    // Negative-path coverage (router never honors the route → navigated:false
    // + reason field) is exercised end-to-end via the uptizm-app MCP smoke
    // test, where the actual GoRouter + the dusk_navigate VM service call
    // round-trip prove the envelope. A testWidgets reproduction would have
    // to drive _observeActivePathUntil's frame-bound poll loop through
    // pumpAndSettle, which deadlocks against the loop's recursive
    // endOfFrame await — verifying the shape that way buys us no signal
    // beyond what the live smoke already proves.

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
      expect(body['popped'], isTrue);
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

    testWidgets('answers popped=false when no Navigator can pop',
        (WidgetTester tester) async {
      // An agent reading only `navigatedBack` could not tell a pop from a
      // no-op at the bottom of the stack; `popped` says which happened.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      final Future<developer.ServiceExtensionResponse> future =
          extDuskNavigateBackHandler(
        'ext.dusk.navigate_back',
        <String, String>{'includeSnapshot': 'false'},
      );
      await tester.pump();
      await tester.pump();
      final developer.ServiceExtensionResponse response = await future;

      final Map<String, dynamic> body =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(body['navigatedBack'], isTrue);
      expect(body['popped'], isFalse);
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

  group('extDuskNavigateBackHandler nested Navigators', () {
    testWidgets(
        'pops a page stacked inside a nested Navigator and get_routes follows',
        (WidgetTester tester) async {
      // The shape a go_router ShellRoute builds: the root Navigator holds ONE
      // page (the shell) and can never pop, the pages stacked inside the shell
      // can. Before the fix the handler popped the root only, did nothing, and
      // still answered navigatedBack: true, so `uri` kept naming the detail
      // page because that page was still mounted.
      final _ShellStackDelegate delegate = _ShellStackDelegate();
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: _shellStackConfig('/monitors', delegate),
        ),
      );
      delegate.push(Uri.parse('/monitors/7'));
      await tester.pumpAndSettle();
      expect(find.text('page /monitors/7'), findsOneWidget);
      expect(buildGetRoutesResponse()['uri'], '/monitors/7');

      final Future<developer.ServiceExtensionResponse> future =
          extDuskNavigateBackHandler(
        'ext.dusk.navigate_back',
        <String, String>{'includeSnapshot': 'false'},
      );
      await tester.pump();
      await tester.pump();
      await future;

      // The Router reports the new location in a post-frame callback, so it
      // lands within the frames the handler already awaited on a live engine.
      await tester.pump();
      expect(find.text('page /monitors/7'), findsNothing);
      expect(buildGetRoutesResponse()['uri'], '/monitors');
    });

    testWidgets('pops the root Navigator before a nested one',
        (WidgetTester tester) async {
      // A page pushed on the root covers whatever a nested Navigator shows, so
      // it is the top of the visible stack and is the one back leaves.
      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            onGenerateInitialRoutes: (NavigatorState navigator, String name) =>
                <Route<void>>[
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const Text('nested-a'),
              ),
              MaterialPageRoute<void>(
                builder: (BuildContext context) => Builder(
                  builder: (BuildContext context) => TextButton(
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) =>
                            const Text('root-cover'),
                      ),
                    ),
                    child: const Text('nested-b'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('nested-b'));
      await tester.pumpAndSettle();
      expect(find.text('root-cover'), findsOneWidget);

      final Future<developer.ServiceExtensionResponse> future =
          extDuskNavigateBackHandler(
        'ext.dusk.navigate_back',
        <String, String>{'includeSnapshot': 'false'},
      );
      await tester.pump();
      await tester.pump();
      await future;
      await tester.pumpAndSettle();

      expect(find.text('root-cover'), findsNothing);
      expect(find.text('nested-b'), findsOneWidget);
    });

    testWidgets('leaves a hidden branch alone when the visible one is bare',
        (WidgetTester tester) async {
      // A go_router StatefulShellRoute keeps every branch alive offstage. A
      // page stacked on the hidden branch is not what the user sees, so back
      // must not pop it and must not answer popped: true for it.
      await tester.pumpWidget(
        MaterialApp(
          home: _TwoBranchShell(
            activeIndex: 1,
            branches: <List<String>>[
              <String>['hidden-list', 'hidden-detail'],
              <String>['visible-list'],
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Future<developer.ServiceExtensionResponse> future =
          extDuskNavigateBackHandler(
        'ext.dusk.navigate_back',
        <String, String>{'includeSnapshot': 'false'},
      );
      await tester.pump();
      await tester.pump();
      final developer.ServiceExtensionResponse response = await future;
      await tester.pumpAndSettle();

      final Map<String, dynamic> body =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(body['popped'], isFalse);
      expect(
        find.text('hidden-detail', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('pops the visible branch, not a hidden one before it',
        (WidgetTester tester) async {
      // The hidden branch comes first in tree order, so a plain pre-order walk
      // reaches it before the visible branch.
      await tester.pumpWidget(
        MaterialApp(
          home: _TwoBranchShell(
            activeIndex: 1,
            branches: <List<String>>[
              <String>['hidden-list', 'hidden-detail'],
              <String>['visible-list', 'visible-detail'],
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('visible-detail'), findsOneWidget);

      final Future<developer.ServiceExtensionResponse> future =
          extDuskNavigateBackHandler(
        'ext.dusk.navigate_back',
        <String, String>{'includeSnapshot': 'false'},
      );
      await tester.pump();
      await tester.pump();
      final developer.ServiceExtensionResponse response = await future;
      await tester.pumpAndSettle();

      final Map<String, dynamic> body =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(body['popped'], isTrue);
      expect(find.text('visible-detail'), findsNothing);
      expect(find.text('visible-list'), findsOneWidget);
      expect(
        find.text('hidden-detail', skipOffstage: false),
        findsOneWidget,
      );
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
  // Step 3.2 — snapshot-in-action-response for navigate + navigate_back.
  // ---------------------------------------------------------------------------

  group('extDuskNavigateHandler snapshot-in-response', () {
    testWidgets('embeds snapshot field in success response by default',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/',
          routes: <String, WidgetBuilder>{
            '/': (BuildContext context) => const Scaffold(
                  body: Text('Home'),
                ),
            '/settings': (BuildContext context) => const Scaffold(
                  body: Text('nav-snap-settings'),
                ),
          },
        ),
      );

      final Future<developer.ServiceExtensionResponse> future =
          extDuskNavigateHandler(
        'ext.dusk.navigate',
        <String, String>{'route': '/settings'},
      );
      await tester.pump();
      await tester.pump();
      final developer.ServiceExtensionResponse response = await future;

      final Map<String, dynamic> body =
          jsonDecode(response.result!) as Map<String, dynamic>;
      // Vanilla MaterialApp + `routes:` is Navigator 1.0; pushNamed does
      // not update the routeInformationProvider, so URL-verify reports
      // navigated=false. The shape contract (route round-trip + snapshot
      // field embedded) is what this test asserts; the true/false
      // outcome is exercised separately via the live MCP smoke test.
      expect(body.containsKey('navigated'), isTrue);
      expect(body['route'], equals('/settings'));
      expect(body['snapshot'], isA<String>());
    });

    testWidgets('omits snapshot when includeSnapshot is false',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/',
          routes: <String, WidgetBuilder>{
            '/': (BuildContext context) => const Scaffold(body: Text('Home')),
            '/about': (BuildContext context) =>
                const Scaffold(body: Text('About')),
          },
        ),
      );

      final Future<developer.ServiceExtensionResponse> future =
          extDuskNavigateHandler(
        'ext.dusk.navigate',
        <String, String>{
          'route': '/about',
          'includeSnapshot': 'false',
        },
      );
      await tester.pump();
      await tester.pump();
      final developer.ServiceExtensionResponse response = await future;

      final Map<String, dynamic> body =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(body.containsKey('snapshot'), isFalse);
      // navigated=true requires a router whose routeInformationProvider
      // updates on push; this MaterialApp + `routes:` Navigator-1.0
      // setup intentionally does not, so the shape contract is what
      // we assert. The live MCP smoke covers the Router-backed path.
      expect(body.containsKey('navigated'), isTrue);
    });

    testWidgets('snapshot YAML is a populated string after navigate',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Route push triggers a 300 ms transition; the handler's two
      // endOfFrame awaits land partway through. Settled-content checks
      // are the caller's responsibility (issue dusk_snap after the
      // animation completes). We assert structural presence of the
      // snapshot key here, not the animation-dependent payload.
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/',
          routes: <String, WidgetBuilder>{
            '/': (BuildContext context) => const Scaffold(body: Text('Home')),
            '/marker': (BuildContext context) => const Scaffold(
                  body: Text('navigate-content-marker'),
                ),
          },
        ),
      );

      final Future<developer.ServiceExtensionResponse> future =
          extDuskNavigateHandler(
        'ext.dusk.navigate',
        <String, String>{'route': '/marker'},
      );
      await tester.pump();
      await tester.pump();
      final developer.ServiceExtensionResponse response = await future;

      final Map<String, dynamic> body =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(body['snapshot'], isA<String>());
    });
  });

  group('extDuskNavigateBackHandler snapshot-in-response', () {
    testWidgets('embeds snapshot field in success response by default',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/',
          routes: <String, WidgetBuilder>{
            '/': (BuildContext context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => Navigator.of(context).pushNamed('/second'),
                    child: const Text('navback-home-marker'),
                  ),
                ),
            '/second': (BuildContext context) => const Scaffold(
                  body: Text('navback-second-page'),
                ),
          },
        ),
      );
      await tester.tap(find.text('navback-home-marker'));
      await tester.pumpAndSettle();

      final Future<developer.ServiceExtensionResponse> future =
          extDuskNavigateBackHandler(
        'ext.dusk.navigate_back',
        <String, String>{},
      );
      await tester.pump();
      await tester.pump();
      final developer.ServiceExtensionResponse response = await future;

      final Map<String, dynamic> body =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(body['navigatedBack'], isTrue);
      expect(body['snapshot'], isA<String>());
    });

    testWidgets('omits snapshot when includeSnapshot is false',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      final Future<developer.ServiceExtensionResponse> future =
          extDuskNavigateBackHandler(
        'ext.dusk.navigate_back',
        <String, String>{'includeSnapshot': 'false'},
      );
      await tester.pump();
      await tester.pump();
      final developer.ServiceExtensionResponse response = await future;

      final Map<String, dynamic> body =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(body.containsKey('snapshot'), isFalse);
      expect(body['navigatedBack'], isTrue);
    });

    testWidgets('snapshot YAML is a populated string after navigate_back',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Pop animation also runs for ~300 ms; same caveat as navigate.
      // We assert structural presence of the snapshot key. Live drive
      // and uptizm-app evidence will confirm settled YAML contents.
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/',
          routes: <String, WidgetBuilder>{
            '/': (BuildContext context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => Navigator.of(context).pushNamed('/inner'),
                    child: const Text('navback-content-marker'),
                  ),
                ),
            '/inner': (BuildContext context) => const Scaffold(
                  body: Text('Inner'),
                ),
          },
        ),
      );
      await tester.tap(find.text('navback-content-marker'));
      await tester.pumpAndSettle();

      final Future<developer.ServiceExtensionResponse> future =
          extDuskNavigateBackHandler(
        'ext.dusk.navigate_back',
        <String, String>{},
      );
      await tester.pump();
      await tester.pump();
      final developer.ServiceExtensionResponse response = await future;

      final Map<String, dynamic> body =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(body['snapshot'], isA<String>());
      expect(body['snapshot'] as String, isNotEmpty);
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

/// A one-screen Router whose provider starts on [location], with no page
/// names: what a go_router app looks like to dusk.
RouterConfig<Uri> _routerConfig(String location) => RouterConfig<Uri>(
      routeInformationProvider: PlatformRouteInformationProvider(
        initialRouteInformation: RouteInformation(uri: Uri.parse(location)),
      ),
      routeInformationParser: const _UriParser(),
      routerDelegate: _UriDelegate(),
    );

/// A Router hosting a nested Navigator inside a single root page: what a
/// go_router `ShellRoute` looks like to dusk. [delegate] owns the stack.
RouterConfig<Uri> _shellStackConfig(
  String location,
  _ShellStackDelegate delegate,
) =>
    RouterConfig<Uri>(
      routeInformationProvider: PlatformRouteInformationProvider(
        initialRouteInformation: RouteInformation(uri: Uri.parse(location)),
      ),
      routeInformationParser: const _UriParser(),
      routerDelegate: delegate,
    );

final class _UriParser extends RouteInformationParser<Uri> {
  const _UriParser();

  @override
  Future<Uri> parseRouteInformation(RouteInformation routeInformation) async =>
      routeInformation.uri;

  @override
  RouteInformation restoreRouteInformation(Uri configuration) =>
      RouteInformation(uri: configuration);
}

final class _UriDelegate extends RouterDelegate<Uri> with ChangeNotifier {
  Uri? _current;

  @override
  Uri? get currentConfiguration => _current;

  @override
  Future<void> setNewRoutePath(Uri configuration) async {
    _current = configuration;
    notifyListeners();
  }

  @override
  Future<bool> popRoute() async => false;

  @override
  Widget build(BuildContext context) => Navigator(
        pages: <Page<void>>[
          MaterialPage<void>(child: Text('${_current ?? ''}')),
        ],
        onDidRemovePage: (Page<Object?> page) {},
      );
}

/// A page with no transition, so a pop finishes inside the frame that starts it.
final class _InstantPage extends Page<void> {
  const _InstantPage({required LocalKey super.key, required this.child});

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => PageRouteBuilder<void>(
        settings: this,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
        ) =>
            child,
      );
}

/// One Navigator per branch, each seeded with its own page names, stacked the
/// way go_router's default `StatefulShellRoute` container keeps them: an
/// [IndexedStack] whose inactive children sit under `Offstage` and a disabled
/// `TickerMode`.
final class _TwoBranchShell extends StatelessWidget {
  const _TwoBranchShell({
    required this.activeIndex,
    required this.branches,
  });

  final int activeIndex;

  final List<List<String>> branches;

  @override
  Widget build(BuildContext context) => IndexedStack(
        index: activeIndex,
        children: <Widget>[
          for (int index = 0; index < branches.length; index++)
            Offstage(
              offstage: index != activeIndex,
              child: TickerMode(
                enabled: index == activeIndex,
                child: Navigator(
                  onGenerateInitialRoutes: (
                    NavigatorState navigator,
                    String name,
                  ) =>
                      <Route<void>>[
                    for (final String page in branches[index])
                      PageRouteBuilder<void>(
                        transitionDuration: Duration.zero,
                        reverseTransitionDuration: Duration.zero,
                        pageBuilder: (
                          BuildContext context,
                          Animation<double> animation,
                          Animation<double> secondaryAnimation,
                        ) =>
                            Text(page),
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
}

/// Root Navigator with ONE page hosting a nested Navigator whose pages follow
/// [_stack]; the router configuration is always the top of that stack.
final class _ShellStackDelegate extends RouterDelegate<Uri>
    with ChangeNotifier {
  final List<Uri> _stack = <Uri>[];

  void push(Uri uri) {
    _stack.add(uri);
    notifyListeners();
  }

  @override
  Uri? get currentConfiguration => _stack.isEmpty ? null : _stack.last;

  @override
  Future<void> setNewRoutePath(Uri configuration) async {
    if (_stack.isNotEmpty && _stack.last == configuration) return;
    _stack
      ..clear()
      ..add(configuration);
    notifyListeners();
  }

  @override
  Future<bool> popRoute() async => false;

  @override
  Widget build(BuildContext context) => Navigator(
        pages: <Page<void>>[
          _InstantPage(
            key: const ValueKey<String>('shell'),
            child: ListenableBuilder(
              listenable: this,
              builder: (BuildContext context, Widget? child) {
                // A Navigator refuses an empty page list, and the first build
                // lands before the initial location is parsed.
                if (_stack.isEmpty) return const SizedBox.shrink();

                return Navigator(
                  pages: <Page<void>>[
                    for (final Uri uri in _stack)
                      _InstantPage(
                        key: ValueKey<String>('$uri'),
                        child: Text('page $uri'),
                      ),
                  ],
                  onDidRemovePage: (Page<Object?> page) {
                    _stack.removeWhere(
                      (Uri uri) => ValueKey<String>('$uri') == page.key,
                    );
                    notifyListeners();
                  },
                );
              },
            ),
          ),
        ],
        onDidRemovePage: (Page<Object?> page) {},
      );
}
