/// Shared helpers for the `test/publishing/` TDD harness.
///
/// Every publishing test loads a real artifact from disk (no fixtures) and
/// asserts presence + structure. The helpers below standardise the load + parse
/// + assertion vocabulary so the 12 sibling test files stay readable.
///
/// Resolution: all paths in [loadFile] / [loadYamlFile] resolve relative to the
/// `fluttersdk_dusk` package root (the directory containing `pubspec.yaml`).
/// We locate the root by walking upward from `Directory.current` until we find
/// a `pubspec.yaml` whose top-level `name:` is `fluttersdk_dusk`. This keeps
/// the harness robust whether `flutter test` is invoked from the package root
/// or from the parent consumer repo.
library;

import 'dart:io';

import 'package:yaml/yaml.dart';

/// Canonical path of the `fluttersdk_dusk` package root, cached after the
/// first successful resolution.
String? _packageRootCache;

/// Returns the absolute path of the `fluttersdk_dusk` package root.
///
/// Walks upward from `Directory.current` looking for a `pubspec.yaml` whose
/// top-level `name:` field is `fluttersdk_dusk`. Throws [StateError] when no
/// such pubspec is found within 10 parent levels.
String packageRoot() {
  if (_packageRootCache != null) {
    return _packageRootCache!;
  }

  Directory dir = Directory.current.absolute;
  for (int i = 0; i < 10; i++) {
    final File pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync()) {
      final dynamic doc = loadYaml(pubspec.readAsStringSync());
      if (doc is Map && doc['name'] == 'fluttersdk_dusk') {
        _packageRootCache = dir.path;
        return _packageRootCache!;
      }
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }

  throw StateError(
    'Could not locate the fluttersdk_dusk package root by walking up from '
    '${Directory.current.path}. The publishing test harness needs the root '
    'to resolve artifact paths.',
  );
}

/// Reads a UTF-8 text file at [relativePath] (resolved against [packageRoot]).
///
/// Throws [TestFailure]-friendly [FileSystemException] when the file does not
/// exist; the test runner surfaces the path in the failure message so the
/// downstream worker knows exactly which artifact to produce.
String loadFile(String relativePath) {
  final File file = File('${packageRoot()}/$relativePath');
  if (!file.existsSync()) {
    throw FileSystemException(
      'Required publishing artifact is missing on disk',
      file.path,
    );
  }
  return file.readAsStringSync();
}

/// Returns true when [relativePath] exists on disk under [packageRoot].
///
/// Use this from `expect(fileExists('path'), isTrue, reason: ...)` to keep the
/// failure message inline with the assertion (preferred over try/catch around
/// [loadFile] when the test only needs an existence check).
bool fileExists(String relativePath) {
  return File('${packageRoot()}/$relativePath').existsSync();
}

/// Loads and parses a YAML file at [relativePath].
///
/// Returns the decoded YAML document (typically a [YamlMap] or [YamlList]).
/// Throws [FileSystemException] when the file is absent, and re-throws any
/// `YamlException` raised by [loadYaml] so the test failure surfaces the
/// parser's diagnostic.
dynamic loadYamlFile(String relativePath) {
  final String raw = loadFile(relativePath);
  return loadYaml(raw);
}

/// Convenience: loads the package `pubspec.yaml` as a parsed YAML map.
YamlMap loadPubspec() {
  final dynamic doc = loadYamlFile('pubspec.yaml');
  if (doc is! YamlMap) {
    throw StateError(
      'pubspec.yaml did not parse as a YAML map; got ${doc.runtimeType}.',
    );
  }
  return doc;
}

/// Asserts [map] contains a top-level key [key].
///
/// Throws [TestFailure] (via `Expect.fail` equivalent, implemented as a
/// thrown [StateError] caught by `expect`) when the key is missing, with a
/// message naming both the key and the available keys for debugging.
void assertHasTopLevelKey(Map<dynamic, dynamic> map, String key,
    {String? label}) {
  if (!map.containsKey(key)) {
    final String origin = label ?? 'map';
    final List<String> available = map.keys.map((dynamic k) => '$k').toList()
      ..sort();
    throw StateError(
      'Expected top-level key "$key" in $origin; available keys: $available.',
    );
  }
}

/// Asserts [content] matches [pattern].
///
/// [label] names the artifact + concern under test, so a failing match prints
/// a message like `License header missing in LICENSE: expected /^MIT License/`.
void assertMatchesRegex(String content, RegExp pattern, String label) {
  if (!pattern.hasMatch(content)) {
    throw StateError(
      '$label: expected content to match ${pattern.pattern} but no match was '
      'found. First 200 chars: ${content.substring(0, content.length < 200 ? content.length : 200)}',
    );
  }
}

/// Asserts a markdown heading [heading] exists in [markdown].
///
/// Matches lines that begin with `#` followed by exactly the heading text
/// (after trimming). Use [headingLevel] (1-6) when you need to pin the heading
/// to a specific depth; the default (`null`) accepts any depth.
void assertSection(String markdown, String heading, {int? headingLevel}) {
  final String prefix = headingLevel == null ? '#+' : '#' * headingLevel;
  final RegExp pattern = RegExp(
    '^$prefix\\s+${RegExp.escape(heading)}\\s*\$',
    multiLine: true,
  );
  if (!pattern.hasMatch(markdown)) {
    throw StateError(
      'Expected markdown section "${'#' * (headingLevel ?? 2)} $heading" '
      'but no matching heading was found.',
    );
  }
}
