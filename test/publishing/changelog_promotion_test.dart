/// Asserts CHANGELOG.md promotes the `[Unreleased]` block into the dated
/// `[0.0.1] - 2026-05-22` release with the required subsections.
///
/// Turned green by **Wave 7 / Step 20** (CHANGELOG promotion). The current
/// file holds an `[Unreleased]` block above an older `[0.0.1] - 2026-05-19`
/// entry; promotion consolidates the Unreleased deltas into the new
/// `[0.0.1] - 2026-05-22` release with Added / Test coverage / Known gaps /
/// Risks Accepted / Backward compat subsections.
library;

import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

void main() {
  group('CHANGELOG.md promotion to [0.0.1] - 2026-05-22', () {
    test('CHANGELOG.md exists at the package root', () {
      expect(fileExists('CHANGELOG.md'), isTrue);
    });

    test('contains exactly one heading "## [0.0.1] - 2026-05-22"', () {
      final String raw = loadFile('CHANGELOG.md');
      final RegExp heading =
          RegExp(r'^## \[0\.0\.1\] - 2026-05-22\s*$', multiLine: true);
      final Iterable<RegExpMatch> matches = heading.allMatches(raw);
      expect(
        matches.length,
        equals(1),
        reason:
            'Step 20 must promote [Unreleased] into a single dated [0.0.1] - 2026-05-22 heading; got ${matches.length}',
      );
    });

    test('still carries an "## [Unreleased]" heading above the 0.0.1 entry',
        () {
      final String raw = loadFile('CHANGELOG.md');
      final RegExp unreleasedPattern =
          RegExp(r'^## \[Unreleased\]\s*$', multiLine: true);
      expect(unreleasedPattern.hasMatch(raw), isTrue,
          reason: 'keep the [Unreleased] scaffold for the next cycle');

      final int unreleasedIndex = raw.indexOf(unreleasedPattern);
      final int releaseIndex =
          raw.indexOf(RegExp(r'^## \[0\.0\.1\] - 2026-05-22', multiLine: true));
      expect(unreleasedIndex, greaterThanOrEqualTo(0));
      expect(releaseIndex, greaterThanOrEqualTo(0));
      expect(
        unreleasedIndex < releaseIndex,
        isTrue,
        reason:
            '[Unreleased] must appear ABOVE [0.0.1] - 2026-05-22 per Keep a Changelog convention',
      );
    });

    test('contains "### Added" subsection under the 0.0.1 release', () {
      final String raw = loadFile('CHANGELOG.md');
      expect(raw.contains('### Added'), isTrue,
          reason: 'Step 20 must include an Added subsection');
    });

    test('contains "### Test coverage" subsection under the 0.0.1 release', () {
      final String raw = loadFile('CHANGELOG.md');
      expect(raw.contains('### Test coverage'), isTrue);
    });

    test('contains "### Known gaps" subsection under the 0.0.1 release', () {
      final String raw = loadFile('CHANGELOG.md');
      expect(raw.contains('### Known gaps'), isTrue);
    });

    test('contains "### Risks Accepted" subsection under the 0.0.1 release',
        () {
      final String raw = loadFile('CHANGELOG.md');
      expect(raw.contains('### Risks Accepted'), isTrue);
    });

    test('contains "### Backward compat" subsection under the 0.0.1 release',
        () {
      final String raw = loadFile('CHANGELOG.md');
      expect(raw.contains('### Backward compat'), isTrue);
    });
  });
}
