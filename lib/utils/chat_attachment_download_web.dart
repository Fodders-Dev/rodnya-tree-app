import 'package:web/web.dart' as web;

const bool supportsChatAttachmentDownload = true;

Future<void> downloadChatAttachment(
  String url, {
  String? suggestedFileName,
}) async {
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..style.display = 'none'
    ..target = '_blank';
  final fileName = suggestedFileName?.trim();
  if (fileName != null && fileName.isNotEmpty) {
    anchor.download = fileName;
  }
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
