/// Asserts `.github/workflows/ci.yml` and `.github/workflows/publish.yml` are
/// present, parse as YAML, and carry the canonical fields demanded by the
/// artisan-style automation contract.
///
/// Turned green by **Wave 4 / Steps 8-9** (ci.yml + publish.yml adapted from
/// `fluttersdk_artisan/.github/workflows/*.yml`).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '_helpers.dart';

void main() {
  group('.github/workflows/ci.yml', () {
    test('exists', () {
      expect(fileExists('.github/workflows/ci.yml'), isTrue);
    });

    test('parses as a YAML map', () {
      final dynamic doc = loadYamlFile('.github/workflows/ci.yml');
      expect(doc, isA<YamlMap>(), reason: 'ci.yml must be a valid YAML map');
    });

    test('declares a top-level "on" trigger block', () {
      final YamlMap doc = loadYamlFile('.github/workflows/ci.yml') as YamlMap;
      // The YAML "on" key is sometimes parsed as boolean true by older parsers;
      // accept either spelling so the test fails on absence, not parser-quirk.
      final bool hasOn = doc.containsKey('on') || doc.containsKey(true);
      expect(hasOn, isTrue,
          reason: 'ci.yml must declare an "on" trigger block');
    });

    test('declares a top-level "jobs" block', () {
      final YamlMap doc = loadYamlFile('.github/workflows/ci.yml') as YamlMap;
      assertHasTopLevelKey(doc, 'jobs', label: 'ci.yml');
      expect(doc['jobs'], isA<YamlMap>());
    });

    test('invokes "flutter test" (not "dart test") for the Flutter package',
        () {
      final String raw = loadFile('.github/workflows/ci.yml');
      expect(
        raw.contains('flutter test'),
        isTrue,
        reason:
            'dusk runs flutter_test, so CI must use "flutter test" not "dart test"',
      );
    });
  });

  group('.github/workflows/publish.yml', () {
    test('exists', () {
      expect(fileExists('.github/workflows/publish.yml'), isTrue);
    });

    test('parses as a YAML map', () {
      final dynamic doc = loadYamlFile('.github/workflows/publish.yml');
      expect(doc, isA<YamlMap>());
    });

    test('declares "permissions.id-token: write" for OIDC publish', () {
      final String raw = loadFile('.github/workflows/publish.yml');
      expect(
        RegExp(r'id-token:\s*write').hasMatch(raw),
        isTrue,
        reason: 'OIDC-based pub publish requires permissions.id-token: write',
      );
    });

    test('declares a top-level "jobs" block', () {
      final YamlMap doc =
          loadYamlFile('.github/workflows/publish.yml') as YamlMap;
      assertHasTopLevelKey(doc, 'jobs', label: 'publish.yml');
    });
  });
}
