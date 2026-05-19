import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img_lib;

import 'package:fluttersdk_dusk/src/extensions/ext_screenshot.dart';

bool _isError(developer.ServiceExtensionResponse response) =>
    response.errorCode != null;

void main() {
  // flutter_test does not paint with a real engine, so the full
  // toImage()/PNG encode/JPEG encode pipeline can hang. We restrict tests
  // to the param-validation + utility paths that do not need rendering.
  // End-to-end screenshot capture is covered by the example/ live drive
  // (`dusk:screenshot --output=...` in the playground sweep).

  group('screenshotHandler — param validation', () {
    testWidgets('errors on malformed rect string', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(),
        ),
      );
      final response = await screenshotHandler(
        'ext.dusk.screenshot',
        const {'rect': 'not,a,rect'},
      );
      expect(_isError(response), isTrue);
    });

    testWidgets('errors on rect with negative dimensions', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(),
        ),
      );
      final response = await screenshotHandler(
        'ext.dusk.screenshot',
        const {'rect': '0,0,-100,-100'},
      );
      expect(_isError(response), isTrue);
    });

    testWidgets('errors on rect with non-numeric tokens', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(),
        ),
      );
      final response = await screenshotHandler(
        'ext.dusk.screenshot',
        const {'rect': '0,0,foo,bar'},
      );
      expect(_isError(response), isTrue);
    });

    testWidgets('errors on rect with wrong field count', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(),
        ),
      );
      final response = await screenshotHandler(
        'ext.dusk.screenshot',
        const {'rect': '0,0,100'},
      );
      expect(_isError(response), isTrue);
    });

    testWidgets('errors on unknown ref', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(),
        ),
      );
      final response = await screenshotHandler(
        'ext.dusk.screenshot',
        const {'ref': 'e999'},
      );
      expect(_isError(response), isTrue);
    });
  });

  group('registerScreenshotExtension', () {
    test('runs without throwing twice in a row (hot-restart safe)', () {
      registerScreenshotExtension();
      registerScreenshotExtension();
    });
  });

  group('encodeToJpeg', () {
    Uint8List buildSamplePng() {
      final image = img_lib.Image(width: 4, height: 4);
      img_lib.fill(image, color: img_lib.ColorRgb8(200, 50, 50));
      return Uint8List.fromList(img_lib.encodePng(image));
    }

    test('returns non-empty JPEG bytes for a valid PNG input', () {
      final png = buildSamplePng();
      final jpeg = encodeToJpeg(png, quality: 70);
      expect(jpeg, isA<Uint8List>());
      expect(jpeg.length, greaterThan(0));
      // JPEG magic bytes: SOI = 0xFFD8
      expect(jpeg[0], equals(0xFF));
      expect(jpeg[1], equals(0xD8));
    });

    test('quality boundary: 1 is accepted', () {
      final png = buildSamplePng();
      final jpeg = encodeToJpeg(png, quality: 1);
      expect(jpeg.length, greaterThan(0));
    });

    test('quality boundary: 100 is accepted', () {
      final png = buildSamplePng();
      final jpeg = encodeToJpeg(png, quality: 100);
      expect(jpeg.length, greaterThan(0));
    });

    test('throws ArgumentError when quality is below 1', () {
      final png = buildSamplePng();
      expect(
        () => encodeToJpeg(png, quality: 0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError when quality is above 100', () {
      final png = buildSamplePng();
      expect(
        () => encodeToJpeg(png, quality: 101),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError when input is not valid PNG data', () {
      expect(
        () => encodeToJpeg(Uint8List.fromList(<int>[0, 1, 2, 3]), quality: 70),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
