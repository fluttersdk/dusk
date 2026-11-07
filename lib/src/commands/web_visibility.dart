import 'package:fluttersdk_artisan/artisan.dart';

import '../cdp/page_visibility.dart';

/// Calls [method] and, when the answer came from a hidden web tab, brings the
/// tab to front over CDP.
///
/// A web response whose `warnings.platform` is `web` was produced while
/// Chrome withheld frames, and the in-isolate wake cannot help there. With a
/// `cdpPort` in the session state the tab is brought to front once. Then:
///
/// - [retry] true (read-only verbs: snap, observe): [method] is called again
///   once and that second response is returned.
/// - [retry] false (mutating verbs): the original response is returned and a
///   stderr notice tells the caller to re-snap. The gesture or write may
///   already have taken effect, so repeating it could apply it twice.
///
/// A healthy response, a non-web warning or a missing `cdpPort` returns the
/// first response untouched and makes no CDP call. A CDP failure prints one
/// stderr line and also returns the first response: the exit code stays the
/// command's own.
///
/// A hidden tab can also fail to answer at all: a verb that waits on timers
/// and frames outlasts the VM Service call and the call throws. With a
/// `cdpPort` and a tab that reports `hidden`, the tab is brought to front
/// the same way: a [retry] verb is called again once, a mutating verb
/// rethrows the original error after a stderr notice, since its gesture may
/// already have fired. Any other error propagates untouched.
Future<Map<String, dynamic>> callExtensionVisible(
  ArtisanContext ctx,
  String method,
  Map<String, dynamic> params, {
  bool retry = false,
}) async {
  // 1. The call itself; anything but a hidden web tab ends here.
  final Map<String, dynamic> response;
  try {
    response = await ctx.callExtension<Map<String, dynamic>>(method, params);
  } on Exception catch (e) {
    if (!_looksLikeNoAnswer(e) || !await _recoveredHiddenTab(ctx)) rethrow;
    if (!retry) {
      ctx.output.error(
        '⚠ The page was hidden and did not answer; it is now in front. The '
        'action may already have run: run dusk:snap to check before the '
        'next step.',
      );
      rethrow;
    }
    return ctx.callExtension<Map<String, dynamic>>(method, params);
  }
  final Object? warnings = response['warnings'];
  if (warnings is! Map<String, dynamic> || warnings['platform'] != 'web') {
    return response;
  }

  // 2. Without a CDP port there is no way to reach the tab from here.
  final Map<String, dynamic>? state = await StateFile.read();
  final int? cdpPort = _asInt(state?['cdpPort']);
  if (cdpPort == null) return response;

  // 3. Bring the tab to front; a failure keeps the response already held.
  final BringToFrontResult result =
      await bringCdpPageToFront(cdpPort, _asInt(state?['webPort']));
  if (!result.succeeded) {
    ctx.output.error(
      '⚠ Could not bring the page to front over CDP on port $cdpPort: '
      '${result.error}',
    );
    return response;
  }

  // 4. Only a read is safe to repeat.
  if (retry) {
    return ctx.callExtension<Map<String, dynamic>>(method, params);
  }
  ctx.output.error(
    '⚠ Brought the hidden page to front. This action ran while it was hidden '
    'and was not repeated: run dusk:snap to check what it did before the '
    'next step.',
  );
  return response;
}

/// Whether [error] is the "no answer in time" failure a hidden tab produces
/// (the VM Service call timing out), as opposed to the app answering with a
/// refusal such as `not a text field` or `obscured`, which a hidden tab still
/// returns and which retrying or raising the window would not change.
bool _looksLikeNoAnswer(Object error) {
  final String text = error.toString().toLowerCase();
  return text.contains('timeoutexception') || text.contains('timed out');
}

/// For a call that threw: true only when the session has a `cdpPort`, the
/// tab reports `hidden` and bringing it to front worked.
Future<bool> _recoveredHiddenTab(ArtisanContext ctx) async {
  final Map<String, dynamic>? state = await StateFile.read();
  final int? cdpPort = _asInt(state?['cdpPort']);
  if (cdpPort == null) return false;

  final int? webPort = _asInt(state?['webPort']);
  if (await isCdpPageHidden(cdpPort, webPort) != true) return false;

  final BringToFrontResult result = await bringCdpPageToFront(cdpPort, webPort);
  if (!result.succeeded) {
    ctx.output.error(
      '⚠ Could not bring the page to front over CDP on port $cdpPort: '
      '${result.error}',
    );
  }
  return result.succeeded;
}

/// Tolerates `int`, `num` or a numeric `String`, so a cross-version state
/// file does not throw on a cast.
int? _asInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}
