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
      title: 'Пока тихо в ленте',
      message: 'Поделитесь семейной новостью, фото или короткой историей.',
      icon: Icons.post_add_outlined,
      actionLabel: 'Написать',
    );
  }

  Future<void> _handleFeedEmptyAction() async {
    if (!_postsUnavailable) {
      await _openCreatePost();
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        if (_pendingIdentityReviewCount > 0 || _identityReviewsUnavailable)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: _buildIdentityReviewBanner(),
          ),
        // Phase 6.3: «Эта неделя в семье» digest above the stories
        // rail. Self-hides when there's nothing happening this
        // week, so the home stays clean for quiet branches.
        if (_branchDigest != null)
          BranchDigestStrip(
            digest: _branchDigest!,
            onTapPerson: (id) =>
                context.push('/relative/details/$id'),
            onTapPost: (id) => context.push('/post/$id'),
          ),
        _buildStoriesSection(),
        const SizedBox(height: 6),
        _buildUpcomingEventsSection(isWideLayout: isWideLayout),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
          child: _buildComposeTeaser(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: _buildFeedFilterStrip(),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
          child: _buildHomeFeedStage(isWideLayout: isWideLayout),
        ),
      ],
    );
  }

  /// Wide-layout left column. Mirrors the narrow stack but only the
  /// feed-related parts — stories rail / events live in the right
  /// sidebar instead, so the user reads the feed without scrolling
  /// past them every time.
  Widget _buildHomeFeedColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        if (_pendingIdentityReviewCount > 0 || _identityReviewsUnavailable)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: _buildIdentityReviewBanner(),
          ),
        // Phase 6.3: digest above the compose teaser even on the
        // wide layout — sidebar still has the bare events list,
        // but the digest is the warmer "this is what's going on
        // RIGHT NOW" surface and belongs in the user's reading flow.
        if (_branchDigest != null)
          BranchDigestStrip(
            digest: _branchDigest!,
            onTapPerson: (id) =>
                context.push('/relative/details/$id'),
            onTapPost: (id) => context.push('/post/$id'),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
          child: _buildComposeTeaser(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: _buildFeedFilterStrip(),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
          // Wide-layout flag is false here on purpose — _buildFeedContent
          // adapts spacing for narrow when the host column is column-
          // shaped (which is exactly what the feed column is).
          child: _buildHomeFeedStage(isWideLayout: false),
        ),
      ],
    );
  }

  /// Wide-layout right column. Always 340dp; contains stories rail +
  /// the events digest. Surfaces what the user wants in their
  /// peripheral vision while reading the feed. Sticky-feeling because
  /// it sits beside (not above) the feed — same reason Instagram /
  /// X put their right rail there.
  Widget _buildHomeSidebarColumn() {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stories rail wrapped in a panel so it reads as a discrete
          // module rather than a free-floating row in dead space.
          GlassPanel(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
            borderRadius: BorderRadius.circular(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text(
                    'Истории',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: tokens.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _buildStoriesSection(),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassPanel(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            borderRadius: BorderRadius.circular(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'События',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: tokens.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                // Sidebar uses a vertical stack instead of the
                // horizontal rail rendered on the home column —
                // 340dp is too narrow for a horizontal scroll to
                // feel useful, and stacked cards read at a glance.
                _buildSidebarUpcomingEvents(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeHeader({
    required bool hasSelectedTree,
    required bool isFriendsTree,
    required String? selectedTreeName,
  }) {
    final theme = Theme.of(context);

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

    final primaryAction = _buildQuickActionButton(
      icon: hasSelectedTree ? Icons.account_tree_outlined : treeIcon,
      label: hasSelectedTree ? 'Дерево' : 'Выбрать',
      onTap: () => context.go('/tree?selector=1'),
      primary: !hasSelectedTree,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(16, hasSelectedTree ? 8 : 10, 16, 0),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        borderRadius: BorderRadius.circular(20),
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
                                  treeLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0,
                                  ),
                                ),
                                Text(
                                  hasSelectedTree
                                      ? (isFriendsTree
                                          ? 'Лента круга'
                                          : 'Лента семьи')
                                      : 'Выберите контекст для ленты',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
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

    final visiblePosts = _visiblePosts;
    if (_posts.isEmpty || visiblePosts.isEmpty) {
      return _buildFeedEmptyState(wideLayout: wideLayout);
    }

    return Column(
      children: visiblePosts
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
                      maxLines: 2,
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
              icon: Icon(
                _postsUnavailable
                    ? Icons.refresh_rounded
                    : Icons.post_add_outlined,
              ),
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

  Future<void> _openCreatePost({String? action}) async {
    // [action] is forwarded to the composer as a query string so the
    // photo / video icons on the teaser actually do something
    // distinct — user feedback was that they were decorative and
    // both led to the same screen. Now: photo icon prefires the
    // gallery picker, video icon prefires the video picker.
    final path = action == null ? '/post/create' : '/post/create?action=$action';
    final result = await context.push(path);
    if (result == true && _currentTreeId != null) {
      await _loadPosts(_currentTreeId!);
    }
  }

  Widget _buildIdentityReviewBanner() {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final unavailable = _identityReviewsUnavailable;
    final title = unavailable
        ? 'Проверки личности не обновились'
        : _pendingIdentityReviewCount == 1
            ? 'Есть совпадение личности'
            : 'Есть проверки личности';
    final message = unavailable
        ? 'Откройте раздел проверки или обновите экран позже.'
        : _pendingIdentityReviewCount == 1
            ? 'Проверьте возможное совпадение, прежде чем объединять данные.'
            : '$_pendingIdentityReviewCount совпадений и запросов ждут решения.';

    return Semantics(
      button: true,
      label: 'home-identity-review-banner',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => context.go('/identity/review'),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tokens.warmSoft,
                  tokens.accentSoft,
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: tokens.surfaceLine),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tokens.surfaceStrong,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tokens.surfaceLine),
                  ),
                  child: Icon(
                    unavailable
                        ? Icons.sync_problem_outlined
                        : Icons.merge_type_rounded,
                    size: 20,
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: AppTheme.sans(
                          color: tokens.ink,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.sans(
                          color: tokens.inkMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: tokens.inkMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComposeTeaser() {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final name = _authService.currentUserDisplayName?.trim();
    final initials = (name == null || name.isEmpty)
        ? 'Я'
        : String.fromCharCode(name.runes.first).toUpperCase();

    // The whole row tap opens the composer for plain text. The two
    // icons on the right are now real CTAs — photo opens the gallery
    // picker on mount, videocam opens the video picker — wrapped in
    // separate InkWells so the teaser tap area doesn't intercept them.
    return Semantics(
      button: true,
      label: 'home-compose-teaser',
      child: GlassPanel(
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(20),
        plain: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _openCreatePost(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            gradient: tokens.accentGradient,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            initials,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: tokens.accentInk,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _treeProviderInstance?.selectedTreeKind ==
                                    TreeKind.friends
                                ? 'Поделиться с кругом...'
                                : 'Поделиться с роднёй...',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Добавить фото',
                onPressed: () => _openCreatePost(action: 'photo'),
                icon: Icon(Icons.photo_outlined, color: tokens.accent),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: 'Добавить видео',
                onPressed: () => _openCreatePost(action: 'video'),
                icon: Icon(Icons.videocam_outlined, color: tokens.warm),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeedFilterStrip() {
    final filters = _HomeScreenState._feedFilters;
    final selectedFilter =
        filters.contains(_selectedFeedFilter) ? _selectedFeedFilter : 'Семья';

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final label = filters[index];
          return Semantics(
            button: true,
            selected: selectedFilter == label,
            label: 'home-feed-filter-$label',
            child: ChoiceChip(
              label: Text(label),
              selected: selectedFilter == label,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onSelected: (_) => _selectFeedFilter(label),
            ),
          );
        },
      ),
    );
  }
}
