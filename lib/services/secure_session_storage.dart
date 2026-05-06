import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Encryption-at-rest wrapper for Родня's session token blob.
///
/// Android: backed by `EncryptedSharedPreferences` (Jetpack Security)
/// using a key from the AndroidKeyStore — survives backup exclusion
/// and is unreadable with `adb pull` / `cat` even on rooted devices
/// without active session unlock.
///
/// iOS: backed by Keychain with `first_unlock` accessibility — same
/// physical security boundary as Apple's own apps.
///
/// Web: falls back to localStorage (still plaintext — there is no
/// Web crypto-keystore equivalent), so on web we keep the historic
/// SharedPreferences path. The wrapper degrades automatically.
///
/// One-shot migration: on first read after install/upgrade, the
/// wrapper reads the legacy SharedPreferences key, writes it into
/// secure storage, and removes the plaintext copy. Subsequent reads
/// skip the prefs hop.
class SecureSessionStorage {
  SecureSessionStorage({
    required SharedPreferences fallbackPreferences,
    FlutterSecureStorage? secureStorage,
    String legacyKey = 'custom_api_session_v1',
    String secureKey = 'custom_api_session_v2_secure',
  })  : _fallbackPreferences = fallbackPreferences,
        _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            ),
        _legacyKey = legacyKey,
        _secureKey = secureKey;

  final SharedPreferences _fallbackPreferences;
  final FlutterSecureStorage _secureStorage;
  final String _legacyKey;
  final String _secureKey;

  bool _legacyMigrationAttempted = false;

  /// True when the platform supports a real crypto-backed keystore.
  /// Web and unsupported targets fall back to plain SharedPreferences.
  bool get _useSecureBackend => !kIsWeb;

  Future<String?> read() async {
    if (!_useSecureBackend) {
      return _fallbackPreferences.getString(_legacyKey);
    }

    if (!_legacyMigrationAttempted) {
      _legacyMigrationAttempted = true;
      try {
        final fromLegacy = _fallbackPreferences.getString(_legacyKey);
        if (fromLegacy != null && fromLegacy.isNotEmpty) {
          // Already-stored secure value wins so we don't overwrite a
          // newer session with a stale backup-restored prefs value.
          final existingSecure = await _secureStorage.read(key: _secureKey);
          if (existingSecure == null || existingSecure.isEmpty) {
            await _secureStorage.write(key: _secureKey, value: fromLegacy);
          }
          await _fallbackPreferences.remove(_legacyKey);
        }
      } catch (error, stackTrace) {
        debugPrint(
          'SecureSessionStorage: legacy migration failed: '
          '$error\n$stackTrace',
        );
      }
    }

    try {
      return await _secureStorage.read(key: _secureKey);
    } catch (error, stackTrace) {
      debugPrint(
        'SecureSessionStorage: read failed, falling back to prefs: '
        '$error\n$stackTrace',
      );
      // Last-ditch: return whatever prefs still has so the user
      // doesn't get bounced to the login screen because of a
      // transient Keystore decoding error.
      return _fallbackPreferences.getString(_legacyKey);
    }
  }

  Future<void> write(String value) async {
    if (!_useSecureBackend) {
      await _fallbackPreferences.setString(_legacyKey, value);
      return;
    }
    try {
      await _secureStorage.write(key: _secureKey, value: value);
      // Belt-and-braces: clean any legacy plaintext entry that an
      // older build might have left behind even after migration ran
      // (e.g. user signs in again after first launch).
      await _fallbackPreferences.remove(_legacyKey);
    } catch (error, stackTrace) {
      debugPrint(
        'SecureSessionStorage: write failed, persisting to prefs: '
        '$error\n$stackTrace',
      );
      await _fallbackPreferences.setString(_legacyKey, value);
    }
  }

  Future<void> delete() async {
    if (!_useSecureBackend) {
      await _fallbackPreferences.remove(_legacyKey);
      return;
    }
    try {
      await _secureStorage.delete(key: _secureKey);
    } catch (error) {
      debugPrint('SecureSessionStorage: secure delete failed: $error');
    }
    // Always also clear the legacy key — protects against a
    // partial-migration state surviving across app restarts.
    await _fallbackPreferences.remove(_legacyKey);
  }
}
