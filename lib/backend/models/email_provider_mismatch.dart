/// Ship Bug B (2026-05-26): payload returned by backend когда
/// OAuth login (Google/VK) hits cross-provider email collision.
///
/// Pre-Bug-B: backend silently linked the new provider к existing user
/// via email match. Account-takeover risk если email is shared либо
/// reused. Post-Bug-B: backend refuses merge → 409 с этим payload так
/// frontend сможет show disambig modal и let user log in через their
/// actual existing provider.
class EmailProviderMismatch {
  const EmailProviderMismatch({
    required this.email,
    required this.existingProviders,
    this.message,
  });

  /// Email that collided. Frontend surfaces в modal subtitle.
  final String email;

  /// Provider names of identities already linked к the existing user.
  /// Frontend renders one button per existing provider («Войти через
  /// Google», «Войти через VK ID»). Order matches backend (typically
  /// passwords first via `listAuthIdentitiesForUser` sort).
  ///
  /// Known values: 'password', 'google', 'vk', 'telegram', 'max'.
  final List<String> existingProviders;

  /// Optional friendly message от backend. Fallback к hard-coded copy
  /// если null/empty.
  final String? message;

  static EmailProviderMismatch? fromJson(Map<String, dynamic> body) {
    if (body['error'] != 'EMAIL_PROVIDER_MISMATCH') return null;
    final providersRaw = body['existingProviders'];
    final providers = providersRaw is List
        ? providersRaw
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    return EmailProviderMismatch(
      email: (body['email'] ?? '').toString(),
      existingProviders: providers,
      message: body['message']?.toString(),
    );
  }
}

/// Typed exception raised by auth service когда backend returns 409
/// EMAIL_PROVIDER_MISMATCH. UI catches this specifically и shows
/// disambig modal вместо generic snackbar.
class EmailProviderMismatchException implements Exception {
  const EmailProviderMismatchException(this.payload);

  final EmailProviderMismatch payload;

  @override
  String toString() =>
      'EmailProviderMismatchException(${payload.email}, '
      'providers=${payload.existingProviders})';
}
