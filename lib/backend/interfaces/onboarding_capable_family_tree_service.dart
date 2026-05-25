import '../models/onboarding_state.dart';

/// Phase 6 chunk 2 (PHASE-6-PROPOSAL.md §3.3): capability mixin для
/// onboarding wizard endpoints. Старый сервер без endpoint'ов →
/// каpability не implements → wizard skipped через router guard.
abstract class OnboardingCapableFamilyTreeService {
  /// `POST /v1/onboarding/seed` — atomic creation tree + persons
  /// + relations. State-based idempotent (DECISIONS.md 2026-05-13):
  /// completed → return existing; incomplete → replace.
  ///
  /// Returns `null` если backend не capable либо network failure
  /// (UI fallback к manual add-relative flow).
  Future<OnboardingSeedResult?> seedOnboarding({
    required OnboardingSeedPayload payload,
  });

  /// `GET /v1/me/onboarding-state`.
  Future<OnboardingState?> getOnboardingState();

  /// `PATCH /v1/me/onboarding-state` — update step без full seed.
  /// Used wizard'ом для resume tracking.
  Future<OnboardingState?> updateOnboardingState({
    required OnboardingStep currentStep,
  });

  /// `POST /v1/me/onboarding-state/skip` (Ship Q1 2026-05-25).
  /// User explicitly defers wizard, gains main-app access. Backend
  /// sets state.skipped=true → session.requiresOnboarding=false.
  /// Wizard остаётся resumable через banner CTA на home screen.
  ///
  /// Idempotent: re-call returns existing state. Completion
  /// (currentStep='done') overrides skip — flag clears.
  ///
  /// Returns `null` если backend incapable либо network failure
  /// (caller surface'ит «попробуйте позже» UX).
  Future<OnboardingState?> skipOnboarding();
}
