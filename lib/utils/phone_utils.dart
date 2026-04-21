class PhoneUtils {
  const PhoneUtils._();

  static String? normalize(String? value, {String? countryCode}) {
    final rawValue = (value ?? '').trim();
    if (rawValue.isEmpty) {
      return null;
    }

    final hasLeadingPlus = rawValue.startsWith('+');
    var digits = rawValue.replaceAll(RegExp(r'\D+'), '');
    if (digits.isEmpty) {
      return null;
    }

    final normalizedCountryCode = _normalizeCountryCode(countryCode);
    final countryDigits =
        normalizedCountryCode?.replaceAll(RegExp(r'\D+'), '') ?? '';

    if (hasLeadingPlus) {
      return '+$digits';
    }

    if (digits.length == 11 && digits.startsWith('8')) {
      digits = '7${digits.substring(1)}';
    }

    if (digits.length == 10 && countryDigits.isNotEmpty) {
      digits = '$countryDigits$digits';
    }

    if (digits.length <= 6) {
      return null;
    }

    return '+$digits';
  }

  static String? _normalizeCountryCode(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D+'), '');
    if (digits.isEmpty) {
      return null;
    }
    return '+$digits';
  }
}
