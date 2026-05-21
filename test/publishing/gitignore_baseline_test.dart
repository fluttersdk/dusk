/// Asserts `.gitignore` matches the canonical artisan baseline shape.
///
/// Turned green by **Wave 3 / Step 6** (.gitignore replaced with the 43-line
/// `fluttersdk_artisan/.gitignore` shape; current dusk file is a 1-line stub
/// containing only `.ac/`).
library;

import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

void main() {
  group('.gitignore baseline', () {
    test('exists at the package root', () {
      expect(fileExists('.gitignore'), isTrue);
    });

    test('has at least 40 lines (artisan baseline is 43; stub was 1)', () {
      final String raw = loadFile('.gitignore');
      final int lineCount = raw.split('\n').length;
      expect(
        lineCount,
        greaterThanOrEqualTo(40),
        reason:
            'Step 6 must replace the 1-line stub with the artisan ~43-line shape; got $lineCount lines',
      );
    });

    test(
        'contains the build + tooling excludes (.dart_tool/, /build/, /coverage/)',
        () {
      final String raw = loadFile('.gitignore');
      for (final String entry in const <String>[
        '.dart_tool/',
        '/build/',
        '/coverage/'
      ]) {
        expect(raw.contains(entry), isTrue,
            reason: '.gitignore must contain "$entry"');
      }
    });

    test('contains IDE excludes (.idea/, *.iml)', () {
      final String raw = loadFile('.gitignore');
      expect(raw.contains('.idea/'), isTrue);
      expect(raw.contains('*.iml'), isTrue);
    });

    test('contains OS scratch excludes (.DS_Store)', () {
      final String raw = loadFile('.gitignore');
      expect(raw.contains('.DS_Store'), isTrue);
    });

    test(
        'contains lockfile + local-state excludes (pubspec.lock, .artisan/, .ac/, CLAUDE.local.md)',
        () {
      final String raw = loadFile('.gitignore');
      expect(raw.contains('pubspec.lock'), isTrue);
      expect(raw.contains('.artisan/'), isTrue);
      expect(raw.contains('.ac/'), isTrue);
      expect(raw.contains('CLAUDE.local.md'), isTrue);
    });
  });
}
