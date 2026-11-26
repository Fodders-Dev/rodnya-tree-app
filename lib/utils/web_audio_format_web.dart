import 'package:web/web.dart' as web;

import 'web_audio_format_stub.dart';

WebAudioFormat resolvePreferredWebAudioFormat() {
  try {
    if (web.MediaRecorder.isTypeSupported('audio/mp4')) {
      return const WebAudioFormat(extension: 'm4a', mimeType: 'audio/mp4');
    }
  } catch (_) {}
  return const WebAudioFormat(extension: 'webm', mimeType: 'audio/webm');
}
