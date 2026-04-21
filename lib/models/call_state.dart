enum CallState {
  ringing,
  active,
  rejected,
  cancelled,
  ended,
  missed,
  failed;

  bool get isTerminal {
    switch (this) {
      case CallState.rejected:
      case CallState.cancelled:
      case CallState.ended:
      case CallState.missed:
      case CallState.failed:
        return true;
      case CallState.ringing:
      case CallState.active:
        return false;
    }
  }

  static CallState fromValue(dynamic value) {
    switch ((value ?? '').toString().trim().toLowerCase()) {
      case 'active':
        return CallState.active;
      case 'rejected':
        return CallState.rejected;
      case 'cancelled':
        return CallState.cancelled;
      case 'ended':
        return CallState.ended;
      case 'missed':
        return CallState.missed;
      case 'failed':
        return CallState.failed;
      default:
        return CallState.ringing;
    }
  }
}
