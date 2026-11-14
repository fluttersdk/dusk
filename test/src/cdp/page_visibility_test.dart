import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/cdp/page_visibility.dart';

import 'fake_cdp_server.dart';

void main() {
  group('bringCdpPageToFront()', () {
    test('sends one Page.bringToFront to the page on the web port', () async {
      final List<String> calls = <String>[];
      final FakeCdpServer server = await FakeCdpServer.start(
        pageUrl: 'http://localhost:5123/',
        handlers: {
          'Page.bringToFront': (Map<String, dynamic> _) async {
            calls.add('Page.bringToFront');
            return <String, dynamic>{};
          },
        },
      );
      addTearDown(server.stop);

      final BringToFrontResult result = await bringCdpPageToFront(
        server.port,
        5123,
      );

      expect(result.succeeded, isTrue);
      expect(result.error, isNull);
      expect(calls, equals(<String>['Page.bringToFront']));
    });

    test('takes the first page tab when no web port is recorded', () async {
      final List<String> calls = <String>[];
      final FakeCdpServer server = await FakeCdpServer.start(
        handlers: {
          'Page.bringToFront': (Map<String, dynamic> _) async {
            calls.add('Page.bringToFront');
            return <String, dynamic>{};
          },
        },
      );
      addTearDown(server.stop);

      final BringToFrontResult result = await bringCdpPageToFront(
        server.port,
        null,
      );

      expect(result.succeeded, isTrue);
      expect(calls, hasLength(1));
    });

    test('fails without a CDP call when no page is on the web port', () async {
      final List<String> calls = <String>[];
      final FakeCdpServer server = await FakeCdpServer.start(
        pageUrl: 'http://localhost:6000/',
        handlers: {
          'Page.bringToFront': (Map<String, dynamic> _) async {
            calls.add('Page.bringToFront');
            return <String, dynamic>{};
          },
        },
      );
      addTearDown(server.stop);

      final BringToFrontResult result = await bringCdpPageToFront(
        server.port,
        5123,
      );

      expect(result.succeeded, isFalse);
      expect(result.error, contains(':5123'));
      expect(calls, isEmpty);
    });

    test('fails without throwing when the port is unreachable', () async {
      final ServerSocket probe = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final int closedPort = probe.port;
      await probe.close();

      final BringToFrontResult result = await bringCdpPageToFront(
        closedPort,
        5123,
      );

      expect(result.succeeded, isFalse);
      expect(result.error, contains('unreachable'));
    });

    test('fails without throwing when Chrome answers with an error', () async {
      final FakeCdpServer server = await FakeCdpServer.start(
        pageUrl: 'http://localhost:5123/',
        handlers:
            <
              String,
              Future<Map<String, dynamic>> Function(Map<String, dynamic>)
            >{},
      );
      addTearDown(server.stop);

      final BringToFrontResult result = await bringCdpPageToFront(
        server.port,
        5123,
      );

      expect(result.succeeded, isFalse);
      expect(result.error, contains('Method not found'));
    });
  });

  group('isCdpPageHidden()', () {
    Future<FakeCdpServer> serverReporting(String? state) async {
      final FakeCdpServer server = await FakeCdpServer.start(
        pageUrl: 'http://localhost:5123/',
        handlers: {
          'Runtime.evaluate': (Map<String, dynamic> _) async =>
              <String, dynamic>{
                'result': <String, dynamic>{'type': 'string', 'value': state},
              },
        },
      );
      addTearDown(server.stop);
      return server;
    }

    test('is true when the tab reports hidden', () async {
      final FakeCdpServer server = await serverReporting('hidden');

      expect(await isCdpPageHidden(server.port, 5123), isTrue);
    });

    test('is false when the tab reports visible', () async {
      final FakeCdpServer server = await serverReporting('visible');

      expect(await isCdpPageHidden(server.port, 5123), isFalse);
    });

    test('is null when the value is not a string', () async {
      final FakeCdpServer server = await serverReporting(null);

      expect(await isCdpPageHidden(server.port, 5123), isNull);
    });

    test('is null, and does not throw, when the port is unreachable', () async {
      expect(await isCdpPageHidden(1, 5123), isNull);
    });
  });
}
