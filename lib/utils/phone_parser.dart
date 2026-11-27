const List<String> _knownDialCodes = <String>[
  '+375',
  '+380',
  '+998',
  '+996',
  '+995',
  '+994',
  '+993',
  '+992',
  '+374',
  '+373',
  '+372',
  '+371',
  '+370',
  '+972',
  '+971',
  '+49',
  '+44',
  '+33',
  '+90',
  '+86',
  '+81',
  '+61',
  '+48',
  '+39',
  '+34',
  '+7',
  '+1',
];

/// Splits an E.164 phone string into `(countryCode, localNumber)` using a
/// longest-match table of common dial codes so `+79991234567` yields `+7`
/// instead of `+79`.
MapEntry<String, String> parsePhoneWithCountryCode(String phoneNumber) {
  final trimmed = phoneNumber.trim();
  if (!trimmed.startsWith('+') || trimmed.length <= 2) {
    return MapEntry<String, String>('', trimmed);
  }
  for (final code in _knownDialCodes) {
    if (trimmed.startsWith(code) && trimmed.length > code.length) {
      return MapEntry<String, String>(
        code,
        trimmed.substring(code.length),
      );
    }
  }
  final fallbackSplit = trimmed.length > 12 ? 3 : 2;
  return MapEntry<String, String>(
    trimmed.substring(0, fallbackSplit),
    trimmed.substring(fallbackSplit),
  );
}
