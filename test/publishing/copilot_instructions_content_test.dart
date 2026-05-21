/// Asserts the Copilot/Claude Code agent-rules content lives under `.github/`.
///
/// Turned green by **Wave 4 / Step 12** (.github/copilot-instructions.md plus
/// the two path-scoped instruction files under `.github/instructions/`).
library;

import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

void main() {
  group('.github/copilot-instructions.md', () {
    test('file exists at .github/copilot-instructions.md', () {
      expect(fileExists('.github/copilot-instructions.md'), isTrue);
    });

    test('contains "Golden Rules" preamble heading', () {
      final String raw = loadFile('.github/copilot-instructions.md');
      expect(
        raw.contains('Golden Rules'),
        isTrue,
        reason: 'Step 12 must port the artisan Golden Rules preamble',
      );
    });
  });

  group('.github/instructions/extensions.instructions.md', () {
    test('file exists', () {
      expect(fileExists('.github/instructions/extensions.instructions.md'),
          isTrue);
    });

    test('declares a "paths:" front-matter or directive', () {
      final String raw =
          loadFile('.github/instructions/extensions.instructions.md');
      expect(
        raw.contains('paths:'),
        isTrue,
        reason:
            'path-scoped instruction files surface their path glob via "paths:"',
      );
    });

    test('references the "registerExtensionIdempotent" guard rule', () {
      final String raw =
          loadFile('.github/instructions/extensions.instructions.md');
      expect(
        raw.contains('registerExtensionIdempotent'),
        isTrue,
        reason:
            'extensions instruction file must call out the idempotent registration helper',
      );
    });
  });

  group('.github/instructions/tests.instructions.md', () {
    test('file exists', () {
      expect(fileExists('.github/instructions/tests.instructions.md'), isTrue);
    });

    test('declares a "paths:" front-matter or directive', () {
      final String raw = loadFile('.github/instructions/tests.instructions.md');
      expect(raw.contains('paths:'), isTrue);
    });

    test('references the "RefRegistry.resetForTesting" tearDown rule', () {
      final String raw = loadFile('.github/instructions/tests.instructions.md');
      expect(
        raw.contains('RefRegistry.resetForTesting'),
        isTrue,
        reason:
            'tests instruction file must call out the RefRegistry tearDown discipline',
      );
    });
  });
}
