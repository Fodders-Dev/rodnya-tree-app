import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// CA1: контракт нативного аудиороутера звонка — seam для тестов
/// (AudioRouteService зависит от него, а не от MethodChannel напрямую).
abstract class CallAudioRouter {
  /// FR5: уведомления о смене аудиоустройств (BT/провод подключили/убрали).
  Stream<void> get deviceChanges;

  /// FR1: режим связи + аудиофокус на старте звонка.
  Future<void> start();

  /// FR1: отпустить фокус, очистить маршрут, вернуть mode на завершении.
  Future<void> stop();

  /// FR2: применить маршрут. true при успехе.
  Future<bool> setRoute(String routeId);

  /// FR5: фактический активный маршрут (для отражения в UI).
  Future<String?> currentRoute();

  /// Гигиена звонков: PROXIMITY_SCREEN_OFF_WAKE_LOCK — гасить экран,
  /// когда телефон у уха (аудио-звонок на ушном динамике).
  Future<void> setProximityEnabled(bool enabled);

  /// P0 teardown: Dart-рингер (audioplayers, AndroidAudioMode.ringtone)
  /// оставляет AudioManager в MODE_RINGTONE после остановки. Возвращает
  /// режим в NORMAL, но только когда НЕ идёт активная call-audio сессия
  /// (guard на !active в нативе) — иначе рокер громкости залипает на
  /// ring-стриме и кнопки громкости телефона «перестают работать».
  Future<void> resetRingtoneModeIfIdle();

  void dispose();
}

/// CA1: тонкая обёртка над нативным каналом аудиороутинга звонка
/// (`rodnya/call_audio`, см. RodnyaCallAudioBridge.kt). Только Android —
/// на web/iOS роутинг остаётся через LiveKit. Все вызовы best-effort:
/// сбой натива не должен ронять звонок.
class NativeCallAudio implements CallAudioRouter {
  NativeCallAudio({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('rodnya/call_audio') {
    // Канал rodnya/call_audio один на процесс, а обработчик у MethodChannel
    // ровно один (last-writer-wins). Запоминаем владельца, чтобы dispose
    // случайного второго экземпляра не снял обработчик у живого звонка
    // (ревью A: защита в глубину к фиксу в settings_screen).
    _handlerOwner = this;
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  /// Текущий владелец обработчика общего канала (последний созданный).
  static NativeCallAudio? _handlerOwner;

  final MethodChannel _channel;
  final StreamController<void> _deviceChanges =
      StreamController<void>.broadcast();

  /// FR5: нативная сторона дёргает это при подключении/отключении
  /// аудиоустройств (BT/провод) — чтобы UI отражал реальность.
  @override
  Stream<void> get deviceChanges => _deviceChanges.stream;

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onAudioDevicesChanged' && !_deviceChanges.isClosed) {
      _deviceChanges.add(null);
    }
  }

  /// FR1: режим связи + аудиофокус на старте звонка.
  @override
  Future<void> start() async {
    await _invoke<void>('start');
  }

  /// FR1: отпустить фокус, очистить маршрут, вернуть mode на завершении.
  @override
  Future<void> stop() async {
    await _invoke<void>('stop');
  }

  /// FR2: применить маршрут (id из AudioRouteService). true при успехе.
  @override
  Future<bool> setRoute(String routeId) async {
    final ok = await _invoke<bool>('setRoute', {'route': routeId});
    return ok ?? false;
  }

  /// FR5: фактический активный маршрут (для отражения в UI).
  @override
  Future<String?> currentRoute() async {
    return _invoke<String?>('currentRoute');
  }

  /// Гигиена звонков: датчик приближения гасит экран у уха. Kotlin-мост
  /// дополнительно отпускает лок в stop()/teardown() (страховка).
  @override
  Future<void> setProximityEnabled(bool enabled) async {
    await _invoke<void>('setProximity', {'enabled': enabled});
  }

  /// P0 teardown: сброс залипшего MODE_RINGTONE после Dart-рингера. Гард на
  /// активную сессию — в нативе (see resetRingtoneModeIfIdle).
  @override
  Future<void> resetRingtoneModeIfIdle() async {
    await _invoke<void>('resetRingtoneModeIfIdle');
  }

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } catch (error) {
      debugPrint('[call-audio] $method failed: $error');
      return null;
    }
  }

  @override
  void dispose() {
    unawaited(_deviceChanges.close());
    // Снимаем обработчик общего канала ТОЛЬКО если им всё ещё владеем мы —
    // иначе dispose чужого экземпляра обнулил бы живой обработчик звонка.
    if (identical(_handlerOwner, this)) {
      _channel.setMethodCallHandler(null);
      _handlerOwner = null;
    }
  }
}
