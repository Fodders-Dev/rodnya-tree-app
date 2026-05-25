import '../models/google_account_preview.dart';

abstract class AuthServiceInterface {
  String? get currentUserId;
  String? get currentUserEmail;
  String? get currentUserDisplayName;
  String? get currentUserPhotoUrl;
  List<String> get currentProviderIds;
  Stream<String?> get authStateChanges;

  /// Phase 6 chunk 4a: true когда backend reports current user
  /// needs `/setup` wizard. Set после `_authenticate` либо
  /// `restoreSession`; persisted в session storage. Caller
  /// (auth_screen post-success либо router guard) redirects к
  /// `/setup`. Defaults к false для legacy users / failed loads.
  ///
  /// Concrete default (false) keeps существующие fake implementations
  /// (test/*Fake*AuthService) backwards-compat. Implementers override
  /// чтобы surface real value.
  bool get currentRequiresOnboarding => false;

  /// Ship Q1 (2026-05-25): mark local session's requiresOnboarding=false
  /// after successful POST /v1/me/onboarding-state/skip. Default
  /// no-op для fake implementations — production CustomApiAuthService
  /// overrides + persists.
  Future<void> markOnboardingSkipped() async {}

  Future<Object?> registerWithEmail({
    required String email,
    required String password,
    required String name,
  });

  Future<Object?> loginWithEmail(String email, String password);

  /// Ship Q2 (2026-05-25): optional [confirm] callback invoked после
  /// Google chooser returns account info, ПЕРЕД backend session
  /// exchange. Returning [GoogleAccountConfirmDecision.confirm]
  /// proceeds; `switchAccount` triggers Google signOut + chooser
  /// retry; `cancel` aborts (throws CustomApiException). Default
  /// null → auto-confirm (backward-compat for tests / scripted flows).
  Future<Object?> signInWithGoogle({
    GoogleAccountConfirmCallback? confirm,
  });
  Future<void> signOut();
  Future<void> resetPassword(String email);
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  });
  Future<void> deleteAccount([String? password]);
  Future<Map<String, dynamic>> checkProfileCompleteness();
  Future<void> processPendingInvitation();
  Future<void> updateDisplayName(String displayName);
  String describeError(Object error);
}
