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

  // =========================================================================
  // End-to-end capture — covers the rasterise + encode path. `runAsync` is
  // required because `toImage()` schedules native engine work that
  // FakeAsync's clock cannot drive. We wrap a real `RepaintBoundary` over
  // the pumped widget so the screenshot handler's repaint-boundary lookup
  // resolves successfully.
  // =========================================================================
  group('screenshotHandler — end-to-end capture', () {
    testWidgets('captures the root viewport as JPEG by default',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(200, 100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const RepaintBoundary(
          child: ColoredBox(
            color: Color(0xFFFF0000),
            child: SizedBox.expand(),
          ),
        ),
      );

      developer.ServiceExtensionResponse? response;
      await tester.runAsync(() async {
        response = await screenshotHandler(
          'ext.dusk.screenshot',
          const <String, String>{},
        );
      });

      expect(_isError(response!), isFalse);
      expect(response!.result, isNotNull);
      expect(response!.result, contains('"format":"jpeg"'));
      expect(response!.result, contains('"width"'));
      expect(response!.result, contains('"height"'));
      expect(response!.result, contains('"base64"'));
    });

    testWidgets('captures the root viewport as PNG when format=png',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(200, 100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const RepaintBoundary(
          child: ColoredBox(
            color: Color(0xFF00FF00),
            child: SizedBox.expand(),
          ),
        ),
      );

      developer.ServiceExtensionResponse? response;
      await tester.runAsync(() async {
        response = await screenshotHandler(
          'ext.dusk.screenshot',
          const <String, String>{'format': 'png'},
        );
      });

      expect(_isError(response!), isFalse);
      expect(response!.result, contains('"format":"png"'));
    });

    testWidgets('honours --quality flag on JPEG encode',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(200, 100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const RepaintBoundary(
          child: ColoredBox(
            color: Color(0xFF0000FF),
            child: SizedBox.expand(),
          ),
        ),
      );

      developer.ServiceExtensionResponse? response;
      await tester.runAsync(() async {
        response = await screenshotHandler(
          'ext.dusk.screenshot',
          const <String, String>{'format': 'jpeg', 'quality': '30'},
        );
      });

      expect(_isError(response!), isFalse);
      expect(response!.result, contains('"format":"jpeg"'));
    });
  });
}
