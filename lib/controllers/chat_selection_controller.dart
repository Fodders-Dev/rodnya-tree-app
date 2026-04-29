import 'package:flutter/foundation.dart';

class ChatSelectionController extends ChangeNotifier {
  final Set<String> _remoteMessageIds = <String>{};
  final Set<String> _outgoingMessageIds = <String>{};

  bool get isSelectionMode =>
      _remoteMessageIds.isNotEmpty || _outgoingMessageIds.isNotEmpty;

  int get selectedMessageCount =>
      _remoteMessageIds.length + _outgoingMessageIds.length;

  bool isRemoteSelected(String messageId) =>
      _remoteMessageIds.contains(messageId);

  bool isOutgoingSelected(String localId) =>
      _outgoingMessageIds.contains(localId);

  void selectRemote(String messageId) {
    if (_remoteMessageIds.add(messageId)) {
      notifyListeners();
    }
  }

  void selectOutgoing(String localId) {
    if (_outgoingMessageIds.add(localId)) {
      notifyListeners();
    }
  }

  void toggleRemote(String messageId) {
    if (!_remoteMessageIds.remove(messageId)) {
      _remoteMessageIds.add(messageId);
    }
    notifyListeners();
  }

  void toggleOutgoing(String localId) {
    if (!_outgoingMessageIds.remove(localId)) {
      _outgoingMessageIds.add(localId);
    }
    notifyListeners();
  }

  void clear() {
    if (!isSelectionMode) {
      return;
    }
    _remoteMessageIds.clear();
    _outgoingMessageIds.clear();
    notifyListeners();
  }
}
