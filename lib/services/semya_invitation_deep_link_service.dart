// Ship FE3b (2026-05-28): семя invitation deep-link token persist.
//
// Complements FE9 wizard auto-detect (3eaa643) — FE9 surfaces pending
// invitations через GET /v1/me/pending-invitations endpoint when user
// reaches welcome step. FE3b adds DIRECT entry path: user clicks
// https://rodnya-tree.ru/invite/{token} from email/chat → app opens →
// /invite/{token} route → этот service handles persistence + accept.
//
// Pre-login persistence rationale — mirror legacy InvitationService
// pattern (lib/services/invitation_service.dart). User flow:
//
//   1. User taps deep link от email на phone WITHOUT app open
//   2. Android opens app via verified App Link (/invite/{token})
//   3. /invite/:token route guard sees user logged out, persists
//      token, redirects к /login?from=/invite/{token}
//   4. After login, router re-resolves /invite/{token} с user
//      authed → service.acceptInvitation(token) → snackbar →
//      navigate к /
//
// Key difference vs legacy InvitationService — token is single capability
// secret (vs treeId + personId pair). Service exposes simple persist /
// read / clear API instead of full pair management.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SemyaInvitationDeepLinkService extends ChangeNotifier {
  static final SemyaInvitationDeepLinkService _instance =
      SemyaInvitationDeepLinkService._internal();
  factory SemyaInvitationDeepLinkService() => _instance;
  SemyaInvitationDeepLinkService._internal() {
    _loadFuture = _restoreFromDisk();
  }

  /// Test-only constructor — allows isolated instances per test случай.
  /// Production code uses singleton via factory.
  @visibleForTesting
  SemyaInvitationDeepLinkService.forTest() {
    _loadFuture = _restoreFromDisk();
  }

  static const String _tokenKey = 'pending_semya_invitation_token_v1';

  String? _pendingToken;
  Future<void>? _loadFuture;

  /// Pending invitation token persisted across OAuth redirects / cold
  /// starts. Null когда no deep link landed либо token consumed.
  String? get pendingToken => _pendingToken;
  bool get hasPendingToken => _pendingToken != null && _pendingToken!.isNotEmpty;

  /// Await initial disk read at cold start. Idempotent — subsequent
  /// awaits return completed Future. Used by router guard перед
  /// route-decision logic.
  Future<void> get ready => _loadFuture ?? Future.value();

  Future<void> _restoreFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final restored = prefs.getString(_tokenKey);
      if (restored != null && restored.isNotEmpty) {
        // RAM-set token wins — guard may have set token синхронно
        // ПЕРЕД _restoreFromDisk завершился. Respect freshest.
        if (_pendingToken == null) {
          _pendingToken = restored;
          debugPrint(
            '[SemyaInvitationDeepLinkService] Restored token from disk',
          );
          notifyListeners();
        }
      }
    } catch (error) {
      debugPrint(
        '[SemyaInvitationDeepLinkService] disk restore failed: $error',
      );
    }
  }

  void setPendingToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return;
    debugPrint(
      '[SemyaInvitationDeepLinkService] Setting pending token (length=${trimmed.length})',
    );
    _pendingToken = trimmed;
    notifyListeners();
    unawaited(_persistToDisk(trimmed));
  }

  Future<void> _persistToDisk(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
    } catch (error) {
      debugPrint(
        '[SemyaInvitationDeepLinkService] persist failed: $error',
      );
    }
  }

  /// Consume + clear. Returns previous token if set. Used by post-login
  /// auto-accept hook — atomic «read once» semantics ensure single
  /// accept attempt even если method invoked multiple times (e.g.,
  /// race between router guard + home screen mount).
  String? consumePendingToken() {
    final token = _pendingToken;
    if (token == null) return null;
    debugPrint('[SemyaInvitationDeepLinkService] Consuming pending token');
    _pendingToken = null;
    notifyListeners();
    unawaited(_clearOnDisk());
    return token;
  }

  void clearPendingToken() {
    if (_pendingToken == null) return;
    _pendingToken = null;
    notifyListeners();
    unawaited(_clearOnDisk());
  }

  Future<void> _clearOnDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
    } catch (error) {
      debugPrint(
        '[SemyaInvitationDeepLinkService] disk clear failed: $error',
      );
    }
  }
}
