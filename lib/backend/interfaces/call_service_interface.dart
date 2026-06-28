import '../../models/call_event.dart';
import '../../models/call_invite.dart';
import '../../models/call_media_mode.dart';

abstract class CallServiceInterface {
  String? get currentUserId;
  Stream<CallEvent> get events;

  Future<void> startRealtimeBridge();

  Future<void> stopRealtimeBridge();

  Future<CallInvite?> getActiveCall({String? chatId});

  Future<CallInvite?> getCall(String callId);

  Future<CallInvite> startCall({
    required String chatId,
    required CallMediaMode mediaMode,
    List<String>? participantIds,
  });

  Future<CallInvite> nudgeCallParticipants(
    String callId, {
    List<String>? participantIds,
  }) {
    throw UnsupportedError('nudgeCallParticipants is not supported');
  }

  Future<CallInvite> acceptCall(String callId);

  /// P1: late-join an already-active (or ringing) call the user is a member
  /// of — the server (POST /v1/calls/:id/join) mints a fresh per-participant
  /// LiveKit token, so any chat member can «залететь в группу» after it
  /// started. Default throws; only the live backend implements it.
  Future<CallInvite> joinCall(String callId) {
    throw UnsupportedError('joinCall is not supported');
  }

  Future<CallInvite> rejectCall(String callId);

  Future<CallInvite> cancelCall(String callId);

  Future<CallInvite> hangUp(String callId);
}
