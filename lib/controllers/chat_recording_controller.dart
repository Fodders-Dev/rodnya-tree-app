import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../utils/voice_waveform.dart';

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
    this.waveform = const <double>[],
  });

  final String path;
  final String fileName;
  final String mimeType;
  final int durationSeconds;
  final List<double> waveform;

  XFile toXFile() {
    return XFile(path, name: fileName, mimeType: mimeType);
  }
}

class ChatRecordingController extends ChangeNotifier {
  ChatRecordingController({
    AudioRecorder? recorder,
    Future<bool> Function()? permissionRequester,
  })  : _recorder = recorder ?? AudioRecorder(),
        _permissionRequester = permissionRequester;

  final AudioRecorder _recorder;

  /// C1/тестируемость: запрос разрешения на микрофон вынесен в инъекцию.
  /// В проде null → штатная логика (web: recorder.hasPermission, native:
  /// permission_handler). В тестах подменяется, чтобы не дёргать каналы.
  final Future<bool> Function()? _permissionRequester;

  Timer? _ticker;
  StreamSubscription? _amplitudeSub;
  ChatRecordingState _state = ChatRecordingState.idle;
  int _durationSeconds = 0;
  String? _errorText;
  ChatRecordingPreview? _preview;
  // C1: путь идущей записи — чтобы отмена/ошибка могли удалить temp-файл
  // (record.cancel() не везде надёжно подчищает, плюс старт может упасть
  // уже после создания пути).
  String? _activeRecordingPath;
  final List<double> _amplitudeSamples = <double>[];

  ChatRecordingState get state => _state;
  int get durationSeconds => _durationSeconds;
  String? get errorText => _errorText;
  ChatRecordingPreview? get preview => _preview;
  XFile? get previewFile => _preview?.toXFile();
  int get previewDurationSeconds => _preview?.durationSeconds ?? 0;
  List<double> get previewWaveform =>
      List<double>.unmodifiable(_preview?.waveform ?? const <double>[]);

  /// C2: «живая» волна для recording-бара — последние [liveWaveformBins]
  /// нормализованных амплитуд (скользящее окно, как в Telegram). Пусто,
  /// пока не пришло ни одного замера.
  static const int liveWaveformBins = 40;
  List<double> get liveWaveform {
    final length = _amplitudeSamples.length;
    if (length <= liveWaveformBins) {
      return List<double>.unmodifiable(_amplitudeSamples);
    }
    return List<double>.unmodifiable(
      _amplitudeSamples.sublist(length - liveWaveformBins),
    );
  }

  bool get isRecordingActive =>
      _state == ChatRecordingState.recording ||
      _state == ChatRecordingState.locked;

  Future<void> start() async {
    // C1: гард не только на активную запись, но и на время запроса
    // разрешения — повторный тап/двойной вызов не должен запрашивать
    // микрофон второй раз и стартовать вторую запись.
    if (isRecordingActive ||
        _state == ChatRecordingState.requestingPermission) {
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
    _amplitudeSamples.clear();
    _durationSeconds = 0;
    _activeRecordingPath = resolvedPath;
    // C1: старт рекордера в try/catch — иначе исключение оставляло
    // контроллер навсегда в requestingPermission (бар «запрашиваю…» висел,
    // запись не шла). На ошибке — чистим частичный файл и в idle.
    try {
      await _recorder.start(
        const RecordConfig(),
        path: resolvedPath,
      );
    } catch (error) {
      debugPrint('ChatRecordingController.start failed: $error');
      await _safeCancelRecorder();
      await _deleteRecordingFile(_activeRecordingPath);
      _activeRecordingPath = null;
      _errorText = 'Не удалось начать запись.';
      _setState(ChatRecordingState.idle);
      return;
    }
    _amplitudeSub?.cancel();
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((amplitude) {
      _amplitudeSamples.add(_normalizeAmplitude(amplitude.current));
      if (_amplitudeSamples.length > 600) {
        _amplitudeSamples.removeRange(0, _amplitudeSamples.length - 600);
      }
      // C2: уведомляем, чтобы recording-бар перерисовал живую волну.
      // Слушатель экрана игнорирует amplitude-only нотификации (состояние
      // не меняется) — перерисовывается только сам бар через AnimatedBuilder.
      notifyListeners();
    });

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _durationSeconds += 1;
      notifyListeners();
    });
    // C1: надёжно переводим в recording — пульсирующий бар обязан появиться.
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
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    final recordedPath = await _recorder.stop();
    final recordedDuration = _durationSeconds;
    _durationSeconds = 0;
    if (recordedPath == null || recordedPath.isEmpty || recordedDuration <= 0) {
      // C1: пустая/нулевая запись — удаляем огрызок temp-файла, не копим.
      await _deleteRecordingFile(recordedPath ?? _activeRecordingPath);
      _activeRecordingPath = null;
      _preview = null;
      _setState(ChatRecordingState.idle);
      return;
    }

    var waveform = downsampleVoiceWaveform(_amplitudeSamples);
    if (waveform.isEmpty) {
      try {
        waveform = buildVoiceWaveformFromBytes(
          await XFile(recordedPath).readAsBytes(),
        );
      } catch (_) {
        waveform = const <double>[];
      }
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
      waveform: waveform,
    );
    // Файл теперь принадлежит preview — за его удаление отвечают
    // discardPreview/cancelCurrent, а не logic очистки активной записи.
    _activeRecordingPath = null;
    _amplitudeSamples.clear();
    _setState(ChatRecordingState.preview);
  }

  Future<void> cancelCurrent() async {
    _ticker?.cancel();
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    if (isRecordingActive) {
      await _safeCancelRecorder();
    }
    // C1: после отмены чистим и temp-файл идущей записи, и возможный
    // preview-файл — отменённые/переписанные голосовые не должны копиться.
    await _deleteRecordingFile(_activeRecordingPath);
    await _deleteRecordingFile(_preview?.path);
    _activeRecordingPath = null;
    _durationSeconds = 0;
    _preview = null;
    _amplitudeSamples.clear();
    _errorText = null;
    _setState(ChatRecordingState.idle);
  }

  void discardPreview() {
    // C1: preview отброшен (re-record / удаление вложения) — temp-файл
    // больше не нужен, удаляем фоном (best-effort).
    unawaited(_deleteRecordingFile(_preview?.path));
    _activeRecordingPath = null;
    _preview = null;
    _errorText = null;
    _amplitudeSamples.clear();
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
    final injected = _permissionRequester;
    if (injected != null) {
      return injected();
    }
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

  /// C1: отмена рекордера не должна ронять остальную очистку (на части
  /// платформ cancel() кидает, если запись уже остановлена).
  Future<void> _safeCancelRecorder() async {
    try {
      await _recorder.cancel();
    } catch (_) {
      // best-effort
    }
  }

  /// C1: удалить temp-файл записи. На web файловой системы нет
  /// (record пишет в blob) — путь там фиктивный, пропускаем.
  Future<void> _deleteRecordingFile(String? filePath) async {
    if (kIsWeb) {
      return;
    }
    final target = filePath?.trim() ?? '';
    if (target.isEmpty) {
      return;
    }
    try {
      final file = File(target);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // невозможность удалить temp некритична
    }
  }

  void _setState(ChatRecordingState nextState) {
    _state = nextState;
    notifyListeners();
  }

  double _normalizeAmplitude(double decibels) {
    if (!decibels.isFinite) {
      return 0.0;
    }
    return math.pow(10, decibels / 40).clamp(0.0, 1.0).toDouble();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_amplitudeSub?.cancel());
    unawaited(_recorder.dispose());
    super.dispose();
  }
}
