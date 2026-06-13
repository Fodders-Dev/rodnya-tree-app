// N4: состояние уведомлений = реальный permission (web), не prefs-флаг.
// Сверка needs-permission / granted / denied / iOS-non-standalone, и что
// запрос разрешения НЕ идёт без жеста (только setNotificationsEnabled).
// Браузерный мост — мок (фейк permission/iOS/standalone).

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/services/browser_notification_bridge.dart';
import 'package:rodnya/services/custom_api_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeBridge implements BrowserNotificationBridge {
  FakeBridge({
    this.permission = BrowserNotificationPermissionStatus.defaultState,
    this.supported = true,
    this.pushSupported = true,
    this.iosWeb = false,
    this.standalone = false,
  });

  BrowserNotificationPermissionStatus permission;
  bool supported;
  bool pushSupported;
  bool iosWeb;
  bool standalone;
  int requestPermissionCalls = 0;

  @override
  bool get isSupported => supported;
  @override
  bool get isPushSupported => pushSupported;
  @override
  bool get isIosWeb => iosWeb;
  @override
  bool get isStandalone => standalone;
  @override
  BrowserNotificationPermissionStatus get permissionStatus => permission;

  @override
  Future<BrowserNotificationPermissionStatus> requestPermission({
    bool prompt = true,
  }) async {
    requestPermissionCalls += 1;
    if (prompt &&
        permission == BrowserNotificationPermissionStatus.defaultState) {
      permission = BrowserNotificationPermissionStatus.granted;
    }
    return permission;
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? tag,
    void Function()? onClick,
  }) async {}

  @override
  Future<BrowserPushSubscription?> subscribeToPush({
    required String publicKey,
  }) async =>
      null;

  @override
  Future<void> unsubscribeFromPush() async {}
}

Future<CustomApiNotificationService> _service(
  FakeBridge bridge, {
  bool isWeb = true,
}) async {
  final prefs = await SharedPreferences.getInstance();
  return CustomApiNotificationService.create(
    preferences: prefs,
    browserNotificationBridge: bridge,
    isWeb: isWeb,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('состояние = реальный permission', () {
    test('default → needsBrowserPermission + CTA, НЕ effectivelyOn', () async {
      final service = await _service(FakeBridge(
        permission: BrowserNotificationPermissionStatus.defaultState,
      ));
      expect(service.needsBrowserPermission, isTrue);
      expect(service.shouldShowPermissionCta, isTrue);
      expect(service.notificationsEffectivelyOn, isFalse);
      expect(service.browserPushUnsupported, isFalse);
      await service.dispose();
    });

    test('granted → effectivelyOn, не нужен запрос/CTA', () async {
      final service = await _service(FakeBridge(
        permission: BrowserNotificationPermissionStatus.granted,
      ));
      expect(service.notificationsEffectivelyOn, isTrue);
      expect(service.needsBrowserPermission, isFalse);
      expect(service.shouldShowPermissionCta, isFalse);
      await service.dispose();
    });

    test('denied → не effectivelyOn, не needs, не CTA', () async {
      final service = await _service(FakeBridge(
        permission: BrowserNotificationPermissionStatus.denied,
      ));
      expect(service.notificationsEffectivelyOn, isFalse);
      expect(service.needsBrowserPermission, isFalse);
      expect(service.shouldShowPermissionCta, isFalse);
      await service.dispose();
    });

    test('native (isWeb=false) → effectivelyOn по prefs-флагу', () async {
      final service = await _service(
        FakeBridge(permission: BrowserNotificationPermissionStatus.unsupported),
        isWeb: false,
      );
      // На native флаг по умолчанию true → «включено».
      expect(service.notificationsEffectivelyOn, isTrue);
      expect(service.needsBrowserPermission, isFalse);
      expect(service.browserPushUnsupported, isFalse);
      await service.dispose();
    });
  });

  group('N3: iOS вне PWA', () {
    test('iOS non-standalone → add-to-home, без needsBrowserPermission',
        () async {
      final service = await _service(FakeBridge(
        permission: BrowserNotificationPermissionStatus.defaultState,
        iosWeb: true,
        standalone: false,
      ));
      expect(service.iosNeedsStandaloneForPush, isTrue);
      expect(service.browserPushUnsupported, isTrue);
      expect(service.needsBrowserPermission, isFalse);
      // CTA показываем (через iosNeeds), но это «добавьте на Домой».
      expect(service.shouldShowPermissionCta, isTrue);
      await service.dispose();
    });

    test('iOS установлен как PWA (standalone) → обычный поток запроса',
        () async {
      final service = await _service(FakeBridge(
        permission: BrowserNotificationPermissionStatus.defaultState,
        iosWeb: true,
        standalone: true,
      ));
      expect(service.iosNeedsStandaloneForPush, isFalse);
      expect(service.needsBrowserPermission, isTrue);
      await service.dispose();
    });
  });

  group('запрос только по жесту', () {
    test('чтение состояния НЕ вызывает requestPermission', () async {
      final bridge = FakeBridge(
        permission: BrowserNotificationPermissionStatus.defaultState,
      );
      final service = await _service(bridge);
      // Просто читаем геттеры — никаких запросов.
      service.needsBrowserPermission;
      service.shouldShowPermissionCta;
      service.notificationsEffectivelyOn;
      expect(bridge.requestPermissionCalls, 0);
      await service.dispose();
    });

    test('setNotificationsEnabled(true, prompt) — единственный запрос (жест)',
        () async {
      final bridge = FakeBridge(
        permission: BrowserNotificationPermissionStatus.defaultState,
      );
      final service = await _service(bridge);
      final ok = await service.setNotificationsEnabled(
        true,
        promptForBrowserPermission: true,
      );
      expect(bridge.requestPermissionCalls, 1);
      expect(ok, isTrue);
      expect(bridge.permission, BrowserNotificationPermissionStatus.granted);
      await service.dispose();
    });
  });

  group('CTA гасится после ответа/закрытия', () {
    test('после grant → CTA скрыт (permission != default)', () async {
      final bridge = FakeBridge(
        permission: BrowserNotificationPermissionStatus.defaultState,
      );
      final service = await _service(bridge);
      expect(service.shouldShowPermissionCta, isTrue);
      await service.setNotificationsEnabled(true,
          promptForBrowserPermission: true);
      expect(service.shouldShowPermissionCta, isFalse);
      await service.dispose();
    });

    test('после deny → CTA скрыт', () async {
      final bridge = FakeBridge(
        permission: BrowserNotificationPermissionStatus.denied,
      );
      final service = await _service(bridge);
      // denied — needs уже false, CTA не показываем.
      expect(service.shouldShowPermissionCta, isFalse);
      await service.dispose();
    });

    test('dismiss → CTA скрыт навсегда (флаг в prefs)', () async {
      final bridge = FakeBridge(
        permission: BrowserNotificationPermissionStatus.defaultState,
      );
      final service = await _service(bridge);
      expect(service.shouldShowPermissionCta, isTrue);
      await service.dismissNotificationCta();
      expect(service.isNotificationCtaDismissed, isTrue);
      expect(service.shouldShowPermissionCta, isFalse);
      await service.dispose();
    });

    test('dismiss переживает пересоздание сервиса (тот же prefs)', () async {
      final prefs = await SharedPreferences.getInstance();
      final first = await CustomApiNotificationService.create(
        preferences: prefs,
        browserNotificationBridge: FakeBridge(),
        isWeb: true,
      );
      await first.dismissNotificationCta();
      await first.dispose();

      final second = await CustomApiNotificationService.create(
        preferences: prefs,
        browserNotificationBridge: FakeBridge(),
        isWeb: true,
      );
      expect(second.isNotificationCtaDismissed, isTrue);
      expect(second.shouldShowPermissionCta, isFalse);
      await second.dispose();
    });
  });
}
