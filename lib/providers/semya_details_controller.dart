import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/semya_capable_family_tree_service.dart';
import '../backend/models/semya.dart';

/// Ship FE2 (2026-05-26): controller для семя details screen.
///
/// Loads semya details + memberships concurrently, exposes loading/
/// error/loaded state. Refresh is opt-in (FE9-10 auto-refresh
/// integration shipped separately).
///
/// Lifecycle: ChangeNotifier — caller wraps в ChangeNotifierProvider
/// либо ListenableBuilder. dispose() inherited.
class SemyaDetailsController with ChangeNotifier {
  /// Test-seam constructor — production uses GetIt resolution.
  SemyaDetailsController({
    required this.semyaId,
    SemyaCapableFamilyTreeService? service,
  }) : _injectedService = service;

  final String semyaId;
  final SemyaCapableFamilyTreeService? _injectedService;

  SemyaDetails? _details;
  List<SemyaMembership> _memberships = const <SemyaMembership>[];
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;
  // Ship FE8 (2026-05-27): per-row mutation guard — userId of row
  // currently in-flight для membership mutation. UI disables menu
  // while in set чтобы prevent double-clicks.
  final Set<String> _pendingMutations = <String>{};
  String? _mutationErrorMessage;

  SemyaDetails? get details => _details;
  List<SemyaMembership> get memberships => _memberships;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get errorMessage => _errorMessage;
  Set<String> get pendingMutations => Set.unmodifiable(_pendingMutations);

  /// Last membership mutation error message (non-null после неудачного
  /// updateMembership либо removeMembership call). UI surfaces через
  /// snackbar и calls [clearMutationError] после показа.
  String? get mutationErrorMessage => _mutationErrorMessage;

  /// Ship FE8: count active owners across current memberships. Used UI-
  /// side для last-owner gating (self-leave disabled когда caller is
  /// sole owner). Memberships list представляет snapshot после last
  /// load — fresh между mutations.
  int get activeOwnerCount =>
      _memberships.where((m) => m.role == SemyaRole.owner).length;

  bool isPending(String userId) => _pendingMutations.contains(userId);

  void clearMutationError() {
    if (_mutationErrorMessage == null) return;
    _mutationErrorMessage = null;
    notifyListeners();
  }

  /// True когда backend service capable (Phase B endpoints exposed).
  bool get isCapable => _resolveService() != null;

  SemyaCapableFamilyTreeService? _resolveService() {
    if (_injectedService != null) return _injectedService;
    if (!GetIt.I.isRegistered<FamilyTreeServiceInterface>()) return null;
    final service = GetIt.I<FamilyTreeServiceInterface>();
    if (service is SemyaCapableFamilyTreeService) {
      return service as SemyaCapableFamilyTreeService;
    }
    return null;
  }

  /// Loads details + memberships в parallel. Idempotent — safe call
  /// multiple times.
  Future<void> load() async {
    final service = _resolveService();
    if (service == null) {
      _hasLoaded = true;
      notifyListeners();
      return;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        service.findSemyaById(semyaId),
        service.listMembershipsForSemya(semyaId),
      ]);
      final fetchedDetails = results[0] as SemyaDetails?;
      final fetchedMembers = results[1] as List<SemyaMembership>;
      _details = fetchedDetails;
      _memberships = List<SemyaMembership>.unmodifiable(fetchedMembers);
      _hasLoaded = true;
      if (fetchedDetails == null) {
        // findSemyaById returned null — likely 404 либо forbidden.
        // Не throwing — controller surface'ит «не доступно» state.
        _errorMessage = 'Не удалось загрузить семью';
      }
    } catch (error) {
      _errorMessage = _describeError(error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  /// Ship FE8 (2026-05-27): change membership role либо invite-grant.
  /// On success refreshes memberships list. On error sets
  /// [mutationErrorMessage] для UI snackbar surface — caller invokes
  /// [clearMutationError] после показа.
  ///
  /// At least one of [role] либо [hasInviteGrant] должен быть non-null
  /// — service layer surfaces 400 INVALID_INPUT otherwise.
  Future<bool> updateMemberRoleOrGrant({
    required String userId,
    SemyaRole? role,
    bool? hasInviteGrant,
  }) async {
    final service = _resolveService();
    if (service == null) {
      _mutationErrorMessage = 'Управление участниками недоступно';
      notifyListeners();
      return false;
    }
    _pendingMutations.add(userId);
    _mutationErrorMessage = null;
    notifyListeners();
    try {
      await service.updateMembership(
        semyaId: semyaId,
        userId: userId,
        role: role,
        hasInviteGrant: hasInviteGrant,
      );
      _pendingMutations.remove(userId);
      // Refresh для consistent state. updateMembership returns updated
      // row но membership list might have дополнительные ripple
      // effects (например, hasInviteGrant auto-cleared при demote из
      // editor). Full reload — safest.
      await load();
      return true;
    } catch (error) {
      _pendingMutations.remove(userId);
      _mutationErrorMessage = _describeError(error);
      notifyListeners();
      return false;
    }
  }

  /// Ship FE8: kick member либо self-leave (backend infers from
  /// actor vs target). Returns SemyaMembershipRemoveResult on success
  /// (wasSelfLeave flag lets UI route к pop-screen vs refresh-list).
  /// На error sets mutationErrorMessage.
  Future<SemyaMembershipRemoveResult?> removeMember({
    required String userId,
  }) async {
    final service = _resolveService();
    if (service == null) {
      _mutationErrorMessage = 'Управление участниками недоступно';
      notifyListeners();
      return null;
    }
    _pendingMutations.add(userId);
    _mutationErrorMessage = null;
    notifyListeners();
    try {
      final result = await service.removeMembership(
        semyaId: semyaId,
        userId: userId,
      );
      _pendingMutations.remove(userId);
      if (!result.wasSelfLeave) {
        // Caller will refresh для kick case. Self-leave UI обычно
        // pops screen, чтобы refresh бессмыслен.
        await load();
      } else {
        notifyListeners();
      }
      return result;
    } catch (error) {
      _pendingMutations.remove(userId);
      _mutationErrorMessage = _describeError(error);
      notifyListeners();
      return null;
    }
  }

  String _describeError(Object error) {
    if (error is SemyaError) return error.message;
    return 'Не удалось загрузить данные';
  }
}
