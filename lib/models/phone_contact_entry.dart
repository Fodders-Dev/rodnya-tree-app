class PhoneContactEntry {
  const PhoneContactEntry({
    required this.displayName,
    required this.phoneNumber,
    required this.normalizedPhoneNumber,
  });

  final String displayName;
  final String phoneNumber;
  final String normalizedPhoneNumber;
}
