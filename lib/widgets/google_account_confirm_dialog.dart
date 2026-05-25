import 'package:flutter/material.dart';

import '../backend/models/google_account_preview.dart';
import '../theme/app_theme.dart';

/// Ship Q2 (2026-05-25): confirmation dialog shown после Google
/// chooser returns account info, ПЕРЕД backend session exchange.
/// Surfaces «Войти в Родню как X (email)?» в нашем UI voice так что
/// user видит exactly which account is about to be used.
///
/// Triggered by Артёма call с мамой: Google chooser показал только
/// Артёма's account on his old phone → мама by reflex picked it →
/// landed в его production. This dialog catches that pattern.
///
/// Three outcomes:
///   • `confirm`        — user explicitly chose this account, proceed.
///   • `switchAccount`  — user wants different account (Google signOut + retry).
///   • `cancel`         — user closes dialog без выбора → auth aborted.
///
/// Static helper [showGoogleAccountConfirmDialog] handles barrierDismissible
/// = false (force explicit choice) + returns sentinel `cancel` when
/// pop'нут другим способом.
Future<GoogleAccountConfirmDecision> showGoogleAccountConfirmDialog(
  BuildContext context,
  GoogleAccountPreview preview,
) async {
  final result = await showDialog<GoogleAccountConfirmDecision>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => GoogleAccountConfirmDialog(preview: preview),
  );
  return result ?? GoogleAccountConfirmDecision.cancel;
}

class GoogleAccountConfirmDialog extends StatelessWidget {
  const GoogleAccountConfirmDialog({super.key, required this.preview});

  final GoogleAccountPreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (isDark ? RodnyaDesignTokens.dark : RodnyaDesignTokens.light);

    return AlertDialog(
      title: const Text('Подтвердите вход'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _AccountAvatar(
                photoUrl: preview.photoUrl,
                fallbackInitial: preview.displayName.isNotEmpty
                    ? preview.displayName[0]
                    : '?',
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preview.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: tokens.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preview.email,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.inkSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Войти в Родню под этим Google-аккаунтом?',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.inkSecondary,
            ),
          ),
        ],
      ),
      actionsOverflowDirection: VerticalDirection.up,
      actions: [
        TextButton(
          key: const Key('google-confirm-switch-account'),
          onPressed: () => Navigator.of(context).pop(
            GoogleAccountConfirmDecision.switchAccount,
          ),
          child: const Text('Сменить аккаунт'),
        ),
        TextButton(
          key: const Key('google-confirm-cancel'),
          onPressed: () => Navigator.of(context).pop(
            GoogleAccountConfirmDecision.cancel,
          ),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const Key('google-confirm-proceed'),
          onPressed: () => Navigator.of(context).pop(
            GoogleAccountConfirmDecision.confirm,
          ),
          child: const Text('Войти'),
        ),
      ],
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({
    required this.photoUrl,
    required this.fallbackInitial,
    required this.color,
  });

  final String? photoUrl;
  final String fallbackInitial;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl?.trim();
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: color.withValues(alpha: 0.15),
        child: Text(
          fallbackInitial.toUpperCase(),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: color.withValues(alpha: 0.15),
      foregroundImage: NetworkImage(url),
      child: Text(
        fallbackInitial.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
