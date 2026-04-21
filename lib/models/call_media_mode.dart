enum CallMediaMode {
  audio,
  video;

  bool get isVideo => this == CallMediaMode.video;

  String get value {
    switch (this) {
      case CallMediaMode.audio:
        return 'audio';
      case CallMediaMode.video:
        return 'video';
    }
  }

  static CallMediaMode fromValue(dynamic value) {
    return (value ?? '').toString().trim().toLowerCase() == 'video'
        ? CallMediaMode.video
        : CallMediaMode.audio;
  }
}
