// lib/services/invitation_service.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Хранит данные приглашения, пришедшего по deep-link
/// `https://rodnya-tree.ru/#/invite?treeId=X&personId=Y`, между
/// вкладкой переходов «гость → /login → авторизация → /».
///
/// Раньше состояние жило только в RAM. Это работало для парольного
/// логина (тот же SPA-instance в браузере), но ломалось:
///
///   * При OAuth-логине (Google / VK ID / MAX / Telegram) браузер
///     уходит на сторонний домен и возвращается полным reload — Dart
///     state wipe'ается, pendingTreeId теряется, гард на следующем
///     заходе видит пусто, привязка `linkPersonToUser` не вызывается.
///   * При входе в Telegram WebView (как у Степы — пример из жизни),
///     где встроенный браузер периодически релоадит вкладку.
///   * При cold-restart мобильного приложения сразу после клика
///     по ссылке.
///
/// Фикс: persist через SharedPreferences. На вебе это localStorage,
/// на мобильных — нативный preferences-стор. Запись маленькая (две
/// uuid-строки), переживает любой reload и cold start.
///
/// `ready` — Future которую вызывающий код может await'ить, чтобы
/// гарантированно получить состояние с диска до того, как читать
/// `hasPendingInvitation`. На практике гард в роутере всё равно
/// вызывает `setPendingInvitation` синхронно из URL, так что на
/// fresh-load сценарии ready не критичен — но важен для проверок
/// после OAuth-возврата, где гард первым делом смотрит «не было ли
/// чего-то ещё в polls».
class InvitationService extends ChangeNotifier {
  static final InvitationService _instance = InvitationService._internal();
  factory InvitationService() => _instance;
  InvitationService._internal() {
    _loadFuture = _restoreFromDisk();
  }

  static const String _treeIdKey = 'pending_invitation_tree_id_v1';
  static const String _personIdKey = 'pending_invitation_person_id_v1';

  String? _pendingTreeId;
  String? _pendingPersonId;
  Future<void>? _loadFuture;
  final StreamController<InvitationProcessOutcome> _outcomesController =
      StreamController<InvitationProcessOutcome>.broadcast();

  String? get pendingTreeId => _pendingTreeId;
  String? get pendingPersonId => _pendingPersonId;

  bool get hasPendingInvitation =>
      _pendingTreeId != null && _pendingPersonId != null;

  /// Outcome stream: каждый завершённый POST на
  /// `/v1/invitations/pending/process` (успешный или нет) кладёт в
  /// этот стрим один [InvitationProcessOutcome]. UI подписывается
  /// в main.dart и показывает snackbar — раньше всё глушилось в
  /// `catch (_) {}` и юзер не понимал, почему ссылка как будто
  /// «ничего не сделала».
  Stream<InvitationProcessOutcome> get outcomes =>
      _outcomesController.stream;

  /// Awaitable hand-off: ждёт первого чтения из persistent storage
  /// при холодном старте. Идемпотентный — повторные await
  /// возвращают завершённый Future.
  Future<void> get ready => _loadFuture ?? Future.value();

  void emitOutcome(InvitationProcessOutcome outcome) {
    if (_outcomesController.isClosed) return;
    _outcomesController.add(outcome);
  }

  Future<void> _restoreFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final restoredTreeId = prefs.getString(_treeIdKey);
      final restoredPersonId = prefs.getString(_personIdKey);
      if (restoredTreeId != null &&
          restoredTreeId.isNotEmpty &&
          restoredPersonId != null &&
          restoredPersonId.isNotEmpty) {
        // Заметим: если в RAM уже есть свежий setPendingInvitation
        // (вызванный URL-гардом до того, как _restoreFromDisk
        // дочитался), уважаем RAM — он гарантированно свежее, чем
        // данные с диска прошлой сессии.
        if (_pendingTreeId == null && _pendingPersonId == null) {
          _pendingTreeId = restoredTreeId;
          _pendingPersonId = restoredPersonId;
          debugPrint(
            '[InvitationService] Restored pending invitation from disk: '
            'treeId=$restoredTreeId, personId=$restoredPersonId',
          );
          notifyListeners();
        }
      }
    } catch (error) {
      debugPrint('[InvitationService] Failed to restore from disk: $error');
    }
  }

  void setPendingInvitation({
    required String treeId,
    required String personId,
  }) {
    debugPrint(
      '[InvitationService] Setting pending invitation: '
      'treeId=$treeId, personId=$personId',
    );
    _pendingTreeId = treeId;
    _pendingPersonId = personId;
    notifyListeners();
    unawaited(_persistToDisk(treeId: treeId, personId: personId));
  }

  Future<void> _persistToDisk({
    required String treeId,
    required String personId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_treeIdKey, treeId);
      await prefs.setString(_personIdKey, personId);
    } catch (error) {
      // Не валим основной поток — даже без диска RAM-состояние
      // даст шанс единичного входа без OAuth-перезагрузки.
      debugPrint('[InvitationService] Failed to persist to disk: $error');
    }
  }

  void clearPendingInvitation() {
    debugPrint('[InvitationService] Clearing pending invitation.');
    _pendingTreeId = null;
    _pendingPersonId = null;
    notifyListeners();
    unawaited(_clearOnDisk());
  }

  Future<void> _clearOnDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_treeIdKey);
      await prefs.remove(_personIdKey);
    } catch (error) {
      debugPrint('[InvitationService] Failed to clear on disk: $error');
    }
  }
}

/// Описывает результат одного вызова
/// `processPendingInvitation` для UI.
class InvitationProcessOutcome {
  const InvitationProcessOutcome.success({
    required this.treeId,
    required this.treeName,
    required this.personId,
  })  : isSuccess = true,
        errorCode = null,
        errorMessage = null;

  const InvitationProcessOutcome.failure({
    required this.errorCode,
    required this.errorMessage,
    this.treeId,
    this.personId,
  })  : isSuccess = false,
        treeName = null;

  final bool isSuccess;
  final String? treeId;
  final String? treeName;
  final String? personId;
  final String? errorCode;
  final String? errorMessage;
}
