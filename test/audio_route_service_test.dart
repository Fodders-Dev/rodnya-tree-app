import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:rodnya/services/audio_route_service.dart';

void main() {
  test('AudioRouteService builds mobile routes from fallback and devices',
      () async {
    final service = AudioRouteService(
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
}

class _FakeRoom extends Fake implements Room {}
