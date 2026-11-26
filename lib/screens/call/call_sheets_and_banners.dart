import 'package:flutter/material.dart';

import '../../models/chat_details.dart';
import '../../services/audio_route_service.dart';
import '../../utils/photo_url.dart';
import 'call_formatters.dart';

Future<String?> showAddCallParticipantSheet({
  required BuildContext context,
  required List<ChatParticipantSummary> addableParticipants,
}) {
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Добавить в звонок',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ),
          for (final participant in addableParticipants)
            ListTile(
              leading: CircleAvatar(
                backgroundImage: buildAvatarImageProvider(participant.photoUrl),
                child: buildAvatarImageProvider(participant.photoUrl) == null
                    ? Text(
                        participant.displayName.trim().isNotEmpty
                            ? participant.displayName.trim()[0].toUpperCase()
                            : '?',
                      )
                    : null,
              ),
              title: Text(participant.displayName),
              trailing: const Icon(Icons.person_add_alt_1),
              onTap: () => Navigator.of(context).pop(participant.userId),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class CallAudioRouteSheet extends StatelessWidget {
  const CallAudioRouteSheet({super.key, required this.service});

  final AudioRouteService service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: AnimatedBuilder(
        animation: service,
        builder: (context, _) {
          final routes = service.routes;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.spatial_audio_off_rounded),
                    const SizedBox(width: 10),
                    Text(
                      'Аудиовыход',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (service.isRefreshing && routes.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (routes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Аудиовыходы не найдены.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  ...routes.map(
                    (route) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(audioRouteIcon(route.type)),
                      title: Text(route.label),
                      trailing: service.isSelecting &&
                              service.selectedRouteId == route.id
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : service.selectedRouteId == route.id
                              ? Icon(
                                  Icons.check_rounded,
                                  color: theme.colorScheme.primary,
                                )
                              : null,
                      onTap: service.isSelecting
                          ? null
                          : () async {
                              await service.selectRoute(route);
                              if (context.mounted &&
                                  service.errorMessage == null) {
                                Navigator.of(context).pop();
                              }
                            },
                    ),
                  ),
                if (service.errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    service.errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class CallReconnectBanner extends StatelessWidget {
  const CallReconnectBanner({
    super.key,
    required this.isReconnecting,
    required this.isRestored,
    this.message,
  });

  final bool isReconnecting;
  final bool isRestored;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = isReconnecting
        ? 'Восстанавливаем звонок. Звук вернётся автоматически.'
        : isRestored
            ? 'Соединение восстановлено.'
            : message ?? 'Проверяем соединение.';
    final color = isRestored
        ? const Color(0xFF4ADE80)
        : isReconnecting
            ? const Color(0xFFFFC857)
            : const Color(0xFFEF4444);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.56)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isRestored ? Icons.check_circle_rounded : Icons.sync_rounded,
                  color: color,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            if (isReconnecting) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  color: color,
                  backgroundColor: Colors.white.withValues(alpha: 0.16),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
