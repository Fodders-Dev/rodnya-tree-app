import '../models/extended_network_slice.dart';

/// Phase 4 chunk 1 (PHASE-4-PROPOSAL.md §3.2): capability mixin
/// для `GET /v1/trees/:treeId/extended-network` endpoint'а.
///
/// Mirror'ит `IdentityConflictsCapableFamilyTreeService` /
/// `GraphPersonAccessCapableFamilyTreeService` pattern — старый
/// сервер без endpoint'а просто не implements этот mixin, UI
/// gracefully disable'ит mode toggle с tooltip'ом «Обновите
/// приложение».
abstract class ExtendedNetworkCapableFamilyTreeService {
  /// Запрос slice'а текущего viewer'а в его tree'е.
  ///
  /// [maxHops] clamped server-side к **2..4** (== privacy fence
  /// `_connectedVisibilityMaxHops`, DECISIONS.md 2026-05-12 Q6.A).
  /// Передача значения вне этого диапазона — defensive parsing
  /// поднимет до 2 либо опустит до 4.
  ///
  /// [includeAnonymous] — если false, anonymous person'ы (без
  /// привязанного user-аккаунта) исключаются из slice'а. Default
  /// true (anonymous'ы — часто main value Phase 4 view'а).
  ///
  /// [branchIds] — placeholder для cross-branch filtering (Phase
  /// 4.1+). v1 ignored unless explicit match с treeId.
  ///
  /// Возвращает `null` если viewer не имеет access (404/403) —
  /// graceful failure для capability detection.
  Future<ExtendedNetworkSlice?> getExtendedNetworkSlice({
    required String treeId,
    int maxHops = 4,
    bool includeAnonymous = true,
    List<String>? branchIds,
  });
}
