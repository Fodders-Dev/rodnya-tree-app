class ProfileContribution {
  const ProfileContribution({
    required this.id,
    required this.treeId,
    required this.personId,
    required this.targetUserId,
    required this.fields,
    required this.status,
    this.authorUserId,
    this.authorDisplayName,
    this.authorPhotoUrl,
    this.message,
    this.createdAt,
    this.updatedAt,
    this.respondedAt,
    this.responderUserId,
  });

  final String id;
  final String treeId;
  final String personId;
  final String targetUserId;
  final String? authorUserId;
  final String? authorDisplayName;
  final String? authorPhotoUrl;
  final String? message;
  final Map<String, dynamic> fields;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? respondedAt;
  final String? responderUserId;

  bool get isPending => status == 'pending';

  factory ProfileContribution.fromJson(Map<String, dynamic> json) {
    return ProfileContribution(
      id: json['id']?.toString() ?? '',
      treeId: json['treeId']?.toString() ?? '',
      personId: json['personId']?.toString() ?? '',
      targetUserId: json['targetUserId']?.toString() ?? '',
      authorUserId: json['authorUserId']?.toString(),
      authorDisplayName: json['authorDisplayName']?.toString(),
      authorPhotoUrl: json['authorPhotoUrl']?.toString(),
      message: json['message']?.toString(),
      fields: (json['fields'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value),
          ) ??
          const <String, dynamic>{},
      status: json['status']?.toString() ?? 'pending',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      respondedAt: DateTime.tryParse(json['respondedAt']?.toString() ?? ''),
      responderUserId: json['responderUserId']?.toString(),
    );
  }
}
