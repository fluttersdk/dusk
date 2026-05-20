import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'fake_cdp_server.dart';

/// Meta-test for the [FakeCdpServer] test harness. Five scenarios:
///   (a) start() + stop() lifecycle clean (no leaked sockets, port reusable).
///   (b) HTTP /json/version returns valid JSON shape.
///   (c) WS upgrade + JSON-RPC round-trip works with a custom handler.
///   (d) failOnJsonVersion = true returns HTTP 500.
///   (e) dropWebSocket = true disconnects mid-stream.
void main() {
  group('FakeCdpServer', () {
    // ---------------------------------------------------------------
    // (a) start() + stop() lifecycle clean
    // ---------------------------------------------------------------
    test(
      'start() returns within 100ms and stop() releases the port for re-bind',
      () async {
        final Stopwatch startSw = Stopwatch()..start();
        final FakeCdpServer server = await FakeCdpServer.start();
        startSw.stop();

        expect(
          startSw.elapsedMilliseconds,
          lessThan(100),
          reason: 'start() must complete within 100ms per plan Done when',
        );

        final int port = server.port;
        expect(port, greaterThan(0));

        final Stopwatch stopSw = Stopwatch()..start();
        await server.stop();
        stopSw.stop();

        expect(
          stopSw.elapsedMilliseconds,
          lessThan(100),
          reason: 'stop() must complete within 100ms per plan Done when',
        );

        // Re-bind the same port to prove the previous HttpServer released its
        // file descriptor cleanly. Bind on the EXACT port; if the harness
        // leaked, the bind throws SocketException.
        final ServerSocket probe =
            await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
        await probe.close();
      },
    );

    test('stop() is idempotent', () async {
      final FakeCdpServer server = await FakeCdpServer.start();
      await server.stop();
      // Second call must not throw.
      await server.stop();
    });

    // ---------------------------------------------------------------
    // (b) HTTP /json/version returns valid JSON shape
    // ---------------------------------------------------------------
    test('HTTP /json/version returns the documented JSON shape', () async {
      final FakeCdpServer server = await FakeCdpServer.start();
      addTearDown(server.stop);

      final HttpClient client = HttpClient();
      final HttpClientRequest req = await client
          .getUrl(Uri.parse('http://localhost:${server.port}/json/version'));
      final HttpClientResponse res = await req.close();

      expect(res.statusCode, equals(HttpStatus.ok));

      final String body = await res.transform(utf8.decoder).join();
      client.close();

      final Map<String, dynamic> json =
          jsonDecode(body) as Map<String, dynamic>;
      expect(json.containsKey('webSocketDebuggerUrl'), isTrue);
      expect(json.containsKey('Browser'), isTrue);
      expect(json.containsKey('Protocol-Version'), isTrue);
      expect(
        json['webSocketDebuggerUrl'] as String,
        equals('ws://localhost:${server.port}/devtools/browser/abc'),
      );
      expect(json['Browser'] as String, contains('Chrome/'));
      expect(json['Protocol-Version'] as String, equals('1.3'));
      expect(
        server.webSocketDebuggerUrl,
        equals(json['webSocketDebuggerUrl']),
      );
    });

    // ---------------------------------------------------------------
    // (c) WS upgrade + JSON-RPC round-trip via custom handler
    // ---------------------------------------------------------------
    test('WS upgrade + JSON-RPC round-trip echoes params via handler',
        () async {
      final FakeCdpServer server = await FakeCdpServer.start(
        handlers: <String,
            Future<Map<String, dynamic>> Function(Map<String, dynamic>)>{
          'Test.echo': (Map<String, dynamic> params) async {
            return <String, dynamic>{'echoed': params['echo']};
          },
        },
      );
      addTearDown(server.stop);

      final WebSocket ws = await WebSocket.connect(server.webSocketDebuggerUrl);
      final Completer<Map<String, dynamic>> received =
          Completer<Map<String, dynamic>>();
      ws.listen((dynamic frame) {
        received.complete(
          jsonDecode(frame as String) as Map<String, dynamic>,
        );
      });

      ws.add(jsonEncode(<String, dynamic>{
        'id': 7,
        'method': 'Test.echo',
        'params': <String, dynamic>{'echo': 'hello'},
      }));

      final Map<String, dynamic> reply =
          await received.future.timeout(const Duration(seconds: 2));
      expect(reply['id'], equals(7));
      expect(reply['result'], isA<Map<String, dynamic>>());
      expect(
        (reply['result'] as Map<String, dynamic>)['echoed'],
        equals('hello'),
      );

      await ws.close();
    });

    test(
      'WS unknown method returns JSON-RPC -32601 error when handlers is empty',
      () async {
        final FakeCdpServer server = await FakeCdpServer.start(
          handlers: <String,
              Future<Map<String, dynamic>> Function(Map<String, dynamic>)>{},
        );
        addTearDown(server.stop);

        final WebSocket ws =
            await WebSocket.connect(server.webSocketDebuggerUrl);
        final Completer<Map<String, dynamic>> received =
            Completer<Map<String, dynamic>>();
        ws.listen((dynamic frame) {
          received.complete(
            jsonDecode(frame as String) as Map<String, dynamic>,
          );
        });

        ws.add(jsonEncode(<String, dynamic>{
          'id': 42,
          'method': 'Unconfigured.method',
          'params': <String, dynamic>{},
        }));

        final Map<String, dynamic> reply =
            await received.future.timeout(const Duration(seconds: 2));
        expect(reply['id'], equals(42));
        expect(reply['error'], isA<Map<String, dynamic>>());
        final Map<String, dynamic> err = reply['error'] as Map<String, dynamic>;
        expect(err['code'], equals(-32601));
        expect(err['message'], equals('Method not found'));

        await ws.close();
      },
    );

    // ---------------------------------------------------------------
    // (d) failOnJsonVersion = true returns HTTP 500
    // ---------------------------------------------------------------
    test('failOnJsonVersion = true returns HTTP 500 with empty body', () async {
      final FakeCdpServer server =
          await FakeCdpServer.start(failOnJsonVersion: true);
      addTearDown(server.stop);

      final HttpClient client = HttpClient();
      final HttpClientRequest req = await client
          .getUrl(Uri.parse('http://localhost:${server.port}/json/version'));
      final HttpClientResponse res = await req.close();

      expect(res.statusCode, equals(HttpStatus.internalServerError));

      final String body = await res.transform(utf8.decoder).join();
      client.close();
      expect(body, isEmpty);
    });

    // ---------------------------------------------------------------
    // (e) dropWebSocket = true disconnects mid-stream
    // ---------------------------------------------------------------
    test('dropWebSocket = true closes the WS after the first incoming frame',
        () async {
      final FakeCdpServer server =
          await FakeCdpServer.start(dropWebSocket: true);
      addTearDown(server.stop);

      final WebSocket ws = await WebSocket.connect(server.webSocketDebuggerUrl);

      // Drain inbound frames so the close handshake from the server side can
      // progress; without a listener the client stream stays paused and
      // WebSocket.done never resolves.
      ws.listen((_) {}, onError: (_) {}, cancelOnError: false);

      ws.add(jsonEncode(<String, dynamic>{
        'id': 1,
        'method': 'Browser.getVersion',
        'params': <String, dynamic>{},
      }));

      // The harness closes the socket as soon as it reads the first frame.
      // WebSocket.done must resolve.
      await ws.done.timeout(const Duration(seconds: 2));
    });

    test('delayResponseMs delays each response by the configured duration',
        () async {
      final FakeCdpServer server = await FakeCdpServer.start(
        handlers: <String,
            Future<Map<String, dynamic>> Function(Map<String, dynamic>)>{
          'Test.ping': (_) async => <String, dynamic>{'pong': true},
        },
        delayResponseMs: const Duration(milliseconds: 200),
      );
      addTearDown(server.stop);

      final WebSocket ws = await WebSocket.connect(server.webSocketDebuggerUrl);
      final Completer<Map<String, dynamic>> received =
          Completer<Map<String, dynamic>>();
      ws.listen((dynamic frame) {
        received.complete(
          jsonDecode(frame as String) as Map<String, dynamic>,
        );
      });

      final Stopwatch sw = Stopwatch()..start();
      ws.add(jsonEncode(<String, dynamic>{
        'id': 3,
        'method': 'Test.ping',
        'params': <String, dynamic>{},
      }));

      await received.future.timeout(const Duration(seconds: 2));
      sw.stop();

      expect(
        sw.elapsedMilliseconds,
        greaterThanOrEqualTo(180),
        reason: 'response should be delayed ~200ms; allow a small jitter floor',
      );

      await ws.close();
    });
  });
}
