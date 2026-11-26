import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../services/audio_route_service.dart';

/// Формат длительности звонка: «м:сс», после часа — «ч:мм:сс».
String formatCallDuration(Duration elapsed) {
  final totalSeconds = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${two(minutes)}:${two(seconds)}';
  }
  return '$minutes:${two(seconds)}';
}

/// Adaptive fit (Telegram/WhatsApp-поведение): ориентации видео и сцены
/// совпадают → cover (небольшой crop, максимум картинки); сильный
/// мисматч (собеседник повернул телефон) → contain (полный кадр с
/// полосами вместо жёсткого центрального кропа). Порог 1.6 — отношение
/// аспектов: 16:9-видео на 19.5:9-экране (1.22) кропится, landscape
/// 16:9 на portrait-сцене (~3.8) letterbox'ится. Неизвестный аспект
/// (кадры ещё не пошли) → contain, прежнее безопасное поведение.
@pragma('vm:prefer-inline')
VideoViewFit resolveAdaptiveVideoFit({
  required double? videoAspect,
  required double? stageAspect,
}) {
  if (videoAspect == null ||
      stageAspect == null ||
      videoAspect <= 0 ||
      stageAspect <= 0) {
    return VideoViewFit.contain;
  }
  final mismatch = videoAspect > stageAspect
      ? videoAspect / stageAspect
      : stageAspect / videoAspect;
  return mismatch <= 1.6 ? VideoViewFit.cover : VideoViewFit.contain;
}

IconData audioRouteIcon(AudioRouteType? type) {
  switch (type) {
    case AudioRouteType.speaker:
      return Icons.volume_up_rounded;
    case AudioRouteType.earpiece:
      return Icons.phone_in_talk_rounded;
    case AudioRouteType.bluetooth:
      return Icons.bluetooth_audio_rounded;
    case AudioRouteType.wired:
      return Icons.headphones_rounded;
    case AudioRouteType.device:
    case null:
      return Icons.spatial_audio_off_rounded;
  }
}

String audioRouteTooltip(AudioRouteOption? route) {
  switch (route?.type) {
    case AudioRouteType.speaker:
      return 'Переключить на наушник';
    case AudioRouteType.earpiece:
      return 'Переключить на динамик';
    case AudioRouteType.bluetooth:
    case AudioRouteType.wired:
    case AudioRouteType.device:
    case null:
      final label = route?.label;
      if (label == null || label.isEmpty) {
        return 'Аудиовыход';
      }
      return 'Аудиовыход: $label';
  }
}

/// G1: подпись плитки участника группового звонка — имя, иначе identity,
/// иначе позиционный фолбэк «Участник N». Используется и в юнит-тестах
/// (без мока LiveKit Room).
String resolveRemoteParticipantLabel({
  required String name,
  required String identity,
  required int index,
}) {
  final trimmedName = name.trim();
  if (trimmedName.isNotEmpty) {
    return trimmedName;
  }
  final trimmedIdentity = identity.trim();
  if (trimmedIdentity.isNotEmpty) {
    return trimmedIdentity;
  }
  return 'Участник ${index + 1}';
}
