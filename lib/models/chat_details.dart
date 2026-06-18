class ChatParticipantSummary {
  const ChatParticipantSummary({
    required this.userId,
    required this.displayName,
    this.photoUrl,
    this.isOnline = false,
    this.lastSeenAt,
  });

  final String userId;
  final String displayName;
  final String? photoUrl;

  /// Live presence flag from the API/realtime channel. True when at least
  /// one of the user's sessions has an active socket on the realtime hub.
  final bool isOnline;

  /// Last time the user was observed online — populated from
  /// `users.lastSeenAt` (persisted on socket disconnect). Null if the
  /// user has never connected since the field was added.
  final DateTime? lastSeenAt;

  factory ChatParticipantSummary.fromMap(Map<String, dynamic> map) {
    final lastSeenRaw = map['lastSeenAt']?.toString();
    return ChatParticipantSummary(
      userId: map['userId']?.toString() ?? '',
      displayName: map['displayName']?.toString() ?? 'Пользователь',
      photoUrl: map['photoUrl']?.toString(),
      isOnline: map['isOnline'] == true,
      lastSeenAt: lastSeenRaw == null || lastSeenRaw.isEmpty
          ? null
          : DateTime.tryParse(lastSeenRaw),
    );
  }

  ChatParticipantSummary copyWith({
    bool? isOnline,
    DateTime? lastSeenAt,
  }) {
    return ChatParticipantSummary(
      userId: userId,
      displayName: displayName,
      photoUrl: photoUrl,
      isOnline: isOnline ?? this.isOnline,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  /// Serialize to a JSON-friendly map. Mirror of [fromMap] so the
  /// [ChatDetailsCache] can persist details to disk.
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'displayName': displayName,
      if (photoUrl != null) 'photoUrl': photoUrl,
      'isOnline': isOnline,
      if (lastSeenAt != null) 'lastSeenAt': lastSeenAt!.toIso8601String(),
    };
  }
}

class ChatBranchRootSummary {
  const ChatBranchRootSummary({
    required this.personId,
    required this.name,
    this.photoUrl,
  });

  final String personId;
  final String name;
  final String? photoUrl;

  factory ChatBranchRootSummary.fromMap(Map<String, dynamic> map) {
    return ChatBranchRootSummary(
      personId: map['personId']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Без имени',
      photoUrl: map['photoUrl']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'personId': personId,
      'name': name,
      if (photoUrl != null) 'photoUrl': photoUrl,
    };
  }
}

class ChatDetails {
  const ChatDetails({
    required this.chatId,
    required this.type,
    required this.participantIds,
    required this.participants,
    required this.branchRoots,
    this.title,
    this.photoUrl,
    this.createdBy,
    this.treeId,
    this.createdAt,
    this.updatedAt,
  });

  final String chatId;
  final String type;
  final String? title;
  final String? photoUrl;
  final List<String> participantIds;
  final String? createdBy;
  final String? treeId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<ChatParticipantSummary> participants;
  final List<ChatBranchRootSummary> branchRoots;

  bool get isGroup => type == 'group' || type == 'branch';
  bool get isBranch => type == 'branch';
  bool get isDirect => type == 'direct';
  bool get isEditableGroup => type == 'group';
  int get memberCount => participants.length;

  String get displayTitle => displayTitleFor(null);

  String displayTitleFor(String? currentUserId) {
    final normalizedTitle = title?.trim();
    if (normalizedTitle != null && normalizedTitle.isNotEmpty) {
      return normalizedTitle;
    }
    if (isBranch) {
      return 'Чат ветки';
    }
    if (isGroup) {
      return 'Групповой чат';
    }
    if (participants.isEmpty) {
      return 'Чат';
    }
    final normalizedUserId = currentUserId?.trim();
    if (normalizedUserId != null && normalizedUserId.isNotEmpty) {
      final other = participants.firstWhere(
        (participant) => participant.userId != normalizedUserId,
        orElse: () => participants.first,
      );
      return other.displayName;
    }
    return participants.first.displayName;
  }

  factory ChatDetails.fromMap(Map<String, dynamic> map) {
    DateTime? parseTimestamp(dynamic value) {
      final raw = value?.toString();
      if (raw == null || raw.isEmpty) {
        return null;
      }
      return DateTime.tryParse(raw);
    }

    return ChatDetails(
      chatId: map['id']?.toString() ?? map['chatId']?.toString() ?? '',
      type: map['type']?.toString() ?? 'direct',
      title: map['title']?.toString(),
      photoUrl: map['photoUrl']?.toString(),
      participantIds: List<String>.from(map['participantIds'] ?? const []),
      createdBy: map['createdBy']?.toString(),
      treeId: map['treeId']?.toString(),
      createdAt: parseTimestamp(map['createdAt']),
      updatedAt: parseTimestamp(map['updatedAt']),
      participants: (map['participants'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .map(ChatParticipantSummary.fromMap)
          .toList(),
      branchRoots: (map['branchRoots'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .map(ChatBranchRootSummary.fromMap)
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': chatId,
      'type': type,
      if (title != null) 'title': title,
      if (photoUrl != null) 'photoUrl': photoUrl,
      'participantIds': participantIds,
      if (createdBy != null) 'createdBy': createdBy,
      if (treeId != null) 'treeId': treeId,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      'participants': participants.map((p) => p.toMap()).toList(),
      'branchRoots': branchRoots.map((b) => b.toMap()).toList(),
    };
  }
}
