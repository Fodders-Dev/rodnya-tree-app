import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Detects manufacturers known to aggressively kill background tasks
/// (Xiaomi/Redpoint MIUI, Honor, Huawei, OnePlus, Oppo, Vivo) and
/// exposes a one-time "show me the autostart whitelist tip" signal
/// the UI can hook into. Without that whitelist, the user's device
/// will silently kill our notification listener and they'll never
/// receive incoming-call pushes when the app is closed.
///
/// Usage from any screen:
/// ```
/// final advisor = GetIt.I<BatteryOptimizationAdvisor>();
/// if (await advisor.shouldShowOnboardingTip()) {
///   // present the dismissible card
///   await advisor.markOnboardingTipShown();
/// }
/// ```
class BatteryOptimizationAdvisor {
  BatteryOptimizationAdvisor({
    required SharedPreferences preferences,
    DeviceInfoPlugin? deviceInfo,
  })  : _preferences = preferences,
        _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final SharedPreferences _preferences;
  final DeviceInfoPlugin _deviceInfo;

  static const String _shownStorageKey = 'rodnya_battery_tip_shown_v1';
  // Manufacturer strings reported by `Build.MANUFACTURER` on Android.
  // Lowercased before comparison; keep the canonical lowercase here.
  static const Set<String> _aggressiveManufacturers = <String>{
    'xiaomi',
    'redmi',
    'poco',
    'huawei',
    'honor',
    'oppo',
    'oneplus',
    'realme',
    'vivo',
    'iqoo',
    'tecno',
    'infinix',
  };

  Future<String?> _manufacturer() async {
    if (kIsWeb) return null;
    try {
      if (defaultTargetPlatform != TargetPlatform.android) return null;
      final info = await _deviceInfo.androidInfo;
      return info.manufacturer.toLowerCase().trim();
    } catch (_) {
      return null;
    }
  }

  /// True if the device is known to need a manual autostart-whitelist
  /// step for background pushes to arrive reliably.
  Future<bool> isAggressiveManufacturer() async {
    final manufacturer = await _manufacturer();
    if (manufacturer == null || manufacturer.isEmpty) return false;
    return _aggressiveManufacturers.any(manufacturer.contains);
  }

  /// One-shot getter the home/profile screen can poll to decide
  /// whether to render the onboarding card.
  Future<bool> shouldShowOnboardingTip() async {
    if (_preferences.getBool(_shownStorageKey) == true) return false;
    return isAggressiveManufacturer();
  }

  Future<void> markOnboardingTipShown() async {
    await _preferences.setBool(_shownStorageKey, true);
  }

  /// Manual reset for testing / settings → "Сбросить советы" button.
  Future<void> resetOnboardingTip() async {
    await _preferences.remove(_shownStorageKey);
  }
}
