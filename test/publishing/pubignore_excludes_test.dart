/// Asserts `.pubignore` excludes example platform dirs and local-state dirs
/// while keeping the canonical published payload (`lib/`, `bin/`,
/// `pubspec.yaml`, `README.md`, `CHANGELOG.md`, `LICENSE`, `doc/`,
/// `analysis_options.yaml`, `install.yaml`).
///
/// Turned green by **Wave 3 / Step 7** (.pubignore adapted from
/// `fluttersdk_artisan/.pubignore`).
library;

import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

/// Returns the set of non-empty, non-comment trimmed lines in `.pubignore`.
List<String> _pubignoreEntries() {
  final String raw = loadFile('.pubignore');
  return raw
      .split('\n')
      .map((String line) => line.trim())
      .where((String line) => line.isNotEmpty && !line.startsWith('#'))
      .toList();
}

void main() {
  group('.pubignore exclusion rules', () {
    test('exists at the package root', () {
      expect(fileExists('.pubignore'), isTrue,
          reason: '.pubignore drives the publish tarball contents');
    });

    test(
        'excludes every example/ platform subdir (android/, ios/, macos/, linux/, windows/, web/)',
        () {
      final List<String> entries = _pubignoreEntries();
      for (final String dir in const <String>[
        'android/',
        'ios/',
        'macos/',
        'linux/',
        'windows/',
        'web/'
      ]) {
        expect(
          entries.any((String e) => e.contains(dir)),
          isTrue,
          reason: '.pubignore must exclude $dir build platform dir',
        );
      }
    });

    test('excludes build/, coverage/, .dart_tool/ (build + test outputs)', () {
      final List<String> entries = _pubignoreEntries();
      for (final String dir in const <String>[
        'build/',
        'coverage/',
        '.dart_tool/'
      ]) {
        expect(entries, contains(dir), reason: '.pubignore must exclude $dir');
      }
    });

    test('excludes IDE + local-state dirs (.idea/, .ac/)', () {
      final List<String> entries = _pubignoreEntries();
      expect(entries, contains('.idea/'));
      expect(entries, contains('.ac/'));
    });

    test('excludes Claude Code instruction files (CLAUDE.md, CLAUDE.local.md)',
        () {
      final List<String> entries = _pubignoreEntries();
      expect(entries, contains('CLAUDE.md'));
      expect(entries, contains('CLAUDE.local.md'));
    });

    test(
        'does NOT exclude shipped artifacts (lib/, bin/, pubspec.yaml, README.md, CHANGELOG.md, LICENSE)',
        () {
      final List<String> entries = _pubignoreEntries();
      for (final String shipped in const <String>[
        'lib/',
        'bin/',
        'pubspec.yaml',
        'README.md',
        'CHANGELOG.md',
        'LICENSE',
        'doc/',
        'analysis_options.yaml',
        'install.yaml',
      ]) {
        expect(
          entries.contains(shipped),
          isFalse,
          reason:
              '.pubignore must NOT exclude $shipped (it must ship in the tarball)',
        );
      }
    });
  });
}
