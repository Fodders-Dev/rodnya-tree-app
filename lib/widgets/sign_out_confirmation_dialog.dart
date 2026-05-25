import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../utils/photo_url.dart';
import 'flow_overlays.dart';

/// Ship Q3 (2026-05-26): confirmation dialog для sign-out. Закрывает
/// Critical #1 из UX audit 2026-05-25: «accidental sign out without
/// confirmation caused session loss during audit».
///
/// Surfaces identity preview (avatar + display name + email) так
/// что user видит exactly из какого аккаунта выходит. `barrierDismissible
/// = false` чтобы случайный tap outside не считался за confirmation.
///
/// Returns `true` если user explicitly confirmed «Выйти», `false`
/// либо `null` при Отмена / dismiss. Caller should treat anything
/// except `true` as «не выходить».
Future<bool> showSignOutConfirmationDialog(
  BuildContext context,
  AuthServiceInterface authService,
) async {
  final result = await showGlassDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => SignOutConfirmationDialog(
      displayName: authService.currentUserDisplayName,
      email: authService.currentUserEmail,
      photoUrl: authService.currentUserPhotoUrl,
    ),
  );
  return result == true;
}

class SignOutConfirmationDialog extends StatelessWidget {
  const SignOutConfirmationDialog({
    super.key,
    this.displayName,
    this.email,
    this.photoUrl,
  });

  final String? displayName;
  final String? email;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final identityName = (displayName ?? '').trim();
    final identityEmail = (email ?? '').trim();
    final fallbackInitial = identityName.isNotEmpty
        ? identityName[0]
        : (identityEmail.isNotEmpty ? identityEmail[0] : '?');

    return GlassDialogFrame(
      icon: Icons.logout_rounded,
      tint: theme.colorScheme.error,
      title: 'Выйти из аккаунта?',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Identity preview row — avatar + name + email. Audit
          // recommendation: «sign out should show account identity».
          // Без этого пользователь не видит, из какого именно
          // аккаунта выходит (например, если на устройстве было
          // несколько сессий).
          Row(
            children: [
              _IdentityAvatar(
                photoUrl: photoUrl,
                fallbackInitial: fallbackInitial,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      identityName.isNotEmpty
                          ? identityName
                          : 'Текущий аккаунт',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (identityEmail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        identityEmail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'На этом устройстве нужно будет войти снова.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('sign-out-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton.tonal(
          key: const Key('sign-out-confirm'),
          style: FilledButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
            backgroundColor: theme.colorScheme.errorContainer,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Выйти'),
        ),
      ],
    );
  }
}

class _IdentityAvatar extends StatelessWidget {
  const _IdentityAvatar({
    required this.photoUrl,
    required this.fallbackInitial,
    required this.color,
  });

  final String? photoUrl;
  final String fallbackInitial;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final normalized = normalizePhotoUrl(photoUrl);
    final placeholder = CircleAvatar(
      radius: 24,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Text(
        fallbackInitial.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    if (normalized == null || normalized.isEmpty) {
      return placeholder;
    }
    return ClipOval(
      child: SizedBox(
        width: 48,
        height: 48,
        child: CachedNetworkImage(
          imageUrl: normalized,
          fit: BoxFit.cover,
          placeholder: (_, __) => placeholder,
          errorWidget: (_, __, ___) => placeholder,
        ),
      ),
    );
  }
}
