import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:rodnya/screens/call_screen.dart';

void main() {
  group('formatCallDuration', () {
    test('до часа — м:сс', () {
      expect(formatCallDuration(Duration.zero), '0:00');
      expect(formatCallDuration(const Duration(seconds: 5)), '0:05');
      expect(formatCallDuration(const Duration(minutes: 12, seconds: 34)),
          '12:34');
      expect(formatCallDuration(const Duration(minutes: 59, seconds: 59)),
          '59:59');
    });

    test('после часа — ч:мм:сс', () {
      expect(formatCallDuration(const Duration(hours: 1)), '1:00:00');
      expect(
        formatCallDuration(
          const Duration(hours: 1, minutes: 2, seconds: 33),
        ),
        '1:02:33',
      );
    });

    test('отрицательный дрейф клампится в ноль', () {
      expect(formatCallDuration(const Duration(seconds: -7)), '0:00');
    });
  });

  group('resolveAdaptiveVideoFit', () {
    test('неизвестные аспекты → contain (безопасный default)', () {
      expect(
        resolveAdaptiveVideoFit(videoAspect: null, stageAspect: 0.5),
        VideoViewFit.contain,
      );
      expect(
        resolveAdaptiveVideoFit(videoAspect: 1.7, stageAspect: null),
        VideoViewFit.contain,
      );
      expect(
        resolveAdaptiveVideoFit(videoAspect: 0, stageAspect: 0.5),
        VideoViewFit.contain,
      );
    });

    test('совпадающая ориентация → cover (16:9 видео на 19.5:9 экране)', () {
      expect(
        resolveAdaptiveVideoFit(
          videoAspect: 9 / 16,
          stageAspect: 9 / 19.5,
        ),
        VideoViewFit.cover,
      );
      // Desktop: landscape видео на широкой сцене.
      expect(
        resolveAdaptiveVideoFit(videoAspect: 16 / 9, stageAspect: 1.6),
        VideoViewFit.cover,
      );
    });

    test('поворот собеседника (мисматч ориентаций) → contain', () {
      // Landscape 16:9 видео на portrait-сцене телефона.
      expect(
        resolveAdaptiveVideoFit(
          videoAspect: 16 / 9,
          stageAspect: 9 / 19.5,
        ),
        VideoViewFit.contain,
      );
      // Portrait видео в широкой групповой плитке.
      expect(
        resolveAdaptiveVideoFit(videoAspect: 9 / 16, stageAspect: 1.6),
        VideoViewFit.contain,
      );
    });
  });
}
