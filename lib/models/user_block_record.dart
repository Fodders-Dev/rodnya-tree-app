class UserBlockRecord {
  const UserBlockRecord({
    required this.id,
    required this.blockedUserId,
    required this.blockedUserDisplayName,
    required this.createdAt,
    this.blockedUserPhotoUrl,
    this.reason,
  });

  final String id;
  final String blockedUserId;
  final String blockedUserDisplayName;
  final String? blockedUserPhotoUrl;
  final DateTime createdAt;
  final String? reason;

  factory UserBlockRecord.fromMap(Map<String, dynamic> map) {
    return UserBlockRecord(
      id: map['id']?.toString() ?? '',
      blockedUserId: map['blockedUserId']?.toString() ?? '',
      blockedUserDisplayName:
          map['blockedUserDisplayName']?.toString().trim().isNotEmpty == true
              ? map['blockedUserDisplayName'].toString().trim()
              : 'Пользователь',
      blockedUserPhotoUrl: map['blockedUserPhotoUrl']?.toString(),
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      reason: map['reason']?.toString(),
    );
  }
}
