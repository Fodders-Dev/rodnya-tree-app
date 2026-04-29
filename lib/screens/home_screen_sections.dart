part of 'home_screen.dart';

class _HomeFeedEmptyViewState {
  const _HomeFeedEmptyViewState({
    required this.title,
    required this.message,
    required this.icon,
    this.actionLabel,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
}

extension _HomeScreenSections on _HomeScreenState {
  _HomeFeedEmptyViewState get _feedEmptyViewState {
    if (_postsUnavailable) {
      return const _HomeFeedEmptyViewState(
        title: 'Лента недоступна',
        message: 'Обновите позже.',
        icon: Icons.cloud_off_outlined,
        actionLabel: 'Обновить',
      );
    }

    return const _HomeFeedEmptyViewState(
      title: 'Лента пуста',
      message: 'Новый пост можно создать из верхней кнопки.',
      icon: Icons.post_add_outlined,
    );
  }

  Future<void> _handleFeedEmptyAction() async {
    if (!_postsUnavailable) {
      return;
    }
    await _refreshCurrentPosts();
  }

  Widget _buildOperationalBanner({required bool hasSelectedTree}) {
    final theme = Theme.of(context);
    final issue = _appStatusService.issue;
    final isSessionIssue = _appStatusService.hasSessionIssue;
    final title = isSessionIssue
        ? 'Нужно заново войти'
        : _appStatusService.isOffline
            ? 'Часть данных временно офлайн'
            : 'Есть что обновить';
    final message = issue?.message ??
        (_appStatusService.isOffline
            ? 'Связь прервалась. Экран можно просматривать, но часть действий и обновлений сейчас недоступна.'
            : hasSelectedTree && _postsUnavailable && _storiesUnavailable
                ? 'Истории и лента не обновились. Откройте экран ещё раз или попробуйте ручное обновление.'
                : hasSelectedTree && _postsUnavailable
                    ? 'Лента не обновилась. Остальные разделы можно продолжать использовать.'
                    : hasSelectedTree && _storiesUnavailable
                        ? 'Истории не обновились. Остальные разделы продолжают работать.'
                        : 'Проверьте состояние экрана и попробуйте обновить данные.');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: GlassPanel(
        padding: const EdgeInsets.all(14),
        borderRadius: BorderRadius.circular(26),
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.42),
        borderColor: theme.colorScheme.secondary.withValues(alpha: 0.16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isSessionIssue
                    ? Icons.lock_reset_outlined
                    : _appStatusService.isOffline
                        ? Icons.cloud_off_outlined
                        : Icons.sync_problem_outlined,
                color: theme.colorScheme.secondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: isSessionIssue
                            ? () => context.go('/login')
                            : () async {
                                _appStatusService.requestRetry();
                                if (_currentTreeId != null) {
                                  await Future.wait([
                                    _loadStories(_currentTreeId!),
                                    _loadEvents(_currentTreeId!),
                                    _loadPosts(_currentTreeId!),
                                  ]);
                                }
                              },
                        icon: Icon(
                          isSessionIssue
                              ? Icons.login_outlined
                              : Icons.refresh_rounded,
                        ),
                        label: Text(
                          isSessionIssue ? 'Войти снова' : 'Обновить данные',
                        ),
                      ),
                      if (!hasSelectedTree)
                        OutlinedButton.icon(
                          onPressed: () => context.go('/tree?selector=1'),
                          icon: const Icon(Icons.account_tree_outlined),
                          label: const Text('Выбрать дерево'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeContentSections({required bool isWideLayout}) {
    return Column(
      children: [
        _buildStoriesSection(),
        const SizedBox(height: 12),
        _buildUpcomingEventsSection(isWideLayout: isWideLayout),
        SizedBox(height: isWideLayout ? 18 : 16),
        _buildHomeFeedStage(isWideLayout: isWideLayout),
      ],
    );
  }

  Widget _buildHomeHeader({
    required bool hasSelectedTree,
    required bool isFriendsTree,
    required String? selectedTreeName,
  }) {
    final theme = Theme.of(context);

    // Action-first: tight glass strip with the active tree pill on the left and
    // the most useful one or two actions on the right. No prose subtitle.
    final treeLabel = !hasSelectedTree
        ? 'Выберите дерево'
        : (selectedTreeName?.trim().isNotEmpty == true
            ? selectedTreeName!.trim()
            : (isFriendsTree ? 'Круг друзей' : 'Семейное дерево'));

    final treeIcon = !hasSelectedTree
        ? Icons.account_tree_outlined
        : (isFriendsTree
            ? Icons.diversity_3_outlined
            : Icons.account_tree_outlined);

    final statusChips = <Widget>[];
    if (hasSelectedTree && _postsUnavailable) {
      statusChips.add(
        _buildHeaderChip(
          icon: Icons.sync_problem_rounded,
          label: 'Лента недоступна',
        ),
      );
    }
    if (hasSelectedTree && _storiesUnavailable) {
      statusChips.add(
        _buildHeaderChip(
          icon: Icons.sync_problem_rounded,
          label: 'Истории недоступны',
        ),
      );
    }

    final primaryAction = hasSelectedTree
        ? _buildQuickActionButton(
            icon: Icons.post_add_outlined,
            label: 'Новый пост',
            onTap: () => context.push('/post/create'),
            primary: true,
          )
        : _buildQuickActionButton(
            icon: Icons.account_tree_outlined,
            label: 'Выбрать дерево',
            onTap: () => context.go('/tree?selector=1'),
            primary: true,
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => context.go('/tree?selector=1'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              treeIcon,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hasSelectedTree
                                      ? 'Активное дерево'
                                      : 'Нет активного дерева',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                Text(
                                  treeLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.unfold_more_rounded,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                primaryAction,
              ],
            ),
            if (statusChips.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: statusChips,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFeedContent({bool wideLayout = false}) {
    if (_isLoadingPosts && _posts.isEmpty) {
      return Column(children: List.generate(3, (_) => const PostCardShimmer()));
    }

    if (_posts.isEmpty) {
      return _buildFeedEmptyState(wideLayout: wideLayout);
    }

    return Column(
      children: _posts
          .map(
            (post) => PostCard(
              post: post,
              onDeleted: () {
                if (_currentTreeId != null) {
                  _loadPosts(_currentTreeId!);
                }
              },
            ),
          )
          .toList(),
    );
  }

  Widget _buildFeedEmptyState({required bool wideLayout}) {
    final state = _feedEmptyViewState;

    if (!wideLayout) {
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: GlassPanel(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          borderRadius: BorderRadius.circular(20),
          child: Row(
            children: [
              Icon(
                state.icon,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      state.message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.actionLabel != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _handleFeedEmptyAction,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(state.actionLabel!),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    return _buildDesktopSideCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              state.icon,
              size: 28,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderChip(
                  icon: _postsUnavailable
                      ? Icons.cloud_off_outlined
                      : Icons.dynamic_feed_outlined,
                  label: _postsUnavailable ? 'Офлайн' : 'Лента',
                  highlighted: !_postsUnavailable,
                ),
                const SizedBox(height: 12),
                Text(
                  state.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  state.message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (state.actionLabel != null) ...[
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: _handleFeedEmptyAction,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(state.actionLabel!),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _refreshCurrentPosts() async {
    final treeId = _currentTreeId;
    if (treeId == null) {
      return;
    }
    await _loadPosts(treeId);
  }

  double _eventCardWidthFor(BoxConstraints constraints) {
    final availableWidth = constraints.maxWidth;
    if (!availableWidth.isFinite || availableWidth <= 0) {
      return 220;
    }
    if (availableWidth < 360) {
      return (availableWidth - 8).clamp(176.0, 220.0);
    }
    if (availableWidth < 520) {
      return (availableWidth * 0.72).clamp(196.0, 236.0);
    }
    if (availableWidth < 760) {
      return (availableWidth * 0.46).clamp(210.0, 248.0);
    }
    return 232;
  }
}
