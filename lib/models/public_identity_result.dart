class PublicIdentityResult {
  const PublicIdentityResult({
    required this.identityId,
    required this.name,
    this.birthYear,
  });

  final String identityId;
  final String name;
  final String? birthYear;

  factory PublicIdentityResult.fromJson(Map<String, dynamic> json) {
    return PublicIdentityResult(
      identityId: json['identityId']?.toString() ?? '',
      name: json['name']?.toString().trim().isNotEmpty == true
          ? json['name'].toString().trim()
          : 'Без имени',
      birthYear: json['birthYear']?.toString(),
    );
  }
}
