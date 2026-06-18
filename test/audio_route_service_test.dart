import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:rodnya/services/audio_route_service.dart';
import 'package:rodnya/services/native_call_audio.dart';

void main() {
  test('AudioRouteService builds mobile routes from fallback and devices',
      () async {
    final service = AudioRouteService(
      enableNativeAudio: false,
      isMobilePlatform: true,
      enumerateAudioOutputs: () async => const <MediaDevice>[
        MediaDevice('bluetooth', 'AirPods', 'audiooutput', null),
        MediaDevice('wired-headset', '', 'audiooutput', null),
      ],
      selectAudioRoute: (_, __) async {},
      deviceChanges: const Stream<List<MediaDevice>>.empty(),
    );

    await service.attachRoom(null);
    await service.refreshRoutes();

    expect(service.routes.map((route) => route.id), [
      'speaker',
      'earpiece',
      'bluetooth',
      'wired-headset',
    ]);
    expect(service.routes[2].label, 'AirPods');
    expect(service.routes[3].label, 'Проводные');
    expect(service.selectedRouteId, 'speaker');
  });

  test('AudioRouteService selects route through injected selector', () async {
    final selectedIds = <String>[];
    final service = AudioRouteService(
      enableNativeAudio: false,
      isMobilePlatform: true,
      enumerateAudioOutputs: () async => const <MediaDevice>[],
      selectAudioRoute: (option, _) async {
        selectedIds.add(option.id);
      },
      deviceChanges: const Stream<List<MediaDevice>>.empty(),
    );

    await service.refreshRoutes();
    await service.selectRoute(service.routes[1]);

    expect(selectedIds, ['earpiece']);
    expect(service.selectedRouteId, 'earpiece');
    expect(service.errorMessage, isNull);
  });

  test('AudioRouteService refreshes when device list changes', () async {
    final controller = StreamController<List<MediaDevice>>();
    var devices = const <MediaDevice>[];
    final service = AudioRouteService(
      enableNativeAudio: false,
      isMobilePlatform: false,
      enumerateAudioOutputs: () async => devices,
      selectAudioRoute: (_, __) async {},
      deviceChanges: controller.stream,
    );
    addTearDown(controller.close);
    addTearDown(service.dispose);

    await service.attachRoom(_FakeRoom());
    expect(service.routes.map((route) => route.id), ['speaker', 'earpiece']);

    devices = const <MediaDevice>[
      MediaDevice('default-output', 'Системный', 'audiooutput', null),
    ];
    controller.add(devices);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(service.routes.map((route) => route.id), ['default-output']);
    expect(service.routes.single.label, 'Системный');
  });

  // CA1: нативный аудиороутинг (Android).
  test('CA1 FR1+FR3: аудиозвонок стартует натив и дефолтит на ушной',
      (() async {
    final native = _FakeCallAudioRouter();
    final service = AudioRouteService(
      isMobilePlatform: true,
      nativeAudio: native,
      enumerateAudioOutputs: () async => const <MediaDevice>[],
      deviceChanges: const Stream<List<MediaDevice>>.empty(),
    );
    addTearDown(service.dispose);

    await service.attachRoom(_FakeRoom(), isVideo: false);

    expect(native.calls, contains('start')); // FR1
    expect(native.calls, contains('setRoute:earpiece')); // FR3 default
    expect(service.selectedRouteId, 'earpiece');

    await service.attachRoom(null);
    expect(native.calls, contains('stop')); // FR1 teardown
  }));

  test('CA1 teardown: dispose останавливает нативный аудиорежим', (() async {
    final native = _FakeCallAudioRouter();
    final service = AudioRouteService(
      isMobilePlatform: true,
      nativeAudio: native,
      enumerateAudioOutputs: () async => const <MediaDevice>[],
      deviceChanges: const Stream<List<MediaDevice>>.empty(),
    );

    await service.attachRoom(_FakeRoom(), isVideo: false);
    native.calls.clear();

    service.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(native.calls.take(2), ['stop', 'dispose']);
  }));

  test('CA1 FR3: видеозвонок дефолтит на динамик', (() async {
    final native = _FakeCallAudioRouter();
    final service = AudioRouteService(
      isMobilePlatform: true,
      nativeAudio: native,
      enumerateAudioOutputs: () async => const <MediaDevice>[],
      deviceChanges: const Stream<List<MediaDevice>>.empty(),
    );
    addTearDown(service.dispose);

    await service.attachRoom(_FakeRoom(), isVideo: true);

    expect(native.calls, contains('setRoute:speaker'));
    expect(service.selectedRouteId, 'speaker');
  }));

  test('CA1 FR5: успешный выбор отражается сразу, факт сверяется позже',
      (() async {
    final native = _FakeCallAudioRouter()
      ..updateCurrentOnSetRoute = false
      ..current = 'speaker'; // система не переключилась на запрошенное
    final service = AudioRouteService(
      isMobilePlatform: true,
      nativeAudio: native,
      enumerateAudioOutputs: () async => const <MediaDevice>[],
      deviceChanges: const Stream<List<MediaDevice>>.empty(),
    );
    addTearDown(service.dispose);
    await service.attachRoom(_FakeRoom(), isVideo: true);

    await service.selectRoute(
      service.routes.firstWhere((route) => route.id == 'earpiece'),
    );

    // Запросили earpiece, Android может ещё мгновение возвращать speaker:
    // UI показывает принятый выбор сразу, а фактический маршрут сверит
    // отложенный refresh.
    expect(native.calls, contains('setRoute:earpiece'));
    expect(service.selectedRouteId, 'earpiece');
  }));

  test('CA1 FR5: сбой переключения не показывает ложный успех', (() async {
    final native = _FakeCallAudioRouter()
      ..setRouteResult = false
      ..current = null;
    final service = AudioRouteService(
      isMobilePlatform: true,
      nativeAudio: native,
      enumerateAudioOutputs: () async => const <MediaDevice>[],
      deviceChanges: const Stream<List<MediaDevice>>.empty(),
    );
    addTearDown(service.dispose);
    await service.attachRoom(_FakeRoom(), isVideo: false);
    final before = service.selectedRouteId;

    await service.selectRoute(
      service.routes.firstWhere((route) => route.id == 'speaker'),
    );

    expect(service.errorMessage, isNotNull);
    expect(service.selectedRouteId, before); // не «speaker»
  }));

  test('CA1 ревью D: attach сериализован — start завершается до stop',
      (() async {
    final native = _FakeCallAudioRouter();
    final service = AudioRouteService(
      isMobilePlatform: true,
      nativeAudio: native,
      enumerateAudioOutputs: () async => const <MediaDevice>[],
      deviceChanges: const Stream<List<MediaDevice>>.empty(),
    );
    addTearDown(service.dispose);

    // Коннект и завершение «впритык», без await первого — очередь должна
    // прогнать attach(room) целиком, и только потом attach(null).
    final attach = service.attachRoom(_FakeRoom(), isVideo: false);
    final detach = service.attachRoom(null);
    await Future.wait<void>(<Future<void>>[attach, detach]);

    final startIdx = native.calls.indexOf('start');
    final stopIdx = native.calls.indexOf('stop');
    expect(startIdx, isNonNegative);
    expect(stopIdx, isNonNegative);
    expect(startIdx, lessThan(stopIdx)); // не переплелись
    expect(native.calls.last, 'stop');
  }));

  test('CA1 ревью E: быстрый второй тап коалесится в последний маршрут',
      (() async {
    final native = _FakeCallAudioRouter();
    final service = AudioRouteService(
      isMobilePlatform: true,
      nativeAudio: native,
      enumerateAudioOutputs: () async => const <MediaDevice>[],
      deviceChanges: const Stream<List<MediaDevice>>.empty(),
    );
    addTearDown(service.dispose);
    await service.attachRoom(_FakeRoom(), isVideo: true); // дефолт — speaker
    native.calls.clear();

    final speaker = service.routes.firstWhere((route) => route.id == 'speaker');
    final earpiece =
        service.routes.firstWhere((route) => route.id == 'earpiece');
    // Два тапа подряд: второй приходит, пока идёт первый → откладывается.
    final first = service.selectRoute(speaker);
    final second = service.selectRoute(earpiece);
    await Future.wait<void>(<Future<void>>[first, second]);
    // Дать отложенному повтору отработать (unawaited в finally).
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(native.calls, contains('setRoute:earpiece'));
    expect(service.selectedRouteId, 'earpiece'); // победил последний тап
  }));

  test('CA1 ревью FR-E: selectRoute после stop (detach) не применяет маршрут',
      (() async {
    final native = _FakeCallAudioRouter();
    final service = AudioRouteService(
      isMobilePlatform: true,
      nativeAudio: native,
      enumerateAudioOutputs: () async => const <MediaDevice>[],
      deviceChanges: const Stream<List<MediaDevice>>.empty(),
    );
    addTearDown(service.dispose);
    await service.attachRoom(_FakeRoom(), isVideo: false);
    final earpiece =
        service.routes.firstWhere((route) => route.id == 'earpiece');

    await service.attachRoom(null); // завершение звонка → stop
    native.calls.clear();

    // Отложенный/коалесцированный тап уже после stop — должен игнорироваться,
    // иначе нативный setRoute заново поднимет mode для законченного звонка.
    await service.selectRoute(earpiece);

    expect(native.calls, isNot(contains('setRoute:earpiece')),
        reason: 'после stop маршрут не применяется (бридж остановлен)');
  }));
}

class _FakeRoom extends Fake implements Room {}

class _FakeCallAudioRouter implements CallAudioRouter {
  bool setRouteResult = true;
  bool updateCurrentOnSetRoute = true;
  String? current;
  final List<String> calls = <String>[];
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get deviceChanges => _changes.stream;

  @override
  Future<void> start() async {
    calls.add('start');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<bool> setRoute(String routeId) async {
    calls.add('setRoute:$routeId');
    if (setRouteResult && updateCurrentOnSetRoute) {
      current = routeId;
    }
    return setRouteResult;
  }

  @override
  Future<String?> currentRoute() async => current;

  @override
  void dispose() {
    calls.add('dispose');
    unawaited(_changes.close());
  }
}
