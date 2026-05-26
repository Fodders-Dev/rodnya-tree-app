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

  SemyaDetails? get details => _details;
  List<SemyaMembership> get memberships => _memberships;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get errorMessage => _errorMessage;

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

  String _describeError(Object error) {
    if (error is SemyaError) return error.message;
    return 'Не удалось загрузить данные';
  }
}
