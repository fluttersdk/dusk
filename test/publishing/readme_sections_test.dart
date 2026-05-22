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

    test(
        'links to or carries CLI command surface (either inline ## CLI Commands '
        'section OR a docs/getting-started link)', () {
      // The README was trimmed in Wave 6 / SEO sweep: the 32-row CLI command
      // reference moved to the docs site. We accept either the inline section
      // OR a docs-site link to keep the package surface discoverable from the
      // landing page.
      final String raw = loadFile('README.md');
      final bool hasInlineSection = _hasHeading(raw, 2, 'CLI Commands');
      final bool linksToDocs =
          raw.contains('fluttersdk.com/dusk/commands') ||
              raw.contains('fluttersdk.com/dusk/getting-started');
      expect(hasInlineSection || linksToDocs, isTrue,
          reason:
              'README must surface the CLI command catalog inline OR link to the docs commands catalog');
    });

    test(
        'links to or carries MCP tool surface (either inline ## MCP Tools '
        'section OR a docs/mcp link)', () {
      final String raw = loadFile('README.md');
      final bool hasInlineSection = _hasHeading(raw, 2, 'MCP Tools');
      final bool linksToDocs = raw.contains('fluttersdk.com/dusk/mcp');
      expect(hasInlineSection || linksToDocs, isTrue,
          reason:
              'README must surface the MCP tool catalog inline OR link to the docs MCP reference');
    });

    test(
        'architecture content reachable from the README (either inline '
        '## Architecture section OR a link to ARCHITECTURE.md / docs)', () {
      final String raw = loadFile('README.md');
      final bool hasInlineSection = _hasHeading(raw, 2, 'Architecture');
      final bool linksOut = raw.contains('ARCHITECTURE.md') ||
          raw.contains('fluttersdk.com/dusk/reference');
      expect(hasInlineSection || linksOut, isTrue,
          reason:
              'README must surface architecture content inline OR link to ARCHITECTURE.md / docs');
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
