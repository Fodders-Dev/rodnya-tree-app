import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/services/battery_optimization_advisor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records every autostart-launch attempt and replies via [_handler], so a
/// test can assert WHICH components were probed, in what order, and how the
/// advisor reacts to success / failure / throwing without touching a device.
class _RecordingLauncher {
  _RecordingLauncher(this._handler);

  final Future<bool> Function(String package, String component) _handler;
  final List<List<String>> calls = <List<String>>[];

  Future<bool> call(String package, String component) {
    calls.add(<String>[package, component]);
    return _handler(package, component);
  }
}

Future<BatteryOptimizationAdvisor> _advisor(AutostartLauncher launcher) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return BatteryOptimizationAdvisor(
    preferences: prefs,
    autostartLauncher: launcher,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('autostartComponentsFor (pure vendor routing)', () {
    test('returns empty for null / empty / unknown / non-OEM vendors', () {
      for (final m in <String?>[null, '', '   ', 'google', 'samsung', 'sony']) {
        expect(
          BatteryOptimizationAdvisor.autostartComponentsFor(m),
          isEmpty,
          reason: 'no autostart deep-link for "$m" → caller must fall back',
        );
      }
    });

    test('Huawei/Honor → three com.huawei.systemmanager candidates', () {
      for (final m in <String>['huawei', 'HUAWEI', ' Honor ', 'honor']) {
        final components = BatteryOptimizationAdvisor.autostartComponentsFor(m);
        expect(components, hasLength(3), reason: m);
        // All target the EMUI system-manager package.
        for (final c in components) {
          expect(c, hasLength(2));
          expect(c[0], 'com.huawei.systemmanager');
          expect(c[1], startsWith('com.huawei.systemmanager.'));
        }
        // Verified-present activities are tried first (fewest misfires on
        // the real HUAWEI TGR-W09); legacy ProtectActivity is the tail.
        expect(
          components.first[1],
          'com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity',
        );
      }
    });

    test('Xiaomi family → MIUI AutoStartManagementActivity', () {
      for (final m in <String>['xiaomi', 'Redmi', 'POCO']) {
        final components = BatteryOptimizationAdvisor.autostartComponentsFor(m);
        expect(components, hasLength(1), reason: m);
        expect(components.single, <String>[
          'com.miui.securitycenter',
          'com.miui.permcenter.autostart.AutoStartManagementActivity',
        ]);
      }
    });

    test('Oppo/Realme → two coloros safecenter candidates', () {
      for (final m in <String>['oppo', 'realme']) {
        final components = BatteryOptimizationAdvisor.autostartComponentsFor(m);
        expect(components, hasLength(2), reason: m);
        expect(components.every((c) => c[0] == 'com.coloros.safecenter'), isTrue);
      }
    });

    test('Vivo/iQOO and OnePlus map to their managers', () {
      expect(
        BatteryOptimizationAdvisor.autostartComponentsFor('vivo').single,
        <String>[
          'com.vivo.permissionmanager',
          'com.vivo.permissionmanager.activity.BgStartUpManagerActivity',
        ],
      );
      expect(
        BatteryOptimizationAdvisor.autostartComponentsFor('iqoo'),
        hasLength(1),
      );
      expect(
        BatteryOptimizationAdvisor.autostartComponentsFor('oneplus').single,
        <String>[
          'com.oneplus.security',
          'com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity',
        ],
      );
    });
  });

  group('openAutostartSettings (fallback + probing behaviour)', () {
    test('non-OEM vendor → returns false WITHOUT launching (→ openAppSettings)',
        () async {
      final launcher = _RecordingLauncher((_, __) async => true);
      final advisor = await _advisor(launcher.call);

      final opened = await advisor.debugOpenAutostartFor('google');

      expect(opened, isFalse, reason: 'card must fall back to openAppSettings');
      expect(launcher.calls, isEmpty, reason: 'no component to even attempt');
    });

    test('all candidates fail → false, every candidate tried in order',
        () async {
      final launcher = _RecordingLauncher((_, __) async => false);
      final advisor = await _advisor(launcher.call);

      final opened = await advisor.debugOpenAutostartFor('huawei');

      expect(opened, isFalse);
      expect(launcher.calls, hasLength(3));
      expect(
        launcher.calls.first[1],
        'com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity',
      );
    });

    test('first candidate opens → true, short-circuits remaining', () async {
      final launcher = _RecordingLauncher((_, __) async => true);
      final advisor = await _advisor(launcher.call);

      final opened = await advisor.debugOpenAutostartFor('huawei');

      expect(opened, isTrue);
      expect(launcher.calls, hasLength(1), reason: 'stops at first success');
    });

    test('falls through a failing candidate to the next that opens', () async {
      var attempt = 0;
      final launcher = _RecordingLauncher((_, __) async => (attempt++) == 1);
      final advisor = await _advisor(launcher.call);

      final opened = await advisor.debugOpenAutostartFor('huawei');

      expect(opened, isTrue);
      expect(launcher.calls, hasLength(2), reason: '1st failed, 2nd opened');
    });

    test('launcher throwing is swallowed → false, no crash', () async {
      final launcher = _RecordingLauncher((_, __) async {
        throw Exception('ActivityNotFound / SecurityException simulation');
      });
      final advisor = await _advisor(launcher.call);

      final opened = await advisor.debugOpenAutostartFor('xiaomi');

      expect(opened, isFalse);
      expect(launcher.calls, hasLength(1));
    });
  });
}
