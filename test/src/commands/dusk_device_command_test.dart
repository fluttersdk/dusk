import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_device_command.dart';
import 'package:fluttersdk_dusk/src/cdp/device_presets.dart';

import '../cdp/fake_cdp_server.dart';

// ---------------------------------------------------------------------------
// Test-only stubs
// ---------------------------------------------------------------------------

/// Minimal [ArtisanContext] that records no VM extension calls.
///
/// DuskDeviceCommand uses [CommandBoot.none] and reads StateFile directly;
/// it never calls [callExtension]. This stub satisfies the constructor
/// contract without needing a live VM Service connection.
class _StubContext extends ArtisanContext {
  _StubContext({
    required ArtisanInput input,
    required ArtisanOutput output,
  }) : super.bare(input, output);

  @override
  Future<T> callExtension<T>(String method,
      [Map<String, dynamic>? params]) async {
    throw UnsupportedError('DuskDeviceCommand must not call ext.* methods');
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Writes a minimal state.json under [home]/.artisan/ with the given [cdpPort].
///
/// Omit [cdpPort] to simulate a state file where CDP was not enabled.
Future<void> _writeStateJson(String home, {int? cdpPort}) async {
  final dir = Directory('$home/.artisan');
  await dir.create(recursive: true);
  final file = File('$home/.artisan/state.json');
  final sb = StringBuffer('{');
  sb.write('"pid": 12345, ');
  sb.write('"vmServiceUri": "ws://127.0.0.1:8181/ws", ');
  sb.write('"webPort": 3100, ');
  sb.write('"startedAt": "2026-01-01T00:00:00.000Z", ');
  sb.write('"profile": "debug", ');
  sb.write('"projectRoot": "/tmp/test", ');
  sb.write('"device": "chrome"');
  if (cdpPort != null) sb.write(', "cdpPort": $cdpPort');
  sb.write('}');
  await file.writeAsString(sb.toString());
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dusk_device_cmd_test_');
  });

  tearDown(() async {
    StateFile.debugHomeOverride = null;
    await tempDir.delete(recursive: true);
  });

  // (a) --list prints all 8 preset names with dimensions.
  test('--list prints all 8 presets with dimensions', () async {
    final output = BufferedOutput();
    final ctx = _StubContext(
      input: MapInput(const {'list': true}),
      output: output,
    );

    final exit = await DuskDeviceCommand().handle(ctx);

    expect(exit, equals(0));
    final content = output.content;
    for (final name in presetNames) {
      expect(content, contains(name));
    }
    // Spot-check the format: "<name>: <w>x<h> @ <dpr>x (mobile=<bool> touch=<bool>)"
    expect(content, contains('iphone-x: 375x812 @ 3.0x'));
    expect(content, contains('desktop-1440: 1440x900 @ 1.0x'));
    expect(content, contains('mobile=true'));
    expect(content, contains('mobile=false'));
  });

  // (f) missing cdpPort in state.json exits 1 with hint.
  test('exits 1 with hint when state.json has no cdpPort', () async {
    StateFile.debugHomeOverride = tempDir.path;
    await _writeStateJson(tempDir.path);

    final output = BufferedOutput();
    final ctx = _StubContext(
      input: MapInput(const {'preset': 'iphone-x'}),
      output: output,
    );

    final exit = await DuskDeviceCommand().handle(ctx);

    expect(exit, equals(1));
    expect(output.content, contains('CDP not enabled'));
    expect(output.content, contains('artisan start --cdp-port'));
  });

  // (f) absent state.json exits 1 with hint.
  test('exits 1 with hint when state.json is absent', () async {
    StateFile.debugHomeOverride = tempDir.path;
    // No state.json written.

    final output = BufferedOutput();
    final ctx = _StubContext(
      input: MapInput(const {'preset': 'iphone-x'}),
      output: output,
    );

    final exit = await DuskDeviceCommand().handle(ctx);

    expect(exit, equals(1));
    expect(output.content, contains('CDP not enabled'));
  });

  // (d) unknown preset exits 1 with actionable hint.
  test('unknown preset exits 1 with actionable hint', () async {
    final server = await FakeCdpServer.start(handlers: {});
    StateFile.debugHomeOverride = tempDir.path;
    await _writeStateJson(tempDir.path, cdpPort: server.port);

    final output = BufferedOutput();
    final ctx = _StubContext(
      input: MapInput(const {'preset': 'super-phone-9000'}),
      output: output,
    );

    final exit = await DuskDeviceCommand().handle(ctx);

    await server.stop();

    expect(exit, equals(1));
    expect(output.content, contains('super-phone-9000'));
    expect(output.content, contains('dusk:device --list'));
  });

  // (b) valid mobile preset sends the 3-call chain in the correct order.
  test(
    'valid mobile preset sends setDeviceMetricsOverride + setTouchEmulationEnabled + setUserAgentOverride',
    () async {
      final List<String> methodOrder = [];
      Map<String, dynamic>? capturedMetrics;
      Map<String, dynamic>? capturedTouch;
      Map<String, dynamic>? capturedUA;

      final server = await FakeCdpServer.start(
        handlers: {
          'Emulation.setDeviceMetricsOverride': (params) async {
            methodOrder.add('Emulation.setDeviceMetricsOverride');
            capturedMetrics = params;
            return {};
          },
          'Emulation.setTouchEmulationEnabled': (params) async {
            methodOrder.add('Emulation.setTouchEmulationEnabled');
            capturedTouch = params;
            return {};
          },
          'Emulation.setUserAgentOverride': (params) async {
            methodOrder.add('Emulation.setUserAgentOverride');
            capturedUA = params;
            return {};
          },
          ..._browserWindowHandlers(),
        },
      );
      StateFile.debugHomeOverride = tempDir.path;
      await _writeStateJson(tempDir.path, cdpPort: server.port);

      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'preset': 'iphone-x'}),
        output: output,
      );

      final exit = await DuskDeviceCommand().handle(ctx);

      await server.stop();

      expect(exit, equals(0));
      expect(
        methodOrder,
        equals([
          'Emulation.setDeviceMetricsOverride',
          'Emulation.setTouchEmulationEnabled',
          'Emulation.setUserAgentOverride',
        ]),
      );
      // Params must match the iphone-x preset values exactly.
      expect(capturedMetrics, containsPair('width', 375));
      expect(capturedMetrics, containsPair('height', 812));
      expect(capturedMetrics, containsPair('deviceScaleFactor', 3.0));
      expect(capturedMetrics, containsPair('mobile', true));
      expect(capturedTouch, containsPair('enabled', true));
      expect(capturedUA, isNotNull);
      final ua = capturedUA!['userAgent'] as String;
      expect(ua, isNotEmpty);
      // Success message includes preset name and dimensions.
      expect(output.content, contains('iphone-x'));
      expect(output.content, contains('375x812'));
    },
  );

  // (c) desktop-1440 has no touch: setTouchEmulationEnabled must be skipped.
  test('desktop-1440 preset skips setTouchEmulationEnabled', () async {
    final List<String> methodOrder = [];

    final server = await FakeCdpServer.start(
      handlers: {
        'Emulation.setDeviceMetricsOverride': (params) async {
          methodOrder.add('Emulation.setDeviceMetricsOverride');
          return {};
        },
        'Emulation.setTouchEmulationEnabled': (params) async {
          methodOrder.add('Emulation.setTouchEmulationEnabled');
          return {};
        },
        'Emulation.setUserAgentOverride': (params) async {
          methodOrder.add('Emulation.setUserAgentOverride');
          return {};
        },
        ..._browserWindowHandlers(),
      },
    );
    StateFile.debugHomeOverride = tempDir.path;
    await _writeStateJson(tempDir.path, cdpPort: server.port);

    final output = BufferedOutput();
    final ctx = _StubContext(
      input: MapInput(const {'preset': 'desktop-1440'}),
      output: output,
    );

    final exit = await DuskDeviceCommand().handle(ctx);

    await server.stop();

    expect(exit, equals(0));
    expect(
      methodOrder,
      equals([
        'Emulation.setDeviceMetricsOverride',
        'Emulation.setUserAgentOverride',
      ]),
    );
    expect(
      methodOrder,
      isNot(contains('Emulation.setTouchEmulationEnabled')),
    );
  });

  // (e) --reset delegates to the 3-call clear chain.
  test(
    '--reset sends setUserAgentOverride + setTouchEmulationEnabled(false) + clearDeviceMetricsOverride',
    () async {
      final List<String> methodOrder = [];
      Map<String, dynamic>? resetUA;
      Map<String, dynamic>? resetTouch;

      final server = await FakeCdpServer.start(
        handlers: {
          'Emulation.setUserAgentOverride': (params) async {
            methodOrder.add('Emulation.setUserAgentOverride');
            resetUA = params;
            return {};
          },
          'Emulation.setTouchEmulationEnabled': (params) async {
            methodOrder.add('Emulation.setTouchEmulationEnabled');
            resetTouch = params;
            return {};
          },
          'Emulation.clearDeviceMetricsOverride': (params) async {
            methodOrder.add('Emulation.clearDeviceMetricsOverride');
            return {};
          },
          ..._browserWindowHandlers(),
        },
      );
      StateFile.debugHomeOverride = tempDir.path;
      await _writeStateJson(tempDir.path, cdpPort: server.port);

      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'reset': true}),
        output: output,
      );

      final exit = await DuskDeviceCommand().handle(ctx);

      await server.stop();

      expect(exit, equals(0));
      expect(
        methodOrder,
        equals([
          'Emulation.setUserAgentOverride',
          'Emulation.setTouchEmulationEnabled',
          'Emulation.clearDeviceMetricsOverride',
        ]),
      );
      expect(resetUA, containsPair('userAgent', ''));
      expect(resetTouch, containsPair('enabled', false));
      expect(output.content, contains('reset'));
    },
  );
}

/// Returns Browser.* CDP handlers that the device command's
/// `_resizeChromeWindow` step calls after every preset / reset apply.
/// Without these, the FakeCdpServer returns `Method not found` and the
/// command exits with code 1 even though the Emulation chain succeeded.
Map<String, Future<Map<String, dynamic>> Function(Map<String, dynamic>)>
    _browserWindowHandlers() {
  return <String, Future<Map<String, dynamic>> Function(Map<String, dynamic>)>{
    'Browser.getWindowForTarget': (Map<String, dynamic> _) async =>
        <String, dynamic>{'windowId': 1, 'bounds': <String, dynamic>{}},
    'Browser.setWindowBounds': (Map<String, dynamic> _) async =>
        <String, dynamic>{},
  };
}
