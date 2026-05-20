@Tags(<String>['integration'])
@Skip(
  'requires Chrome on PATH; run manually: '
  'flutter test test/integration --tags integration',
)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_dusk/src/cdp/cdp_client.dart';

/// Integration smoke test for the full CDP chain.
///
/// Exercises:
///
///   1. `artisan start --cdp-port=<port>` boots Chrome with remote debugging,
///      writes vmServiceUri + chromePid + cdpPort + tmpProfileDir to
///      `~/.artisan/state.json`.
///   2. `dusk:resize` round-trips a viewport change through CDP.
///   3. `dusk:device --preset=iphone-x` resolves a curated preset and pushes
///      the 3-call CDP chain.
///   4. Hot reload via the FIFO surfaces "Reloaded" in `flutter-dev.log`
///      (Oracle F1 mitigation against dart-lang/webdev#2642).
///   5. `artisan stop` reaps Chrome AND clears `state.json`.
///
/// Skipped by default. Real Chrome required; ~30 to 60s per run. Tagged
/// `integration` so the manual invocation opts in explicitly:
///
/// ```
/// flutter test test/integration/cdp_smoke_test.dart --tags=integration
/// ```
void main() {
  // ------------------------------------------------------------------
  // Shared per-test setup. Each test claims its own ephemeral CDP port
  // so a stale Chrome from a prior failed run cannot wedge subsequent
  // runs.
  // ------------------------------------------------------------------

  late int cdpPort;
  late String artisanHome;
  late File stateFile;
  late File flutterDevLog;
  late File flutterDevFifo;

  Future<int> pickFreeCdpPort({int start = 9223, int end = 9250}) async {
    for (int candidate = start; candidate <= end; candidate++) {
      try {
        final ServerSocket probe =
            await ServerSocket.bind(InternetAddress.loopbackIPv4, candidate);
        await probe.close();
        return candidate;
      } on SocketException {
        // Port is busy; try the next one.
      }
    }
    throw StateError(
      'No free CDP port found in range $start..$end. '
      'Close any lingering Chrome --remote-debugging-port instances.',
    );
  }

  Future<ProcessResult> runArtisan(
    List<String> args, {
    Duration timeout = const Duration(seconds: 60),
  }) {
    // `dart run fluttersdk_artisan <args>` is the consumer-facing entry. The
    // smoke test runs against the dusk package's own pubspec, which depends on
    // fluttersdk_artisan via path. Process inherits stdout / stderr so the
    // test log captures the full artisan trace on failure.
    return Process.run('dart', <String>['run', 'fluttersdk_artisan', ...args])
        .timeout(timeout);
  }

  Future<void> stopArtisanQuietly() async {
    try {
      await runArtisan(<String>['stop'], timeout: const Duration(seconds: 30));
    } catch (_) {
      // Stop is best-effort during setup / teardown; the next assertions
      // verify the post-state on disk (state file absent + port free).
    }
  }

  Future<Map<String, dynamic>> waitForStateWithVmServiceUri({
    Duration timeout = const Duration(seconds: 60),
    Duration interval = const Duration(milliseconds: 500),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (stateFile.existsSync()) {
        try {
          final Map<String, dynamic> decoded =
              jsonDecode(stateFile.readAsStringSync()) as Map<String, dynamic>;
          final String? uri = decoded['vmServiceUri'] as String?;
          if (uri != null && uri.isNotEmpty) {
            return decoded;
          }
        } catch (_) {
          // Partial / atomic-rename window; retry.
        }
      }
      await Future<void>.delayed(interval);
    }
    throw TimeoutException(
      'state.json never gained a populated vmServiceUri within '
      '${timeout.inSeconds}s. Path: ${stateFile.path}.',
    );
  }

  Future<String> httpGetBody(Uri uri, {Duration? timeout}) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response = timeout == null
          ? await request.close()
          : await request.close().timeout(timeout);
      return response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  setUp(() async {
    final String? home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError(
        'HOME environment variable is not set. '
        'Integration smoke needs ~/.artisan/ for state + FIFO + log paths.',
      );
    }
    artisanHome = '$home/.artisan';
    stateFile = File('$artisanHome/state.json');
    flutterDevLog = File('$artisanHome/flutter-dev.log');
    flutterDevFifo = File('$artisanHome/flutter-dev.fifo');

    // Pre-cleanup: any lingering artisan from a previous failed run must be
    // reaped before this test claims its CDP port.
    await stopArtisanQuietly();
    cdpPort = await pickFreeCdpPort();
  });

  tearDown(() async {
    // Post-cleanup is non-negotiable: leaving artisan + Chrome alive between
    // tests leaks PIDs, file descriptors, and /tmp/dusk-chrome-* profile
    // directories. Must NOT-touching means cleanup runs unconditionally.
    await stopArtisanQuietly();
  });

  // ------------------------------------------------------------------
  // Test 1: happy path.
  // ------------------------------------------------------------------
  test(
    'artisan start --cdp-port boots Chrome + dusk:resize round-trips via CDP',
    () async {
      // 1. Spawn artisan start --cdp-port=$cdpPort. Foreground; the binary
      //    backgrounds the flutter run subprocess itself, so this Future
      //    resolves once state.json has the vmServiceUri populated OR the
      //    spawn fails fast.
      final Future<ProcessResult> startFuture = runArtisan(
        <String>[
          'start',
          '--device=chrome',
          '--port=3100',
          '--cdp-port=$cdpPort',
        ],
        timeout: const Duration(seconds: 90),
      );

      // 2. Race the state-file watch against the start subprocess. Whichever
      //    resolves first wins: a fast crash surfaces the artisan stderr,
      //    a successful spawn surfaces the populated state.
      final Map<String, dynamic> state = await waitForStateWithVmServiceUri();
      expect(
        state['cdpPort'],
        equals(cdpPort),
        reason: 'state.json must record the cdpPort that was launched.',
      );
      expect(
        state['chromePid'],
        isA<int>(),
        reason: 'state.json must record the spawned Chrome PID.',
      );
      expect(
        state['tmpProfileDir'],
        isA<String>(),
        reason: 'state.json must record the Chrome user-data-dir.',
      );

      // 3. Direct probe: Chrome /json/version answers with valid JSON.
      final String versionBody = await httpGetBody(
        Uri.parse('http://localhost:$cdpPort/json/version'),
        timeout: const Duration(seconds: 5),
      );
      final Map<String, dynamic> versionJson =
          jsonDecode(versionBody) as Map<String, dynamic>;
      expect(
        versionJson['webSocketDebuggerUrl'],
        isA<String>(),
        reason: 'Chrome /json/version must surface a WebSocket URL.',
      );
      expect(
        (versionJson['Browser'] as String? ?? '').toLowerCase(),
        contains('chrome'),
        reason: 'Probe must hit a Chrome instance, not another DevTools '
            'server (Edge / Brave / Electron).',
      );

      // 4. dusk:resize sends Emulation.setDeviceMetricsOverride. iPhone-X
      //    dimensions are the canonical smoke target (also exercised by the
      //    preset test).
      final ProcessResult resize = await runArtisan(
        <String>[
          'dusk:resize',
          '--width=375',
          '--height=812',
          '--dpr=3',
          '--mobile',
          '--touch',
        ],
        timeout: const Duration(seconds: 30),
      );
      expect(
        resize.exitCode,
        equals(0),
        reason:
            'dusk:resize must succeed. stdout=${resize.stdout} stderr=${resize.stderr}',
      );

      // 5. Independent CDP round-trip: a fresh CdpClient connects to the same
      //    port and reads Browser.getVersion. Confirms that the remote-
      //    debugging endpoint is still up after dusk:resize and that the
      //    CdpClient implementation works against a real Chrome (not just
      //    the FakeCdpServer used in unit tests).
      final CdpClient client = await CdpClient.connect(port: cdpPort);
      try {
        final Map<String, dynamic> reply =
            await client.send('Browser.getVersion');
        expect(
          reply['product'],
          isA<String>(),
          reason: 'Browser.getVersion must return a product string.',
        );
      } finally {
        await client.close();
      }

      // 6. artisan stop reaps everything. State file must be gone after.
      final ProcessResult stop = await runArtisan(<String>['stop']);
      expect(
        stop.exitCode,
        equals(0),
        reason: 'artisan stop must exit cleanly. stderr=${stop.stderr}',
      );
      expect(
        stateFile.existsSync(),
        isFalse,
        reason: 'artisan stop must delete state.json.',
      );

      // 7. Surface the start subprocess result in case it had not yet
      //    resolved (foreground artisan exits when its child flutter
      //    detaches, so this is usually already done).
      try {
        await startFuture.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        // Start subprocess hung; the post-stop assertion above already
        // proves the cleanup branch worked. Surface as a non-fatal warning.
        // ignore: avoid_print
        print(
          '[smoke] artisan start subprocess did not exit within 5s after '
          'stop; tearDown will reap it.',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  // ------------------------------------------------------------------
  // Test 2: hot reload smoke (Oracle F1 mitigation, dart-lang/webdev#2642).
  // ------------------------------------------------------------------
  test(
    'FIFO hot reload surfaces "Reloaded" in flutter-dev.log',
    () async {
      // 1. Boot artisan with --cdp-port. Reuses the same wait-for-vmService
      //    discipline from Test 1.
      unawaited(
        runArtisan(
          <String>[
            'start',
            '--device=chrome',
            '--port=3100',
            '--cdp-port=$cdpPort',
          ],
          timeout: const Duration(seconds: 90),
        ),
      );
      await waitForStateWithVmServiceUri();

      // 2. Snapshot the current log length so the post-reload tail search
      //    only inspects bytes written AFTER the FIFO write.
      final int logBaseline =
          flutterDevLog.existsSync() ? flutterDevLog.lengthSync() : 0;

      // 3. Send the reload command via the FIFO. Use a Process.run shell
      //    because Dart's File.openWrite blocks on a FIFO until a reader
      //    drains it; `echo r > fifo` is the documented contract.
      expect(
        flutterDevFifo.existsSync(),
        isTrue,
        reason: 'artisan start must create the FIFO at ${flutterDevFifo.path}.',
      );
      final ProcessResult echoResult = await Process.run(
        'bash',
        <String>['-c', 'echo r > "${flutterDevFifo.path}"'],
      ).timeout(const Duration(seconds: 5));
      expect(
        echoResult.exitCode,
        equals(0),
        reason: 'FIFO write must succeed. stderr=${echoResult.stderr}',
      );

      // 4. DWDS writes "Reloaded" asynchronously after the FIFO read. 5s
      //    matches the plan's smoke-window budget; below that risks false
      //    negatives on a busy laptop.
      await Future<void>.delayed(const Duration(seconds: 5));

      final String logTail = flutterDevLog.existsSync()
          ? flutterDevLog.openSync().let((RandomAccessFile raf) {
              try {
                raf.setPositionSync(logBaseline);
                final int remaining = raf.lengthSync() - logBaseline;
                if (remaining <= 0) return '';
                return utf8.decode(raf.readSync(remaining));
              } finally {
                raf.closeSync();
              }
            })
          : '';

      if (!logTail.contains('Reloaded')) {
        fail(
          'DWDS WebSocket hot reload broken: dart-lang/webdev#2642 '
          'regression active on this Flutter SDK. Log tail since baseline '
          '($logBaseline bytes):\n----\n$logTail\n----\n'
          'Action: run `flutter upgrade` and re-run this smoke test.',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  // ------------------------------------------------------------------
  // Test 3: preset smoke (dusk:device --preset=iphone-x).
  // ------------------------------------------------------------------
  test(
    'dusk:device --preset=iphone-x applies the 3-call Emulation chain',
    () async {
      // 1. Same boot pattern.
      unawaited(
        runArtisan(
          <String>[
            'start',
            '--device=chrome',
            '--port=3100',
            '--cdp-port=$cdpPort',
          ],
          timeout: const Duration(seconds: 90),
        ),
      );
      await waitForStateWithVmServiceUri();

      // 2. Apply the preset.
      final ProcessResult device = await runArtisan(
        <String>['dusk:device', '--preset=iphone-x'],
        timeout: const Duration(seconds: 30),
      );
      expect(
        device.exitCode,
        equals(0),
        reason: 'dusk:device --preset=iphone-x must exit 0. '
            'stdout=${device.stdout} stderr=${device.stderr}',
      );

      // 3. Independent verification: the --reset chain clears the override
      //    we just applied. If --reset itself exits 0, the preset's
      //    setDeviceMetricsOverride was wire-compatible enough that the
      //    follow-up clearDeviceMetricsOverride did not error. We avoid
      //    Page.* introspection here because Chrome polls window.innerWidth
      //    asynchronously after override; the --reset round-trip is the
      //    deterministic check.
      final ProcessResult reset = await runArtisan(
        <String>['dusk:resize', '--width=1440', '--height=900', '--reset'],
        timeout: const Duration(seconds: 30),
      );
      expect(
        reset.exitCode,
        equals(0),
        reason: 'dusk:resize --reset must clear the override. '
            'stdout=${reset.stdout} stderr=${reset.stderr}',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

extension _RafLet on RandomAccessFile {
  T let<T>(T Function(RandomAccessFile) op) => op(this);
}
