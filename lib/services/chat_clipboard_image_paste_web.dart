import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'chat_clipboard_image_paste_base.dart';

class ChatClipboardImagePasteService {
  ChatClipboardImagePasteService() {
    _pasteListener = _handlePaste.toJS;
    web.document.addEventListener('paste', _pasteListener);
  }

  final StreamController<ChatClipboardImage> _imagesController =
      StreamController<ChatClipboardImage>.broadcast();
  late final web.EventListener _pasteListener;

  Stream<ChatClipboardImage> get images => _imagesController.stream;

  void _handlePaste(web.Event event) {
    if (!event.isA<web.ClipboardEvent>()) {
      return;
    }
    final clipboardEvent = event as web.ClipboardEvent;
    final clipboardData = clipboardEvent.clipboardData;
    if (clipboardData == null) {
      return;
    }

    final items = clipboardData.items;
    var handledImage = false;
    final itemCount = items.length;
    for (var index = 0; index < itemCount; index++) {
      final item = items[index];
      final mimeType = item.type.toLowerCase().trim();
      if (!mimeType.startsWith('image/')) {
        continue;
      }

      final file = item.getAsFile();
      if (file == null) {
        continue;
      }

      handledImage = true;
      unawaited(_emitFile(file, fallbackMimeType: mimeType));
    }

    if (handledImage) {
      clipboardEvent.preventDefault();
    }
  }

  Future<void> _emitFile(
    web.File file, {
    required String fallbackMimeType,
  }) async {
    try {
      final buffer = await file.arrayBuffer().toDart;
      final bytes = buffer.toDart.asUint8List();
      if (bytes.isEmpty || _imagesController.isClosed) {
        return;
      }

      final mimeType =
          file.type.trim().isNotEmpty ? file.type.trim() : fallbackMimeType;
      _imagesController.add(
        ChatClipboardImage(
          bytes: bytes,
          mimeType: mimeType,
          name: _fileName(file, mimeType),
        ),
      );
    } catch (error, stackTrace) {
      if (!_imagesController.isClosed) {
        _imagesController.addError(error, stackTrace);
      }
    }
  }

  String _fileName(web.File file, String mimeType) {
    final rawName = file.name.trim();
    if (rawName.isNotEmpty && rawName != 'image.png') {
      return rawName;
    }
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    return 'clipboard-$timestamp${_extensionForMimeType(mimeType)}';
  }

  String _extensionForMimeType(String mimeType) {
    switch (mimeType.toLowerCase().trim()) {
      case 'image/jpeg':
      case 'image/jpg':
        return '.jpg';
      case 'image/webp':
        return '.webp';
      case 'image/gif':
        return '.gif';
      case 'image/bmp':
        return '.bmp';
      default:
        return '.png';
    }
  }

  void dispose() {
    web.document.removeEventListener('paste', _pasteListener);
    unawaited(_imagesController.close());
  }
}
