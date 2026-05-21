/// Asserts `install.yaml` reflects the live dusk surface count (32 CLI
/// commands / 31 MCP tool descriptors), NOT the stale 11 / 17 numbers from the
/// pre-CDP planning era.
///
/// Turned green by **Wave 7 / Step 21** (install.yaml header comment refresh).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '_helpers.dart';

void main() {
  group('install.yaml freshness', () {
    test('install.yaml exists at the package root', () {
      expect(fileExists('install.yaml'), isTrue);
    });

    test('parses as a YAML document (map or list)', () {
      final dynamic doc = loadYamlFile('install.yaml');
      expect(
        doc is YamlMap || doc is YamlList,
        isTrue,
        reason:
            'install.yaml must parse via package:yaml; got ${doc.runtimeType}',
      );
    });

    test('header does NOT contain the stale "11 dusk CLI commands" string', () {
      final String raw = loadFile('install.yaml');
      expect(
        raw.contains('11 dusk CLI commands'),
        isFalse,
        reason:
            'Step 21 must replace the stale 11-command count with the live count',
      );
    });

    test('header does NOT contain the stale "17 dusk_* MCP tools" string', () {
      final String raw = loadFile('install.yaml');
      expect(
        raw.contains('17 dusk_* MCP tools'),
        isFalse,
        reason:
            'Step 21 must replace the stale 17-tool count with the live count',
      );
    });

    test('header references the live dusk CLI command count (32 commands)', () {
      final String raw = loadFile('install.yaml');
      expect(
        raw.contains('32 '),
        isTrue,
        reason:
            'Step 21 must surface "32" (live CLI command count) in the header comment',
      );
    });

    test('header references the live MCP tool descriptor count (31 tools)', () {
      final String raw = loadFile('install.yaml');
      expect(
        raw.contains('31 '),
        isTrue,
        reason:
            'Step 21 must surface "31" (live MCP tool descriptor count) in the header comment',
      );
    });
  });
}
