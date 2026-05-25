import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/onboarding_capable_family_tree_service.dart';
import '../backend/models/onboarding_state.dart';

/// Phase 6 chunk 2 (PHASE-6-PROPOSAL.md §3.1): wizard state controller.
///
/// Holds:
///   • server-side persisted state (currentStep / completed flag).
///   • local form state (profile fields + relatives slots) — НЕ
///     persisted в SharedPreferences (per Q8 — resume-at-step,
///     form data lost on app close).
///   • submission state (saving / error).
///
/// Lifecycle: создаётся wizard screen'ом при entry, dispose при
/// exit. Если backend service не implements [OnboardingCapableFamilyTreeService]
/// — controller `isCapable=false` → router guard redirect'нёт user'а
/// мимо wizard'а (silent skip).
class OnboardingController extends ChangeNotifier {
  OnboardingController({
    required OnboardingCapableFamilyTreeService? service,
    AuthServiceInterface? authService,
  })  : _service = service,
        _authService = authService {
    _hydrateFromServer();
  }

  final OnboardingCapableFamilyTreeService? _service;

  /// Ship Q1: invoked после successful skip / submit чтобы local
  /// session.requiresOnboarding=false без waiting for next refresh.
  /// Optional — tests / fakes могут omit'нуть.
  final AuthServiceInterface? _authService;

  OnboardingState _state = OnboardingState.fresh;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  // Local form state (in-memory only — Q8 «form lost on abandon»).
  String _profileName = '';
  String? _profileGender;
  String? _profileBirthDate;
  final List<OnboardingRelativeDraft> _relatives = <OnboardingRelativeDraft>[
    OnboardingRelativeDraft(),
    OnboardingRelativeDraft(),
  ];

  // ── Getters ──────────────────────────────────────────────────────

  bool get isCapable => _service != null;
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;

  OnboardingState get state => _state;
  OnboardingStep get currentStep => _state.currentStep;
  bool get completed => _state.completed;

  String get profileName => _profileName;
  String? get profileGender => _profileGender;
  String? get profileBirthDate => _profileBirthDate;
  List<OnboardingRelativeDraft> get relatives =>
      List<OnboardingRelativeDraft>.unmodifiable(_relatives);

  /// Min 1 valid relative (имя + relationToMe заполнены).
  /// Optional — Q2 sub-decision: skip allowed.
  bool get hasMinimumRelatives =>
      _relatives.any((r) => r.isValid);

  /// Profile step valid: name non-empty.
  bool get profileStepValid => _profileName.trim().isNotEmpty;

  // ── Server sync ──────────────────────────────────────────────────

  Future<void> _hydrateFromServer() async {
    final service = _service;
    if (service == null) {
      _isLoading = false;
      notifyListeners();
      return;
    }
    try {
      final fetched = await service.getOnboardingState();
      if (fetched != null) {
        _state = fetched;
      }
    } catch (e) {
      _error = '$e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setStep(OnboardingStep step) async {
    if (_state.currentStep == step) return;
    _state = _state.copyWith(currentStep: step);
    notifyListeners();
    final service = _service;
    if (service != null) {
      // Fire-and-forget update — UI doesn't block on persistence.
      unawaited(service.updateOnboardingState(currentStep: step));
    }
  }

  /// Ship Q1 (2026-05-25): user explicitly «Пропустил» wizard. Calls
  /// backend POST /v1/me/onboarding-state/skip → server sets
  /// state.skipped=true + session.requiresOnboarding=false. Locally
  /// marks auth session чтобы router guards immediately unblock.
  ///
  /// Returns `true` если backend confirmed skip. На failure
  /// (incapable либо network), returns `false` — wizard остаётся
  /// open, UI shows error.
  Future<bool> skipOnboarding() async {
    final service = _service;
    if (service == null) return false;
    if (_isSubmitting) return false;
    _isSubmitting = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await service.skipOnboarding();
      if (updated == null) {
        _error = 'Не удалось сохранить — попробуйте ещё раз.';
        _isSubmitting = false;
        notifyListeners();
        return false;
      }
      _state = updated;
      _isSubmitting = false;
      // Local session mutation — fire-and-forget; auth service
      // persists через secure storage и broadcast'нёт subscribers.
      unawaited(_authService?.markOnboardingSkipped() ?? Future<void>.value());
      notifyListeners();
      return true;
    } catch (e) {
      _error = '$e';
      _isSubmitting = false;
      notifyListeners();
      return false;
    }
  }

  // ── Profile mutations ────────────────────────────────────────────

  void setProfileName(String value) {
    _profileName = value;
    notifyListeners();
  }

  void setProfileGender(String? value) {
    _profileGender = value;
    notifyListeners();
  }

  void setProfileBirthDate(String? value) {
    _profileBirthDate = value;
    notifyListeners();
  }

  // ── Relatives mutations ──────────────────────────────────────────

  void setRelativeName(int index, String value) {
    if (index < 0 || index >= _relatives.length) return;
    _relatives[index] = _relatives[index].copyWith(name: value);
    notifyListeners();
  }

  void setRelativeRelation(int index, OnboardingRelationToMe? value) {
    if (index < 0 || index >= _relatives.length) return;
    _relatives[index] = _relatives[index].copyWith(relationToMe: value);
    notifyListeners();
  }

  void setRelativeBirthDate(int index, String? value) {
    if (index < 0 || index >= _relatives.length) return;
    _relatives[index] = _relatives[index].copyWith(birthDate: value);
    notifyListeners();
  }

  void addRelativeSlot() {
    if (_relatives.length >= 5) return;
    _relatives.add(OnboardingRelativeDraft());
    notifyListeners();
  }

  void removeRelativeSlot(int index) {
    if (index < 0 || index >= _relatives.length) return;
    if (_relatives.length <= 1) return;
    _relatives.removeAt(index);
    notifyListeners();
  }

  // ── Submit ───────────────────────────────────────────────────────

  /// Submits seed payload. Returns true on success.
  /// На success — controller.completed = true, treeId set'нут.
  /// Caller (wizard screen) navigates на /tree после successful submit.
  Future<bool> submit() async {
    final service = _service;
    if (service == null) return false;
    if (!profileStepValid) {
      _error = 'Имя обязательно';
      notifyListeners();
      return false;
    }
    _isSubmitting = true;
    _error = null;
    notifyListeners();
    final payload = OnboardingSeedPayload(
      profile: OnboardingProfile(
        name: _profileName.trim(),
        gender: _profileGender,
        birthDate: _profileBirthDate,
      ),
      relatives: _relatives
          .where((r) => r.isValid)
          .map((r) => r.toRelative())
          .toList(growable: false),
    );
    try {
      final result = await service.seedOnboarding(payload: payload);
      if (result == null) {
        _error = 'Не удалось сохранить — попробуйте ещё раз.';
        _isSubmitting = false;
        notifyListeners();
        return false;
      }
      _state = _state.copyWith(
        completed: true,
        currentStep: OnboardingStep.done,
        treeId: result.treeId,
        personIds: result.personIds,
      );
      _isSubmitting = false;
      // Completion implies onboarding satisfied — clear session flag
      // (defensive: same path as skip, ensures resume banner hides
      // regardless of next refresh timing).
      unawaited(_authService?.markOnboardingSkipped() ?? Future<void>.value());
      notifyListeners();
      return true;
    } catch (e) {
      _error = '$e';
      _isSubmitting = false;
      notifyListeners();
      return false;
    }
  }
}

/// Draft slot для relatives step. In-memory только (Q8 — form lost
/// on abandon, resume restarts step).
class OnboardingRelativeDraft {
  OnboardingRelativeDraft({
    this.name = '',
    this.relationToMe,
    this.gender,
    this.birthDate,
  });

  String name;
  OnboardingRelationToMe? relationToMe;
  String? gender;
  String? birthDate;

  OnboardingRelativeDraft copyWith({
    String? name,
    OnboardingRelationToMe? relationToMe,
    String? gender,
    String? birthDate,
  }) {
    return OnboardingRelativeDraft(
      name: name ?? this.name,
      relationToMe: relationToMe ?? this.relationToMe,
      gender: gender ?? this.gender,
      birthDate: birthDate ?? this.birthDate,
    );
  }

  bool get isValid =>
      name.trim().isNotEmpty && relationToMe != null;

  OnboardingRelative toRelative() {
    return OnboardingRelative(
      name: name.trim(),
      relationToMe: relationToMe!,
      gender: gender ?? _inferGenderFromRelation(relationToMe!),
      birthDate: birthDate,
    );
  }

  static String? _inferGenderFromRelation(OnboardingRelationToMe rel) {
    switch (rel) {
      case OnboardingRelationToMe.mother:
      case OnboardingRelationToMe.grandmother:
        return 'female';
      case OnboardingRelationToMe.father:
      case OnboardingRelationToMe.grandfather:
        return 'male';
      case OnboardingRelationToMe.sibling:
      case OnboardingRelationToMe.child:
      case OnboardingRelationToMe.spouse:
        return null;
    }
  }
}
