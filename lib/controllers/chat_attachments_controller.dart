import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class ChatAttachmentsController extends ChangeNotifier {
  ChatAttachmentsController({
    this.maxAttachments = 6,
  });

  final int maxAttachments;
  final List<XFile> _attachments = <XFile>[];

  UnmodifiableListView<XFile> get attachments =>
      UnmodifiableListView<XFile>(_attachments);

  bool get isEmpty => _attachments.isEmpty;
  bool get isNotEmpty => _attachments.isNotEmpty;
  int get length => _attachments.length;
  int get remainingSlots {
    final remaining = maxAttachments - _attachments.length;
    if (remaining <= 0) {
      return 0;
    }
    if (remaining > maxAttachments) {
      return maxAttachments;
    }
    return remaining;
  }

  bool any(bool Function(XFile file) test) => _attachments.any(test);

  int addAll(Iterable<XFile> files) {
    if (remainingSlots <= 0) {
      return 0;
    }
    final nextFiles = files.take(remainingSlots).toList(growable: false);
    if (nextFiles.isEmpty) {
      return 0;
    }
    _attachments.addAll(nextFiles);
    notifyListeners();
    return nextFiles.length;
  }

  void replaceAll(Iterable<XFile> files) {
    final nextFiles = files.take(maxAttachments).toList(growable: false);
    if (listEquals(_attachments, nextFiles)) {
      return;
    }
    _attachments
      ..clear()
      ..addAll(nextFiles);
    notifyListeners();
  }

  void clear() {
    if (_attachments.isEmpty) {
      return;
    }
    _attachments.clear();
    notifyListeners();
  }

  bool remove(XFile file) {
    final removed = _attachments.remove(file);
    if (removed) {
      notifyListeners();
    }
    return removed;
  }

  XFile removeAt(int index) {
    final removed = _attachments.removeAt(index);
    notifyListeners();
    return removed;
  }

  void removeWhere(bool Function(XFile file) test) {
    final beforeLength = _attachments.length;
    _attachments.removeWhere(test);
    if (_attachments.length != beforeLength) {
      notifyListeners();
    }
  }
}
