class CallSession {
  const CallSession({
    required this.roomName,
    required this.url,
    required this.token,
    required this.participantIdentity,
    this.participantName,
    this.createdAt,
  });

  final String roomName;
  final String url;
  final String token;
  final String participantIdentity;
  final String? participantName;
  final DateTime? createdAt;

  factory CallSession.fromMap(Map<String, dynamic> map) {
    return CallSession(
      roomName: map['roomName']?.toString() ?? '',
      url: map['url']?.toString() ?? '',
      token: map['token']?.toString() ?? '',
      participantIdentity: map['participantIdentity']?.toString() ?? '',
      participantName: map['participantName']?.toString(),
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'roomName': roomName,
      'url': url,
      'token': token,
      'participantIdentity': participantIdentity,
      if (participantName != null) 'participantName': participantName,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    };
  }
}
