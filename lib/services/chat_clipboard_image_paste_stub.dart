import 'dart:async';

import 'chat_clipboard_image_paste_base.dart';

class ChatClipboardImagePasteService {
  const ChatClipboardImagePasteService();

  Stream<ChatClipboardImage> get images =>
      const Stream<ChatClipboardImage>.empty();

  void dispose() {}
}
