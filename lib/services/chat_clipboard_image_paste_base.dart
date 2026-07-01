import 'dart:typed_data';

class ChatClipboardImage {
  const ChatClipboardImage({
    required this.bytes,
    required this.mimeType,
    required this.name,
  });

  final Uint8List bytes;
  final String mimeType;
  final String name;
}
