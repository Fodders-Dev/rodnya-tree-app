import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

Color callConnectionQualityColor(
  ConnectionQuality quality, {
  bool isReconnecting = false,
}) {
  if (isReconnecting) {
    return const Color(0xFFFFC857);
  }
  switch (quality) {
    case ConnectionQuality.excellent:
      return const Color(0xFF4ADE80);
    case ConnectionQuality.good:
      return const Color(0xFFFBBF24);
    case ConnectionQuality.poor:
      return const Color(0xFFFB923C);
    case ConnectionQuality.lost:
      return const Color(0xFFEF4444);
    case ConnectionQuality.unknown:
      return const Color(0xFFCBD5E1);
  }
}

String callConnectionQualityLabel(
  ConnectionQuality quality, {
  bool isReconnecting = false,
}) {
  if (isReconnecting) {
    return 'Переподключение';
  }
  switch (quality) {
    case ConnectionQuality.excellent:
      return 'Связь отличная';
    case ConnectionQuality.good:
      return 'Связь хорошая';
    case ConnectionQuality.poor:
      return 'Слабая связь';
    case ConnectionQuality.lost:
      return 'Связь потеряна';
    case ConnectionQuality.unknown:
      return 'Качество связи...';
  }
}

IconData callConnectionQualityIcon(
  ConnectionQuality quality, {
  bool isReconnecting = false,
}) {
  if (isReconnecting) {
    return Icons.sync_rounded;
  }
  switch (quality) {
    case ConnectionQuality.excellent:
    case ConnectionQuality.good:
      return Icons.wifi_rounded;
    case ConnectionQuality.poor:
    case ConnectionQuality.lost:
      return Icons.wifi_off_rounded;
    case ConnectionQuality.unknown:
      return Icons.wifi_rounded;
  }
}

class CallConnectionQualityBadge extends StatelessWidget {
  const CallConnectionQualityBadge({
    super.key,
    required this.quality,
    this.isReconnecting = false,
    this.compact = false,
  });

  final ConnectionQuality quality;
  final bool isReconnecting;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = callConnectionQualityColor(
      quality,
      isReconnecting: isReconnecting,
    );
    final label = callConnectionQualityLabel(
      quality,
      isReconnecting: isReconnecting,
    );
    final icon = callConnectionQualityIcon(
      quality,
      isReconnecting: isReconnecting,
    );

    return Tooltip(
      message: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.72)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 5 : 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: color,
                size: compact ? 14 : 16,
              ),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
