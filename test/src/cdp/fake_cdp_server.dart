import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// In-process fake of Chrome's DevTools Protocol surface, used by the CDP
/// subsystem test suite (CdpClient, ChromeFinder, DuskResizeCommand,
/// DuskDeviceCommand). Binds an [HttpServer] on
/// [InternetAddress.loopbackIPv4] with an ephemeral port (port: 0), serves
/// `/json/version`, accepts `WebSocketTransformer.upgrade` on
/// `/devtools/browser/abc`, routes JSON-RPC frames to caller-supplied
/// handlers.
///
/// Test-only: the file lives under `test/src/cdp/` and is NEVER exported
/// from `lib/`. Consumed by sibling test files via the relative import
/// `import 'fake_cdp_server.dart';` (within the same directory) or
/// `import '../../cdp/fake_cdp_server.dart';` (from `test/src/commands/`).
///
/// The class name omits the leading underscore the plan suggests because
/// Dart's underscore mangles library-private visibility, which would block
/// cross-test-file imports from Steps 1 / 6 / 7. The test-only invariant is
/// upheld by file location (under `test/`), not by name mangling.
class FakeCdpServer {
  FakeCdpServer._({
    required HttpServer httpServer,
    required Map<String,
            Future<Map<String, dynamic>> Function(Map<String, dynamic> params)>?
        handlers,
    required bool failOnJsonVersion,
    required bool dropWebSocket,
    required Duration delayResponseMs,
  })  : _httpServer = httpServer,
        _handlers = handlers,
        _failOnJsonVersion = failOnJsonVersion,
        _dropWebSocket = dropWebSocket,
        _delayResponseMs = delayResponseMs;

  /// Spins up the fake server on an ephemeral loopback port.
  ///
  /// - [handlers]: per-method JSON-RPC handlers. Each entry's key is a CDP
  ///   `method` string (e.g. `Browser.getVersion`, `Emulation.setDeviceMetricsOverride`);
  ///   the function receives the incoming `params` map and returns the
  ///   `result` map. Methods absent from the map (or any method when
  ///   [handlers] itself is null) get the JSON-RPC -32601 "Method not found"
  ///   error envelope. Pass `<String, Future<Map<String, dynamic>> Function(Map<String, dynamic>)>{}`
  ///   to mean "no methods configured; everything errors".
  /// - [failOnJsonVersion]: when true, the `/json/version` route responds
  ///   with HTTP 500 + empty body. The WebSocket upgrade route stays open;
  ///   this models a "Chrome is alive but discovery is broken" failure.
  /// - [dropWebSocket]: when true, the harness accepts the WS upgrade, reads
  ///   exactly one inbound frame, and closes the socket immediately without
  ///   replying. Models a mid-session disconnect for CdpClient timeout-path
  ///   testing.
  /// - [delayResponseMs]: when greater than [Duration.zero], each WS reply
  ///   waits this long before being written. Used to exercise CdpClient's
  ///   per-request timeout.
  static Future<FakeCdpServer> start({
    Map<String,
            Future<Map<String, dynamic>> Function(Map<String, dynamic> params)>?
        handlers,
    bool failOnJsonVersion = false,
    bool dropWebSocket = false,
    Duration delayResponseMs = Duration.zero,
  }) async {
    final HttpServer httpServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );

    final FakeCdpServer server = FakeCdpServer._(
      httpServer: httpServer,
      handlers: handlers,
      failOnJsonVersion: failOnJsonVersion,
      dropWebSocket: dropWebSocket,
      delayResponseMs: delayResponseMs,
    );

    // Fire-and-forget request loop. Errors here would otherwise drown the
    // test report; we capture each request inside try/catch and ignore
    // socket-level disconnects, which are normal during teardown.
    server._serveLoop = server._serve();
    return server;
  }

  final HttpServer _httpServer;
  final Map<String,
          Future<Map<String, dynamic>> Function(Map<String, dynamic> params)>?
      _handlers;
  final bool _failOnJsonVersion;
  final bool _dropWebSocket;
  final Duration _delayResponseMs;

  final List<WebSocket> _openSockets = <WebSocket>[];
  Future<void>? _serveLoop;
  bool _stopped = false;

  /// Loopback port chosen by the OS at bind time.
  int get port => _httpServer.port;

  /// Canonical WebSocket URL clients should connect to. Matches the
  /// `webSocketDebuggerUrl` field returned by `/json/version`.
  String get webSocketDebuggerUrl =>
      'ws://localhost:$port/devtools/browser/abc';

  /// Closes every open WebSocket then shuts down the HTTP server.
  /// Idempotent: subsequent calls return without throwing.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;

    // 1. Close every accepted WS so dart:io releases the underlying TCP
    //    sockets before HttpServer.close.
    for (final WebSocket ws in List<WebSocket>.of(_openSockets)) {
      try {
        await ws.close();
      } catch (_) {
        // Already closed (test asserted on .done, etc.). Safe to ignore.
      }
    }
    _openSockets.clear();

    // 2. force: true cancels any in-flight HttpRequest, releases the port
    //    immediately, and lets the test re-bind on the same port to verify
    //    cleanup.
    await _httpServer.close(force: true);

    // 3. Drain the serve loop so the test process does not exit while a
    //    request handler is still mid-flight. Errors thrown after close
    //    (e.g. canceled subscriptions) are swallowed; the loop's job is
    //    done.
    try {
      await _serveLoop;
    } catch (_) {
      // Expected when force-close races a request handler.
    }
  }

  Future<void> _serve() async {
    await for (final HttpRequest request in _httpServer) {
      try {
        await _handleRequest(request);
      } catch (_) {
        // Per-request failures must not crash the loop; the test asserts
        // observable behavior (status code, frame contents) which already
        // accounts for the error envelopes.
      }
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    // 1a. /json: tab discovery handshake. CdpClient.connect calls this to
    //     locate the first `type: "page"` tab and reuse its
    //     webSocketDebuggerUrl. Returns a JSON ARRAY of tab descriptors so
    //     CdpClient's array-or-bust parser is satisfied. Honors
    //     [failOnJsonVersion] (the flag covers any tab-list failure path).
    if (request.method == 'GET' && request.uri.path == '/json') {
      if (_failOnJsonVersion) {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
        return;
      }
      final List<Map<String, dynamic>> body = <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'page',
          'id': 'tab-0',
          'title': 'Fake tab',
          'url': 'about:blank',
          'webSocketDebuggerUrl': webSocketDebuggerUrl,
        },
      ];
      request.response.statusCode = HttpStatus.ok;
      request.response.headers
          .set(HttpHeaders.contentTypeHeader, 'application/json');
      request.response.write(jsonEncode(body));
      await request.response.close();
      return;
    }

    // 1b. /json/version: legacy browser-level discovery endpoint. Some
    //     tests still exercise the metadata payload directly.
    if (request.method == 'GET' && request.uri.path == '/json/version') {
      if (_failOnJsonVersion) {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
        return;
      }
      final Map<String, dynamic> body = <String, dynamic>{
        'webSocketDebuggerUrl': webSocketDebuggerUrl,
        'Browser': 'Chrome/130.0.0.0',
        'Protocol-Version': '1.3',
      };
      request.response.statusCode = HttpStatus.ok;
      request.response.headers
          .set(HttpHeaders.contentTypeHeader, 'application/json');
      request.response.write(jsonEncode(body));
      await request.response.close();
      return;
    }

    // 2. /devtools/browser/abc: WebSocket upgrade + JSON-RPC dispatch.
    if (request.uri.path == '/devtools/browser/abc') {
      final WebSocket ws = await WebSocketTransformer.upgrade(request);
      _openSockets.add(ws);
      _attachWebSocketHandler(ws);
      return;
    }

    // 3. Anything else: 404.
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  void _attachWebSocketHandler(WebSocket ws) {
    ws.listen(
      (dynamic frame) async {
        // 1. Drop-mode short-circuit: close on the first inbound frame.
        if (_dropWebSocket) {
          await ws.close();
          return;
        }

        // 2. Parse the JSON-RPC envelope. Malformed frames are ignored;
        //    a real client would not produce them.
        final Map<String, dynamic> envelope;
        try {
          envelope = jsonDecode(frame as String) as Map<String, dynamic>;
        } catch (_) {
          return;
        }

        final dynamic rawId = envelope['id'];
        final String method = (envelope['method'] as String?) ?? '';
        final Map<String, dynamic> params =
            (envelope['params'] as Map<String, dynamic>?) ??
                <String, dynamic>{};

        // 3. Compute the reply via the configured handler. Default error
        //    envelope when no handler is registered for the method.
        Map<String, dynamic> reply;
        final Future<Map<String, dynamic>> Function(Map<String, dynamic>)?
            handler = _handlers?[method];
        if (handler == null) {
          reply = <String, dynamic>{
            'id': rawId,
            'error': <String, dynamic>{
              'code': -32601,
              'message': 'Method not found',
            },
          };
        } else {
          try {
            final Map<String, dynamic> result = await handler(params);
            reply = <String, dynamic>{
              'id': rawId,
              'result': result,
            };
          } catch (e) {
            reply = <String, dynamic>{
              'id': rawId,
              'error': <String, dynamic>{
                'code': -32000,
                'message': e.toString(),
              },
            };
          }
        }

        // 4. Optional artificial latency for timeout-path tests.
        if (_delayResponseMs > Duration.zero) {
          await Future<void>.delayed(_delayResponseMs);
        }

        // 5. Send the reply, guarding against a socket closed mid-handler.
        try {
          ws.add(jsonEncode(reply));
        } catch (_) {
          // Socket dropped between handler resolution and write; harmless.
        }
      },
      onDone: () {
        _openSockets.remove(ws);
      },
      onError: (Object _) {
        _openSockets.remove(ws);
      },
      cancelOnError: true,
    );
  }
}
