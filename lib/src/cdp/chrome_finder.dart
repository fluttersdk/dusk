import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'cdp_client.dart';

// Re-export DuskCdpException so existing callers / tests that import only
// chrome_finder.dart keep compiling. The canonical declaration lives in
// cdp_client.dart (Wave 2); the Wave 1 local copy was removed when Step 1
// landed.
export 'cdp_client.dart' show DuskCdpException;

/// Represents the response from Chrome's `/json/version` endpoint.
///
/// All three fields are sourced directly from the JSON payload Chrome serves
/// when the remote-debugging port is open and healthy.
final class ChromeInfo {
  /// The WebSocket URL used to open a CDP session with the browser.
  final String webSocketDebuggerUrl;

  /// Human-readable browser identification string (e.g. "Chrome/130.0.0.0").
  final String browser;

  /// CDP protocol version string (e.g. "1.3").
  final String protocolVersion;

  const ChromeInfo({
    required this.webSocketDebuggerUrl,
    required this.browser,
    required this.protocolVersion,
  });
}

/// Probes a Chrome remote-debugging port until Chrome is ready or the timeout
/// expires.
///
/// Usage: call [ChromeFinder.probe] with the port Chrome was launched on. On
/// success it returns a [ChromeInfo] containing the WebSocket debugger URL and
/// browser version strings. On failure it throws [DuskCdpException].
final class ChromeFinder {
  ChromeFinder._();

  // ------------------------------------------------------------------
  // Test-seam (mirrors chrome_reaper.dart:32-78 injection pattern)
  // ------------------------------------------------------------------

  /// Default HTTP GET implementation used in production.
  ///
  /// Exposed so tests can reset the seam after swapping it out:
  /// `ChromeFinder.chromeFinderHttpGet = ChromeFinder.defaultHttpGet;`
  static Future<String> defaultHttpGet(Uri uri) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response = await request.close();
      if (response.statusCode == 404) {
        throw ChromeFinderHttpNotFoundException(uri.port);
      }
      return response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  /// Injectable HTTP GET function. Production code keeps the [defaultHttpGet]
  /// default; tests swap via field reassignment:
  ///
  /// ```dart
  /// ChromeFinder.chromeFinderHttpGet = (uri) async => '{"Browser": "..."}';
  /// ```
  @visibleForTesting
  static Future<String> Function(Uri) chromeFinderHttpGet = defaultHttpGet;

  // ------------------------------------------------------------------
  // Public API
  // ------------------------------------------------------------------

  /// Polls `http://localhost:<port>/json/version` in a retry loop until
  /// [timeout] elapses or Chrome responds with a valid CDP JSON payload.
  ///
  /// Behaviour by outcome:
  ///
  /// - **Chrome responds (2xx)**: parses JSON, returns [ChromeInfo].
  /// - **Port open but 404**: throws [DuskCdpException] immediately with a
  ///   hint that the port does not serve the Chrome DevTools Protocol. This
  ///   case is empirically observed when Chrome is running without
  ///   `--remote-debugging-port`.
  /// - **Connection refused (SocketException)**: sleeps [interval] and retries
  ///   until [timeout] elapses.
  /// - **Timeout**: throws [DuskCdpException] with a "timed out" message.
  static Future<ChromeInfo> probe({
    required int port,
    Duration timeout = const Duration(seconds: 10),
    Duration interval = const Duration(milliseconds: 250),
  }) async {
    final Uri uri = Uri.parse('http://localhost:$port/json/version');
    final DateTime deadline = DateTime.now().add(timeout);

    // 1. Retry loop: keep probing until the deadline passes.
    while (DateTime.now().isBefore(deadline)) {
      try {
        final String body = await chromeFinderHttpGet(uri);

        // 2. Parse the JSON payload Chrome returns.
        final dynamic decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          throw DuskCdpException(
            'Port $port returned unexpected JSON shape from /json/version.',
          );
        }

        // 3. Extract the three required fields and return ChromeInfo.
        final String? wsUrl = decoded['webSocketDebuggerUrl'] as String?;
        final String? browser = decoded['Browser'] as String?;
        final String? protocolVersion = decoded['Protocol-Version'] as String?;

        if (wsUrl == null || browser == null || protocolVersion == null) {
          throw DuskCdpException(
            'Port $port /json/version response is missing required fields '
            '(webSocketDebuggerUrl, Browser, Protocol-Version).',
          );
        }

        return ChromeInfo(
          webSocketDebuggerUrl: wsUrl,
          browser: browser,
          protocolVersion: protocolVersion,
        );
      } on ChromeFinderHttpNotFoundException catch (e) {
        // 4. Port is open but Chrome is not serving CDP. Throw immediately;
        //    retrying will not help.
        throw DuskCdpException(
          'Port ${e.port} is open but does not serve Chrome DevTools Protocol. '
          'Is it the right Chrome instance?',
        );
      } on SocketException {
        // 5. Connection refused: Chrome has not opened the port yet. Sleep and
        //    retry as long as there is budget remaining.
        if (DateTime.now().add(interval).isAfter(deadline)) break;
        await Future<void>.delayed(interval);
      }
    }

    // 6. Deadline passed without a successful response.
    throw DuskCdpException(
      'Chrome on port $port timed out after ${timeout.inSeconds}s. '
      'Ensure Chrome was launched with --remote-debugging-port=$port.',
    );
  }
}

/// Sentinel raised by [ChromeFinder.chromeFinderHttpGet] implementations when
/// the server responds with HTTP 404.
///
/// [ChromeFinder.defaultHttpGet] raises this when the status code is 404.
/// The probe loop catches it and immediately re-throws as [DuskCdpException]
/// without retrying, because a 404 means the port is open but Chrome is not
/// serving the DevTools Protocol.
///
/// Tests that stub [ChromeFinder.chromeFinderHttpGet] to simulate a 404
/// response must throw this type (not a local sentinel) so the probe loop
/// handles it correctly.
@visibleForTesting
final class ChromeFinderHttpNotFoundException implements Exception {
  const ChromeFinderHttpNotFoundException(this.port);

  /// The port that returned HTTP 404.
  final int port;

  @override
  String toString() => 'ChromeFinderHttpNotFoundException on port $port';
}
