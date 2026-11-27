class IdentityClaim {
  const IdentityClaim({
    required this.id,
    required this.identityId,
    required this.personId,
    required this.claimantUserId,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
    this.personName,
    this.treeId,
    this.treeName,
  });

  final String id;
  final String identityId;
  final String personId;
  final String claimantUserId;
  final String status;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? personName;
  final String? treeId;
  final String? treeName;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isCanceled => status == 'canceled' || status == 'cancelled';

  factory IdentityClaim.fromJson(Map<String, dynamic> json) {
    final rawPersonName = json['personName']?.toString().trim();
    final rawTreeId = json['treeId']?.toString().trim();
    final rawTreeName = json['treeName']?.toString().trim();
    return IdentityClaim(
      id: json['id']?.toString() ?? '',
      identityId: json['identityId']?.toString() ?? '',
      personId: json['personId']?.toString() ?? '',
      claimantUserId: json['claimantUserId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      resolvedAt: DateTime.tryParse(json['resolvedAt']?.toString() ?? ''),
      personName: rawPersonName != null && rawPersonName.isNotEmpty
          ? rawPersonName
          : null,
      treeId: rawTreeId != null && rawTreeId.isNotEmpty ? rawTreeId : null,
      treeName:
          rawTreeName != null && rawTreeName.isNotEmpty ? rawTreeName : null,
    );
  }
}
