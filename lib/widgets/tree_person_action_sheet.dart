import 'package:flutter/material.dart';

import '../models/family_person.dart';
import '../theme/app_theme.dart';
import '../utils/photo_url.dart';

/// Ship Q4 (2026-05-26): bottom sheet с actions для tapped tree person.
/// Закрывает Critical #4 из UX audit 2026-05-25: «Details/edit/delete
/// path for a person is not discoverable from the main card».
///
/// Существующий inline person sheet оставлен intact для edit-mode
/// multi-action workflows. Modal sheet pops on non-edit tap чтобы
/// surfaceить пять action paths очевидным образом:
///   • Открыть профиль
///   • Редактировать
///   • Добавить родственника
///   • Связать с существующим (если еще не linked к real user)
///   • Удалить (с consequence copy)
///
/// Сall through `showTreePersonActionSheet` helper — handles modal
/// lifecycle + safety check `mounted` после await.
Future<void> showTreePersonActionSheet(
  BuildContext context, {
  required FamilyPerson person,
  required VoidCallback onOpenProfile,
  required VoidCallback onEdit,
  required VoidCallback onAddRelative,
  required VoidCallback onConnect,
  required VoidCallback onDelete,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => TreePersonActionSheet(
      person: person,
      onOpenProfile: () {
        Navigator.of(sheetContext).pop();
        onOpenProfile();
      },
      onEdit: () {
        Navigator.of(sheetContext).pop();
        onEdit();
      },
      onAddRelative: () {
        Navigator.of(sheetContext).pop();
        onAddRelative();
      },
      onConnect: () {
        Navigator.of(sheetContext).pop();
        onConnect();
      },
      onDelete: () {
        Navigator.of(sheetContext).pop();
        onDelete();
      },
    ),
  );
}

class TreePersonActionSheet extends StatelessWidget {
  const TreePersonActionSheet({
    super.key,
    required this.person,
    required this.onOpenProfile,
    required this.onEdit,
    required this.onAddRelative,
    required this.onConnect,
    required this.onDelete,
  });

  final FamilyPerson person;
  final VoidCallback onOpenProfile;
  final VoidCallback onEdit;
  final VoidCallback onAddRelative;
  final VoidCallback onConnect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (isDark ? RodnyaDesignTokens.dark : RodnyaDesignTokens.light);
    final lifeDates = _formatLifeDates(person);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: avatar + full name + life dates. Audit explicitly
            // recommends person preview ПЕРЕД actions так что user видит
            // exactly которую карточку трогает.
            Row(
              children: [
                _PersonAvatar(
                  photoUrl: person.photoUrl,
                  fallbackInitial: person.name.isNotEmpty
                      ? person.name[0]
                      : '?',
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (lifeDates.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          lifeDates,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tokens.inkSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 0.6,
              color: tokens.surfaceLine.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 8),
            _ActionTile(
              key: const Key('tree-action-open-profile'),
              icon: Icons.account_circle_outlined,
              label: 'Открыть профиль',
              onTap: onOpenProfile,
            ),
            _ActionTile(
              key: const Key('tree-action-edit'),
              icon: Icons.edit_outlined,
              label: 'Редактировать',
              onTap: onEdit,
            ),
            _ActionTile(
              key: const Key('tree-action-add-relative'),
              icon: Icons.person_add_alt_outlined,
              label: 'Добавить родственника',
              onTap: onAddRelative,
            ),
            _ActionTile(
              key: const Key('tree-action-connect'),
              icon: Icons.link_rounded,
              label: 'Связать с существующим',
              onTap: onConnect,
            ),
            _ActionTile(
              key: const Key('tree-action-delete'),
              icon: Icons.delete_outline_rounded,
              label: 'Удалить',
              isDestructive: true,
              onTap: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  static String _formatLifeDates(FamilyPerson person) {
    final birth = person.birthDate?.year;
    final death = person.deathDate?.year;
    if (birth == null && death == null) return '';
    if (birth != null && death != null) return '$birth – $death';
    if (birth != null) return person.isAlive ? 'Род. $birth' : '$birth – ?';
    return '? – $death';
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isDestructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: color,
          fontWeight: isDestructive ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({
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
      radius: 26,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Text(
        fallbackInitial.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
    );
    final image = buildAvatarImageProvider(normalized);
    if (image == null) return placeholder;
    return CircleAvatar(
      radius: 26,
      backgroundColor: color.withValues(alpha: 0.15),
      foregroundImage: image,
      child: Text(
        fallbackInitial.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
    );
  }
}
