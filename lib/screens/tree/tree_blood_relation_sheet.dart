part of '../tree_view_screen.dart';

class _BloodRelationSheet extends StatelessWidget {
  const _BloodRelationSheet({
    required this.target,
    required this.relation,
  });

  final FamilyPerson target;
  final BloodRelation relation;

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
                    color: scheme.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.account_tree_rounded,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        relation.found
                            ? 'Это ваш${_genderEnding(target.gender.name)} ${relation.label}'
                            : 'Родство не найдено',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (relation.found)
                        Text(
                          'Степень родства: ${relation.degree}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      else
                        Text(
                          'Между вами и ${target.displayName} нет общего предка в дереве. Возможно, нужно добавить пропущенного родственника.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (relation.found && relation.chain.length > 1) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: relation.chain.length * 2 - 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    if (index.isOdd) {
                      // Edge arrow between two avatars.
                      final edgeIndex = (index - 1) ~/ 2;
                      final edge = relation.edges.length > edgeIndex
                          ? relation.edges[edgeIndex]
                          : '';
                      return _BloodRelationArrow(edgeType: edge);
                    }
                    final personIndex = index ~/ 2;
                    final preview = relation.chain[personIndex];
                    return _BloodRelationAvatar(
                      preview: preview,
                      isSelf: personIndex == 0,
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _genderEnding(String? gender) {
    final g = (gender ?? '').toLowerCase();
    if (g == 'female') return 'а';
    return '';
  }
}

class _BloodRelationAvatar extends StatelessWidget {
  const _BloodRelationAvatar({required this.preview, required this.isSelf});

  final BloodRelationPersonPreview preview;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasPhoto = preview.photoUrl != null && preview.photoUrl!.isNotEmpty;
    final initial = (preview.name?.isNotEmpty == true)
        ? preview.name!.substring(0, 1).toUpperCase()
        : '?';
    return SizedBox(
      width: 90,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: scheme.surfaceContainerHigh,
                backgroundImage:
                    hasPhoto ? NetworkImage(preview.photoUrl!) : null,
                child: hasPhoto ? null : Text(initial),
              ),
              if (isSelf)
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Вы',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            preview.name ?? '—',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _BloodRelationArrow extends StatelessWidget {
  const _BloodRelationArrow({required this.edgeType});

  /// `parent` — walker is the parent going DOWN to a child.
  /// `child`  — walker is the child going UP to a parent.
  /// `sibling` — lateral.
  final String edgeType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    IconData icon;
    String hint;
    switch (edgeType) {
      case 'parent':
        icon = Icons.south_rounded; // going down to descendant
        hint = 'ребёнок';
        break;
      case 'child':
        icon = Icons.north_rounded; // going up to ancestor
        hint = 'родитель';
        break;
      case 'sibling':
        icon = Icons.east_rounded; // lateral
        hint = 'брат/сестра';
        break;
      default:
        icon = Icons.east_rounded;
        hint = '';
    }
    return SizedBox(
      width: 32,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(height: 2),
          Text(
            hint,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 9,
            ),
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
