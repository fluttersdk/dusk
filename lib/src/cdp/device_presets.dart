// UA string fragments used in the curated preset entries below.
// Keep private: chromeVer, safariVer etc. are internal detail and must not
// become top-level public constants.
//
// Because kDevicePresets is a compile-time const, user-agent strings must be
// string literals rather than runtime function calls. Each UA is inlined
// directly in the preset entry. The fragments below document the shared
// components for readability and future maintenance.
//
// Chrome 130.0.6723.92 / Safari WebKit 605.1.15 / iOS 17.0 / macOS 14.5.
//
// iOS 17.0 Safari shape:
//   Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)
//   AppleWebKit/605.1.15 (KHTML, like Gecko) Version/19.2 Mobile/15E148 Safari/605.1.15
//
// iPad iOS 17.0 Safari shape:
//   Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X)
//   AppleWebKit/605.1.15 (KHTML, like Gecko) Version/19.2 Mobile/15E148 Safari/605.1.15
//
// Android Chrome shape:
//   Mozilla/5.0 (Linux; Android <ver>; <device>)
//   AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.6723.92 Mobile Safari/537.36
//
// Desktop macOS Chrome shape:
//   Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5)
//   AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.6723.92 Safari/537.36

/// A single device emulation preset for Chrome DevTools Protocol.
///
/// All fields map directly to CDP Emulation.setDeviceMetricsOverride parameters.
/// [deviceScaleFactor] MUST be > 0: passing 0 to CDP disables the override and
/// falls back to the host display DPR, making tests non-deterministic.
final class DevicePreset {
  /// Viewport width in CSS pixels.
  final int width;

  /// Viewport height in CSS pixels.
  final int height;

  /// Device pixel ratio. Always > 0 in curated presets (0 = use host DPR).
  final double deviceScaleFactor;

  /// Whether to emulate a mobile device (viewport meta + text autosizing).
  final bool isMobile;

  /// Whether to synthesise touch events.
  final bool hasTouch;

  /// User agent string sent via Emulation.setUserAgentOverride.
  final String userAgent;

  const DevicePreset({
    required this.width,
    required this.height,
    required this.deviceScaleFactor,
    required this.isMobile,
    required this.hasTouch,
    required this.userAgent,
  });
}

/// Curated device preset database: 8 entries covering the most common
/// responsive testing targets. Keys are lowercase, hyphenated.
///
/// deviceScaleFactor is always explicit and > 0. See [lookupPreset] for
/// case-insensitive, hyphen-normalised access.
const Map<String, DevicePreset> kDevicePresets = <String, DevicePreset>{
  'iphone-x': DevicePreset(
    width: 375,
    height: 812,
    deviceScaleFactor: 3.0,
    isMobile: true,
    hasTouch: true,
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)'
        ' AppleWebKit/605.1.15 (KHTML, like Gecko)'
        ' Version/19.2 Mobile/15E148 Safari/605.1.15',
  ),
  'iphone-13': DevicePreset(
    width: 390,
    height: 844,
    deviceScaleFactor: 3.0,
    isMobile: true,
    hasTouch: true,
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)'
        ' AppleWebKit/605.1.15 (KHTML, like Gecko)'
        ' Version/19.2 Mobile/15E148 Safari/605.1.15',
  ),
  'iphone-15-pro': DevicePreset(
    width: 393,
    height: 852,
    deviceScaleFactor: 3.0,
    isMobile: true,
    hasTouch: true,
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)'
        ' AppleWebKit/605.1.15 (KHTML, like Gecko)'
        ' Version/19.2 Mobile/15E148 Safari/605.1.15',
  ),
  'pixel-5': DevicePreset(
    width: 393,
    height: 851,
    deviceScaleFactor: 2.75,
    isMobile: true,
    hasTouch: true,
    userAgent: 'Mozilla/5.0 (Linux; Android 13; Pixel 5)'
        ' AppleWebKit/537.36 (KHTML, like Gecko)'
        ' Chrome/130.0.6723.92 Mobile Safari/537.36',
  ),
  'pixel-8': DevicePreset(
    width: 412,
    height: 915,
    deviceScaleFactor: 2.625,
    isMobile: true,
    hasTouch: true,
    userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8)'
        ' AppleWebKit/537.36 (KHTML, like Gecko)'
        ' Chrome/130.0.6723.92 Mobile Safari/537.36',
  ),
  'ipad-pro-12.9': DevicePreset(
    width: 1024,
    height: 1366,
    deviceScaleFactor: 2.0,
    isMobile: true,
    hasTouch: true,
    userAgent: 'Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X)'
        ' AppleWebKit/605.1.15 (KHTML, like Gecko)'
        ' Version/19.2 Mobile/15E148 Safari/605.1.15',
  ),
  'desktop-1440': DevicePreset(
    width: 1440,
    height: 900,
    deviceScaleFactor: 1.0,
    isMobile: false,
    hasTouch: false,
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5)'
        ' AppleWebKit/537.36 (KHTML, like Gecko)'
        ' Chrome/130.0.6723.92 Safari/537.36',
  ),
  'desktop-1920': DevicePreset(
    width: 1920,
    height: 1080,
    deviceScaleFactor: 1.0,
    isMobile: false,
    hasTouch: false,
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5)'
        ' AppleWebKit/537.36 (KHTML, like Gecko)'
        ' Chrome/130.0.6723.92 Safari/537.36',
  ),
};

/// All preset names in insertion order.
List<String> get presetNames => kDevicePresets.keys.toList();

/// Looks up a preset by name, normalising the input:
/// lowercase, underscores and spaces replaced with hyphens,
/// adjacent hyphens collapsed to a single hyphen.
///
/// Returns null when no matching preset exists.
DevicePreset? lookupPreset(String name) {
  // 1. Lowercase.
  var normalised = name.toLowerCase();
  // 2. Replace underscores and spaces with hyphens.
  normalised = normalised.replaceAll(RegExp(r'[_\s]'), '-');
  // 3. Collapse runs of adjacent hyphens to a single hyphen.
  normalised = normalised.replaceAll(RegExp(r'-{2,}'), '-');
  return kDevicePresets[normalised];
}
