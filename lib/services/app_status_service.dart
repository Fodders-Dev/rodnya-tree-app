import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

enum AppStatusIssueType { network, sessionExpired, service }

class AppStatusIssue {
  const AppStatusIssue({
    required this.type,
    required this.message,
    this.retryable = true,
  });

  final AppStatusIssueType type;
  final String message;
  final bool retryable;

  @override
  bool operator ==(Object other) {
    return other is AppStatusIssue &&
        other.type == type &&
        other.message == message &&
        other.retryable == retryable;
  }

  @override
  int get hashCode => Object.hash(type, message, retryable);
}

class AppStatusService extends ChangeNotifier {
  AppStatusService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  StreamSubscription<dynamic>? _connectivitySubscription;

  bool _initialized = false;
  bool _isOffline = false;
  AppStatusIssue? _issue;
  int _retryToken = 0;

  bool get isOffline => _isOffline;
  AppStatusIssue? get issue => _issue;
  int get retryToken => _retryToken;
  bool get hasVisibleStatus => _isOffline || _issue != null;
  bool get hasSessionIssue => _issue?.type == AppStatusIssueType.sessionExpired;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    final initialResults = await _connectivity.checkConnectivity();
    _applyConnectivityState(initialResults);
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(_applyConnectivityState);
  }

  void reportSessionExpired([
    String message = 'Сессия истекла. Войдите снова.',
  ]) {
    _setIssue(
      AppStatusIssue(
        type: AppStatusIssueType.sessionExpired,
        message: message,
        retryable: false,
      ),
    );
  }

  void reportNetworkIssue([
    String message = 'Нет соединения. Проверьте интернет и попробуйте ещё раз.',
  ]) {
    _setIssue(
      AppStatusIssue(
        type: AppStatusIssueType.network,
        message: message,
      ),
    );
  }

  void reportServiceIssue(
    String message, {
    bool retryable = true,
  }) {
    final normalizedMessage = message.trim();
    if (normalizedMessage.isEmpty) {
      return;
    }
    _setIssue(
      AppStatusIssue(
        type: AppStatusIssueType.service,
        message: normalizedMessage,
        retryable: retryable,
      ),
    );
  }

  void reportError(
    Object error, {
    String? fallbackMessage,
    bool retryable = true,
  }) {
    final normalized = error.toString().toLowerCase();
    if (_looksLikeSessionIssue(normalized)) {
      reportSessionExpired();
      return;
    }
    if (_looksLikeNetworkIssue(normalized)) {
      reportNetworkIssue(
        fallbackMessage ??
            'Не удалось связаться с сервером. Проверьте интернет и попробуйте ещё раз.',
      );
      return;
    }
    if (fallbackMessage != null && fallbackMessage.trim().isNotEmpty) {
      reportServiceIssue(
        fallbackMessage,
        retryable: retryable,
      );
    }
  }

  void clearIssue({bool keepSessionIssue = false}) {
    if (_issue == null) {
      return;
    }
    if (keepSessionIssue && hasSessionIssue) {
      return;
    }
    _issue = null;
    notifyListeners();
  }

  void clearSessionIssue() {
    if (!hasSessionIssue) {
      return;
    }
    _issue = null;
    notifyListeners();
  }

  void requestRetry() {
    _retryToken += 1;
    if (!hasSessionIssue && _issue != null) {
      _issue = null;
    }
    notifyListeners();
  }

  void _applyConnectivityState(dynamic rawValue) {
    final results = rawValue is List<ConnectivityResult>
        ? rawValue
        : <ConnectivityResult>[rawValue as ConnectivityResult];
    final nextOffline = results.isEmpty ||
        results.every((result) => result == ConnectivityResult.none);

    final shouldNotify = _isOffline != nextOffline ||
        (!nextOffline && _issue?.type == AppStatusIssueType.network);
    _isOffline = nextOffline;
    if (!nextOffline && _issue?.type == AppStatusIssueType.network) {
      _issue = null;
    }
    if (shouldNotify) {
      notifyListeners();
    }
  }

  void _setIssue(AppStatusIssue nextIssue) {
    if (_issue == nextIssue) {
      return;
    }
    _issue = nextIssue;
    notifyListeners();
  }

  bool _looksLikeSessionIssue(String message) {
    return message.contains('401') ||
        message.contains('403') ||
        message.contains('unauthorized') ||
        message.contains('session') ||
        message.contains('сесс') ||
        message.contains('expired');
  }

  bool _looksLikeNetworkIssue(String message) {
    return message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('connection refused') ||
        message.contains('connection reset') ||
        message.contains('network is unreachable') ||
        message.contains('timed out') ||
        message.contains('xmlhttprequest error') ||
        message.contains('clientexception');
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
