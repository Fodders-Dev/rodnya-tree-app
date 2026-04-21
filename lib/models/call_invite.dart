import 'call_media_mode.dart';
import 'call_session.dart';
import 'call_state.dart';

class CallInvite {
  const CallInvite({
    required this.id,
    required this.chatId,
    required this.initiatorId,
    required this.recipientId,
    required this.participantIds,
    required this.mediaMode,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    this.roomName,
    this.acceptedAt,
    this.endedAt,
    this.endedReason,
    this.session,
  });

  final String id;
  final String chatId;
  final String initiatorId;
  final String recipientId;
  final List<String> participantIds;
  final CallMediaMode mediaMode;
  final CallState state;
  final String? roomName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? acceptedAt;
  final DateTime? endedAt;
  final String? endedReason;
  final CallSession? session;

  bool isOutgoingFor(String userId) => initiatorId == userId;
  bool isIncomingFor(String userId) => recipientId == userId;

  CallInvite copyWith({
    CallState? state,
    String? roomName,
    DateTime? updatedAt,
    DateTime? acceptedAt,
    DateTime? endedAt,
    String? endedReason,
    CallSession? session,
  }) {
    return CallInvite(
      id: id,
      chatId: chatId,
      initiatorId: initiatorId,
      recipientId: recipientId,
      participantIds: participantIds,
      mediaMode: mediaMode,
      state: state ?? this.state,
      roomName: roomName ?? this.roomName,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      endedAt: endedAt ?? this.endedAt,
      endedReason: endedReason ?? this.endedReason,
      session: session ?? this.session,
    );
  }

  factory CallInvite.fromMap(Map<String, dynamic> map) {
    final participantIds = (map['participantIds'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toList();
    return CallInvite(
      id: map['id']?.toString() ?? '',
      chatId: map['chatId']?.toString() ?? '',
      initiatorId: map['initiatorId']?.toString() ?? '',
      recipientId: map['recipientId']?.toString() ?? '',
      participantIds: participantIds,
      mediaMode: CallMediaMode.fromValue(map['mediaMode']),
      state: CallState.fromValue(map['state']),
      roomName: map['roomName']?.toString(),
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse(map['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      acceptedAt: DateTime.tryParse(map['acceptedAt']?.toString() ?? ''),
      endedAt: DateTime.tryParse(map['endedAt']?.toString() ?? ''),
      endedReason: map['endedReason']?.toString(),
      session: map['session'] is Map<String, dynamic>
          ? CallSession.fromMap(map['session'] as Map<String, dynamic>)
          : null,
    );
  }
}
