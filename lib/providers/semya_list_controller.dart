import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/semya_capable_family_tree_service.dart';
import '../backend/models/semya.dart';

/// Phase B Ship FE1: семя list controller. Mirrors TreeProvider
/// pattern (ChangeNotifier + GetIt service resolution + persisted
/// selection через SharedPreferences).
///
/// Responsibilities (Ship FE1 scope):
///   * Load caller's список семей через GET /v1/me/semya
///   * Track selected семя id с SharedPreferences persistence
///   * Expose loading/error state для widgets
///   * refresh() для manual reload (push-triggered auto-refresh
///     integration deferred к Ship FE9-10)
///
/// NOT Ship FE1 (deferred):
///   * create/rename/delete семя — Ship FE2+
///   * Membership management — Ship FE2/FE8
///   * Hide filter / browse / pull — later ships
///   * Realtime hub event subscription для семя-mutated events —
///     Ship FE10 либо когда backend exposes new event type
class SemyaListController with ChangeNotifier {
  static const _selectedSemyaIdKey = 'phase_b_selected_semya_id';

  /// Test-seam constructor — production normally uses GetIt resolution.
  SemyaListController({SemyaCapableFamilyTreeService? service})
      : _injectedService = service;

  final SemyaCapableFamilyTreeService? _injectedService;

  List<Semya> _semyi = const <Semya>[];
  String? _selectedSemyaId;
  bool _isLoading = false;
  String? _errorMessage;
  bool _hasLoaded = false;

  /// Available семья for caller. Empty list когда нет membership
  /// (пользователь либо без семья yet — production migration
  /// Week 8 даст каждому «Моя семья», либо backend doesn't expose
  /// caps).
  List<Semya> get semyi => _semyi;

  /// Currently selected семя id, либо null если ни одна не выбрана.
  /// Persisted to SharedPreferences для survival across app restarts.
  String? get selectedSemyaId => _selectedSemyaId;

  /// Convenience: resolves selected семя object либо null.
  Semya? get selectedSemya {
    if (_selectedSemyaId == null) return null;
    for (final entry in _semyi) {
      if (entry.id == _selectedSemyaId) return entry;
    }
    return null;
  }

  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get errorMessage => _errorMessage;

  /// True когда backend exposes Phase B caps. False — UI fallback
  /// к legacy tree provider behavior (за feature flag default OFF).
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

  /// Initial load — fetches list + restores persisted selection.
  /// Idempotent: safe к call multiple times (subsequent calls re-fetch
  /// list, preserve current selection если still valid).
  Future<void> loadInitial() async {
    final prefs = await SharedPreferences.getInstance();
    final storedId = prefs.getString(_selectedSemyaIdKey);
    if (storedId != null && storedId.isNotEmpty) {
      _selectedSemyaId = storedId;
    }
    await refresh();
  }

  /// Manually re-fetch семя list. Preserves selection if id still
  /// present в new list; clears selection otherwise.
  Future<void> refresh() async {
    final service = _resolveService();
    if (service == null) {
      _hasLoaded = true;
      _semyi = const <Semya>[];
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final list = await service.listMySemya();
      _semyi = List<Semya>.unmodifiable(list);
      _hasLoaded = true;
      // Validate selection — clear если stale
      if (_selectedSemyaId != null) {
        final stillExists = _semyi.any((s) => s.id == _selectedSemyaId);
        if (!stillExists) {
          await _persistSelection(null);
          _selectedSemyaId = null;
        }
      }
      // Auto-select default — single семя becomes implicit selection
      if (_selectedSemyaId == null && _semyi.length == 1) {
        await _persistSelection(_semyi.first.id);
        _selectedSemyaId = _semyi.first.id;
      }
    } catch (error) {
      _errorMessage = _describeError(error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Select семя by id. Persists selection. No-op если same id либо
  /// id отсутствует в current list.
  Future<void> selectSemya(String? semyaId) async {
    if (semyaId == _selectedSemyaId) return;
    if (semyaId != null && !_semyi.any((s) => s.id == semyaId)) {
      // Defensive — отверстие edge case: caller tries to select stale id
      // before refresh ran. Reject silently.
      return;
    }
    await _persistSelection(semyaId);
    _selectedSemyaId = semyaId;
    notifyListeners();
  }

  /// Clear selection без полного refresh. Used когда semя deleted либо
  /// caller explicitly «вне семья» mode.
  Future<void> clearSelection() async {
    if (_selectedSemyaId == null) return;
    await _persistSelection(null);
    _selectedSemyaId = null;
    notifyListeners();
  }

  Future<void> _persistSelection(String? id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (id == null || id.isEmpty) {
        await prefs.remove(_selectedSemyaIdKey);
      } else {
        await prefs.setString(_selectedSemyaIdKey, id);
      }
    } catch (error) {
      debugPrint(
        'SemyaListController: persist selection failed: $error',
      );
    }
  }

  String _describeError(Object error) {
    if (error is SemyaError) {
      return error.message;
    }
    return 'Не удалось загрузить семьи';
  }
}
