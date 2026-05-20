import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/cdp/chrome_finder.dart';

void main() {
  group('ChromeFinder', () {
    // Reset the test-seam after each test so a stub from one test cannot
    // contaminate the next.
    setUp(() {
      ChromeFinder.chromeFinderHttpGet = ChromeFinder.defaultHttpGet;
    });

    // ---------------------------------------------------------------
    // (a) probe() returns ChromeInfo on a valid /json/version response
    // ---------------------------------------------------------------
    test(
      'probe() returns ChromeInfo when fake server responds with valid /json/version JSON',
      () async {
        const Map<String, dynamic> body = <String, dynamic>{
          'webSocketDebuggerUrl': 'ws://localhost:9222/devtools/browser/abc',
          'Browser': 'Chrome/130.0.0.0',
          'Protocol-Version': '1.3',
        };

        // Stub the HTTP get seam: succeed on first call.
        ChromeFinder.chromeFinderHttpGet = (Uri uri) async {
          expect(uri.port, equals(9222));
          expect(uri.path, equals('/json/version'));
          return jsonEncode(body);
        };

        final ChromeInfo info = await ChromeFinder.probe(port: 9222);

        expect(
          info.webSocketDebuggerUrl,
          equals('ws://localhost:9222/devtools/browser/abc'),
        );
        expect(info.browser, equals('Chrome/130.0.0.0'));
        expect(info.protocolVersion, equals('1.3'));
      },
    );

    // ---------------------------------------------------------------
    // (b) probe() retries on connection refused, then succeeds
    // ---------------------------------------------------------------
    test(
      'probe() retries on connection refused then succeeds when fake server comes up',
      () async {
        var callCount = 0;

        // First two calls simulate SocketException; third succeeds.
        ChromeFinder.chromeFinderHttpGet = (Uri uri) async {
          callCount++;
          if (callCount < 3) {
            throw const SocketException('Connection refused');
          }
          return jsonEncode(<String, dynamic>{
            'webSocketDebuggerUrl': 'ws://localhost:9223/devtools/browser/xyz',
            'Browser': 'Chrome/130.0.0.0',
            'Protocol-Version': '1.3',
          });
        };

        final ChromeInfo info = await ChromeFinder.probe(
          port: 9223,
          timeout: const Duration(seconds: 5),
          interval: const Duration(milliseconds: 1),
        );

        expect(info.browser, equals('Chrome/130.0.0.0'));
        expect(callCount, equals(3));
      },
    );

    // ---------------------------------------------------------------
    // (c) probe() throws DuskCdpException on HTTP 404
    // ---------------------------------------------------------------
    test(
      'probe() throws DuskCdpException on HTTP 404 (port open but no CDP)',
      () async {
        ChromeFinder.chromeFinderHttpGet = (Uri uri) async {
          throw ChromeFinderHttpNotFoundException(uri.port);
        };

        await expectLater(
          ChromeFinder.probe(
            port: 9224,
            timeout: const Duration(seconds: 2),
            interval: const Duration(milliseconds: 1),
          ),
          throwsA(
            isA<DuskCdpException>().having(
              (DuskCdpException e) => e.message,
              'message',
              contains('does not serve Chrome DevTools Protocol'),
            ),
          ),
        );
      },
    );

    // ---------------------------------------------------------------
    // (d) probe() throws DuskCdpException with "timed out" when port
    //     never accepts connection
    // ---------------------------------------------------------------
    test(
      'probe() throws DuskCdpException with "timed out" message when port never accepts connection',
      () async {
        ChromeFinder.chromeFinderHttpGet = (Uri uri) async {
          throw const SocketException('Connection refused');
        };

        await expectLater(
          ChromeFinder.probe(
            port: 9225,
            timeout: const Duration(milliseconds: 50),
            interval: const Duration(milliseconds: 5),
          ),
          throwsA(
            isA<DuskCdpException>().having(
              (DuskCdpException e) => e.message,
              'message',
              contains('timed out'),
            ),
          ),
        );
      },
    );
  });
}
