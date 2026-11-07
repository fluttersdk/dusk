/// Line diff between two accessibility snapshots, the cheap answer to "what
/// did that action change" for an agent that would otherwise re-read a whole
/// screen.
///
/// Pure functions with no binding access.
library;

/// A ref-bearing snapshot line: the `[ref=eN]` token, then only the
/// state-dependent suffix markers (` [offscreen]`, ` [occluded]`) to the end.
final RegExp _refLine =
    RegExp(r'\[ref=(\w+)\](?: \[(?:offscreen|occluded)\])*$');

/// Diffs [current] against [previous], both in the `ext.dusk.snap` text
/// format.
///
/// A null [previous] means no baseline exists yet, so the full [current] text
/// is returned unchanged.
///
/// Otherwise the result lists only the lines that differ, then a footer
/// `(K of N lines changed)` where K counts the listed lines and N is the
/// number of lines in [current]:
///
/// - `- old` then `+ new` for a ref whose line changed,
/// - `+ line` for a row only [current] has,
/// - `- line` for a row only [previous] has.
///
/// Changed and added lines come first, in [current] order; removed lines
/// follow, in [previous] order.
///
/// Ref lines are matched on their `[ref=eN]` token, which is stable per
/// semantics node across snapshots, and compared with the trailing visibility
/// markers ignored: a node scrolling off screen is not a change to what it
/// says. Every other line (plain text, `typeable: true`, enricher output) has
/// no token and is matched on its exact text, one for one when it repeats.
String diffSnapshots(String? previous, String current) {
  if (previous == null) return current;

  final List<String> currentLines = _lines(current);
  final Map<String, String> previousByKey = _keyed(_lines(previous));

  // 1. Walk the new snapshot, consuming each previous line it accounts for.
  final List<String> out = <String>[];
  for (final MapEntry<String, String> entry in _keyed(currentLines).entries) {
    final String? old = previousByKey.remove(entry.key);
    final String line = entry.value;
    if (old == null) {
      out.add('+ $line');
    } else if (_comparable(old) != _comparable(line)) {
      out
        ..add('- $old')
        ..add('+ $line');
    }
  }

  // 2. What is left of the previous snapshot is gone from the current one.
  for (final String gone in previousByKey.values) {
    out.add('- $gone');
  }

  out.add('(${out.length} of ${currentLines.length} lines changed)');
  return out.join('\n');
}

List<String> _lines(String snapshot) {
  return snapshot.split('\n').where((String l) => l.isNotEmpty).toList();
}

/// Keys each line in order: by ref token when it has one, else by its text,
/// with an occurrence counter so repeats pair up one for one.
Map<String, String> _keyed(List<String> lines) {
  final Map<String, int> seen = <String, int>{};
  final Map<String, String> keyed = <String, String>{};
  for (final String line in lines) {
    final RegExpMatch? match = _refLine.firstMatch(line);
    final String base = match == null ? 'text:$line' : 'ref:${match.group(1)}';
    final int n = seen.update(base, (int c) => c + 1, ifAbsent: () => 0);
    keyed['$base#$n'] = line;
  }
  return keyed;
}

/// [line] with the visibility markers dropped, so a marker-only difference
/// compares equal.
String _comparable(String line) {
  final RegExpMatch? match = _refLine.firstMatch(line);
  if (match == null) return line;
  return '${line.substring(0, match.start)}[ref=${match.group(1)}]';
}
