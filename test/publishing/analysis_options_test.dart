/// Asserts `analysis_options.yaml` includes the `flutter_lints` ruleset.
///
/// Turned green by **Wave 3 / Step 5** (creates analysis_options.yaml with
/// `include: package:flutter_lints/flutter.yaml`).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '_helpers.dart';

void main() {
  group('analysis_options.yaml', () {
    test('exists at the package root', () {
      expect(fileExists('analysis_options.yaml'), isTrue);
    });

    test('parses as a YAML map', () {
      final dynamic doc = loadYamlFile('analysis_options.yaml');
      expect(doc, isA<YamlMap>(),
          reason: 'analysis_options.yaml must be a valid YAML map');
    });

    test('declares "include: package:flutter_lints/flutter.yaml"', () {
      final YamlMap doc = loadYamlFile('analysis_options.yaml') as YamlMap;
      expect(
        doc['include'],
        equals('package:flutter_lints/flutter.yaml'),
        reason: 'pana scores the flutter_lints include directly',
      );
    });
  });
}
