import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// Exception thrown by [CdpClient] when the Chrome DevTools Protocol session
/// cannot be established or a request fails.
///
/// One concrete type covers every failure mode (port unreachable, malformed
/// JSON, WebSocket refused, per-request timeout, CDP error envelope). Callers
/// (DuskResizeCommand, DuskDeviceCommand, StartCommand's post-scrape Page.navigate)
/// branch on this single type rather than parse error strings.
final class DuskCdpException implements Exception {
  final String message;

  const DuskCdpException(this.message);

  @override
  String toString() => 'DuskCdpException: $message';
}

/// Signature for the test-injectable HTTP GET hook used during the
/// `/json/version` handshake.
@visibleForTesting
typedef HttpGet = Future<String> Function(Uri url);

/// Signature for the test-injectable WebSocket connect hook used to open the
/// CDP session.
@visibleForTesting
typedef WsConnect = Future<WebSocket> Function(String url);

/// Minimal in-house Chrome DevTools Protocol client.
///
/// Usage:
///
/// ```dart
/// final client = await CdpClient.connect(port: 9222);
/// try {
///   await client.send('Emulation.setDeviceMetricsOverride', {
///     'width': 375,
///     'height': 812,
///     'deviceScaleFactor': 3,
///     'mobile': true,
///   });
/// } finally {
///   await client.close();
/// }
/// ```
///
/// V1 surface intentionally narrow: [connect], [send], [close]. Typed wrappers
/// for individual CDP methods live in the consumer (DuskResizeCommand,
/// DuskDeviceCommand, StartCommand). CDP events (frames without an `id` field)
/// are ignored; the Emulation methods used by V1 are all request/response.
///
/// V1 connects to the browser-level WebSocket (i.e. `webSocketDebuggerUrl`
/// from `/json/version`) which is sufficient for Emulation.* + Browser.*
/// + Page.navigate against the single foreground tab.
final class CdpClient {
  CdpClient._({required WebSocket ws}) : _ws = ws {
    _connected = true;
    _subscription = _ws!.listen(
      _onMessage,
      onDone: _onDisconnect,
      onError: (Object _) => _onDisconnect(),
      cancelOnError: false,
    );
  }

  // ------------------------------------------------------------------
  // Test-seam (mirrors chrome_reaper.dart:32-78 injection pattern)
  // ------------------------------------------------------------------

  /// Default HTTP GET implementation used in production.
  ///
  /// Issues a single GET against [uri] via dart:io's [HttpClient], returns the
  /// utf8-decoded body. Closes the client on every path. Surfaced as a static
  /// field so tests can reset the seam:
  /// `CdpClient.cdpHttpGet = CdpClient.defaultHttpGet;`.
  static Future<String> defaultHttpGet(Uri uri) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response = await request.close();
      return response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  /// Default WebSocket connect implementation. Production code keeps the
  /// dart:io [WebSocket.connect] default; tests swap via field reassignment.
  static Future<WebSocket> defaultWsConnect(String url) =>
      WebSocket.connect(url);

  /// Injectable HTTP GET hook. Tests swap via field reassignment:
  ///
  /// ```dart
  /// CdpClient.cdpHttpGet = (uri) async => '{"webSocketDebuggerUrl": "..."}';
  /// ```
  @visibleForTesting
  static HttpGet cdpHttpGet = defaultHttpGet;

  /// Injectable WebSocket connect hook. Tests swap via field reassignment:
  ///
  /// ```dart
  /// CdpClient.cdpWsConnect = (url) async => throw SocketException('refused');
  /// ```
  @visibleForTesting
  static WsConnect cdpWsConnect = defaultWsConnect;

  // ------------------------------------------------------------------
  // Internal state
  // ------------------------------------------------------------------

  WebSocket? _ws;
  StreamSubscription<dynamic>? _subscription;
  bool _connected = false;
  int _nextId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pending =
      <int, Completer<Map<String, dynamic>>>{};

  /// Per-request timeout. Mirrors the 30s window used in flutter_skill's
  /// cdp_driver.dart so CDP calls fail loudly rather than hang the test
  /// suite or a live agent invocation.
  static const Duration _requestTimeout = Duration(seconds: 30);

  /// True once the WebSocket is open and not yet closed.
  bool get isConnected => _connected;

  // ------------------------------------------------------------------
  // Public API
  // ------------------------------------------------------------------

  /// Opens a CDP session against Chrome's remote-debugging endpoint on
  /// [port].
  ///
  /// Flow:
  ///
  ///   1. HTTP GET `http://localhost:<port>/json/version`.
  ///   2. Parse `webSocketDebuggerUrl` from the JSON response.
  ///   3. Open a WebSocket against that URL.
  ///
  /// Throws [DuskCdpException] when the port is unreachable, the body is not
  /// valid JSON, the JSON is missing `webSocketDebuggerUrl`, or the WebSocket
  /// handshake fails.
  static Future<CdpClient> connect({
    required int port,
    Duration handshakeTimeout = const Duration(seconds: 10),
  }) async {
    // V1 connects to the FIRST page tab (type: "page") from /json. The browser
    // endpoint at /json/version returns the browser-level WebSocket which does
    // NOT expose Emulation.* / Page.* (those are page-level domains; sending
    // them browser-level returns -32601 Method not found). The /json endpoint
    // lists every tab + worker; we filter for `type: "page"` and use the
    // first match's webSocketDebuggerUrl.
    final Uri listUri = Uri.parse('http://localhost:$port/json');

    // 1. HTTP handshake. SocketException + HttpException + any other failure
    //    becomes a typed "port unreachable" error so callers branch on a
    //    single exception type.
    final String body;
    try {
      body = await cdpHttpGet(listUri).timeout(handshakeTimeout);
    } catch (e) {
      throw DuskCdpException(
        'Chrome DevTools port unreachable on $port: $e',
      );
    }

    // 2. Parse the JSON envelope. /json returns a List of tab descriptors;
    //    non-list / wrong-shape responses are surfaced as DuskCdpException.
    final List<dynamic> tabs;
    try {
      final dynamic raw = jsonDecode(body);
      if (raw is! List<dynamic>) {
        throw const FormatException('not a JSON array');
      }
      tabs = raw;
    } catch (e) {
      throw DuskCdpException(
        'Chrome /json on port $port returned non-JSON-array response: $e',
      );
    }

    // 3. Filter for page tabs and pick the first one. Service worker, shared
    //    worker, and iframe tabs are excluded; Emulation.* targets the page.
    Map<String, dynamic>? pageTab;
    for (final dynamic entry in tabs) {
      if (entry is Map<String, dynamic> && entry['type'] == 'page') {
        pageTab = entry;
        break;
      }
    }
    if (pageTab == null) {
      throw DuskCdpException(
        'Chrome /json on port $port returned no page tab. '
        'Open a tab in the running Chrome before retrying.',
      );
    }

    final String? wsUrl = pageTab['webSocketDebuggerUrl'] as String?;
    if (wsUrl == null || wsUrl.isEmpty) {
      throw DuskCdpException(
        'Chrome /json on port $port page tab is missing webSocketDebuggerUrl.',
      );
    }

    // 4. Open the WebSocket. Refused / timeout / TLS errors become
    //    DuskCdpException too.
    final WebSocket ws;
    try {
      ws = await cdpWsConnect(wsUrl).timeout(handshakeTimeout);
    } catch (e) {
      throw DuskCdpException(
        'WebSocket connection to $wsUrl refused: $e',
      );
    }

    return CdpClient._(ws: ws);
  }

  /// Sends a JSON-RPC request and returns the parsed `result` map.
  ///
  /// Registers a [Completer] in `_pending[id]`, writes the envelope to the
  /// WebSocket, returns the completer's future. The future completes with the
  /// `result` map on success or with a [DuskCdpException] on either an error
  /// envelope or the 30s [_requestTimeout].
  Future<Map<String, dynamic>> send(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (!_connected || _ws == null) {
      throw const DuskCdpException(
        'CDP client is not connected; call connect() first.',
      );
    }

    final int id = _nextId++;
    final Completer<Map<String, dynamic>> completer =
        Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    final Map<String, dynamic> envelope = <String, dynamic>{
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    };

    try {
      _ws!.add(jsonEncode(envelope));
    } catch (e) {
      _pending.remove(id);
      throw DuskCdpException(
        'Failed to write CDP request "$method" to WebSocket: $e',
      );
    }

    return completer.future.timeout(
      _requestTimeout,
      onTimeout: () {
        _pending.remove(id);
        throw DuskCdpException(
          'CDP call "$method" timed out after ${_requestTimeout.inSeconds}s.',
        );
      },
    );
  }

  /// Closes the WebSocket and drains every pending [Completer] with a
  /// [DuskCdpException].
  ///
  /// Idempotent: subsequent calls return immediately. Pending Completers are
  /// failed BEFORE the WebSocket close so in-flight `send()` futures resolve
  /// with a typed error rather than dangling forever.
  Future<void> close() async {
    if (!_connected) return;
    _connected = false;

    // 1. Drain pending Completers first; once we close the WebSocket, the
    //    listener may or may not fire onDone before the test asserts.
    _failAllPending('CDP client closed.');

    // 2. Cancel the inbound subscription so a late frame after close cannot
    //    race the drain.
    try {
      await _subscription?.cancel();
    } catch (_) {
      // Subscription already canceled by onDone; not actionable.
    }
    _subscription = null;

    // 3. Close the socket. Errors from a half-closed peer are swallowed; the
    //    drain above already settled the public futures.
    try {
      await _ws?.close();
    } catch (_) {
      // Best-effort; the WebSocket may already be torn down.
    }
    _ws = null;
  }

  // ------------------------------------------------------------------
  // Internals
  // ------------------------------------------------------------------

  void _onMessage(dynamic raw) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      // Malformed inbound frame: ignore. The CDP wire format never produces
      // these in practice; defensive guard only.
      return;
    }

    final dynamic rawId = json['id'];
    if (rawId is! int) {
      // Event frame (no id). V1 does not subscribe to events; drop it.
      return;
    }

    final Completer<Map<String, dynamic>>? completer = _pending.remove(rawId);
    if (completer == null) return;

    final dynamic error = json['error'];
    if (error is Map<String, dynamic>) {
      completer.completeError(
        DuskCdpException(
          'CDP error ${error['code']}: ${error['message']}',
        ),
      );
      return;
    }

    final dynamic result = json['result'];
    completer.complete(
      result is Map<String, dynamic> ? result : <String, dynamic>{},
    );
  }

  void _onDisconnect() {
    _connected = false;
    _failAllPending('CDP WebSocket disconnected.');
  }

  void _failAllPending(String reason) {
    if (_pending.isEmpty) return;
    final List<Completer<Map<String, dynamic>>> drained =
        List<Completer<Map<String, dynamic>>>.of(_pending.values);
    _pending.clear();
    for (final Completer<Map<String, dynamic>> completer in drained) {
      if (!completer.isCompleted) {
        completer.completeError(DuskCdpException(reason));
      }
    }
  }
}
