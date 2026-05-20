import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_screenshot_command.dart';

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

void main() {
  group('DuskScreenshotCommand', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dusk_screenshot_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

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

    test('handle writes the decoded base64 payload to --output path', () async {
      const fakeBase64 = 'aGVsbG8td29ybGQ='; // "hello-world"
      final outPath = '${tempDir.path}/snap.png';
      final ctx = _StubContext(
        input: MapInput({'output': outPath, 'format': 'png', 'quality': '90'}),
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
      expect(File(outPath).readAsBytesSync(), equals(base64Decode(fakeBase64)));
    });

    test('handle defaults format to jpeg + quality to 70 when omitted',
        () async {
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

    test('handle returns 1 when --output is missing', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
      );
      final exit = await DuskScreenshotCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });

    test('handle returns 1 when extension response carries no base64',
        () async {
      final ctx = _StubContext(
        input: MapInput({'output': '${tempDir.path}/snap.png'}),
        output: BufferedOutput(),
        response: const {'error': 'no base64'},
      );
      final exit = await DuskScreenshotCommand().handle(ctx);
      expect(exit, equals(1));
    });
  });
}
