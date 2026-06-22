import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Launches an explicit OEM autostart Activity by package + fully-qualified
/// class name. Returns true on a successful start, false on any failure.
/// Injected in tests; defaults to the native [MethodChannel] bridge.
typedef AutostartLauncher = Future<bool> Function(
  String package,
  String component,
);

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
    AutostartLauncher? autostartLauncher,
  })  : _preferences = preferences,
        _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
        _autostartLauncher = autostartLauncher ?? _launchViaPlatformChannel;

  final SharedPreferences _preferences;
  final DeviceInfoPlugin _deviceInfo;
  final AutostartLauncher _autostartLauncher;

  // Thin native bridge: asks MainActivity to startActivity() an explicit
  // ComponentName. See `rodnya/oem_settings` in MainActivity.kt.
  static const MethodChannel _oemChannel = MethodChannel('rodnya/oem_settings');

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

  /// Vendor-specific autostart / "protected apps" settings screens, as
  /// `[packageName, fullyQualifiedActivity]` pairs to try IN ORDER. The
  /// general Android app-settings screen does NOT surface these on
  /// Huawei/Xiaomi/Oppo/Vivo/OnePlus — and it's exactly the autostart
  /// whitelist that lets a killed app wake up on a push/call. Class names
  /// and even package names drift across firmware versions, so we keep a
  /// few candidates per vendor and let the caller probe them one by one.
  ///
  /// Returns an empty list for unknown / non-OEM manufacturers (and for
  /// aggressive vendors we have no deep-link for, e.g. Tecno/Infinix) — the
  /// caller then falls back to the standard app-settings screen. Pure and
  /// side-effect-free so the routing is unit-testable without a device.
  ///
  /// NB (verified on HUAWEI TGR-W09 / Android 12): the EMUI activities are
  /// component-protected and require the manifest permission
  /// `com.huawei.permission.external_app_settings.USE_COMPONENT`; without it
  /// every candidate throws SecurityException and we degrade to the fallback.
  static List<List<String>> autostartComponentsFor(String? manufacturer) {
    final m = manufacturer?.toLowerCase().trim() ?? '';
    if (m.isEmpty) return const <List<String>>[];
    if (m.contains('huawei') || m.contains('honor')) {
      return const <List<String>>[
        <String>[
          'com.huawei.systemmanager',
          'com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity',
        ],
        <String>[
          'com.huawei.systemmanager',
          'com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity',
        ],
        <String>[
          'com.huawei.systemmanager',
          'com.huawei.systemmanager.optimize.process.ProtectActivity',
        ],
      ];
    }
    if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
      return const <List<String>>[
        <String>[
          'com.miui.securitycenter',
          'com.miui.permcenter.autostart.AutoStartManagementActivity',
        ],
      ];
    }
    if (m.contains('oppo') || m.contains('realme')) {
      return const <List<String>>[
        <String>[
          'com.coloros.safecenter',
          'com.coloros.safecenter.permission.startup.StartupAppListActivity',
        ],
        <String>[
          'com.coloros.safecenter',
          'com.coloros.safecenter.startupapp.StartupAppListActivity',
        ],
      ];
    }
    if (m.contains('vivo') || m.contains('iqoo')) {
      return const <List<String>>[
        <String>[
          'com.vivo.permissionmanager',
          'com.vivo.permissionmanager.activity.BgStartUpManagerActivity',
        ],
      ];
    }
    if (m.contains('oneplus')) {
      return const <List<String>>[
        <String>[
          'com.oneplus.security',
          'com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity',
        ],
      ];
    }
    return const <List<String>>[];
  }

  /// Best-effort deep-link into the device's autostart / protected-apps
  /// whitelist. Tries each known vendor component in turn and returns true
  /// as soon as one opens. Returns false for unknown vendors or when every
  /// candidate fails — the UI must then fall back to [openAppSettings] so
  /// the user is never left staring at nothing.
  Future<bool> openAutostartSettings() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return _openAutostartFor(await _manufacturer());
  }

  /// Test seam: same logic as [openAutostartSettings] but with an explicit
  /// manufacturer, bypassing platform/device lookup.
  @visibleForTesting
  Future<bool> debugOpenAutostartFor(String? manufacturer) =>
      _openAutostartFor(manufacturer);

  Future<bool> _openAutostartFor(String? manufacturer) async {
    for (final candidate in autostartComponentsFor(manufacturer)) {
      try {
        if (await _autostartLauncher(candidate[0], candidate[1])) {
          return true;
        }
      } catch (_) {
        // Keep probing the remaining candidates; never throw.
      }
    }
    return false;
  }

  static Future<bool> _launchViaPlatformChannel(
    String package,
    String component,
  ) async {
    try {
      final ok = await _oemChannel.invokeMethod<bool>('startActivity', {
        'package': package,
        'component': component,
      });
      return ok == true;
    } catch (_) {
      // PlatformException / MissingPluginException (non-Android, no engine).
      return false;
    }
  }
}
