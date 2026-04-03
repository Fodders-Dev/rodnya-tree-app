import 'package:flutter/foundation.dart';

import 'browser_notification_bridge_stub.dart'
    if (dart.library.html) 'browser_notification_bridge_web.dart';

enum BrowserNotificationPermissionStatus {
  granted,
  denied,
  defaultState,
  unsupported,
}

abstract class BrowserNotificationBridge {
  bool get isSupported;
  BrowserNotificationPermissionStatus get permissionStatus;

  Future<BrowserNotificationPermissionStatus> requestPermission({
    bool prompt = true,
  });

  Future<void> showNotification({
    required String title,
    required String body,
    String? tag,
    VoidCallback? onClick,
  });
}

BrowserNotificationBridge createBrowserNotificationBridge() =>
    createBrowserNotificationBridgeImpl();
