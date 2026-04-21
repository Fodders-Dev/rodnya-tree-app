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
  });

  Future<CallInvite> acceptCall(String callId);

  Future<CallInvite> rejectCall(String callId);

  Future<CallInvite> cancelCall(String callId);

  Future<CallInvite> hangUp(String callId);
}
