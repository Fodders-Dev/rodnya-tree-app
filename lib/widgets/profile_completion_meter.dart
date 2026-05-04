import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../theme/app_theme.dart';

/// One field the profile-completion meter can recommend filling.
class _CompletionItem {
  const _CompletionItem({required this.label, required this.filled});
  final String label;
  final bool filled;
}

/// Lightweight onboarding nudge for the profile screen — shows "X из Y
/// заполнено" with a progress bar and an inline list of remaining
/// items. Tapping the card opens the profile editor. Hidden entirely
/// when all checked items are filled (so it doesn't clutter complete
/// profiles).
///
/// Pulled out of profile_screen so the score logic is testable without
/// mounting the whole screen.
class ProfileCompletionMeter extends StatelessWidget {
  const ProfileCompletionMeter({
    super.key,
    required this.profile,
    required this.onTap,
  });

  final UserProfile profile;
  final VoidCallback onTap;

  /// The fields we count toward completion. Picked to be the items the
  /// user gets the most value from filling — avatar shows up in every
  /// surface, name lets others find them, birth date drives the events
  /// digest, city anchors them geographically, bio adds personality.
  static const _itemDefinitions = [
    'Аватар',
    'Имя',
    'Дата рождения',
    'Город',
    'О себе',
  ];

  static List<_CompletionItem> _itemsFor(UserProfile profile) {
    return [
      _CompletionItem(
        label: _itemDefinitions[0],
        filled: (profile.photoURL ?? '').trim().isNotEmpty,
      ),
      _CompletionItem(
        label: _itemDefinitions[1],
        filled: profile.firstName.trim().isNotEmpty ||
            profile.displayName.trim().isNotEmpty,
      ),
      _CompletionItem(
        label: _itemDefinitions[2],
        filled: profile.birthDate != null,
      ),
      _CompletionItem(
        label: _itemDefinitions[3],
        filled: (profile.city ?? '').trim().isNotEmpty,
      ),
      _CompletionItem(
        label: _itemDefinitions[4],
        filled: profile.bio.trim().isNotEmpty,
      ),
    ];
  }

  /// Public wrapper for tests / external callers — score in 0..100.
  static int scoreFor(UserProfile profile) {
    final items = _itemsFor(profile);
    if (items.isEmpty) return 0;
    final filled = items.where((i) => i.filled).length;
    return ((filled / items.length) * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    final items = _itemsFor(profile);
    final filled = items.where((i) => i.filled).length;
    final total = items.length;
    if (filled >= total) {
      return const SizedBox.shrink();
    }
    final progress = filled / total;
    final missing = items.where((i) => !i.filled).toList();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        child: Container(
          decoration: BoxDecoration(
            color: tokens.surfaceStrong,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.surfaceLine),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tokens.accentSoft,
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                    child: Icon(
                      Icons.rocket_launch_outlined,
                      color: tokens.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Заполните профиль',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: tokens.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Готово $filled из $total · ещё немного и родня узнает вас лучше',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tokens.inkSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${(progress * 100).round()}%',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: tokens.accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: tokens.surfaceLine,
                  valueColor: AlwaysStoppedAnimation(tokens.accent),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: missing
                    .map(
                      (item) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.bgBase.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: tokens.surfaceLine),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add,
                              size: 14,
                              color: tokens.inkSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              item.label,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: tokens.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
