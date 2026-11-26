part of '../tree_view_screen.dart';

class _IdentitySuggestionsSheet extends StatelessWidget {
  const _IdentitySuggestionsSheet({
    required this.suggestions,
    required this.onConfirm,
    required this.onDismiss,
  });

  final List<IdentitySuggestion> suggestions;
  final Future<void> Function(IdentitySuggestion suggestion) onConfirm;
  final Future<void> Function(IdentitySuggestion suggestion) onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.lightbulb_outline_rounded,
                    color: scheme.tertiary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Возможные дубликаты',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        suggestions.length == 1
                            ? 'Кажется, этот человек уже есть в одном из ваших деревьев. Связать карточки?'
                            : 'Кажется, этот человек уже есть в ${suggestions.length} ваших деревьях. Связать?',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final suggestion in suggestions) ...[
              _SuggestionRow(
                suggestion: suggestion,
                onConfirm: () => onConfirm(suggestion),
                onDismiss: () => onDismiss(suggestion),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.suggestion,
    required this.onConfirm,
    required this.onDismiss,
  });

  final IdentitySuggestion suggestion;
  final Future<void> Function() onConfirm;
  final Future<void> Function() onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reasons = suggestion.reasons.join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: suggestion.targetPhotoUrl != null &&
                        suggestion.targetPhotoUrl!.isNotEmpty
                    ? NetworkImage(suggestion.targetPhotoUrl!)
                    : null,
                backgroundColor: scheme.surfaceContainer,
                child: suggestion.targetPhotoUrl == null
                    ? Text(
                        suggestion.targetDisplayName.isNotEmpty
                            ? suggestion.targetDisplayName[0]
                            : '?',
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suggestion.targetDisplayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (suggestion.targetTreeName.isNotEmpty)
                      Text(
                        'Из «${suggestion.targetTreeName}»',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: suggestion.confidence == 'high'
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${(suggestion.score * 100).round()}%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: suggestion.confidence == 'high'
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              reasons,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Не он'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onConfirm,
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: const Text('Связать'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Phase 3.4 chunk 5: _IdentityConflictsSheet + _ConflictRow +
// _ConflictSide + _kIdentityConflictFieldLabels / helpers
// extracted into [`lib/widgets/identity_conflicts_sheet.dart`]
// (reusable across canvas + relative_details + relatives_screen).
// Behavior-preserving move; old test'ы tree_view_screen зелёные.

// ── Phase 4: «Кем мы приходимся?» result sheet ─────────────────────
// Header with the relationship label, then a horizontal strip of
// avatars connecting the viewer to the target person, with arrows
// between cards showing the edge direction (UP/DOWN/LATERAL).
