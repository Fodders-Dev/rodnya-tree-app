class IdentityClaim {
  const IdentityClaim({
    required this.id,
    required this.identityId,
    required this.personId,
    required this.claimantUserId,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
  });

  final String id;
  final String identityId;
  final String personId;
  final String claimantUserId;
  final String status;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';

  factory IdentityClaim.fromJson(Map<String, dynamic> json) {
    return IdentityClaim(
      id: json['id']?.toString() ?? '',
      identityId: json['identityId']?.toString() ?? '',
      personId: json['personId']?.toString() ?? '',
      claimantUserId: json['claimantUserId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      resolvedAt: DateTime.tryParse(json['resolvedAt']?.toString() ?? ''),
    );
  }
}
