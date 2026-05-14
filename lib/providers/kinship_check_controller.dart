import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend/interfaces/kinship_check_capable_family_tree_service.dart';
import '../backend/models/kinship_check.dart';

/// Phase 6 chunk 3 (PHASE-6-PROPOSAL.md §2.4-§2.6 + §3.1): «мы
/// родственники?» discover flow controller.
///
/// Holds:
///   • received / issued lists (pending + recent terminal — for
///     surfacing «ваши запросы»).
///   • outgoing 4-step flow state (DiscoverStep enum).
///   • response (accept/reject) submission state.
///
/// Service nullable — caller (screen) detects `isCapable=false` через
/// router либо capability check + falls back gracefully.
class KinshipCheckController extends ChangeNotifier {
  KinshipCheckController({
    required KinshipCheckCapableFamilyTreeService? service,
  }) : _service = service;

  final KinshipCheckCapableFamilyTreeService? _service;

  // ── Outgoing flow state ────────────────────────────────────────

  DiscoverStep _step = DiscoverStep.start;
  String? _selectedTargetUserId;
  String? _selectedTargetDisplayName;
  KinshipCheck? _submittedCheck;

  // ── Lists state ────────────────────────────────────────────────

  List<KinshipCheck> _received = const <KinshipCheck>[];
  List<KinshipCheck> _issued = const <KinshipCheck>[];
  bool _isLoadingLists = false;

  // ── Submission / response state ────────────────────────────────

  bool _isSubmitting = false;
  bool _isResponding = false;
  String? _respondingCheckId;
  String? _error;

  // ── Getters ────────────────────────────────────────────────────

  bool get isCapable => _service != null;
  DiscoverStep get step => _step;
  String? get selectedTargetUserId => _selectedTargetUserId;
  String? get selectedTargetDisplayName => _selectedTargetDisplayName;
  KinshipCheck? get submittedCheck => _submittedCheck;
  List<KinshipCheck> get received => List<KinshipCheck>.unmodifiable(_received);
  List<KinshipCheck> get issued => List<KinshipCheck>.unmodifiable(_issued);
  bool get isLoadingLists => _isLoadingLists;
  bool get isSubmitting => _isSubmitting;
  bool get isResponding => _isResponding;
  String? get respondingCheckId => _respondingCheckId;
  String? get error => _error;

  /// Pending received only (used для top banner либо tab badge).
  List<KinshipCheck> get pendingReceived => _received
      .where((c) => c.status == KinshipCheckStatus.pending)
      .toList(growable: false);

  // ── Lists management ───────────────────────────────────────────

  /// Hydrate both received + issued lists. Called on screen mount
  /// либо после respond/submit для refresh.
  Future<void> refresh() async {
    final service = _service;
    if (service == null) return;
    _isLoadingLists = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait<List<KinshipCheck>>([
        service.listReceivedKinshipChecks(),
        service.listIssuedKinshipChecks(),
      ]);
      _received = results[0];
      _issued = results[1];
    } catch (e) {
      _error = '$e';
    } finally {
      _isLoadingLists = false;
      notifyListeners();
    }
  }

  // ── Outgoing flow transitions ──────────────────────────────────

  void selectTarget({
    required String userId,
    required String displayName,
  }) {
    if (userId.isEmpty) return;
    _selectedTargetUserId = userId;
    _selectedTargetDisplayName = displayName;
    _step = DiscoverStep.confirming;
    _error = null;
    notifyListeners();
  }

  void backToSearch() {
    _selectedTargetUserId = null;
    _selectedTargetDisplayName = null;
    _step = DiscoverStep.start;
    _error = null;
    notifyListeners();
  }

  void reset() {
    _selectedTargetUserId = null;
    _selectedTargetDisplayName = null;
    _submittedCheck = null;
    _step = DiscoverStep.start;
    _error = null;
    notifyListeners();
  }

  /// Submit pending kinship check. Transitions step → sent on
  /// success. Returns true on success.
  Future<bool> submitCheck() async {
    final service = _service;
    final targetId = _selectedTargetUserId;
    if (service == null || targetId == null || targetId.isEmpty) {
      _error = 'Не выбран получатель запроса';
      notifyListeners();
      return false;
    }
    _isSubmitting = true;
    _error = null;
    notifyListeners();
    try {
      final result = await service.createKinshipCheck(targetUserId: targetId);
      if (result == null) {
        _error = 'Не удалось отправить запрос. Попробуйте ещё раз.';
        _isSubmitting = false;
        notifyListeners();
        return false;
      }
      _submittedCheck = result.check;
      _step = DiscoverStep.sent;
      _isSubmitting = false;
      notifyListeners();
      // Fire-and-forget refresh of issued list — keeps history view
      // current, но не блокирует UI flow.
      unawaited(refresh());
      return true;
    } on KinshipCheckError catch (e) {
      _error = e.message;
      _isSubmitting = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = '$e';
      _isSubmitting = false;
      notifyListeners();
      return false;
    }
  }

  // ── Bilateral consent: respond to received ─────────────────────

  /// Target accepts либо rejects. On accept — backend computes BFS,
  /// returned check carries `result`. On reject — initiator получает
  /// «отклонил» notification.
  ///
  /// Returns the updated check (с result populated если accepted).
  Future<KinshipCheck?> respondToCheck({
    required String checkId,
    required KinshipCheckDecision decision,
  }) async {
    final service = _service;
    if (service == null || checkId.isEmpty) return null;
    _isResponding = true;
    _respondingCheckId = checkId;
    _error = null;
    notifyListeners();
    try {
      final updated = await service.respondToKinshipCheck(
        checkId: checkId,
        decision: decision,
      );
      if (updated == null) {
        _error = 'Не удалось обработать ответ. Попробуйте ещё раз.';
        _isResponding = false;
        _respondingCheckId = null;
        notifyListeners();
        return null;
      }
      // Optimistic local update — replace в received list.
      _received = _received
          .map((c) => c.id == checkId ? updated : c)
          .toList(growable: false);
      _isResponding = false;
      _respondingCheckId = null;
      notifyListeners();
      // Background refresh — keeps both lists в sync.
      unawaited(refresh());
      return updated;
    } on KinshipCheckError catch (e) {
      _error = e.message;
      _isResponding = false;
      _respondingCheckId = null;
      notifyListeners();
      return null;
    } catch (e) {
      _error = '$e';
      _isResponding = false;
      _respondingCheckId = null;
      notifyListeners();
      return null;
    }
  }

  /// Find an issued check by id (used когда user navigates back в
  /// сёт result screen).
  KinshipCheck? findIssuedById(String checkId) {
    for (final c in _issued) {
      if (c.id == checkId) return c;
    }
    return null;
  }

  /// Find a received check by id.
  KinshipCheck? findReceivedById(String checkId) {
    for (final c in _received) {
      if (c.id == checkId) return c;
    }
    return null;
  }
}

/// Outgoing 4-step flow state per PHASE-6-PROPOSAL.md §2.4 wireframe.
/// `result` step shown when [KinshipCheckController.submittedCheck]
/// transitions из pending → accepted/rejected (через push либо
/// background poll).
enum DiscoverStep {
  /// Search target user.
  start,

  /// Preview chosen target + «Отправить запрос?» CTA.
  confirming,

  /// «Запрос отправлен» — pending response.
  sent,

  /// «Вы родственники!» либо «не нашли связи» — has result.
  result,
}
