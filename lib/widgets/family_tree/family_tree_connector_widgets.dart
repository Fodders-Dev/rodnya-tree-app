part of '../interactive_family_tree.dart';

class _ConnectorRelationTypePicker extends StatelessWidget {
  const _ConnectorRelationTypePicker({
    required this.sourceName,
    required this.targetName,
  });

  final String sourceName;
  final String targetName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Кто такие друг другу?',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Выберите связь между «$sourceName» и «$targetName»',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _ConnectorRelationButton(
                  icon: Icons.escalator_warning_outlined,
                  label: 'Родитель → ребёнок',
                  // Source is the PARENT of the target — that's the
                  // direction the user dragged. If they meant
                  // "child of" they should drag the other way.
                  relationType: RelationType.parent,
                ),
                const SizedBox(width: 10),
                _ConnectorRelationButton(
                  icon: Icons.favorite_outline,
                  label: 'Супруги',
                  relationType: RelationType.spouse,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _ConnectorRelationButton(
                  icon: Icons.family_restroom_outlined,
                  label: 'Брат/сестра',
                  relationType: RelationType.sibling,
                ),
                const SizedBox(width: 10),
                _ConnectorRelationButton(
                  icon: Icons.more_horiz_rounded,
                  label: 'Другая связь',
                  relationType: RelationType.other,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Отмена'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact chip used as the LongPressDraggable.feedback during an
/// edge-first connect drag. Shows the source person's name on a
/// small accent pill so the user always sees what they're carrying.
/// We avoid using the full card as feedback because the card's
/// internal Column overflows when wrapped in the Overlay's
/// unbounded constraints.
class _ConnectorDragFeedbackChip extends StatelessWidget {
  const _ConnectorDragFeedbackChip({
    required this.label,
    required this.color,
    required this.foreground,
  });

  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cable_rounded, size: 16, color: foreground),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              label.isEmpty ? '...' : label,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Live preview line drawn from the long-pressed source card to
/// wherever the user's pointer currently is. Dashed + accent color
/// so the user reads it as "in progress, not yet a real edge".
/// Repainted only while the user is actively dragging — when the
class _ConnectorRelationButton extends StatelessWidget {
  const _ConnectorRelationButton({
    required this.icon,
    required this.label,
    required this.relationType,
  });

  final IconData icon;
  final String label;
  final RelationType relationType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).pop(relationType),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(
                  alpha: 0.6,
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: theme.colorScheme.primary, size: 28),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact "Новый человек" dialog used by the canvas-level
/// blank-card creator. Asks for the bare minimum to seed a person
/// node — name parts + gender — and pops with a `personData` map
/// the host pipes to family_tree_service.addRelative(...) WITHOUT
/// a follow-up createRelation call. Relations get added later by
/// the user via the edge-first connector.
///
/// Deliberately simpler than AddRelativeScreen — no birth/death
/// dates, no photo upload, no relationship-type picker. The user
/// is in flow ("I want to throw down a card and connect it"); we
