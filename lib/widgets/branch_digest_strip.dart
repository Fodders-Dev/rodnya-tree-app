import 'package:flutter/material.dart';

import '../backend/models/branch_digest.dart';
import '../theme/app_theme.dart';

/// Phase 6.3: «Эта неделя в семье» strip — compact horizontal rail
/// of cards summarizing what's happening in the active branch this
/// week. Shows upcoming birthdays, memorial anniversaries, recent
/// posts, and freshly-added persons. Tap on any card fires
/// [onTapPerson] / [onTapPost] so the host can navigate.
///
/// Renders nothing when the digest is empty — keeps the home feed
/// clean for users with quiet branches.
class BranchDigestStrip extends StatelessWidget {
  const BranchDigestStrip({
    super.key,
    required this.digest,
    this.onTapPerson,
    this.onTapPost,
  });

  final BranchDigest digest;
  final void Function(String personId)? onTapPerson;
  final void Function(String postId)? onTapPost;

  @override
  Widget build(BuildContext context) {
    if (digest.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    final cards = <Widget>[];
    for (final birthday in digest.birthdays) {
      cards.add(_BirthdayCard(
        birthday: birthday,
        tokens: tokens,
        onTap: () => onTapPerson?.call(birthday.personId),
      ));
    }
    for (final memorial in digest.memorials) {
      cards.add(_MemorialCard(
        memorial: memorial,
        tokens: tokens,
        onTap: () => onTapPerson?.call(memorial.personId),
      ));
    }
    for (final newPerson in digest.newPersons) {
      cards.add(_NewPersonCard(
        person: newPerson,
        tokens: tokens,
        onTap: () => onTapPerson?.call(newPerson.personId),
      ));
    }
    for (final post in digest.recentPosts) {
      cards.add(_RecentPostCard(
        post: post,
        tokens: tokens,
        onTap: () => onTapPost?.call(post.postId),
      ));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Эта неделя в семье',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: tokens.ink,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, index) => cards[index],
            ),
          ),
        ],
      ),
    );
  }
}

class _BirthdayCard extends StatelessWidget {
  const _BirthdayCard({
    required this.birthday,
    required this.tokens,
    required this.onTap,
  });

  final BranchDigestBirthday birthday;
  final RodnyaDesignTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daysLabel = _humanizeDaysUntil(birthday.daysUntil);
    return _DigestCardShell(
      tokens: tokens,
      accent: tokens.accent,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🎂', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 6),
              Text(
                daysLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: tokens.accent,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            birthday.name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: tokens.ink,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            'исполнится ${birthday.age}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.inkSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemorialCard extends StatelessWidget {
  const _MemorialCard({
    required this.memorial,
    required this.tokens,
    required this.onTap,
  });

  final BranchDigestMemorial memorial;
  final RodnyaDesignTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daysLabel = _humanizeDaysUntil(memorial.daysUntil);
    return _DigestCardShell(
      tokens: tokens,
      accent: tokens.warm,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🕯️', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 6),
              Text(
                daysLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: tokens.warm,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            memorial.name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: tokens.ink,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '${memorial.yearsSince} лет годовщина',
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.inkSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _NewPersonCard extends StatelessWidget {
  const _NewPersonCard({
    required this.person,
    required this.tokens,
    required this.onTap,
  });

  final BranchDigestNewPerson person;
  final RodnyaDesignTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _DigestCardShell(
      tokens: tokens,
      accent: tokens.accent,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('👋', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 6),
              Text(
                'Новый родственник',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: tokens.accent,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            person.name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: tokens.ink,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _RecentPostCard extends StatelessWidget {
  const _RecentPostCard({
    required this.post,
    required this.tokens,
    required this.onTap,
  });

  final BranchDigestPost post;
  final RodnyaDesignTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = post.imageUrls.isNotEmpty;
    return _DigestCardShell(
      tokens: tokens,
      accent: tokens.accent,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(hasImage ? '📸' : '✍️',
                  style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 6),
              Text(
                'Новый пост',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: tokens.accent,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            post.authorName,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: tokens.ink,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            post.content.isNotEmpty
                ? post.content
                : (hasImage ? 'Поделился фото' : '—'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.inkSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _DigestCardShell extends StatelessWidget {
  const _DigestCardShell({
    required this.tokens,
    required this.accent,
    required this.onTap,
    required this.child,
  });

  final RodnyaDesignTokens tokens;
  final Color accent;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tokens.surfaceStrong.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 168,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accent.withValues(alpha: 0.32),
              width: 1.0,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

String _humanizeDaysUntil(int daysUntil) {
  if (daysUntil <= 0) return 'Сегодня';
  if (daysUntil == 1) return 'Завтра';
  if (daysUntil < 5) return 'Через $daysUntil дня';
  return 'Через $daysUntil дней';
}
