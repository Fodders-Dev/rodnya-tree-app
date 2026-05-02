import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Per-device, per-install identifier for binding sessions to a physical
/// device.  Persisted in SharedPreferences so that a single device keeps the
/// same identity across app restarts; this lets the backend recognise
/// re-logins as "same device" and surface a stable entry in the active-sessions
/// list.
class ClientInstanceId {
  ClientInstanceId._();

  static const String _storageKey = 'rodnya.client_instance_id.v1';

  static String? _cachedValue;
  static Future<String>? _initFuture;

  /// Fast accessor — returns the cached id once [ensureInitialized] has run.
  /// Falls back to a transient uuid only if storage is not yet warm; the
  /// caller is expected to await [ensureInitialized] during app boot.
  static String get current {
    return _cachedValue ??= const Uuid().v4();
  }

  /// Loads the persisted id from SharedPreferences, generating one on first
  /// launch.  Idempotent and concurrency-safe.
  static Future<String> ensureInitialized() {
    return _initFuture ??= _loadOrCreate();
  }

  static Future<String> _loadOrCreate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored != null && stored.isNotEmpty) {
        _cachedValue = stored;
        return stored;
      }
      final generated = const Uuid().v4();
      await prefs.setString(_storageKey, generated);
      _cachedValue = generated;
      return generated;
    } catch (error, stackTrace) {
      // If storage fails (e.g. unsupported platform during tests) fall back
      // to a session-scoped uuid so the app still works, but log it loudly.
      debugPrint('ClientInstanceId: storage init failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      final fallback = _cachedValue ?? const Uuid().v4();
      _cachedValue = fallback;
      return fallback;
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _cachedValue = null;
    _initFuture = null;
  }
}
