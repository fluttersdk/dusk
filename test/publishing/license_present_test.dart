/// Asserts the package ships an MIT `LICENSE` file at the package root.
///
/// Turned green by **Wave 3 / Step 4** (LICENSE creation, MIT boilerplate from
/// `fluttersdk_artisan/LICENSE`, attribution updated to
/// `2026 Anilcan Cakir from FlutterSDK`).
library;

import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

void main() {
  group('LICENSE artifact', () {
    test('exists at the package root (filename: LICENSE, not LICENSE.md)', () {
      expect(fileExists('LICENSE'), isTrue,
          reason: 'pana looks for LICENSE (no extension)');
      expect(fileExists('LICENSE.md'), isFalse,
          reason: 'LICENSE.md would be a separate file; use LICENSE');
    });

    test('declares the MIT License header', () {
      final String raw = loadFile('LICENSE');
      expect(raw.contains('MIT License'), isTrue,
          reason: 'LICENSE must contain "MIT License" header');
    });

    test('declares the 2026 Anilcan Cakir from FlutterSDK copyright line', () {
      final String raw = loadFile('LICENSE');
      expect(
        raw.contains('Copyright (c) 2026 Anilcan Cakir from FlutterSDK'),
        isTrue,
        reason:
            'attribution must be verbatim "Copyright (c) 2026 Anilcan Cakir from FlutterSDK"',
      );
    });

    test('contains the standard MIT "Permission is hereby granted" clause', () {
      final String raw = loadFile('LICENSE');
      expect(
        raw.contains('Permission is hereby granted, free of charge'),
        isTrue,
        reason: 'pana recognises licenses by their canonical clause text',
      );
    });

    test('contains the standard MIT "WITHOUT WARRANTY" clause', () {
      final String raw = loadFile('LICENSE');
      expect(
        raw.contains('WITHOUT WARRANTY OF ANY KIND'),
        isTrue,
        reason:
            'pana looks for the warranty disclaimer to classify the license',
      );
    });
  });
}
