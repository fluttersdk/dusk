import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/cdp/device_presets.dart';

void main() {
  group('kDevicePresets', () {
    test('contains exactly 8 preset keys', () {
      expect(kDevicePresets.keys, hasLength(8));
    });

    test('contains all expected preset keys', () {
      expect(
        kDevicePresets.keys,
        containsAll([
          'iphone-x',
          'iphone-13',
          'iphone-15-pro',
          'pixel-5',
          'pixel-8',
          'ipad-pro-12.9',
          'desktop-1440',
          'desktop-1920',
        ]),
      );
    });

    test('every preset has deviceScaleFactor > 0 (Oracle F3)', () {
      for (final entry in kDevicePresets.entries) {
        expect(
          entry.value.deviceScaleFactor,
          greaterThan(0),
          reason: '${entry.key} has deviceScaleFactor == 0',
        );
      }
    });

    test('mobile presets have hasTouch = true', () {
      const mobileKeys = [
        'iphone-x',
        'iphone-13',
        'iphone-15-pro',
        'pixel-5',
        'pixel-8',
        'ipad-pro-12.9',
      ];
      for (final key in mobileKeys) {
        final preset = kDevicePresets[key]!;
        expect(preset.hasTouch, isTrue,
            reason: '$key should have hasTouch=true');
        expect(preset.isMobile, isTrue,
            reason: '$key should have isMobile=true');
      }
    });

    test('desktop presets have isMobile=false and hasTouch=false', () {
      const desktopKeys = ['desktop-1440', 'desktop-1920'];
      for (final key in desktopKeys) {
        final preset = kDevicePresets[key]!;
        expect(preset.isMobile, isFalse,
            reason: '$key should have isMobile=false');
        expect(preset.hasTouch, isFalse,
            reason: '$key should have hasTouch=false');
      }
    });

    test('iphone-x has correct dimensions and DPR', () {
      final preset = kDevicePresets['iphone-x']!;
      expect(preset.width, equals(375));
      expect(preset.height, equals(812));
      expect(preset.deviceScaleFactor, equals(3.0));
    });

    test('iphone-13 has correct dimensions and DPR', () {
      final preset = kDevicePresets['iphone-13']!;
      expect(preset.width, equals(390));
      expect(preset.height, equals(844));
      expect(preset.deviceScaleFactor, equals(3.0));
    });

    test('iphone-15-pro has correct dimensions and DPR', () {
      final preset = kDevicePresets['iphone-15-pro']!;
      expect(preset.width, equals(393));
      expect(preset.height, equals(852));
      expect(preset.deviceScaleFactor, equals(3.0));
    });

    test('pixel-5 has correct dimensions and DPR', () {
      final preset = kDevicePresets['pixel-5']!;
      expect(preset.width, equals(393));
      expect(preset.height, equals(851));
      expect(preset.deviceScaleFactor, equals(2.75));
    });

    test('pixel-8 has correct dimensions and DPR', () {
      final preset = kDevicePresets['pixel-8']!;
      expect(preset.width, equals(412));
      expect(preset.height, equals(915));
      expect(preset.deviceScaleFactor, equals(2.625));
    });

    test('ipad-pro-12.9 has correct dimensions and DPR', () {
      final preset = kDevicePresets['ipad-pro-12.9']!;
      expect(preset.width, equals(1024));
      expect(preset.height, equals(1366));
      expect(preset.deviceScaleFactor, equals(2.0));
    });

    test('desktop-1440 has correct dimensions and DPR', () {
      final preset = kDevicePresets['desktop-1440']!;
      expect(preset.width, equals(1440));
      expect(preset.height, equals(900));
      expect(preset.deviceScaleFactor, equals(1.0));
    });

    test('desktop-1920 has correct dimensions and DPR', () {
      final preset = kDevicePresets['desktop-1920']!;
      expect(preset.width, equals(1920));
      expect(preset.height, equals(1080));
      expect(preset.deviceScaleFactor, equals(1.0));
    });

    test('all presets have non-empty UA strings', () {
      for (final entry in kDevicePresets.entries) {
        expect(
          entry.value.userAgent,
          isNotEmpty,
          reason: '${entry.key} has empty userAgent',
        );
      }
    });
  });

  group('lookupPreset', () {
    test('returns preset for exact lowercase key', () {
      expect(lookupPreset('iphone-x'), equals(kDevicePresets['iphone-x']));
    });

    test('returns preset for mixed-case input (case-insensitive)', () {
      expect(lookupPreset('Iphone-X'), equals(kDevicePresets['iphone-x']));
    });

    test('returns preset for uppercase input', () {
      expect(lookupPreset('IPHONE-X'), equals(kDevicePresets['iphone-x']));
    });

    test('normalizes underscore to hyphen', () {
      expect(lookupPreset('iphone_x'), equals(kDevicePresets['iphone-x']));
    });

    test('normalizes space to hyphen', () {
      expect(lookupPreset('iphone x'), equals(kDevicePresets['iphone-x']));
    });

    test('collapses adjacent hyphens', () {
      expect(lookupPreset('iphone--x'), equals(kDevicePresets['iphone-x']));
    });

    test('returns null for unknown preset', () {
      expect(lookupPreset('unknown'), isNull);
    });

    test('returns null for empty string', () {
      expect(lookupPreset(''), isNull);
    });
  });

  group('presetNames', () {
    test('returns list of 8 names', () {
      expect(presetNames, hasLength(8));
    });

    test('contains all preset keys', () {
      expect(presetNames, containsAll(kDevicePresets.keys));
    });
  });
}
