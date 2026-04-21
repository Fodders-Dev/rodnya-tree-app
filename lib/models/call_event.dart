import 'call_invite.dart';

enum CallEventType {
  inviteCreated,
  stateUpdated;

  static CallEventType fromValue(String value) {
    return value == 'call.invite.created'
        ? CallEventType.inviteCreated
        : CallEventType.stateUpdated;
  }
}

class CallEvent {
  const CallEvent({
    required this.type,
    required this.call,
  });

  final CallEventType type;
  final CallInvite call;
}
