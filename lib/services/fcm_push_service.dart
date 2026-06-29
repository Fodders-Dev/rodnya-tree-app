import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class FcmPushService {
  FcmPushService({FirebaseMessaging? messaging})
      : _injectedMessaging = messaging;

  final FirebaseMessaging? _injectedMessaging;
  // Resolve FirebaseMessaging.instance LAZILY. Touching it in the constructor
  // throws a JS TypeError on WEB (Firebase isn't auto-initialized there the way
  // it is on Android via google-services), which crashed app startup for every
  // web user and — because startup_failure_policy matches 'typeerror' — was
  // mis-shown as «Сохранённая сессия больше не подходит». Only the Android-gated
  // methods ever read this getter, so web never reaches it.
  FirebaseMessaging get _messaging =>
      _injectedMessaging ?? FirebaseMessaging.instance;
  final StreamController<String> _pushTokensController =
      StreamController<String>.broadcast();

  StreamSubscription<String>? _tokenSubscription;
  bool _initialized = false;

  static Future<FirebaseApp>? _firebaseInitialization;

  Stream<String> get pushTokens => _pushTokensController.stream;

  Future<void> startForegroundWarmup() async {
    if (!_isAndroidRuntime) {
      return;
    }
    await _ensureInitialized();
    unawaited(getFcmPushToken());
  }

  Future<String?> getFcmPushToken() async {
    if (!_isAndroidRuntime) {
      return null;
    }
    try {
      await _ensureInitialized();
      final token = (await _messaging.getToken())?.trim();
      if (token == null || token.isEmpty) {
        return null;
      }
      if (!_pushTokensController.isClosed) {
        _pushTokensController.add(token);
      }
      return token;
    } catch (error, stackTrace) {
      debugPrint('FCM token unavailable: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
    await _pushTokensController.close();
  }

  bool get _isAndroidRuntime =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }

    if (Firebase.apps.isEmpty) {
      await (_firebaseInitialization ??= Firebase.initializeApp());
    }
    _initialized = true;
    _ensureTokenListener();
  }

  void _ensureTokenListener() {
    if (_tokenSubscription != null) {
      return;
    }
    _tokenSubscription = _messaging.onTokenRefresh.listen((token) {
      final normalizedToken = token.trim();
      if (normalizedToken.isEmpty || _pushTokensController.isClosed) {
        return;
      }
      _pushTokensController.add(normalizedToken);
    }, onError: (Object error, StackTrace stackTrace) {
      debugPrint('FCM token refresh stream failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    });
  }
}
