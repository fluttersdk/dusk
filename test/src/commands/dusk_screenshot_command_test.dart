import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/cdp/cdp_client.dart';
import 'package:fluttersdk_dusk/src/commands/dusk_screenshot_command.dart';

import '../cdp/fake_cdp_server.dart';

// ---------------------------------------------------------------------------
// Shared context stub: records last callExtension invocation for assertions.
// ---------------------------------------------------------------------------

class _StubContext extends ArtisanContext {
  _StubContext({
    required ArtisanInput input,
    required ArtisanOutput output,
    Map<String, dynamic> response = const {},
  })  : _response = response,
        super.bare(input, output);

  final Map<String, dynamic> _response;
  String? lastMethod;
  Map<String, dynamic>? lastParams;

  @override
  Future<T> callExtension<T>(String method,
      [Map<String, dynamic>? params]) async {
    lastMethod = method;
    lastParams = params;
    return _response as T;
  }
}

// ---------------------------------------------------------------------------
// StateFile helper: writes a minimal state.json under a temp dir and wires
// StateFile.debugHomeOverride so DuskScreenshotCommand.handle() reads it.
// ---------------------------------------------------------------------------

Future<void> _writeState(
  Directory tempDir,
  Map<String, dynamic> data,
) async {
  final stateDir = Directory('${tempDir.path}/.artisan');
  await stateDir.create(recursive: true);
  final stateFile = File('${stateDir.path}/state.json');
  await stateFile.writeAsString(jsonEncode(data));
}

void main() {
  group('DuskScreenshotCommand', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dusk_screenshot_test_');
      CdpClient.cdpHttpGet = CdpClient.defaultHttpGet;
      CdpClient.cdpWsConnect = CdpClient.defaultWsConnect;
    });

    tearDown(() async {
      StateFile.debugHomeOverride = null;
      CdpClient.cdpHttpGet = CdpClient.defaultHttpGet;
      CdpClient.cdpWsConnect = CdpClient.defaultWsConnect;
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Already removed; harmless.
      }
    });

    group('metadata', () {
      test('name is dusk:screenshot', () {
        expect(DuskScreenshotCommand().name, equals('dusk:screenshot'));
      });

      test('boot is CommandBoot.connected', () {
        expect(DuskScreenshotCommand().boot, equals(CommandBoot.connected));
      });

      test('configure declares --output / --format / --quality', () {
        final parser = ArgParser();
        DuskScreenshotCommand().configure(parser);
        expect(
          parser.options.keys,
          containsAll(<String>['output', 'format', 'quality']),
        );
      });
    });

    group('handle() — native (ext.dusk.screenshot) path', () {
      test('writes the decoded base64 payload to --output path', () async {
        const fakeBase64 = 'aGVsbG8td29ybGQ='; // "hello-world"
        final outPath = '${tempDir.path}/snap.png';

        // No cdpPort in state: native path.
        await _writeState(tempDir, {
          'pid': 1234,
          'vmServiceUri': 'ws://localhost:8181/ws',
        });
        StateFile.debugHomeOverride = tempDir.path;

        final ctx = _StubContext(
          input:
              MapInput({'output': outPath, 'format': 'png', 'quality': '90'}),
          output: BufferedOutput(),
          response: const {'base64': fakeBase64},
        );

        final exit = await DuskScreenshotCommand().handle(ctx);
        expect(exit, equals(0));
        expect(ctx.lastMethod, equals('ext.dusk.screenshot'));
        expect(
          ctx.lastParams,
          allOf(containsPair('format', 'png'), containsPair('quality', 90)),
        );
        expect(File(outPath).existsSync(), isTrue);
        expect(
          File(outPath).readAsBytesSync(),
          equals(base64Decode(fakeBase64)),
        );
      });

      test('defaults format to jpeg + quality to 70 when omitted', () async {
        await _writeState(tempDir, {'pid': 1234});
        StateFile.debugHomeOverride = tempDir.path;

        final ctx = _StubContext(
          input: MapInput({'output': '${tempDir.path}/snap.jpg'}),
          output: BufferedOutput(),
          response: const {'base64': 'aGVsbG8='},
        );
        await DuskScreenshotCommand().handle(ctx);
        expect(
          ctx.lastParams,
          allOf(containsPair('format', 'jpeg'), containsPair('quality', 70)),
        );
      });

      test('returns 1 when --output is missing', () async {
        await _writeState(tempDir, {'pid': 1234});
        StateFile.debugHomeOverride = tempDir.path;

        final ctx = _StubContext(
          input: MapInput(const {}),
          output: BufferedOutput(),
        );
        final exit = await DuskScreenshotCommand().handle(ctx);
        expect(exit, equals(1));
        expect(ctx.lastMethod, isNull);
      });

      test('returns 1 when extension response carries no base64', () async {
        await _writeState(tempDir, {'pid': 1234});
        StateFile.debugHomeOverride = tempDir.path;

        final ctx = _StubContext(
          input: MapInput({'output': '${tempDir.path}/snap.png'}),
          output: BufferedOutput(),
          response: const {'error': 'no base64'},
        );
        final exit = await DuskScreenshotCommand().handle(ctx);
        expect(exit, equals(1));
      });
    });

    group('handle() — CDP (Page.captureScreenshot) path', () {
      // Minimal 1x1 white PNG in base64 (real parseable PNG bytes).
      const fakePngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

      // -----------------------------------------------------------------------
      // (a) With cdpPort set: sends Page.enable then Page.captureScreenshot and
      //     writes decoded bytes to --output.
      // -----------------------------------------------------------------------
      test(
        'sends Page.enable then Page.captureScreenshot and writes file',
        () async {
          final List<String> callOrder = <String>[];
          Map<String, dynamic>? capturedScreenshotParams;

          final server = await FakeCdpServer.start(
            handlers: {
              'Page.enable': (Map<String, dynamic> _) async {
                callOrder.add('Page.enable');
                return <String, dynamic>{};
              },
              'Page.captureScreenshot': (Map<String, dynamic> params) async {
                callOrder.add('Page.captureScreenshot');
                capturedScreenshotParams = params;
                return <String, dynamic>{'data': fakePngBase64};
              },
            },
          );
          addTearDown(server.stop);

          await _writeState(tempDir, {'cdpPort': server.port});
          StateFile.debugHomeOverride = tempDir.path;

          final outPath = '${tempDir.path}/web_shot.png';
          final output = BufferedOutput();
          final ctx = _StubContext(
            input: MapInput({
              'output': outPath,
              'format': 'png',
              'quality': '90',
            }),
            output: output,
          );

          final exit = await DuskScreenshotCommand().handle(ctx);

          // 1. Command exited successfully.
          expect(exit, equals(0));

          // 2. CDP calls were made in the correct order.
          expect(callOrder,
              equals(<String>['Page.enable', 'Page.captureScreenshot']));

          // 3. captureScreenshot received the expected params.
          expect(capturedScreenshotParams, isNotNull);
          expect(capturedScreenshotParams!['format'], equals('png'));
          expect(capturedScreenshotParams!['fromSurface'], equals(true));
          expect(capturedScreenshotParams!.containsKey('captureBeyondViewport'),
              isFalse);

          // 4. The file on disk contains the decoded PNG bytes.
          expect(File(outPath).existsSync(), isTrue);
          expect(
            File(outPath).readAsBytesSync(),
            equals(base64Decode(fakePngBase64)),
          );

          // 5. The native ext.dusk.screenshot extension was NOT called.
          expect(ctx.lastMethod, isNull);
        },
      );

      // -----------------------------------------------------------------------
      // (b) JPEG with quality: quality param is forwarded in captureScreenshot.
      // -----------------------------------------------------------------------
      test(
        'forwards quality param for jpeg format',
        () async {
          Map<String, dynamic>? capturedParams;

          final server = await FakeCdpServer.start(
            handlers: {
              'Page.enable': (Map<String, dynamic> _) async =>
                  <String, dynamic>{},
              'Page.captureScreenshot': (Map<String, dynamic> params) async {
                capturedParams = params;
                return <String, dynamic>{'data': fakePngBase64};
              },
            },
          );
          addTearDown(server.stop);

          await _writeState(tempDir, {'cdpPort': server.port});
          StateFile.debugHomeOverride = tempDir.path;

          final ctx = _StubContext(
            input: MapInput({
              'output': '${tempDir.path}/shot.jpg',
              'format': 'jpeg',
              'quality': '80',
            }),
            output: BufferedOutput(),
          );

          await DuskScreenshotCommand().handle(ctx);

          expect(capturedParams!['format'], equals('jpeg'));
          expect(capturedParams!['quality'], equals(80));
        },
      );

      // -----------------------------------------------------------------------
      // (c) PNG format: quality param is NOT forwarded.
      // -----------------------------------------------------------------------
      test(
        'does not forward quality for png format',
        () async {
          Map<String, dynamic>? capturedParams;

          final server = await FakeCdpServer.start(
            handlers: {
              'Page.enable': (Map<String, dynamic> _) async =>
                  <String, dynamic>{},
              'Page.captureScreenshot': (Map<String, dynamic> params) async {
                capturedParams = params;
                return <String, dynamic>{'data': fakePngBase64};
              },
            },
          );
          addTearDown(server.stop);

          await _writeState(tempDir, {'cdpPort': server.port});
          StateFile.debugHomeOverride = tempDir.path;

          final ctx = _StubContext(
            input: MapInput({
              'output': '${tempDir.path}/shot.png',
              'format': 'png',
              'quality': '90',
            }),
            output: BufferedOutput(),
          );

          await DuskScreenshotCommand().handle(ctx);

          expect(capturedParams!.containsKey('quality'), isFalse);
        },
      );

      // -----------------------------------------------------------------------
      // (d) CDP connect failure → exit 1 + error message.
      // -----------------------------------------------------------------------
      test(
        'exits 1 with error message when CDP connect fails',
        () async {
          final server = await FakeCdpServer.start();
          final int closedPort = server.port;
          await server.stop();

          await _writeState(tempDir, {'cdpPort': closedPort});
          StateFile.debugHomeOverride = tempDir.path;

          final output = BufferedOutput();
          final ctx = _StubContext(
            input: MapInput({
              'output': '${tempDir.path}/shot.png',
              'format': 'png',
              'quality': '90',
            }),
            output: output,
          );

          final exit = await DuskScreenshotCommand().handle(ctx);

          expect(exit, equals(1));
          expect(output.content, contains('Failed to connect to Chrome CDP'));
        },
      );

      // -----------------------------------------------------------------------
      // (e) Non-numeric cdpPort (corrupt / cross-version state) → native path,
      //     not a force-cast crash.
      // -----------------------------------------------------------------------
      test(
        'falls through to ext.dusk.screenshot when cdpPort is not numeric',
        () async {
          await _writeState(tempDir, {'cdpPort': 'not-a-port'});
          StateFile.debugHomeOverride = tempDir.path;

          const fakeBase64 = 'aGVsbG8=';
          final ctx = _StubContext(
            input: MapInput({
              'output': '${tempDir.path}/shot.png',
              'format': 'png',
              'quality': '90',
            }),
            output: BufferedOutput(),
            response: const {'base64': fakeBase64},
          );

          final exit = await DuskScreenshotCommand().handle(ctx);

          expect(exit, equals(0));
          expect(ctx.lastMethod, equals('ext.dusk.screenshot'));
        },
      );

      // -----------------------------------------------------------------------
      // (f) CDP response missing `data` → exit 1 with a clear error, not an
      //     uncaught cast exception.
      // -----------------------------------------------------------------------
      test(
        'exits 1 with error message when CDP returns no data',
        () async {
          final server = await FakeCdpServer.start(
            handlers: {
              'Page.enable': (Map<String, dynamic> _) async =>
                  <String, dynamic>{},
              'Page.captureScreenshot': (Map<String, dynamic> _) async =>
                  <String, dynamic>{},
            },
          );
          addTearDown(server.stop);

          await _writeState(tempDir, {'cdpPort': server.port});
          StateFile.debugHomeOverride = tempDir.path;

          final output = BufferedOutput();
          final ctx = _StubContext(
            input: MapInput({
              'output': '${tempDir.path}/shot.png',
              'format': 'png',
              'quality': '90',
            }),
            output: output,
          );

          final exit = await DuskScreenshotCommand().handle(ctx);

          expect(exit, equals(1));
          expect(output.content, contains('no image data'));
        },
      );
    });
  });
}
