part of 'home_screen.dart';

/// What the empty-feed CTA does when tapped.
enum _FeedEmptyAction { write, refresh, addRelative }

class _HomeFeedEmptyViewState {
  const _HomeFeedEmptyViewState({
    required this.title,
    required this.message,
    required this.icon,
    this.actionLabel,
    this.action = _FeedEmptyAction.write,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final _FeedEmptyAction action;
}

extension _HomeScreenSections on _HomeScreenState {
  _HomeFeedEmptyViewState get _feedEmptyViewState {
    if (_postsUnavailable) {
      return const _HomeFeedEmptyViewState(
        title: 'Лента недоступна',
        message: 'Обновите позже.',
        icon: Icons.cloud_off_outlined,
        actionLabel: 'Обновить',
        action: _FeedEmptyAction.refresh,
      );
    }

    // State-aware (UX-audit 2.2): a tree with nobody but the viewer
    // has no audience to post to — guide them to build the family
    // first instead of writing into the void.
    if (_hasFamilyAudience == false) {
      return const _HomeFeedEmptyViewState(
        title: 'Начните своё дерево',
        message: 'Добавьте первого родственника — и лента оживёт.',
        icon: Icons.person_add_alt_1_outlined,
        actionLabel: 'Добавить родственника',
        action: _FeedEmptyAction.addRelative,
      );
    }

    return const _HomeFeedEmptyViewState(
      title: 'Пока тихо в ленте',
      message: 'Поделитесь семейной новостью, фото или короткой историей.',
      icon: Icons.post_add_outlined,
      actionLabel: 'Написать',
      action: _FeedEmptyAction.write,
    );
  }

  Future<void> _handleFeedEmptyAction() async {
    switch (_feedEmptyViewState.action) {
      case _FeedEmptyAction.refresh:
        await _refreshCurrentPosts();
        return;
      case _FeedEmptyAction.addRelative:
        // Tree screen is where relatives are added.
        if (mounted) context.go('/tree');
        return;
      case _FeedEmptyAction.write:
        await _openCreatePost();
        return;
    }
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
                                await _loadPosts(
                                    branchId: _selectedFeedBranchId);
                                if (_currentTreeId != null) {
                                  await Future.wait([
                                    _loadStories(_currentTreeId!),
                                    _loadEvents(_currentTreeId!),
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

  /// Everything above the posts list on the narrow (phone) layout:
  /// identity-review banner, stories rail, events rail, compose teaser,
  /// branch chips. The posts themselves are no longer a child here —
  /// they render as a separate virtualized [SliverList] (see
  /// [_buildNarrowFeedSliver]) so off-screen cards recycle instead of
  /// all mounting at once inside one SliverToBoxAdapter.
  Widget _buildFeedHeaderSections() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        if (_pendingIdentityReviewCount > 0 || _identityReviewsUnavailable)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: _buildIdentityReviewBanner(),
          ),
        // «Эта неделя в семье» digest removed at user's request — the
        // block ate vertical space without earning it. The
        // BranchDigestStrip widget + backend wiring stay parked for
        // a possible later re-introduction in a different shape.
        _buildStoriesSection(),
        const SizedBox(height: 6),
        _buildUpcomingEventsSection(isWideLayout: false),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
          child: _buildComposeTeaser(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: _buildFeedBranchStrip(),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  /// Narrow-layout posts as a recycling [SliverList]. Loading / empty
  /// states stay box-shaped (they're small, fixed-size) in a
  /// [SliverToBoxAdapter]; only the populated list virtualizes. Keeps
  /// the same horizontal inset (14) the feed stage used to carry so
  /// spacing is unchanged. PostCards key on `post.id` so element state
  /// follows the right post as the list recycles.
  Widget _buildNarrowFeedSliver() {
    if (_isLoadingPosts && _posts.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 0, 14, 0),
          child: Column(
            children: [
              PostCardShimmer(),
              PostCardShimmer(),
              PostCardShimmer(),
            ],
          ),
        ),
      );
    }

    // Phase E2c: posts + gatherings, merged newest-first.
    final entries = _feedEntries;
    if (entries.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
          child: _buildFeedEmptyState(wideLayout: false),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      sliver: SliverList.builder(
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return _PostEntrance(
            key: ValueKey(entry.id),
            child: entry.isPost
                ? PostCard(
                    post: entry.post!,
                    onDeleted: () =>
                        _loadPosts(branchId: _selectedFeedBranchId),
                  )
                : GatheringCard(gathering: entry.gathering!),
          );
        },
      ),
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
        // «Эта неделя в семье» убран и из wide-варианта тоже —
        // юзер просил полностью снять блок. Backend wiring и сам
        // BranchDigestStrip widget остаются на случай если позже
        // вернёмся к этой идее в другом форм-факторе.
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
          child: _buildComposeTeaser(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: _buildFeedBranchStrip(),
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

  /// Box-shaped feed renderer used by the wide (desktop) layout. The
  /// narrow layout virtualizes via [_buildNarrowFeedSliver] instead.
  /// Loading → content → empty cross-fade through an AnimatedSwitcher so
  /// the first posts settle in rather than hard-cutting over the shimmer.
  Widget _buildFeedContent({bool wideLayout = false}) {
    final Widget child;
    if (_isLoadingPosts && _posts.isEmpty) {
      child = Column(
        key: const ValueKey('feed-loading'),
        children: List.generate(3, (_) => const PostCardShimmer()),
      );
    } else {
      // Phase E2c: posts + gatherings, merged newest-first.
      final entries = _feedEntries;
      if (entries.isEmpty) {
        child = KeyedSubtree(
          key: const ValueKey('feed-empty'),
          child: _buildFeedEmptyState(wideLayout: wideLayout),
        );
      } else {
        child = Column(
          key: const ValueKey('feed-content'),
          children: entries
              .map(
                (entry) => entry.isPost
                    ? PostCard(
                        key: ValueKey(entry.id),
                        post: entry.post!,
                        onDeleted: () =>
                            _loadPosts(branchId: _selectedFeedBranchId),
                      )
                    : GatheringCard(
                        key: ValueKey(entry.id),
                        gathering: entry.gathering!,
                      ),
              )
              .toList(),
        );
      }
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: child,
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
                      // 3 lines so the warm copy isn't clipped to «ко…»
                      // (was maxLines: 2).
                      maxLines: 3,
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
    // Feed reload uses the chip-strip scope (`_selectedFeedBranchId`),
    // not the BranchSwitcher's `_currentTreeId`. The two were sync'd
    // before the audience-mode rework, but now feed scope is its own
    // axis and refresh has to follow that.
    await _loadPosts(branchId: _selectedFeedBranchId);
  }

  Future<void> _openCreatePost({String? action}) async {
    // [action] is forwarded to the composer as a query string so the
    // photo / video icons on the teaser actually do something
    // distinct — user feedback was that they were decorative and
    // both led to the same screen. Now: photo icon prefires the
    // gallery picker, video icon prefires the video picker.
    final path =
        action == null ? '/post/create' : '/post/create?action=$action';
    final result = await context.push(path);
    if (result == true) {
      await _loadPosts(branchId: _selectedFeedBranchId);
    }
  }

  Future<void> _openCreateGathering() async {
    // Phase E2: gatherings land in the same feed as posts (E2c), so a
    // successful create refreshes it just like a post does.
    final result = await context.push('/gathering/create');
    if (result == true) {
      await _loadPosts(branchId: _selectedFeedBranchId);
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
        key: _tourTeaserKey,
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
              // Phase E2: «Встреча» — a separate composer entry next to the
              // post media icons (doesn't touch the post-create flow).
              IconButton(
                key: const Key('compose-gathering'),
                tooltip: 'Создать встречу',
                onPressed: _openCreateGathering,
                icon: Icon(Icons.event_outlined, color: tokens.accent),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Branch-scope chips for the feed: «Все» (audience-mode) on the
  /// left, then one chip per branch the viewer is in. Tapping a
  /// branch chip narrows the feed to posts whose `branchIds[]`
  /// includes that branch — server-side filter via the `treeId`
  /// query param. Tapping «Все» clears the narrowing and the
  /// viewer sees the union of every branch's posts.
  ///
  /// Hidden when the viewer has only one branch — the strip would
  /// degenerate to «Все» + that branch and never affect what's
  /// shown, so the noise isn't worth the row of UI. Keeps the home
  /// feed clean for fresh accounts with a single tree.
  Widget _buildFeedBranchStrip() {
    return Consumer<TreeProvider>(
      builder: (context, treeProvider, _) {
        final branches = treeProvider.availableTrees;
        if (branches.length < 2) {
          return const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        final entries = <_FeedBranchChipEntry>[
          const _FeedBranchChipEntry(id: null, label: 'Все'),
          for (final branch in branches)
            _FeedBranchChipEntry(id: branch.id, label: branch.name),
        ];
        return SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final selected = _selectedFeedBranchId == entry.id;
              return Semantics(
                button: true,
                selected: selected,
                label: 'home-feed-branch-${entry.id ?? 'all'}',
                child: ChoiceChip(
                  label: Text(entry.label),
                  selected: selected,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  avatar: entry.id == null
                      ? Icon(
                          Icons.all_inclusive,
                          size: 16,
                          color: theme.colorScheme.primary,
                        )
                      : null,
                  onSelected: (_) => _selectFeedBranch(entry.id),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Tiny value object so the chip builder doesn't reach into
/// `FamilyTree` for trivial fields (we only need id+label) and
/// the «Все» pseudo-entry can share the same shape as real
/// branches.
class _FeedBranchChipEntry {
  const _FeedBranchChipEntry({required this.id, required this.label});

  final String? id;
  final String label;
}

/// One-shot fade + slight slide-up when a feed card first mounts, so the
/// narrow (virtualized) feed settles in rather than snapping on instantly
/// (P5). Light + short, in the same easeOutCubic spirit as the reaction
/// chip micro-animations. The wide layout gets its motion from the
/// AnimatedSwitcher in [_buildFeedContent] instead, so this is narrow-only.
/// One entry in the mixed home feed — either a [Post] or a [Gathering]
/// (Phase E2c). Exactly one of the two is non-null.
class _HomeFeedEntry {
  const _HomeFeedEntry.post(Post this.post) : gathering = null;
  const _HomeFeedEntry.gathering(Gathering this.gathering) : post = null;

  final Post? post;
  final Gathering? gathering;

  bool get isPost => post != null;
  String get id => post?.id ?? gathering!.id;
  DateTime get createdAt => post?.createdAt ?? gathering!.createdAt;
}

class _PostEntrance extends StatefulWidget {
  const _PostEntrance({super.key, required this.child});

  final Widget child;

  @override
  State<_PostEntrance> createState() => _PostEntranceState();
}

class _PostEntranceState extends State<_PostEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.04),
    end: Offset.zero,
  ).animate(_fade);

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
