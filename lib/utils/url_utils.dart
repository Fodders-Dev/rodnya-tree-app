class UrlUtils {
  /// Ensures that image URLs from our API are always HTTPS and correctly formatted.
  /// This prevents 'Mixed Content' issues in browsers when the app is on HTTPS
  /// but the API returns HTTP links for media/avatars.
  static String? normalizeImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) {
      return null;
    }

    final trimmed = url.trim();

    // If it's our own API domain on HTTP, force it to HTTPS
    if (trimmed.startsWith('http://api.rodnya-tree.ru')) {
      return 'https://${trimmed.substring('http://'.length)}';
    }

    // You can add more domains here if needed (e.g. for dev/staging)
    if (trimmed.startsWith('http://api.fodder-development.ru')) {
      return 'https://${trimmed.substring('http://'.length)}';
    }

    return trimmed;
  }
}
