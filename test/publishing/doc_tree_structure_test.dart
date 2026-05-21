/// Asserts the 18-file `doc/` tree exists with the canonical artisan shape:
/// `doc/getting-started/` (3) + `doc/commands/` (8) + `doc/mcp/` (3) +
/// `doc/plugins/` (3) + `doc/reference/` (1).
///
/// Turned green by **Wave 6 / Steps 15-19** (one wave per `doc/` subdir).
library;

import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

const List<String> _expectedDocFiles = <String>[
  // doc/getting-started/ (3)
  'doc/getting-started/index.md',
  'doc/getting-started/installation.md',
  'doc/getting-started/quickstart.md',
  // doc/commands/ (8)
  'doc/commands/index.md',
  'doc/commands/dusk-install.md',
  'doc/commands/dusk-snap.md',
  'doc/commands/dusk-tap.md',
  'doc/commands/dusk-screenshot.md',
  'doc/commands/dusk-find.md',
  'doc/commands/dusk-doctor.md',
  'doc/commands/dusk-observe.md',
  // doc/mcp/ (3)
  'doc/mcp/overview.md',
  'doc/mcp/setup.md',
  'doc/mcp/tool-reference.md',
  // doc/plugins/ (3)
  'doc/plugins/magic-integration.md',
  'doc/plugins/wind-integration.md',
  'doc/plugins/enricher-authoring.md',
  // doc/reference/ (1)
  'doc/reference/actionability-gate.md',
];

void main() {
  group('doc/ tree structure', () {
    test('expected file list has the documented count of 18 files', () {
      // Sanity guard so future edits to _expectedDocFiles stay in sync with
      // the plan's "18 files" deliverable.
      expect(
        _expectedDocFiles.length,
        equals(18),
        reason:
            'Plan commits to 18 doc files; the test list must mirror that count exactly',
      );
    });

    for (final String path in _expectedDocFiles) {
      test('$path exists', () {
        expect(fileExists(path), isTrue, reason: 'doc tree is missing $path');
      });
    }
  });
}
