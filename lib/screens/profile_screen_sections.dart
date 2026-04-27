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
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.mark_email_read_outlined,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Предложения под контролем',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Сейчас новых семейных правок нет. Когда кто-то предложит обновление вашего профиля, оно появится здесь.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
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

  Widget _buildTrustSummarySection() {
    final status = _accountLinkingStatus;
    if (status == null) {
      return const SizedBox.shrink();
    }

    return AccountTrustSummaryCard(
      status: status,
      onManage: () => context.push('/profile/edit'),
    );
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.qr_code_2_rounded,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Профильный код и QR',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@$profileCode',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            connectionLink == null
                ? 'Выберите активное дерево, и мы соберём QR для быстрого поиска, связи и привязки родственника именно к этому дереву.'
                : selectedTreeName?.trim().isNotEmpty == true
                    ? 'Ссылка и QR ведут сразу в сценарий поиска и связи для дерева “$selectedTreeName”.'
                    : 'Ссылка и QR ведут прямо в сценарий поиска по профильному коду внутри выбранного дерева.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: const Icon(Icons.alternate_email_outlined, size: 18),
                label: Text('Код: @$profileCode'),
                visualDensity: VisualDensity.compact,
              ),
              if (selectedTreeName?.trim().isNotEmpty == true)
                Chip(
                  avatar: const Icon(Icons.account_tree_outlined, size: 18),
                  label: Text(selectedTreeName!),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (connectionLink == null)
            OutlinedButton.icon(
              onPressed: () => context.go('/tree?selector=1'),
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('Выбрать дерево'),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 144,
                  height: 144,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: QrImageView(
                    data: connectionLink.toString(),
                    version: QrVersions.auto,
                    padding: EdgeInsets.zero,
                    eyeStyle: const QrEyeStyle(
                      color: Colors.black,
                      eyeShape: QrEyeShape.square,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      color: Colors.black,
                      dataModuleShape: QrDataModuleShape.square,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        connectionLink.toString(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () =>
                                _copyProfileConnectionLink(connectionLink),
                            icon: const Icon(Icons.copy_outlined, size: 18),
                            label: const Text('Скопировать'),
                          ),
                          FilledButton.icon(
                            onPressed: () =>
                                _shareProfileConnectionLink(connectionLink),
                            icon: const Icon(Icons.share_outlined, size: 18),
                            label: const Text('Поделиться'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
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

  Widget _buildContextBadge({
    required BuildContext context,
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraphContextBanner(
    BuildContext context, {
    required bool isFriendsTree,
    required String selectedTreeName,
    FamilyPerson? selectedTreePerson,
  }) {
    final theme = Theme.of(context);
    final personPhotoUrl = selectedTreePerson?.primaryPhotoUrl;
    final photoCount = selectedTreePerson?.photoGallery.length ?? 0;
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isFriendsTree
                    ? Icons.diversity_3_outlined
                    : Icons.account_tree_outlined,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isFriendsTree ? 'Активен круг' : 'Активно дерево',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildContextBadge(
                context: context,
                icon: isFriendsTree
                    ? Icons.diversity_3_outlined
                    : Icons.account_tree_outlined,
                label: selectedTreeName,
              ),
              _buildContextBadge(
                context: context,
                icon: Icons.person_outline,
                label: 'Мой профиль',
              ),
              FilledButton.tonalIcon(
                onPressed: () => context.go('/tree'),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Дерево'),
              ),
            ],
          ),
          if (selectedTreePerson != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSecondaryContainer
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.onSecondaryContainer
                      .withValues(alpha: 0.12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundImage: personPhotoUrl != null
                            ? NetworkImage(personPhotoUrl)
                            : null,
                        child: personPhotoUrl == null
                            ? Text(
                                selectedTreePerson.initials,
                                style: const TextStyle(fontSize: 14),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Карточка в дереве',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              selectedTreePerson.displayName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildContextBadge(
                                  context: context,
                                  icon: Icons.photo_library_outlined,
                                  label: photoCount == 0
                                      ? 'Без фото'
                                      : photoCount == 1
                                          ? '1 фото'
                                          : '$photoCount фото',
                                ),
                                if (selectedTreePerson.primaryPhotoUrl != null)
                                  _buildContextBadge(
                                    context: context,
                                    icon: Icons.star_outline,
                                    label: 'Основное фото',
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => context
                            .push('/relative/details/${selectedTreePerson.id}'),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Открыть'),
                      ),
                      OutlinedButton.icon(
                        onPressed: photoCount == 0
                            ? null
                            : () => _showSelectedTreePersonGallery(
                                selectedTreePerson),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(
                          photoCount == 0 ? 'Фото' : 'Фото ($photoCount)',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _showSelectedTreePersonHistory(selectedTreePerson),
                        icon: const Icon(Icons.history_outlined),
                        label: const Text('История'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── New helper widgets called from the redesigned build() ─────────────────

  /// Stats row widget passed to PersonDossierView (posts / relatives / trees).
  Widget _buildStatsRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _StatBadge(
          value: _postCount.toString(),
          label: 'Постов',
          onTap: null,
        ),
        _StatDivider(),
        _StatBadge(
          value: _relativeCount.toString(),
          label: _graphStatLabel(context),
          onTap: () => context.go('/relatives'),
        ),
        _StatDivider(),
        _StatBadge(
          value: _treeCount.toString(),
          label: 'Деревья',
          onTap: () => context.go('/tree?selector=1'),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.only(top: 12),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
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
                            fontSize: 14,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Карточка в дереве',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        person.displayName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  tooltip: 'Открыть карточку',
                  onPressed: () =>
                      context.push('/relative/details/${person.id}'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: photoCount == 0
                      ? null
                      : () => _showSelectedTreePersonGallery(person),
                  icon: const Icon(Icons.photo_library_outlined, size: 16),
                  label: Text(
                    photoCount == 0 ? 'Фото' : 'Фото ($photoCount)',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showSelectedTreePersonHistory(person),
                  icon: const Icon(Icons.history_outlined, size: 16),
                  label: const Text('История'),
                ),
              ],
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
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
      height: 32,
      child: VerticalDivider(
        color:
            Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
        width: 1,
      ),
    );
  }
}
