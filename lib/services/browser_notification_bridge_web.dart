import 'dart:async';
import 'dart:html' as html;

import 'browser_notification_bridge.dart';

class _HtmlBrowserNotificationBridge implements BrowserNotificationBridge {
  @override
  bool get isSupported => html.Notification.supported;

  @override
  BrowserNotificationPermissionStatus get permissionStatus =>
      _permissionFromRaw(html.Notification.permission ?? 'default');

  @override
  Future<BrowserNotificationPermissionStatus> requestPermission({
    bool prompt = true,
  }) async {
    if (!isSupported) {
      return BrowserNotificationPermissionStatus.unsupported;
    }
    if (!prompt) {
      return permissionStatus;
    }

    final rawPermission = await html.Notification.requestPermission();
    return _permissionFromRaw(rawPermission);
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? tag,
    void Function()? onClick,
  }) async {
    if (!isSupported ||
        permissionStatus != BrowserNotificationPermissionStatus.granted) {
      return;
    }

    final notification = html.Notification(
      title,
      body: body,
      tag: tag,
    );

    StreamSubscription<html.Event>? clickSubscription;
    clickSubscription = notification.onClick.listen((_) {
      onClick?.call();
      notification.close();
      unawaited(clickSubscription?.cancel());
    });

    unawaited(
      Future<void>.delayed(const Duration(seconds: 8), () {
        notification.close();
        unawaited(clickSubscription?.cancel());
      }),
    );
  }

  BrowserNotificationPermissionStatus _permissionFromRaw(String rawValue) {
    switch (rawValue) {
      case 'granted':
        return BrowserNotificationPermissionStatus.granted;
      case 'denied':
        return BrowserNotificationPermissionStatus.denied;
      case 'default':
        return BrowserNotificationPermissionStatus.defaultState;
      default:
        return BrowserNotificationPermissionStatus.unsupported;
    }
  }
}

BrowserNotificationBridge createBrowserNotificationBridgeImpl() =>
    _HtmlBrowserNotificationBridge();
