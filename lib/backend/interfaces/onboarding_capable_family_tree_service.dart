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
}
