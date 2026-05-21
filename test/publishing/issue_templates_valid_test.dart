/// Asserts the 4 `.github/ISSUE_TEMPLATE/*.yml` files exist and parse as YAML.
///
/// Turned green by **Wave 4 / Step 11** (issue templates adapted from
/// `fluttersdk_artisan/.github/ISSUE_TEMPLATE/*.yml` with dusk Subsystem
/// dropdown values).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '_helpers.dart';

const List<String> _templateFiles = <String>[
  '.github/ISSUE_TEMPLATE/config.yml',
  '.github/ISSUE_TEMPLATE/bug_report.yml',
  '.github/ISSUE_TEMPLATE/feature_request.yml',
  '.github/ISSUE_TEMPLATE/documentation.yml',
];

void main() {
  group('.github/ISSUE_TEMPLATE/*.yml presence + parse', () {
    for (final String path in _templateFiles) {
      test('$path exists', () {
        expect(fileExists(path), isTrue, reason: 'Step 11 must create $path');
      });

      test('$path parses as YAML', () {
        final dynamic doc = loadYamlFile(path);
        // config.yml is a YamlMap; *_report / feature_request / documentation
        // are also YamlMaps under GitHub's issue forms schema.
        expect(doc, isA<YamlMap>(), reason: '$path must be a valid YAML map');
      });
    }
  });

  group('.github/ISSUE_TEMPLATE/config.yml schema', () {
    test('disables blank issues via "blank_issues_enabled: false"', () {
      // Only run when the file exists; the existence assertion above already
      // produces a clear failure when it does not.
      if (!fileExists('.github/ISSUE_TEMPLATE/config.yml')) {
        fail(
            '.github/ISSUE_TEMPLATE/config.yml is missing; cannot assert blank_issues_enabled');
      }
      final YamlMap doc =
          loadYamlFile('.github/ISSUE_TEMPLATE/config.yml') as YamlMap;
      expect(
        doc['blank_issues_enabled'],
        equals(false),
        reason: 'config.yml must disable blank issues',
      );
    });
  });
}
