import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/onboarding_capable_family_tree_service.dart';
import '../backend/models/onboarding_state.dart';
import '../theme/app_theme.dart';

/// Ship Q1 (2026-05-25): home-screen banner showing «resume wizard»
/// CTA для users who tapped «Пропустить» в onboarding welcome step.
/// Renders nothing когда:
///   • backend service не capable (legacy server)
///   • auth service indicates no skipped state
///   • OnboardingState.shouldShowResumeBanner == false
///
/// Tap navigates к /setup чтобы resume wizard — wizard's existing
/// state hydration picks up currentStep, banner re-evaluates после
/// completion via authStateChanges subscription.
class OnboardingResumeBanner extends StatefulWidget {
  const OnboardingResumeBanner({super.key});

  @override
  State<OnboardingResumeBanner> createState() =>
      _OnboardingResumeBannerState();
}

class _OnboardingResumeBannerState extends State<OnboardingResumeBanner> {
  bool _resolved = false;
  OnboardingState? _state;
  StreamSubscription<String?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _resolve();
    if (GetIt.I.isRegistered<AuthServiceInterface>()) {
      // Re-fetch state когда session changes (skip / completion /
      // refresh broadcast'нут authStateChanges).
      _authSubscription =
          GetIt.I<AuthServiceInterface>().authStateChanges.listen((_) {
        if (!mounted) return;
        _resolve();
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _resolve() async {
    if (!GetIt.I.isRegistered<FamilyTreeServiceInterface>()) {
      if (mounted) setState(() => _resolved = true);
      return;
    }
    final service = GetIt.I<FamilyTreeServiceInterface>();
    if (service is! OnboardingCapableFamilyTreeService) {
      if (mounted) setState(() => _resolved = true);
      return;
    }
    try {
      final fetched =
          await (service as OnboardingCapableFamilyTreeService)
              .getOnboardingState();
      if (!mounted) return;
      setState(() {
        _state = fetched;
        _resolved = true;
      });
    } catch (_) {
      if (mounted) setState(() => _resolved = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolved) return const SizedBox.shrink();
    final state = _state;
    if (state == null || !state.shouldShowResumeBanner) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (isDark ? RodnyaDesignTokens.dark : RodnyaDesignTokens.light);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Material(
        color: tokens.surfaceStrong.withValues(alpha: isDark ? 0.92 : 0.96),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          side: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.45),
          ),
        ),
        child: InkWell(
          key: const Key('onboarding-resume-banner'),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          onTap: () => context.go('/setup'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.account_tree_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Закончите настройку дерева',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: tokens.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Вы пропустили мастер. Добавьте свою карточку '
                        'и близких — это поможет быстрее найти родню.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.inkSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: tokens.inkSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
