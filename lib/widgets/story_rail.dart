import 'package:flutter/material.dart';

import '../models/story.dart';
import 'glass_panel.dart';
import 'story_visuals.dart';

class StoryRail extends StatelessWidget {
  const StoryRail({
    super.key,
    required this.title,
    required this.currentUserId,
    required this.stories,
    required this.isLoading,
    required this.onCreateStory,
    required this.onOpenStories,
    this.unavailable = false,
    this.onRetry,
    this.emptyLabel = 'Добавьте первую историю.',
  });

  final String title;
  final String currentUserId;
  final List<Story> stories;
  final bool isLoading;
  final VoidCallback onCreateStory;
  final ValueChanged<List<Story>> onOpenStories;
  final bool unavailable;
  final VoidCallback? onRetry;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final groups = _groupStories();
    final theme = Theme.of(context);

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      borderRadius: BorderRadius.circular(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!isLoading)
                _StoryMetaChip(
                  icon: Icons.bolt_rounded,
                  label: groups.isEmpty ? 'Пусто' : '${groups.length} активн.',
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (isLoading && groups.isEmpty)
            const _StoryLoadingRail()
          else if (unavailable)
            _StoryStatusBanner(
              icon: Icons.cloud_off_outlined,
              label: 'Истории недоступны',
              actionLabel: onRetry == null ? null : 'Повторить',
              onTap: onRetry,
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 106,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: groups.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _StoryAvatarTile.add(
                          onTap: onCreateStory,
                        );
                      }

                      final group = groups[index - 1];
                      return _StoryAvatarTile.story(
                        label: group.authorId == currentUserId
                            ? 'Вы'
                            : group.label,
                        initials: group.initials,
                        imageUrl: group.imageUrl,
                        palette: group.palette,
                        hasUnseen: group.hasUnseen,
                        storyType: group.latestStory.type,
                        badgeCount: group.stories.length,
                        semanticLabel: group.authorId == currentUserId
                            ? 'story-rail-group-own'
                            : 'story-rail-group-${group.authorId}',
                        onTap: () => onOpenStories(group.stories),
                      );
                    },
                  ),
                ),
                if (groups.isEmpty) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      emptyLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  List<_StoryGroup> _groupStories() {
    final groupsByAuthor = <String, List<Story>>{};

    for (final story in stories) {
      groupsByAuthor.putIfAbsent(story.authorId, () => <Story>[]).add(story);
    }

    final groups = groupsByAuthor.entries.map((entry) {
      final authorStories = List<Story>.from(entry.value)
        ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
      final latestStory = authorStories.last;
      final label = latestStory.authorName.trim().isEmpty
          ? 'История'
          : latestStory.authorName;

      return _StoryGroup(
        authorId: entry.key,
        label: label,
        imageUrl: storyCoverUrl(latestStory),
        initials: storyInitialsFor(label),
        stories: authorStories,
        hasUnseen: entry.key == currentUserId
            ? false
            : authorStories.any((story) => !story.isViewedBy(currentUserId)),
        latestCreatedAt: latestStory.createdAt,
        latestStory: latestStory,
        palette:
            storyPaletteForSeed('${latestStory.authorId}:${latestStory.id}'),
      );
    }).toList();

    groups.sort((left, right) {
      if (left.authorId == currentUserId) {
        return -1;
      }
      if (right.authorId == currentUserId) {
        return 1;
      }
      return right.latestCreatedAt.compareTo(left.latestCreatedAt);
    });

    return groups;
  }
}

class _StoryGroup {
  const _StoryGroup({
    required this.authorId,
    required this.label,
    required this.imageUrl,
    required this.initials,
    required this.stories,
    required this.hasUnseen,
    required this.latestCreatedAt,
    required this.latestStory,
    required this.palette,
  });

  final String authorId;
  final String label;
  final String? imageUrl;
  final String initials;
  final List<Story> stories;
  final bool hasUnseen;
  final DateTime latestCreatedAt;
  final Story latestStory;
  final StoryVisualPalette palette;
}

class _StoryAvatarTile extends StatelessWidget {
  const _StoryAvatarTile._({
    required this.label,
    required this.palette,
    required this.onTap,
    this.semanticLabel,
    this.initials,
    this.imageUrl,
    this.badgeCount,
    this.hasUnseen = false,
    this.storyType,
    this.isAddTile = false,
  });

  factory _StoryAvatarTile.add({
    required VoidCallback onTap,
  }) {
    return _StoryAvatarTile._(
      label: 'Создать',
      palette: storyPaletteForSeed('story:create'),
      onTap: onTap,
      initials: '+',
      semanticLabel: 'story-rail-add',
      isAddTile: true,
    );
  }

  factory _StoryAvatarTile.story({
    required String label,
    required String initials,
    required String? imageUrl,
    required StoryVisualPalette palette,
    required bool hasUnseen,
    required StoryType storyType,
    required VoidCallback onTap,
    String? semanticLabel,
    int? badgeCount,
  }) {
    return _StoryAvatarTile._(
      label: label,
      initials: initials,
      imageUrl: imageUrl,
      palette: palette,
      hasUnseen: hasUnseen,
      storyType: storyType,
      badgeCount: badgeCount,
      onTap: onTap,
      semanticLabel: semanticLabel,
    );
  }

  final String label;
  final String? initials;
  final String? imageUrl;
  final StoryVisualPalette palette;
  final String? semanticLabel;
  final bool hasUnseen;
  final StoryType? storyType;
  final VoidCallback onTap;
  final int? badgeCount;
  final bool isAddTile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ringColor = hasUnseen
        ? palette.accent.withValues(alpha: 0.98)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.58);

    return Semantics(
      button: true,
      label: semanticLabel,
      onTap: onTap,
      child: SizedBox(
        width: 82,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Column(
            children: [
              Container(
                width: 74,
                height: 74,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: ringColor,
                    width: hasUnseen ? 2.6 : 1.15,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      StoryPosterBackground(
                        palette: palette,
                        imageUrl: imageUrl,
                        dimmed: !isAddTile &&
                            imageUrl != null &&
                            imageUrl!.isNotEmpty,
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white
                                  .withValues(alpha: isAddTile ? 0.14 : 0.04),
                              Colors.black
                                  .withValues(alpha: isAddTile ? 0.22 : 0.18),
                            ],
                          ),
                        ),
                      ),
                      if (isAddTile)
                        Center(
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                              ),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        )
                      else ...[
                        Align(
                          alignment: Alignment.center,
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor:
                                Colors.black.withValues(alpha: 0.24),
                            child: Text(
                              initials ?? 'И',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        if (storyType != null)
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: _StoryTypeBadge(storyType: storyType!),
                          ),
                      ],
                      if (!isAddTile && badgeCount != null && badgeCount! > 1)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: _StoryCountBadge(count: badgeCount!),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryMetaChip extends StatelessWidget {
  const _StoryMetaChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryCountBadge extends StatelessWidget {
  const _StoryCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Text(
        count.toString(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _StoryTypeBadge extends StatelessWidget {
  const _StoryTypeBadge({required this.storyType});

  final StoryType storyType;

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    switch (storyType) {
      case StoryType.video:
        icon = Icons.videocam_rounded;
        break;
      case StoryType.image:
        icon = Icons.image_rounded;
        break;
      case StoryType.text:
        icon = Icons.text_fields_rounded;
        break;
    }

    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Icon(icon, size: 12, color: Colors.white),
    );
  }
}

class _StoryLoadingRail extends StatelessWidget {
  const _StoryLoadingRail();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 106,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return SizedBox(
            width: 82,
            child: Column(
              children: [
                Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 56,
                  height: 10,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StoryStatusBanner extends StatelessWidget {
  const _StoryStatusBanner({
    required this.icon,
    required this.label,
    this.actionLabel,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (actionLabel != null && onTap != null)
              TextButton(
                onPressed: onTap,
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}
