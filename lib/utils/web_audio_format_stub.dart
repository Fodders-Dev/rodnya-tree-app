class WebAudioFormat {
  const WebAudioFormat({
    required this.extension,
    required this.mimeType,
  });

  final String extension;
  final String mimeType;
}

WebAudioFormat resolvePreferredWebAudioFormat() {
  return const WebAudioFormat(extension: 'webm', mimeType: 'audio/webm');
}
