import 'package:fluttersdk_artisan/artisan.dart';

import 'perf_support.dart';

/// Masks the secrets a scenario load collected (every `${env.*}` value and
/// every `secret: true` param) as `***`, in a line of text or a JSON tree.
///
/// Each secret is masked in two forms: as it is, and as it reads inside a
/// JSON string (`jsonEncode` without the quotes), since an error that quotes
/// an extension's params or a navigate payload carries the encoded form, in
/// which a `"` has become `\"`.
final class PerfRedactor {
  PerfRedactor(Set<String> secrets)
      : _masks = <String>{
          for (final String secret in secrets)
            if (secret.isNotEmpty) ...<String>[secret, perfJsonInner(secret)],
        }.toList()
          // Longest first: a secret that contains another would otherwise
          // leave the rest of itself behind the shorter one's mask.
          ..sort((String a, String b) => b.length.compareTo(a.length));

  final List<String> _masks;

  /// [text] with every secret, raw or JSON-encoded, replaced by `***`.
  String redact(String text) => _masks.fold(
        text,
        (String line, String mask) => line.replaceAll(mask, '***'),
      );

  /// A copy of [value] (maps, lists and scalars as `jsonDecode` answers
  /// them) with every string leaf [redact]ed. Keys and non-string scalars
  /// are kept, so the tree still encodes to valid JSON whatever the secret.
  Object? redactJson(Object? value) => switch (value) {
        String() => redact(value),
        Map<String, Object?>() => <String, Object?>{
            for (final MapEntry<String, Object?>(:String key, :Object? value)
                in value.entries)
              key: redactJson(value),
          },
        List<Object?>() => <Object?>[
            for (final Object? item in value) redactJson(item),
          ],
        _ => value,
      };
}

/// An [ArtisanOutput] that [PerfRedactor.redact]s every line before the
/// output it wraps sees it, so an error, a diagnostic, a success line or a
/// `--json` envelope cannot print a secret.
final class RedactingOutput implements ArtisanOutput {
  RedactingOutput(this._inner, this._redactor);

  final ArtisanOutput _inner;
  final PerfRedactor _redactor;

  @override
  int get verbosity => _inner.verbosity;

  @override
  void writeln(String text, {int level = 1}) =>
      _inner.writeln(_redactor.redact(text), level: level);

  @override
  void info(String text, {int level = 1}) =>
      _inner.info(_redactor.redact(text), level: level);

  @override
  void success(String text, {int level = 1}) =>
      _inner.success(_redactor.redact(text), level: level);

  @override
  void warning(String text, {int level = 1}) =>
      _inner.warning(_redactor.redact(text), level: level);

  @override
  void error(String text) => _inner.error(_redactor.redact(text));

  @override
  void comment(String text, {int level = 2}) =>
      _inner.comment(_redactor.redact(text), level: level);

  @override
  void debug(String text) => _inner.debug(_redactor.redact(text));
}
