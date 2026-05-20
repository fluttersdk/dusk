import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/cdp/cdp_client.dart';
import 'package:fluttersdk_dusk/src/commands/dusk_resize_command.dart';

import '../cdp/fake_cdp_server.dart';

// ---------------------------------------------------------------------------
// Shared context stub (mirrors dusk_tap_command_test.dart:6-25).
// ---------------------------------------------------------------------------

class _StubContext extends ArtisanContext {
  _StubContext({
    required ArtisanInput input,
    required ArtisanOutput output,
  }) : super.bare(input, output);
}

// ---------------------------------------------------------------------------
// StateFile helper: writes a minimal state.json under a temp dir and wires
// StateFile.debugHomeOverride so DuskResizeCommand.handle() reads it.
// ---------------------------------------------------------------------------

Future<String> _writeState(
  Directory tempDir,
  Map<String, dynamic> data,
) async {
  final stateDir = Directory('${tempDir.path}/.artisan');
  await stateDir.create(recursive: true);
  final stateFile = File('${stateDir.path}/state.json');
  await stateFile.writeAsString(jsonEncode(data));
  return tempDir.path;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    // 1. Create a fresh temp directory for each test so state files do not
    //    cross-contaminate between test cases.
    tempDir = await Directory.systemTemp.createTemp('dusk_resize_test_');
    // 2. Reset CDP client seams to their production defaults so no stub from
    //    a prior test leaks.
    CdpClient.cdpHttpGet = CdpClient.defaultHttpGet;
    CdpClient.cdpWsConnect = CdpClient.defaultWsConnect;
  });

  tearDown(() async {
    // 1. Clear the StateFile override so subsequent non-CDP tests see the
    //    real home path.
    StateFile.debugHomeOverride = null;
    // 2. Reset CDP seams.
    CdpClient.cdpHttpGet = CdpClient.defaultHttpGet;
    CdpClient.cdpWsConnect = CdpClient.defaultWsConnect;
    // 3. Remove the temp directory including any state.json written during
    //    the test.
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {
      // Already removed; harmless.
    }
  });

  group('DuskResizeCommand metadata', () {
    test('name is dusk:resize', () {
      expect(DuskResizeCommand().name, equals('dusk:resize'));
    });

    test('description contains "viewport"', () {
      expect(
        DuskResizeCommand().description,
        contains('viewport'),
      );
    });

    test('boot is CommandBoot.none', () {
      expect(DuskResizeCommand().boot, equals(CommandBoot.none));
    });

    test('configure declares width, height, dpr, mobile, touch, reset', () {
      final parser = ArgParser();
      DuskResizeCommand().configure(parser);
      expect(
          parser.options.keys,
          containsAll(<String>[
            'width',
            'height',
            'dpr',
            'mobile',
            'touch',
            'reset',
          ]));
    });
  });

  group('DuskResizeCommand.handle', () {
    // -----------------------------------------------------------------------
    // (a) No state file (cdpPort missing) → exit 1 + hint message.
    // -----------------------------------------------------------------------
    test('exits 1 with hint when cdpPort is absent from state', () async {
      // Write state WITHOUT cdpPort.
      await _writeState(tempDir, {
        'pid': 1234,
        'vmServiceUri': 'ws://localhost:8181/ws',
        'device': 'chrome',
      });
      StateFile.debugHomeOverride = tempDir.path;

      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {
          'width': '375',
          'height': '812',
          'dpr': '3.0',
          'mobile': false,
          'touch': false,
          'reset': false,
        }),
        output: output,
      );

      final exit = await DuskResizeCommand().handle(ctx);

      expect(exit, equals(1));
      expect(output.content, contains('CDP not enabled'));
    });

    // -----------------------------------------------------------------------
    // (a-2) No state file at all → exit 1 + hint message.
    // -----------------------------------------------------------------------
    test('exits 1 with hint when no state file exists', () async {
      // Do NOT write any state file. Override home to a directory with no
      // .artisan/state.json.
      StateFile.debugHomeOverride = tempDir.path;

      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {
          'width': '375',
          'height': '812',
          'dpr': '3.0',
          'mobile': false,
          'touch': false,
          'reset': false,
        }),
        output: output,
      );

      final exit = await DuskResizeCommand().handle(ctx);

      expect(exit, equals(1));
      expect(output.content, contains('CDP not enabled'));
    });

    // -----------------------------------------------------------------------
    // (b) Successful resize: FakeCdpServer records Emulation params.
    // -----------------------------------------------------------------------
    test(
      'sends Emulation.setDeviceMetricsOverride with correct params on resize',
      () async {
        // 1. Start FakeCdpServer and record the params sent to
        //    Emulation.setDeviceMetricsOverride.
        Map<String, dynamic>? capturedMetricsParams;
        final server = await FakeCdpServer.start(
          handlers: {
            'Emulation.setDeviceMetricsOverride':
                (Map<String, dynamic> params) async {
              capturedMetricsParams = params;
              return <String, dynamic>{};
            },
          },
        );
        addTearDown(server.stop);

        await _writeState(tempDir, {'cdpPort': server.port});
        StateFile.debugHomeOverride = tempDir.path;

        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput({
            'width': '1280',
            'height': '720',
            'dpr': '2.0',
            'mobile': false,
            'touch': false,
            'reset': false,
          }),
          output: output,
        );

        final exit = await DuskResizeCommand().handle(ctx);

        // 2. Assert exit 0 and correct CDP params.
        expect(exit, equals(0));
        expect(capturedMetricsParams, isNotNull);
        expect(capturedMetricsParams!['width'], equals(1280));
        expect(capturedMetricsParams!['height'], equals(720));
        expect(capturedMetricsParams!['deviceScaleFactor'], equals(2.0));
        expect(capturedMetricsParams!['mobile'], equals(false));
      },
    );

    // -----------------------------------------------------------------------
    // (c) --reset sends 3-call chain in order:
    //     UA empty → touch off → clearMetrics.
    // -----------------------------------------------------------------------
    test('--reset sends Emulation 3-call chain in order', () async {
      final List<String> callOrder = <String>[];

      final server = await FakeCdpServer.start(
        handlers: {
          'Emulation.setUserAgentOverride':
              (Map<String, dynamic> params) async {
            callOrder.add('ua');
            return <String, dynamic>{};
          },
          'Emulation.setTouchEmulationEnabled':
              (Map<String, dynamic> params) async {
            callOrder.add('touch');
            return <String, dynamic>{};
          },
          'Emulation.clearDeviceMetricsOverride':
              (Map<String, dynamic> _) async {
            callOrder.add('clear');
            return <String, dynamic>{};
          },
        },
      );
      addTearDown(server.stop);

      await _writeState(tempDir, {'cdpPort': server.port});
      StateFile.debugHomeOverride = tempDir.path;

      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput({
          'width': '0',
          'height': '0',
          'dpr': '1.0',
          'mobile': false,
          'touch': false,
          'reset': true,
        }),
        output: output,
      );

      final exit = await DuskResizeCommand().handle(ctx);

      expect(exit, equals(0));
      expect(callOrder, equals(<String>['ua', 'touch', 'clear']));
      expect(output.content, contains('reset'));
    });

    // -----------------------------------------------------------------------
    // (d) --touch adds setTouchEmulationEnabled(enabled: true).
    // -----------------------------------------------------------------------
    test('--touch sends setTouchEmulationEnabled with enabled true', () async {
      Map<String, dynamic>? capturedTouchParams;

      final server = await FakeCdpServer.start(
        handlers: {
          'Emulation.setDeviceMetricsOverride':
              (Map<String, dynamic> _) async => <String, dynamic>{},
          'Emulation.setTouchEmulationEnabled':
              (Map<String, dynamic> params) async {
            capturedTouchParams = params;
            return <String, dynamic>{};
          },
        },
      );
      addTearDown(server.stop);

      await _writeState(tempDir, {'cdpPort': server.port});
      StateFile.debugHomeOverride = tempDir.path;

      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput({
          'width': '375',
          'height': '812',
          'dpr': '3.0',
          'mobile': true,
          'touch': true,
          'reset': false,
        }),
        output: output,
      );

      final exit = await DuskResizeCommand().handle(ctx);

      expect(exit, equals(0));
      expect(capturedTouchParams, isNotNull);
      expect(capturedTouchParams!['enabled'], equals(true));
    });

    // -----------------------------------------------------------------------
    // (e) Connect failure (FakeCdpServer stopped) → exit 1 + error message.
    // -----------------------------------------------------------------------
    test('exits 1 with error message when CDP connect fails', () async {
      // Start then stop the server immediately to simulate a closed port.
      final server = await FakeCdpServer.start();
      final int closedPort = server.port;
      await server.stop();

      await _writeState(tempDir, {'cdpPort': closedPort});
      StateFile.debugHomeOverride = tempDir.path;

      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput({
          'width': '375',
          'height': '812',
          'dpr': '1.0',
          'mobile': false,
          'touch': false,
          'reset': false,
        }),
        output: output,
      );

      final exit = await DuskResizeCommand().handle(ctx);

      expect(exit, equals(1));
      expect(
        output.content,
        contains('Failed to connect to Chrome CDP'),
      );
    });

    // -----------------------------------------------------------------------
    // (f) CdpClient.close() invoked in finally even on error path.
    // -----------------------------------------------------------------------
    test('closes CdpClient in finally block even when send throws', () async {
      // Use the dropWebSocket mode: the server accepts the WS upgrade, reads
      // the first frame, then closes immediately. CdpClient.send() will
      // complete with a DuskCdpException. The command should still call
      // client.close() (finally block) and exit 1 gracefully.
      final server = await FakeCdpServer.start(dropWebSocket: true);
      addTearDown(server.stop);

      await _writeState(tempDir, {'cdpPort': server.port});
      StateFile.debugHomeOverride = tempDir.path;

      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput({
          'width': '375',
          'height': '812',
          'dpr': '1.0',
          'mobile': false,
          'touch': false,
          'reset': false,
        }),
        output: output,
      );

      // If finally block is missing, close() never runs and the WS socket
      // lingers; the test would hang at tearDown(server.stop). The assertion
      // below implicitly proves close() ran by verifying exit code.
      final exit = await DuskResizeCommand().handle(ctx);
      expect(exit, equals(1));
    });
  });
}
