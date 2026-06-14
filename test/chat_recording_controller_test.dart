// C1: юнит-тесты ChatRecordingController — починка записи голоса.
// Покрывают: гард повторного start() во время запроса разрешения,
// try/catch вокруг recorder.start() (ошибка → idle, не зависаем в
// requestingPermission), отказ в разрешении → denied, и очистку
// temp-файла при cancelCurrent().

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:record/record.dart';
import 'package:rodnya/controllers/chat_recording_controller.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.tempPath);

  final String tempPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

class _FakeRecorder implements AudioRecorder {
  _FakeRecorder({this.startError = false, this.createFile = false});

  final bool startError;
  final bool createFile;

  int startCalls = 0;
  int cancelCalls = 0;
  int stopCalls = 0;
  String? lastPath;
  final StreamController<Amplitude> _amp =
      StreamController<Amplitude>.broadcast();

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    startCalls++;
    lastPath = path;
    if (startError) {
      throw Exception('start boom');
    }
    if (createFile && !kIsWeb) {
      await File(path).writeAsBytes(<int>[0, 1, 2, 3]);
    }
  }

  @override
  Future<String?> stop() async {
    stopCalls++;
    return lastPath;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    // Намеренно НЕ удаляем файл — проверяем, что temp подчищает контроллер.
  }

  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) => _amp.stream;

  // C2: тест толкает «живые» амплитуды в поток рекордера.
  void pushAmplitude(double current) {
    _amp.add(Amplitude(current: current, max: 0));
  }

  @override
  Future<void> dispose() async {
    await _amp.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('rec_ctrl_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('гард: повторный start() во время requestingPermission не дублирует',
      () async {
    var permCalls = 0;
    final completer = Completer<bool>();
    final recorder = _FakeRecorder();
    final controller = ChatRecordingController(
      recorder: recorder,
      permissionRequester: () {
        permCalls++;
        return completer.future;
      },
    );
    addTearDown(controller.dispose);

    final first = controller.start();
    // Первый вызов завис на запросе разрешения.
    expect(controller.state, ChatRecordingState.requestingPermission);

    // Повторный вызов обязан мгновенно выйти — без второго запроса.
    await controller.start();
    expect(permCalls, 1);

    completer.complete(true);
    await first;

    expect(controller.state, ChatRecordingState.recording);
    expect(recorder.startCalls, 1);

    await controller.cancelCurrent();
  });

  test('отказ в разрешении → denied, запись не стартует', () async {
    final recorder = _FakeRecorder();
    final controller = ChatRecordingController(
      recorder: recorder,
      permissionRequester: () async => false,
    );
    addTearDown(controller.dispose);

    await controller.start();

    expect(controller.state, ChatRecordingState.denied);
    expect(recorder.startCalls, 0);
    expect(controller.errorText, isNotNull);
  });

  test('ошибка recorder.start() → idle, не зависаем в requestingPermission',
      () async {
    final recorder = _FakeRecorder(startError: true);
    final controller = ChatRecordingController(
      recorder: recorder,
      permissionRequester: () async => true,
    );
    addTearDown(controller.dispose);

    await controller.start();

    expect(controller.state, ChatRecordingState.idle);
    expect(controller.errorText, isNotNull);
    // Рекордер пытались отменить в рамках очистки.
    expect(recorder.cancelCalls, 1);
  });

  test('C2: liveWaveform наполняется по амплитуде и шлёт notify', () async {
    final recorder = _FakeRecorder();
    final controller = ChatRecordingController(
      recorder: recorder,
      permissionRequester: () async => true,
    );
    addTearDown(controller.dispose);

    await controller.start();
    expect(controller.state, ChatRecordingState.recording);
    expect(controller.liveWaveform, isEmpty);

    var notifies = 0;
    controller.addListener(() => notifies++);

    recorder.pushAmplitude(-12);
    recorder.pushAmplitude(-6);
    await Future<void>.delayed(Duration.zero);

    expect(controller.liveWaveform.length, 2);
    expect(
      controller.liveWaveform.every((value) => value >= 0 && value <= 1),
      isTrue,
    );
    expect(notifies, greaterThanOrEqualTo(2),
        reason: 'каждая амплитуда должна перерисовывать живую волну');

    await controller.cancelCurrent();
  });

  test('C2: liveWaveform держит скользящее окно последних замеров', () async {
    final recorder = _FakeRecorder();
    final controller = ChatRecordingController(
      recorder: recorder,
      permissionRequester: () async => true,
    );
    addTearDown(controller.dispose);

    await controller.start();
    for (var i = 0; i < ChatRecordingController.liveWaveformBins + 15; i++) {
      recorder.pushAmplitude(-10);
    }
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.liveWaveform.length,
      ChatRecordingController.liveWaveformBins,
    );

    await controller.cancelCurrent();
  });

  test('cancelCurrent() удаляет временный файл записи', () async {
    final recorder = _FakeRecorder(createFile: true);
    final controller = ChatRecordingController(
      recorder: recorder,
      permissionRequester: () async => true,
    );
    addTearDown(controller.dispose);

    await controller.start();
    expect(controller.state, ChatRecordingState.recording);

    final recordedPath = recorder.lastPath;
    expect(recordedPath, isNotNull);
    expect(File(recordedPath!).existsSync(), isTrue,
        reason: 'старт должен был создать temp-файл');

    await controller.cancelCurrent();

    expect(controller.state, ChatRecordingState.idle);
    expect(File(recordedPath).existsSync(), isFalse,
        reason: 'cancelCurrent обязан удалить temp-файл записи');
    expect(controller.preview, isNull);
    expect(controller.durationSeconds, 0);
  });
}
