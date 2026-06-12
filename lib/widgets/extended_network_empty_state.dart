import 'package:flutter/material.dart';

/// Phase 6 chunk 4c (PHASE-6-PROPOSAL.md §2.7): empty-state guidance
/// для extended view когда slice loaded but contains no foreign
/// nodes (`ownerMap.isEmpty`).
///
/// Rendered as a banner card above tree canvas (не replaces canvas
/// — user still sees own tree). Tone: future-positive («появится,
/// когда»), не sad («У вас нет родственников»).
///
/// CTAs invoke callbacks injected by caller — keeps widget pure
/// presentation, parent owns navigation:
///   • `onShareInvitation` — copies invite link для семьи (existing
///     Phase 1 invite flow).
///   • `onFindRelatives` — opens discover «мы родственники?» screen
///     (Phase 6 chunk 3, `/discover/relatives`).
class ExtendedNetworkEmptyState extends StatelessWidget {
  const ExtendedNetworkEmptyState({
    super.key,
    required this.onShareInvitation,
    required this.onFindRelatives,
    this.onDismiss,
    this.onBackToMine,
  });

  final VoidCallback onShareInvitation;
  final VoidCallback onFindRelatives;

  /// Закрыть карточку (владелец решает, помнить ли выбор). Карточка
  /// висит ПОВЕРХ канваса — без крестика она запирала просмотр дерева.
  final VoidCallback? onDismiss;

  /// Выйти из режима «Все» обратно к своему дереву — главный «выход»,
  /// который на телефоне иначе спрятан в фильтрах.
  final VoidCallback? onBackToMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.18),
          width: 0.7,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (onDismiss != null)
            Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  key: const Key('extended-empty-dismiss'),
                  tooltip: 'Скрыть',
                  padding: EdgeInsets.zero,
                  onPressed: onDismiss,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 22,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          Icon(
            Icons.diversity_3_rounded,
            size: 44,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 14),
          Text(
            'Пока никого не нашлось через ваше дерево',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Расширенная сеть появится, когда кто-то из ваших родных '
            'тоже соберёт своё дерево либо подтвердит связь через '
            '«Найти родню».',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onShareInvitation,
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('Поделиться приглашением'),
              ),
              OutlinedButton.icon(
                onPressed: onFindRelatives,
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: const Text('Найти родню'),
              ),
            ],
          ),
          if (onBackToMine != null) ...[
            const SizedBox(height: 6),
            TextButton(
              key: const Key('extended-empty-back-to-mine'),
              onPressed: onBackToMine,
              child: const Text('Показать моё дерево'),
            ),
          ],
        ],
      ),
    );
  }
}
