import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'browser_notification_bridge.dart';

class _HtmlBrowserNotificationBridge implements BrowserNotificationBridge {
  @override
  bool get isSupported => web.window.has('Notification');

  @override
  bool get isPushSupported =>
      isSupported &&
      web.window.isSecureContext &&
      web.window.navigator.has('serviceWorker');

  @override
  bool get isIosWeb {
    final ua = web.window.navigator.userAgent.toLowerCase();
    if (ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod')) {
      return true;
    }
    // iPadOS 13+ маскируется под десктопный Mac — отличаем по тач-вводу.
    final isMac = ua.contains('macintosh');
    final maxTouchPoints = web.window.navigator.maxTouchPoints;
    return isMac && maxTouchPoints > 1;
  }

  @override
  bool get isStandalone {
    // navigator.standalone — legacy iOS Safari флаг установленного PWA.
    final navStandalone = (web.window.navigator as JSObject)
        .getProperty<JSAny?>('standalone'.toJS);
    if (navStandalone.isA<JSBoolean>() && (navStandalone as JSBoolean).toDart) {
      return true;
    }
    try {
      return web.window.matchMedia('(display-mode: standalone)').matches;
    } catch (_) {
      return false;
    }
  }

  @override
  BrowserNotificationPermissionStatus get permissionStatus => isSupported
      ? _permissionFromRaw(web.Notification.permission)
      : BrowserNotificationPermissionStatus.unsupported;

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

    final rawPermission =
        (await web.Notification.requestPermission().toDart).toDart;
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

    final options = tag != null
        ? web.NotificationOptions(body: body, tag: tag)
        : web.NotificationOptions(body: body);
    final notification = web.Notification(title, options);

    notification.onclick = ((web.Event _) {
      onClick?.call();
      notification.close();
    }).toJS;

    unawaited(
      Future<void>.delayed(const Duration(seconds: 8), () {
        notification.close();
      }),
    );
  }

  @override
  Future<BrowserPushSubscription?> subscribeToPush({
    required String publicKey,
  }) async {
    if (!isPushSupported ||
        permissionStatus != BrowserNotificationPermissionStatus.granted) {
      return null;
    }

    final registration = await web.window.navigator.serviceWorker
        .register(
          '/push/push-sw.js'.toJS,
          web.RegistrationOptions(scope: '/push/'),
        )
        .toDart;

    var subscription = await registration.pushManager.getSubscription().toDart;
    subscription ??= await registration.pushManager
        .subscribe(
          web.PushSubscriptionOptionsInit(
            userVisibleOnly: true,
            applicationServerKey: _decodeBase64Url(publicKey).toJS,
          ),
        )
        .toDart;

    final serialized = subscription.toJSON().dartify();
    final token = jsonEncode(serialized);
    return BrowserPushSubscription(token: token);
  }

  @override
  Future<void> unsubscribeFromPush() async {
    if (!isPushSupported) {
      return;
    }

    final registration = await web.window.navigator.serviceWorker
        .getRegistration('/push/')
        .toDart;
    if (registration == null) {
      return;
    }

    final subscription =
        await registration.pushManager.getSubscription().toDart;
    if (subscription == null) {
      return;
    }

    await subscription.unsubscribe().toDart;
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

  Uint8List _decodeBase64Url(String value) {
    final normalized = value
        .replaceAll('-', '+')
        .replaceAll('_', '/')
        .padRight((value.length + 3) & ~3, '=');
    return Uint8List.fromList(base64Decode(normalized));
  }
}

BrowserNotificationBridge createBrowserNotificationBridgeImpl() =>
    _HtmlBrowserNotificationBridge();
