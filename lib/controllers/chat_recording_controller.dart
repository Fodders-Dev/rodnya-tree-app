import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

enum ChatRecordingState {
  idle,
  requestingPermission,
  recording,
  locked,
  preview,
  sending,
  failed,
  denied,
}

class ChatRecordingPreview {
  const ChatRecordingPreview({
    required this.path,
    required this.fileName,
    required this.mimeType,
    required this.durationSeconds,
  });

  final String path;
  final String fileName;
  final String mimeType;
  final int durationSeconds;

  XFile toXFile() {
    return XFile(path, name: fileName, mimeType: mimeType);
  }
}

class ChatRecordingController extends ChangeNotifier {
  ChatRecordingController({
    AudioRecorder? recorder,
  }) : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  Timer? _ticker;
  ChatRecordingState _state = ChatRecordingState.idle;
  int _durationSeconds = 0;
  String? _errorText;
  ChatRecordingPreview? _preview;

  ChatRecordingState get state => _state;
  int get durationSeconds => _durationSeconds;
  String? get errorText => _errorText;
  ChatRecordingPreview? get preview => _preview;
  XFile? get previewFile => _preview?.toXFile();
  int get previewDurationSeconds => _preview?.durationSeconds ?? 0;
  bool get isRecordingActive =>
      _state == ChatRecordingState.recording ||
      _state == ChatRecordingState.locked;

  Future<void> start() async {
    if (isRecordingActive) {
      return;
    }

    _errorText = null;
    _setState(ChatRecordingState.requestingPermission);
    final granted = await _requestMicrophonePermission();
    if (!granted) {
      _errorText = 'Доступ к микрофону отклонен.';
      _setState(ChatRecordingState.denied);
      return;
    }

    final recordingPath = await _buildRecordingPath();
    final resolvedPath = recordingPath ??
        'voice_note_${DateTime.now().millisecondsSinceEpoch}.webm';
    _preview = null;
    _durationSeconds = 0;
    await _recorder.start(
      const RecordConfig(),
      path: resolvedPath,
    );

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _durationSeconds += 1;
      notifyListeners();
    });
    _setState(ChatRecordingState.recording);
  }

  void lock() {
    if (_state != ChatRecordingState.recording) {
      return;
    }
    _setState(ChatRecordingState.locked);
  }

  Future<void> stopToPreview() async {
    if (!isRecordingActive) {
      return;
    }

    _ticker?.cancel();
    final recordedPath = await _recorder.stop();
    final recordedDuration = _durationSeconds;
    _durationSeconds = 0;
    if (recordedPath == null || recordedPath.isEmpty || recordedDuration <= 0) {
      _preview = null;
      _setState(ChatRecordingState.idle);
      return;
    }

    final fileName = kIsWeb
        ? 'voice_note_${recordedDuration}s_${DateTime.now().millisecondsSinceEpoch}.webm'
        : 'voice_note_${recordedDuration}s_${DateTime.now().millisecondsSinceEpoch}'
            '${path.extension(recordedPath).trim().isNotEmpty ? path.extension(recordedPath).trim() : '.m4a'}';
    _preview = ChatRecordingPreview(
      path: recordedPath,
      fileName: fileName,
      mimeType: kIsWeb ? 'audio/webm' : 'audio/m4a',
      durationSeconds: recordedDuration,
    );
    _setState(ChatRecordingState.preview);
  }

  Future<void> cancelCurrent() async {
    _ticker?.cancel();
    if (isRecordingActive) {
      await _recorder.cancel();
    }
    _durationSeconds = 0;
    _preview = null;
    _errorText = null;
    _setState(ChatRecordingState.idle);
  }

  void discardPreview() {
    _preview = null;
    _errorText = null;
    _setState(ChatRecordingState.idle);
  }

  void markSending() {
    if (_preview == null) {
      return;
    }
    _errorText = null;
    _setState(ChatRecordingState.sending);
  }

  void markSendFailed(String message) {
    if (_preview == null) {
      return;
    }
    _errorText = message;
    _setState(ChatRecordingState.failed);
  }

  void completeSend() {
    _preview = null;
    _errorText = null;
    _durationSeconds = 0;
    _setState(ChatRecordingState.idle);
  }

  Future<bool> _requestMicrophonePermission() async {
    if (kIsWeb) {
      return _recorder.hasPermission();
    }

    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<String?> _buildRecordingPath() async {
    if (kIsWeb) {
      return null;
    }

    final directory = await getTemporaryDirectory();
    return path.join(
      directory.path,
      'voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
  }

  void _setState(ChatRecordingState nextState) {
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_recorder.dispose());
    super.dispose();
  }
}
