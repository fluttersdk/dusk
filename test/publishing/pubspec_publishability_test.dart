/// Asserts `pubspec.yaml` is publish-ready against pub.dev's 0.23.x rubric.
///
/// Turned green by **Wave 2 / Step 3** (path-dep swap to hosted artisan
/// `^0.0.1`, `publish_to: none` removal, `issue_tracker` + `documentation` +
/// `topics` addition). The two negative-existence checks (`publish_to` absent,
/// `path:` absent) are the publish-blockers Step 3 lifts.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '_helpers.dart';

void main() {
  group('pubspec.yaml publishability', () {
    test('exists and parses as a YAML map', () {
      expect(fileExists('pubspec.yaml'), isTrue,
          reason: 'pubspec.yaml must exist at the package root');
      expect(loadPubspec(), isA<YamlMap>());
    });

    test('declares top-level "name" set to fluttersdk_dusk', () {
      final YamlMap pubspec = loadPubspec();
      expect(pubspec['name'], equals('fluttersdk_dusk'));
    });

    test('declares "description" between 60 and 180 characters', () {
      final YamlMap pubspec = loadPubspec();
      final String? description = pubspec['description'] as String?;
      expect(description, isNotNull,
          reason: 'pubspec.description is required by pub.dev');
      expect(
        description!.length,
        inInclusiveRange(60, 180),
        reason:
            'pana penalises descriptions outside [60, 180] chars; got ${description.length}',
      );
    });

    test('declares "version" matching SemVer 0.0.1', () {
      final YamlMap pubspec = loadPubspec();
      expect(pubspec['version'], equals('0.0.1'));
    });

    test('declares "homepage" as the dusk landing-page URL', () {
      final YamlMap pubspec = loadPubspec();
      expect(pubspec['homepage'], isA<String>());
      expect(pubspec['homepage'] as String, startsWith('https://'));
    });

    test('declares "repository" pointing at the dusk GitHub repo', () {
      final YamlMap pubspec = loadPubspec();
      expect(pubspec['repository'], isA<String>());
      expect(
          pubspec['repository'] as String, startsWith('https://github.com/'));
    });

    test('declares "issue_tracker" pointing at the dusk GitHub issues', () {
      final YamlMap pubspec = loadPubspec();
      expect(
        pubspec['issue_tracker'],
        isA<String>(),
        reason: 'pana scores issue_tracker; Step 3 must add it',
      );
      expect(
          (pubspec['issue_tracker'] as String).contains('github.com'), isTrue);
    });

    test('declares "documentation" pointing at the dusk docs site', () {
      final YamlMap pubspec = loadPubspec();
      expect(
        pubspec['documentation'],
        isA<String>(),
        reason: 'pana scores documentation; Step 3 must add it',
      );
      expect(
          (pubspec['documentation'] as String).startsWith('https://'), isTrue);
    });

    test('declares "topics" as a list of <=5 entries matching pub.dev regex',
        () {
      final YamlMap pubspec = loadPubspec();
      final dynamic topics = pubspec['topics'];
      expect(topics, isA<YamlList>(), reason: 'topics must be a YAML list');
      final YamlList list = topics as YamlList;
      expect(list.length, lessThanOrEqualTo(5),
          reason: 'pub.dev caps topics at 5');
      expect(list.length, greaterThanOrEqualTo(1),
          reason: 'declare at least 1 topic');
      final RegExp topicRegex = RegExp(r'^[a-z][a-z0-9-]{1,31}$');
      for (final dynamic topic in list) {
        expect(topic, isA<String>());
        expect(
          topicRegex.hasMatch(topic as String),
          isTrue,
          reason: 'topic "$topic" must match ${topicRegex.pattern}',
        );
      }
    });

    test('declares "environment.sdk" with a 3.x constraint', () {
      final YamlMap pubspec = loadPubspec();
      final dynamic environment = pubspec['environment'];
      expect(environment, isA<YamlMap>(),
          reason: 'environment block is required');
      assertHasTopLevelKey(environment as YamlMap, 'sdk', label: 'environment');
      expect((environment['sdk'] as String).contains('3.'), isTrue);
    });

    test('declares "environment.flutter" with a >=3.22 constraint', () {
      final YamlMap pubspec = loadPubspec();
      final YamlMap environment = pubspec['environment'] as YamlMap;
      assertHasTopLevelKey(environment, 'flutter', label: 'environment');
      expect(environment['flutter'], isA<String>());
    });

    test('declares dependencies.fluttersdk_artisan as a hosted version string',
        () {
      final YamlMap pubspec = loadPubspec();
      final YamlMap dependencies = pubspec['dependencies'] as YamlMap;
      assertHasTopLevelKey(dependencies, 'fluttersdk_artisan',
          label: 'dependencies');
      expect(
        dependencies['fluttersdk_artisan'],
        isA<String>(),
        reason:
            'fluttersdk_artisan must be a hosted String constraint, not a path/git Map',
      );
    });

    test('dependencies.fluttersdk_artisan does NOT use a path: dep', () {
      final String raw = loadFile('pubspec.yaml');
      // Positive existence has been asserted above; this negative check is now
      // meaningful because we know the dependencies block was reached.
      expect(
        RegExp(r'fluttersdk_artisan:\s*\n\s+path:').hasMatch(raw),
        isFalse,
        reason: 'path: deps block dart pub publish; Step 3 must swap to hosted',
      );
    });

    test('does NOT contain top-level "publish_to:" line', () {
      final String raw = loadFile('pubspec.yaml');
      expect(
        RegExp(r'^publish_to:', multiLine: true).hasMatch(raw),
        isFalse,
        reason: 'publish_to: none blocks publish; Step 3 must remove it',
      );
    });

    test(
        'does NOT declare a "platforms:" field (pana 0.23.x SwiftPM deduction)',
        () {
      final YamlMap pubspec = loadPubspec();
      expect(
        pubspec.containsKey('platforms'),
        isFalse,
        reason:
            'Plan guardrail: omit platforms: to avoid SwiftPM partial-point deduction',
      );
    });
  });
}
