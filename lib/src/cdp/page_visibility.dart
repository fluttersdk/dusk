import 'package:meta/meta.dart';

import 'cdp_client.dart';

/// Outcome of [bringCdpPageToFront]: success, or the reason it failed.
@immutable
final class BringToFrontResult {
  const BringToFrontResult.success() : error = null;

  const BringToFrontResult.failure(String this.error);

  /// Why the page could not be brought to front; null on success.
  final String? error;

  bool get succeeded => error == null;
}

/// Whether the app's tab in the Chrome on [cdpPort] reports
/// `document.visibilityState: "hidden"`; null when that cannot be read.
///
/// For the caller whose extension call threw: a hidden tab never answers
/// (Chrome withholds the frames the answer waits for), and an error that has
/// another cause must not raise the user's window. Same tab selection as
/// [bringCdpPageToFront]. Never throws.
Future<bool?> isCdpPageHidden(int cdpPort, int? webPort) async {
  CdpClient? client;
  try {
    client = await CdpClient.connect(
      port: cdpPort,
      matchUrlSubstring: webPort == null ? null : ':$webPort',
    );
    final Map<String, dynamic> result = await client.send(
      'Runtime.evaluate',
      <String, dynamic>{
        'expression': 'document.visibilityState',
        'returnByValue': true,
      },
    );
    final Object? value = (result['result'] as Map<String, dynamic>?)?['value'];
    return value is String ? value == 'hidden' : null;
  } on DuskCdpException {
    return null;
  } finally {
    await client?.close();
  }
}

/// Sends `Page.bringToFront` to the app's tab in the Chrome on [cdpPort].
///
/// Chrome withholds frames from a hidden tab, and code inside the app cannot
/// make the tab visible, so recovery has to come from outside the isolate.
/// [webPort] picks the tab serving this run (`:<webPort>` in its URL) rather
/// than an orphan tab left by a killed run; when it is null the first page
/// tab is used, as `dusk:screenshot` does.
///
/// Never throws: every [DuskCdpException] (port unreachable, no matching tab,
/// a CDP error envelope, a timeout) becomes a [BringToFrontResult.failure],
/// because the caller already holds a valid response it must not lose.
Future<BringToFrontResult> bringCdpPageToFront(
  int cdpPort,
  int? webPort,
) async {
  final CdpClient client;
  try {
    client = await CdpClient.connect(
      port: cdpPort,
      matchUrlSubstring: webPort == null ? null : ':$webPort',
    );
  } on DuskCdpException catch (e) {
    return BringToFrontResult.failure(e.message);
  }

  try {
    await client.send('Page.bringToFront');
    return const BringToFrontResult.success();
  } on DuskCdpException catch (e) {
    return BringToFrontResult.failure(e.message);
  } finally {
    await client.close();
  }
}
