/// Asserts README.md follows the artisan-style landing-page shape (H1 plus the
/// canonical H2 sections enumerated in the plan's Wave 6 / Step 14).
///
/// Turned green by **Wave 6 / Step 14** (README full rewrite to artisan
/// landing-page shape adapted to dusk surface).
library;

import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

bool _hasHeading(String markdown, int level, String text) {
  final String prefix = '#' * level;
  final RegExp pattern = RegExp(
    '^${RegExp.escape(prefix)}\\s+${RegExp.escape(text)}\\s*\$',
    multiLine: true,
  );
  return pattern.hasMatch(markdown);
}

void main() {
  group('README.md sections (artisan landing-page shape)', () {
    test('README.md exists at the package root', () {
      expect(fileExists('README.md'), isTrue);
    });

    test('declares an H1 naming the package (literal "fluttersdk_dusk" or the brand-name "Dusk")', () {
      final String raw = loadFile('README.md');
      // The artisan-style centered <h1 align="center"> heading uses "Dusk"
      // as the brand-name H1; the markdown-style "# fluttersdk_dusk" form is
      // also accepted for back-compat with the prior README shape.
      final RegExp markdownH1 = RegExp(r'^# .*fluttersdk_dusk', multiLine: true);
      final RegExp centeredH1 =
          RegExp(r'<h1[^>]*>\s*(Dusk|fluttersdk_dusk)\s*</h1>', caseSensitive: false);
      expect(markdownH1.hasMatch(raw) || centeredH1.hasMatch(raw), isTrue,
          reason: 'README must open with an H1 naming the package');
    });

    test('contains "## Why Dusk?" section', () {
      // Capitalised "Dusk" matches the brand-name H1 in the rewritten
      // (telescope-shape) README. The lowercase form is still accepted for
      // back-compat with the prior shape.
      final String raw = loadFile('README.md');
      final bool capitalised = _hasHeading(raw, 2, 'Why Dusk?');
      final bool lowercase = _hasHeading(raw, 2, 'Why dusk?');
      expect(capitalised || lowercase, isTrue,
          reason: 'README must carry the "Why Dusk?" (or "Why dusk?") section');
    });

    test('contains "## Features" section', () {
      expect(_hasHeading(loadFile('README.md'), 2, 'Features'), isTrue);
    });

    test('contains "## Quick Start" section', () {
      expect(_hasHeading(loadFile('README.md'), 2, 'Quick Start'), isTrue);
    });

    test('contains "## CLI Commands" section', () {
      expect(_hasHeading(loadFile('README.md'), 2, 'CLI Commands'), isTrue);
    });

    test('contains "## MCP Tools" section', () {
      expect(_hasHeading(loadFile('README.md'), 2, 'MCP Tools'), isTrue);
    });

    test('contains "## Architecture" section', () {
      expect(_hasHeading(loadFile('README.md'), 2, 'Architecture'), isTrue);
    });

    test('contains "## AI Agent Integration" section', () {
      expect(_hasHeading(loadFile('README.md'), 2, 'AI Agent Integration'),
          isTrue);
    });

    test('contains "## Documentation" section', () {
      expect(_hasHeading(loadFile('README.md'), 2, 'Documentation'), isTrue);
    });

    test('contains "## Contributing" section', () {
      expect(_hasHeading(loadFile('README.md'), 2, 'Contributing'), isTrue);
    });

    test('contains "## License" section', () {
      expect(_hasHeading(loadFile('README.md'), 2, 'License'), isTrue);
    });

    test('does NOT contain em-dash or en-dash characters', () {
      final String raw = loadFile('README.md');
      expect(raw.contains('—'), isFalse,
          reason:
              'README must not use em-dash (U+2014); use commas/colons/periods');
      expect(raw.contains('–'), isFalse,
          reason:
              'README must not use en-dash (U+2013); use commas/colons/periods');
    });
  });
}
