/// Small readers the perf files and the perf commands share: a JSON value
/// taken as a map or a list, a flag as a bool, a secret as it reads inside
/// JSON, and a path made absolute or shown relative to a file.
///
/// Pure Dart with no Flutter import: `scenario.dart` uses it, and the CLI
/// wrapper that loads scenarios has to stay Flutter-free.
library;

import 'dart:convert';
import 'dart:io';

/// [value] when it is a JSON object, else an empty map.
Map<String, dynamic> perfMap(Object? value) =>
    value is Map<String, dynamic> ? value : const <String, dynamic>{};

/// [value] when it is a JSON array, else an empty list.
List<dynamic> perfList(Object? value) =>
    value is List<dynamic> ? value : const <dynamic>[];

/// A flag as a bool: CLI flags arrive as bools, a hand-built input or an MCP
/// argument may carry `'true'` or `'1'`. Anything else is false.
bool perfReadBool(Object? raw) => switch (raw) {
      final bool value => value,
      final String value => value == 'true' || value == '1',
      _ => false,
    };

/// `jsonEncode(value)` without its quotes: how [value] reads inside a JSON
/// string, where a `"` has become `\"`.
String perfJsonInner(String value) {
  final String encoded = jsonEncode(value);
  return encoded.substring(1, encoded.length - 1);
}

/// [path] made absolute against the working directory, `.` and `..`
/// resolved.
String perfAbsolutePath(String path) =>
    Uri.file(File(path).absolute.path).normalizePath().toFilePath();

/// [target] as a problem or an origin shows it: relative to the directory
/// of [file] when it is under it, else as it is.
String perfShownPath(String target, {required String file}) {
  final String dir = File(file).parent.path;
  final String prefix = dir.endsWith(Platform.pathSeparator)
      ? dir
      : '$dir${Platform.pathSeparator}';
  return target.startsWith(prefix) ? target.substring(prefix.length) : target;
}
