/// Ship Q2 (2026-05-25): wrapper for Google account info surfaced
/// в confirm-dialog ПЕРЕД backend session exchange.
///
/// Context: Артёма mama tapped «Войти через Google» on his old phone.
/// Google Play had only Артёма's account → chooser показал его aldı →
/// мама by reflex picked it (single-account chooser feels like «нажми
/// чтобы продолжить»). She landed в Артёма's production аккаунт.
///
/// Protection: после Google authenticate() but ДО POST /v1/auth/google,
/// surface confirmation dialog в нашем UI voice: «Войти в Родню как
/// X (email)?» с photo. Если user cancels — никакого backend call.
class GoogleAccountPreview {
  const GoogleAccountPreview({
    required this.email,
    required this.displayName,
    this.photoUrl,
  });

  final String email;
  final String displayName;
  final String? photoUrl;
}

/// Outcome of confirm dialog. `confirm` proceeds к backend exchange;
/// `switchAccount` triggers Google signOut + chooser retry; `cancel`
/// aborts flow entirely.
enum GoogleAccountConfirmDecision {
  confirm,
  switchAccount,
  cancel,
}

/// Callback signature: invoked by auth service после Google chooser
/// returns account info. UI implementation shows dialog, returns
/// user's decision. Service maps decision → action (proceed / retry
/// chooser / throw cancelled).
typedef GoogleAccountConfirmCallback = Future<GoogleAccountConfirmDecision>
    Function(GoogleAccountPreview preview);
