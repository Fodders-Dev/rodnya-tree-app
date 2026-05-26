import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/semya_capable_family_tree_service.dart';
import '../backend/models/semya.dart';
import '../backend/models/semya_invitation.dart';

/// Ship FE3 (2026-05-26): controller для семя invitations list +
/// send/revoke actions. Mirrors SemyaDetailsController pattern —
/// ChangeNotifier, GetIt service resolution, test-seam constructor.
///
/// Lifecycle: caller (invitations screen) creates controller scoped
/// к semyaId, dispose'нет при unmount.
///
/// Bot пути:
///   * load() — fetch invitations list (initial либо refresh)
///   * sendInvitation({email/phone/userId, role}) — POST + refresh list
///   * revoke(invitationId) — DELETE + refresh list
class SemyaInvitationsController with ChangeNotifier {
  SemyaInvitationsController({
    required this.semyaId,
    SemyaCapableFamilyTreeService? service,
  }) : _injectedService = service;

  final String semyaId;
  final SemyaCapableFamilyTreeService? _injectedService;

  List<SemyaInvitation> _invitations = const <SemyaInvitation>[];
  bool _isLoading = false;
  bool _hasLoaded = false;
  bool _isSending = false;
  bool _isRevoking = false;
  String? _errorMessage;

  /// Last successfully created invitation — caller (send screen) uses
  /// для display token / share button. Cleared on next sendInvitation()
  /// либо load() invocation.
  SemyaInvitation? _lastCreated;

  List<SemyaInvitation> get invitations => _invitations;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  bool get isSending => _isSending;
  bool get isRevoking => _isRevoking;
  String? get errorMessage => _errorMessage;
  SemyaInvitation? get lastCreated => _lastCreated;

  /// True когда service capable. False — UI shows empty state без CTA.
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

  Future<void> load() async {
    final service = _resolveService();
    if (service == null) {
      _hasLoaded = true;
      _invitations = const <SemyaInvitation>[];
      notifyListeners();
      return;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final list = await service.listInvitationsForSemya(semyaId);
      _invitations = List<SemyaInvitation>.unmodifiable(list);
      _hasLoaded = true;
    } catch (error) {
      _errorMessage = _describeError(error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  /// Sends invitation. Updates `lastCreated` на success, refreshes list.
  /// Returns true когда backend accepted (201/200), false otherwise —
  /// `errorMessage` is set in failure case.
  Future<bool> sendInvitation({
    required SemyaRole role,
    String? recipientEmail,
    String? recipientPhone,
    String? recipientUserId,
  }) async {
    final service = _resolveService();
    if (service == null) {
      _errorMessage = 'Сервис недоступен';
      notifyListeners();
      return false;
    }
    final email = recipientEmail?.trim();
    final phone = recipientPhone?.trim();
    final userId = recipientUserId?.trim();
    if ((email == null || email.isEmpty) &&
        (phone == null || phone.isEmpty) &&
        (userId == null || userId.isEmpty)) {
      _errorMessage = 'Укажите email либо телефон получателя';
      notifyListeners();
      return false;
    }
    _isSending = true;
    _errorMessage = null;
    _lastCreated = null;
    notifyListeners();
    try {
      final invitation = await service.createInvitation(
        semyaId: semyaId,
        role: role,
        recipientEmail: email,
        recipientPhone: phone,
        recipientUserId: userId,
      );
      _lastCreated = invitation;
      _isSending = false;
      notifyListeners();
      // Background refresh — list updated independently без blocking
      // success surface.
      unawaited(load());
      return true;
    } catch (error) {
      _errorMessage = _describeError(error);
      _isSending = false;
      notifyListeners();
      return false;
    }
  }

  /// Revokes invitation by id. Returns true on success.
  Future<bool> revoke(String invitationId) async {
    final service = _resolveService();
    if (service == null) return false;
    _isRevoking = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await service.revokeInvitation(
        semyaId: semyaId,
        invitationId: invitationId,
      );
      _isRevoking = false;
      notifyListeners();
      await load();
      return true;
    } catch (error) {
      _errorMessage = _describeError(error);
      _isRevoking = false;
      notifyListeners();
      return false;
    }
  }

  void clearLastCreated() {
    if (_lastCreated == null) return;
    _lastCreated = null;
    notifyListeners();
  }

  String _describeError(Object error) {
    if (error is SemyaError) return error.message;
    return 'Не удалось выполнить операцию';
  }
}
