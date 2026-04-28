part of 'profile_screen.dart';

extension _ProfileScreenSections on _ProfileScreenState {
  Widget _buildProfileStateCard({
    required IconData icon,
    required String title,
    required String message,
    bool showProgress = false,
    List<Widget> actions = const <Widget>[],
  }) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GlassPanel(
            padding: const EdgeInsets.all(24),
            borderRadius: BorderRadius.circular(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 28,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.38,
                  ),
                ),
                if (showProgress) ...[
                  const SizedBox(height: 18),
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContributionEmptyState() {
    final theme = Theme.of(context);

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      borderRadius: BorderRadius.circular(20),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.mark_email_read_outlined,
              color: theme.colorScheme.primary,
              size: 21,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Предложений нет',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Новые правки появятся здесь.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _profileCodeLabel() {
    final profile = _userProfile;
    if (profile == null) {
      return null;
    }
    final username = profile.username.trim();
    if (username.isNotEmpty) {
      return username.startsWith('@') ? username.substring(1) : username;
    }
    return null;
  }

  Widget _buildProfileConnectionSection({
    required String? selectedTreeId,
    required String? selectedTreeName,
  }) {
    final profileCode = _profileCodeLabel();
    if (profileCode == null) {
      return const SizedBox.shrink();
    }

    final connectionLink =
        _buildProfileConnectionLink(selectedTreeId, profileCode);
    final theme = Theme.of(context);

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      borderRadius: BorderRadius.circular(20),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.qr_code_2_rounded,
              color: theme.colorScheme.secondary,
              size: 21,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Профильный код',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '@$profileCode',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (connectionLink == null)
            OutlinedButton(
              onPressed: () => context.go('/tree?selector=1'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Дерево'),
            )
          else ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Скопировать ссылку',
              onPressed: () => _copyProfileConnectionLink(connectionLink),
              icon: const Icon(Icons.copy_outlined, size: 20),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Поделиться',
              onPressed: () => _shareProfileConnectionLink(connectionLink),
              icon: const Icon(Icons.share_outlined, size: 20),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStoriesRailSection() {
    return StoryRail(
      title: 'Истории',
      currentUserId: _currentUserId ?? '',
      stories: _userStories,
      isLoading: _isLoadingStories,
      unavailable: _storiesUnavailable,
      onRetry: () {
        if (_currentUserId != null) {
          _loadStoriesForContext(
            selectedTreeId: context.read<TreeProvider>().selectedTreeId,
            currentUserId: _currentUserId!,
          );
        }
      },
      onCreateStory: () async {
        final result = await context.push('/stories/create');
        if (!mounted) {
          return;
        }
        if (result == true && _currentUserId != null) {
          _loadStoriesForContext(
            selectedTreeId: context.read<TreeProvider>().selectedTreeId,
            currentUserId: _currentUserId!,
          );
        }
      },
      onOpenStories: (stories) async {
        if (stories.isEmpty) {
          return;
        }
        final story = stories.last;
        final route = '/stories/view/${story.treeId}/${story.authorId}';
        await context.push(
          route,
        );
        if (!mounted) {
          return;
        }
        if (_currentUserId != null) {
          _loadStoriesForContext(
            selectedTreeId: context.read<TreeProvider>().selectedTreeId,
            currentUserId: _currentUserId!,
          );
        }
      },
      emptyLabel: 'Добавьте первую историю.',
    );
  }

  Future<void> _acceptContribution(ProfileContribution contribution) async {
    try {
      await _profileService.acceptProfileContribution(contribution.id);
      await _loadUserData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Предложение применено к профилю.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeUserFacingError(
              authService: _authService,
              error: error,
              fallbackMessage:
                  'Не удалось применить правку. Попробуйте ещё раз.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _rejectContribution(ProfileContribution contribution) async {
    try {
      await _profileService.rejectProfileContribution(contribution.id);
      await _loadUserData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Предложение отклонено.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeUserFacingError(
              authService: _authService,
              error: error,
              fallbackMessage:
                  'Не удалось отклонить правку. Попробуйте ещё раз.',
            ),
          ),
        ),
      );
    }
  }

  Widget _buildContributionCard(ProfileContribution contribution) {
    final theme = Theme.of(context);
    final fieldSummary = contribution.fields.entries
        .map((entry) => '${_contributionFieldLabel(entry.key)}: ${entry.value}')
        .join('\n');

    return GlassPanel(
      plain: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            contribution.authorDisplayName?.trim().isNotEmpty == true
                ? contribution.authorDisplayName!
                : 'Родственник',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if ((contribution.message ?? '').isNotEmpty) ...[
            Text(
              contribution.message!,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
          ],
          Text(
            fieldSummary,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _acceptContribution(contribution),
                  child: const Text('Принять'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _rejectContribution(contribution),
                  child: const Text('Отклонить'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _contributionFieldLabel(String fieldKey) {
    switch (fieldKey) {
      case 'firstName':
        return 'Имя';
      case 'lastName':
        return 'Фамилия';
      case 'middleName':
        return 'Отчество';
      case 'maidenName':
        return 'Девичья фамилия';
      case 'birthDate':
        return 'Дата рождения';
      case 'birthPlace':
        return 'Место рождения';
      case 'bio':
        return 'О человеке';
      case 'aboutFamily':
        return 'Для семьи';
      case 'familyStatus':
        return 'Семейное положение';
      case 'education':
        return 'Учёба';
      case 'work':
        return 'Работа и дело';
      case 'hometown':
        return 'Родной город';
      case 'languages':
        return 'Языки';
      case 'values':
        return 'Ценности';
      case 'religion':
        return 'Религия';
      case 'interests':
        return 'Интересы';
      default:
        return fieldKey;
    }
  }

  // ── New helper widgets called from the redesigned build() ─────────────────

  /// Stats row widget passed to PersonDossierView (posts / relatives / trees).
  Widget _buildStatsRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: _StatBadge(
            value: _postCount.toString(),
            label: 'Постов',
            onTap: null,
          ),
        ),
        _StatDivider(),
        Flexible(
          child: _StatBadge(
            value: _relativeCount.toString(),
            label: _graphStatLabel(context),
            onTap: () => context.go('/relatives'),
          ),
        ),
        _StatDivider(),
        Flexible(
          child: _StatBadge(
            value: _treeCount.toString(),
            label: 'Деревья',
            onTap: () => context.go('/tree?selector=1'),
          ),
        ),
      ],
    );
  }

  /// Compact tree context chip for the PersonDossierView headerChips list.
  Widget _buildTreeChip(
    BuildContext context, {
    required String label,
    required bool isFriends,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: scheme.primary.withValues(alpha: 0.22),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFriends
                  ? Icons.diversity_3_outlined
                  : Icons.account_tree_outlined,
              size: 14,
              color: scheme.primary,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact "tree card" row — replaces the old big GraphContextBanner.
  Widget _buildTreeCardCompact(
    BuildContext context, {
    required FamilyPerson person,
    required bool isFriendsTree,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final photoCount = person.photoGallery.length;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        borderRadius: BorderRadius.circular(20),
        plain: true,
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: person.primaryPhotoUrl != null
                  ? NetworkImage(person.primaryPhotoUrl!)
                  : null,
              backgroundColor: scheme.primary.withValues(alpha: 0.12),
              foregroundColor: scheme.primary,
              child: person.primaryPhotoUrl == null
                  ? Text(
                      person.initials,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Карточка в дереве',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    person.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: photoCount == 0 ? 'Фото пока нет' : 'Фото ($photoCount)',
              icon: const Icon(Icons.photo_library_outlined, size: 19),
              onPressed: photoCount == 0
                  ? null
                  : () => _showSelectedTreePersonGallery(person),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'История',
              icon: const Icon(Icons.history_outlined, size: 19),
              onPressed: () => _showSelectedTreePersonHistory(person),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Открыть карточку',
              icon: const Icon(Icons.open_in_new_rounded, size: 19),
              onPressed: () => context.push('/relative/details/${person.id}'),
            ),
          ],
        ),
      ),
    );
  }

  /// Small "Account settings" card that replaces the full trust-summary panel.
  Widget _buildAccountSettingsLink(ColorScheme scheme, ThemeData theme) {
    final status = _accountLinkingStatus;
    final hasLinkedChannel =
        status?.primaryTrustedChannel?.label.isNotEmpty == true;

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      borderRadius: BorderRadius.circular(20),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.shield_outlined, size: 20, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasLinkedChannel ? 'Аккаунт защищён' : 'Настройки аккаунта',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (hasLinkedChannel)
                  Text(
                    'Основной канал: ${status!.primaryTrustedChannel?.label}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => context.push('/profile/settings'),
            child: const Text('Настройки'),
          ),
        ],
      ),
    );
  }
}

// ── Stat badge widget ─────────────────────────────────────────────────────────

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.value,
    required this.label,
    required this.onTap,
  });

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: VerticalDivider(
        color:
            Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
        width: 1,
      ),
    );
  }
}
