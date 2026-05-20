import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/cdp/cdp_client.dart';

import 'fake_cdp_server.dart';

void main() {
  group('CdpClient', () {
    // Reset the test-seams after every case so a stub from one test cannot
    // contaminate the next.
    setUp(() {
      CdpClient.cdpHttpGet = CdpClient.defaultHttpGet;
      CdpClient.cdpWsConnect = CdpClient.defaultWsConnect;
    });

    tearDown(() {
      CdpClient.cdpHttpGet = CdpClient.defaultHttpGet;
      CdpClient.cdpWsConnect = CdpClient.defaultWsConnect;
    });

    // ---------------------------------------------------------------
    // (a) connect() succeeds against a healthy FakeCdpServer.
    // ---------------------------------------------------------------
    test(
      'connect() opens a WebSocket against a healthy FakeCdpServer',
      () async {
        final FakeCdpServer server = await FakeCdpServer.start();
        addTearDown(server.stop);

        final CdpClient client = await CdpClient.connect(port: server.port);
        addTearDown(client.close);

        expect(client.isConnected, isTrue);
      },
    );

    // ---------------------------------------------------------------
    // (b) HTTP /json/version unreachable → DuskCdpException with
    //     "port unreachable" message.
    // ---------------------------------------------------------------
    test(
      'connect() throws DuskCdpException with "port unreachable" when /json/version fails',
      () async {
        // Stub cdpHttpGet to throw a SocketException-flavoured failure that
        // models a closed port. CdpClient should surface this as a typed
        // DuskCdpException containing the literal "port unreachable" phrase.
        CdpClient.cdpHttpGet = (Uri uri) async {
          throw const SocketException('Connection refused');
        };

        await expectLater(
          () => CdpClient.connect(port: 65432),
          throwsA(
            isA<DuskCdpException>().having(
              (DuskCdpException e) => e.message,
              'message',
              contains('port unreachable'),
            ),
          ),
        );
      },
    );

    // ---------------------------------------------------------------
    // (c) WebSocket connect refused → DuskCdpException.
    // ---------------------------------------------------------------
    test(
      'connect() throws DuskCdpException when the WebSocket handshake is refused',
      () async {
        // The HTTP /json/version step succeeds (handshake URL parsed) but
        // the WebSocket connect throws. CdpClient must rethrow as a typed
        // DuskCdpException so callers (DuskResizeCommand, etc.) can branch
        // on a single exception type.
        final FakeCdpServer server = await FakeCdpServer.start();
        addTearDown(server.stop);

        CdpClient.cdpWsConnect = (String url) async {
          throw const SocketException('WebSocket connection refused');
        };

        await expectLater(
          () => CdpClient.connect(port: server.port),
          throwsA(
            isA<DuskCdpException>().having(
              (DuskCdpException e) => e.message,
              'message',
              contains('WebSocket'),
            ),
          ),
        );
      },
    );

    // ---------------------------------------------------------------
    // (d) send() round-trips a method call through the correlation map.
    // ---------------------------------------------------------------
    test(
      'send() round-trips a JSON-RPC call through the id<->Completer map',
      () async {
        final FakeCdpServer server = await FakeCdpServer.start(
          handlers: <String,
              Future<Map<String, dynamic>> Function(Map<String, dynamic>)>{
            'Browser.getVersion': (Map<String, dynamic> params) async {
              return <String, dynamic>{
                'protocolVersion': '1.3',
                'product': 'Chrome/130.0.0.0',
                'revision': '@abc',
                'userAgent': 'Mozilla/5.0',
                'jsVersion': '13.0',
              };
            },
            'Emulation.setDeviceMetricsOverride':
                (Map<String, dynamic> params) async {
              // Echo the params back inside the result so the test can assert
              // the correlation map preserved them across the round-trip.
              return <String, dynamic>{'echoed': params};
            },
          },
        );
        addTearDown(server.stop);

        final CdpClient client = await CdpClient.connect(port: server.port);
        addTearDown(client.close);

        final Map<String, dynamic> getVersion =
            await client.send('Browser.getVersion');
        expect(getVersion['product'], equals('Chrome/130.0.0.0'));
        expect(getVersion['protocolVersion'], equals('1.3'));

        final Map<String, dynamic> setMetrics = await client.send(
          'Emulation.setDeviceMetricsOverride',
          <String, dynamic>{
            'width': 375,
            'height': 812,
            'deviceScaleFactor': 3,
            'mobile': true,
          },
        );
        final Map<String, dynamic> echoed =
            setMetrics['echoed'] as Map<String, dynamic>;
        expect(echoed['width'], equals(375));
        expect(echoed['height'], equals(812));
        expect(echoed['deviceScaleFactor'], equals(3));
        expect(echoed['mobile'], isTrue);
      },
    );

    // ---------------------------------------------------------------
    // (e) send() with an error response completeError's the Future.
    // ---------------------------------------------------------------
    test(
      'send() completeError\'s the Future when CDP returns an error envelope',
      () async {
        // Passing an empty handlers map causes FakeCdpServer to reply with the
        // JSON-RPC -32601 "Method not found" error envelope for every method.
        final FakeCdpServer server = await FakeCdpServer.start(
          handlers: <String,
              Future<Map<String, dynamic>> Function(Map<String, dynamic>)>{},
        );
        addTearDown(server.stop);

        final CdpClient client = await CdpClient.connect(port: server.port);
        addTearDown(client.close);

        await expectLater(
          () => client.send('Emulation.fakeMethodThatDoesNotExist'),
          throwsA(
            isA<DuskCdpException>().having(
              (DuskCdpException e) => e.message,
              'message',
              contains('-32601'),
            ),
          ),
        );
      },
    );

    // ---------------------------------------------------------------
    // (f) close() drains pending Completers without hanging.
    // ---------------------------------------------------------------
    test(
      'close() drains pending Completers without hanging',
      () async {
        // Use delayResponseMs so the FakeCdpServer never replies before close
        // is called. The send() Future must complete (with an error) once
        // close() drains the pending map; if drain leaks, the test times out.
        final FakeCdpServer server = await FakeCdpServer.start(
          handlers: <String,
              Future<Map<String, dynamic>> Function(Map<String, dynamic>)>{
            'Browser.getVersion': (Map<String, dynamic> _) async {
              return <String, dynamic>{};
            },
          },
          delayResponseMs: const Duration(seconds: 30),
        );
        addTearDown(server.stop);

        final CdpClient client = await CdpClient.connect(port: server.port);

        // Fire a request that will not return before close(). Attach an
        // error sink IMMEDIATELY so the Future never propagates an unhandled
        // error when close() drains the Completer below.
        Object? pendingError;
        final Future<void> pendingObserved =
            client.send('Browser.getVersion').then<void>(
          (_) => null,
          onError: (Object e) {
            pendingError = e;
          },
        );

        // Give the WS write time to flush, then close the client.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await client.close().timeout(const Duration(seconds: 2));

        // The pending send must complete (with an error) so callers do not
        // leak Completers across a tear-down.
        await pendingObserved.timeout(const Duration(seconds: 2));
        expect(pendingError, isA<DuskCdpException>());

        expect(client.isConnected, isFalse);
      },
    );
  });
}
