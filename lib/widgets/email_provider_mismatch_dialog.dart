import 'package:flutter/material.dart';

import '../backend/models/email_provider_mismatch.dart';
import 'flow_overlays.dart';

/// Ship Bug B (2026-05-26): disambig modal shown когда backend returns
/// 409 EMAIL_PROVIDER_MISMATCH (cross-provider email collision).
/// Mirrors Q2 confirm-dialog pattern — explicit user choice ПЕРЕД any
/// auth action.
///
/// User options:
///   • «Войти через {provider}» — каждый existing provider gets its own
///     button. Returns provider name (e.g. 'google'). Caller dispatches
///     к correct sign-in flow.
///   • «Отмена» — closes modal без действия. Returns null.
///
/// barrierDismissible=false чтобы user не tap'нул мимо в spиn moment
/// без понимания почему login не сработал.
Future<String?> showEmailProviderMismatchDialog(
  BuildContext context,
  EmailProviderMismatch payload,
) async {
  final result = await showGlassDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) =>
        EmailProviderMismatchDialog(payload: payload),
  );
  return result;
}

class EmailProviderMismatchDialog extends StatelessWidget {
  const EmailProviderMismatchDialog({super.key, required this.payload});

  final EmailProviderMismatch payload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final providers = payload.existingProviders;
    return GlassDialogFrame(
      icon: Icons.shield_outlined,
      tint: theme.colorScheme.primary,
      title: 'Этот email уже используется',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (payload.email.isNotEmpty) ...[
            Text(
              payload.email,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            (payload.message ?? '').isNotEmpty
                ? payload.message!
                : 'Войдите тем способом, который вы привязали раньше — '
                    'после этого вы сможете добавить новый вход в настройках.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('email-provider-mismatch-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        ...providers.map(
          (provider) => FilledButton.tonal(
            key: Key('email-provider-mismatch-pick-$provider'),
            onPressed: () => Navigator.of(context).pop(provider),
            child: Text('Войти через ${_providerLabel(provider)}'),
          ),
        ),
      ],
    );
  }

  static String _providerLabel(String provider) {
    switch (provider) {
      case 'password':
        return 'Email и пароль';
      case 'google':
        return 'Google';
      case 'vk':
        return 'VK ID';
      case 'telegram':
        return 'Telegram';
      case 'max':
        return 'MAX';
      default:
        return provider;
    }
  }
}
