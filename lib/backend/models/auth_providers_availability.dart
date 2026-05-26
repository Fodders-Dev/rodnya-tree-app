/// Ship Q3a (2026-05-26): backend-driven capability flags для 4
/// social-login providers. Fetched at auth-screen mount; if backend
/// returns `null` либо capability data missing (legacy server) →
/// frontend renders ВСЕ buttons как раньше (graceful degradation).
///
/// Parsed from `/health` payload's `authProviders` object:
///   {"authProviders": {"google": bool, "vk": bool, "telegram": bool, "max": bool}}
///
/// Notably: Google capability also requires CLIENT-side `googleWebClientId`
/// (google_sign_in package needs it locally). Auth screen combines
/// `availability.google && isGoogleSignInConfigured`. Other providers
/// are server-side OAuth — single flag enough.
class AuthProvidersAvailability {
  const AuthProvidersAvailability({
    this.google = false,
    this.vk = false,
    this.telegram = false,
    this.max = false,
  });

  final bool google;
  final bool vk;
  final bool telegram;
  final bool max;

  /// Defensive: if `/health` response doesn't contain `authProviders`
  /// либо field is malformed, return null so caller falls back на
  /// legacy «render all» behavior.
  static AuthProvidersAvailability? fromHealthJson(Map<String, dynamic> json) {
    final raw = json['authProviders'];
    if (raw is! Map<String, dynamic>) return null;
    return AuthProvidersAvailability(
      google: raw['google'] == true,
      vk: raw['vk'] == true,
      telegram: raw['telegram'] == true,
      max: raw['max'] == true,
    );
  }
}
