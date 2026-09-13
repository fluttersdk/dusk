import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards `server.json`, the MCP registry manifest, against the drift that
/// hand-maintained version sites always attract.
///
/// Nothing in the package reads this file: it is published by hand with
/// `mcp-publisher publish`, so neither the analyzer nor the release flow can
/// notice when `pubspec.yaml` moves and it does not. The registry rejects a
/// version string it has already seen and never lets one be rewritten, so a
/// stale number here is not a cosmetic problem. It either publishes metadata
/// labelled with the previous release or fails the cut outright.
///
/// The description cap is asserted for the same reason. It is 100 characters
/// in the 2025-12-11 schema, small enough that an ordinary edit overruns it,
/// and the only other place that shows up is a rejected publish.
void main() {
  group('server.json', () {
    late Map<String, dynamic> manifest;

    setUp(() {
      manifest = jsonDecode(File('server.json').readAsStringSync())
          as Map<String, dynamic>;
    });

    test('version matches the version declared in pubspec.yaml', () {
      final Match? declared = RegExp(r'^version:\s*(\S+)', multiLine: true)
          .firstMatch(File('pubspec.yaml').readAsStringSync());
      expect(declared, isNotNull, reason: 'pubspec.yaml has no version: line');

      expect(
        manifest['version'],
        declared!.group(1),
        reason: 'server.json is published by hand; bump it with pubspec.yaml',
      );
    });

    test('description fits the registry limit of 100 characters', () {
      expect((manifest['description'] as String).length, lessThanOrEqualTo(100));
    });

    test('name is the registry namespace for this package', () {
      expect(manifest['name'], 'io.github.fluttersdk/dusk');
    });
  });
}
