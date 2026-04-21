import 'package:flutter/material.dart';

import '../models/account_linking_status.dart';
import 'glass_panel.dart';

class AccountTrustSummaryCard extends StatelessWidget {
  const AccountTrustSummaryCard({
    super.key,
    required this.status,
    this.onManage,
  });

  final AccountLinkingStatus status;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trustedChannels = status.trustedChannels;
    final linkedLoginMethods = trustedChannels
        .where((channel) => channel.isLoginMethod && channel.isLinked)
        .map((channel) => channel.label)
        .toList();
    AccountTrustedChannel? primaryChannel;
    for (final channel in trustedChannels) {
      if (channel.isPrimary) {
        primaryChannel = channel;
        break;
      }
    }
    final summaryTitle = status.summaryTitle?.trim().isNotEmpty == true
        ? status.summaryTitle!.trim()
        : 'Подтвердите аккаунт через удобный канал';
    final summaryDetail = status.summaryDetail?.trim().isNotEmpty == true
        ? status.summaryDetail!.trim()
        : 'VK, Telegram, Google и MAX заменяют старую привязку к SMS.';

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.verified_user_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Доверенные каналы',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summaryTitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (onManage != null)
                FilledButton.tonalIcon(
                  onPressed: onManage,
                  icon: const Icon(Icons.tune_outlined, size: 18),
                  label: const Text('Управлять'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            summaryDetail,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (primaryChannel != null || linkedLoginMethods.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest
                    .withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (primaryChannel != null) ...[
                    Text(
                      'Основной канал',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      primaryChannel.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  if (primaryChannel != null && linkedLoginMethods.isNotEmpty)
                    const SizedBox(height: 10),
                  if (linkedLoginMethods.isNotEmpty) ...[
                    Text(
                      'Войти можно через',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      linkedLoginMethods.join(', '),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (trustedChannels.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: trustedChannels
                  .map((channel) => _ChannelChip(channel: channel))
                  .toList(),
            ),
          ],
          if ((status.mergeStrategySummary ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              status.mergeStrategySummary!.trim(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChannelChip extends StatelessWidget {
  const _ChannelChip({required this.channel});

  final AccountTrustedChannel channel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = channel.isPrimary
        ? theme.colorScheme.primary
        : channel.isTrustedChannel
            ? theme.colorScheme.tertiary
            : theme.colorScheme.outline;
    final statusLabel = channel.isPrimary
        ? 'Основной'
        : channel.isTrustedChannel
            ? 'Подтверждён'
            : channel.isLinked
                ? 'Привязан'
                : 'Не привязан';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_providerIcon(channel.provider), size: 18, color: accent),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                channel.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                statusLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _providerIcon(String provider) {
    switch (provider) {
      case 'telegram':
        return Icons.send_outlined;
      case 'vk':
        return Icons.alternate_email_outlined;
      case 'google':
        return Icons.mail_outline_rounded;
      case 'max':
        return Icons.chat_bubble_outline_rounded;
      case 'password':
      default:
        return Icons.lock_outline_rounded;
    }
  }
}
