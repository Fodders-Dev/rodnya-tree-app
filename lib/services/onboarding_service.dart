import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the user has seen the onboarding tour.
///
/// We store a single boolean in [SharedPreferences] under a versioned key —
/// bumping the suffix lets us re-show the tour after a major redesign without
/// needing to wipe storage. The service is intentionally tiny: callers do
/// `await OnboardingService.instance.hasSeen()` before deciding to push the
/// onboarding route, and `markSeen()` on completion / skip.
class OnboardingService {
  OnboardingService._();
  static final OnboardingService instance = OnboardingService._();

  static const String _kSeenKey = 'onboarding_seen_v1';

  Future<bool> hasSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kSeenKey) ?? false;
    } catch (_) {
      // SharedPreferences can throw on web in private-mode browsers — treat
      // any error as "not seen" so the tour shows once. We don't loop on it
      // because the caller will markSeen() on success / skip.
      return false;
    }
  }

  Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSeenKey, true);
    } catch (_) {
      // Ignore — see hasSeen comment.
    }
  }

  /// Test / settings hook — lets us re-trigger the tour. Not wired into UI
  /// yet but a future "Show onboarding again" entry in Settings can call it.
  Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kSeenKey);
    } catch (_) {
      // Ignore.
    }
  }
}
