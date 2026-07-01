// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'chat_clipboard_image_paste_base.dart';

class ChatClipboardImagePasteService {
  ChatClipboardImagePasteService() {
    _pasteSubscription = html.document.onPaste.listen(_handlePaste);
  }

  final StreamController<ChatClipboardImage> _imagesController =
      StreamController<ChatClipboardImage>.broadcast();
  late final StreamSubscription<html.ClipboardEvent> _pasteSubscription;

  Stream<ChatClipboardImage> get images => _imagesController.stream;

  void _handlePaste(html.ClipboardEvent event) {
    final clipboardData = event.clipboardData;
    if (clipboardData == null) {
      return;
    }

    final items = clipboardData.items;
    if (items == null) {
      return;
    }

    var handledImage = false;
    final itemCount = items.length ?? 0;
    for (var index = 0; index < itemCount; index++) {
      final item = items[index];
      final mimeType = item.type?.toLowerCase().trim() ?? '';
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
      event.preventDefault();
    }
  }

  Future<void> _emitFile(
    html.File file, {
    required String fallbackMimeType,
  }) async {
    try {
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoadEnd.first;

      final result = reader.result;
      Uint8List? bytes;
      if (result is ByteBuffer) {
        bytes = result.asUint8List();
      } else if (result is Uint8List) {
        bytes = result;
      } else if (result is List<int>) {
        bytes = Uint8List.fromList(result);
      }
      if (bytes == null || bytes.isEmpty || _imagesController.isClosed) {
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

  String _fileName(html.File file, String mimeType) {
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
    unawaited(_pasteSubscription.cancel());
    unawaited(_imagesController.close());
  }
}
