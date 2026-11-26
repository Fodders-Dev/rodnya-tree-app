part of '../relatives_screen.dart';

extension _RelativesHeaderSection on _RelativesScreenState {
  /// Phase 3.4 chunk 5: tree-level summary banner. Возвращает
  /// SizedBox.shrink если conflict'ов нет — caller's wrap'ы
  /// padding'и schum'ятся autoMagic'ом (banner сам decide'ит).
  Widget _maybeConflictTreeBanner() {
    if (_conflictCounts.isEmpty || _treeConflictsCache.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: IdentityConflictsHeaderBanner(
        count: _conflictCounts.length,
        onTap: _showAllTreeConflicts,
        scope: ConflictBannerScope.tree,
      ),
    );
  }

  // Чанк 26: было 1500 — выше типичного десктопного окна (1280/1440), так
  // что боковая панель на деле никогда не показывалась на этих ширинах и
  // экран тихо падал на мобильную раскладку внутри «десктопного» окна.
  // 1100 согласован с порогом чатов (тот же паттерн список+панель).
  bool _isWideLayout(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1100;

  bool _isFriendsTree(TreeProvider provider) =>
      provider.selectedTreeKind == TreeKind.friends;

  String _graphAddLabel(TreeProvider provider) =>
      _isFriendsTree(provider) ? 'Добавить человека' : 'Добавить родственника';

  String _graphFindLabel(TreeProvider provider) =>
      _isFriendsTree(provider) ? 'Найти человека' : 'Найти родственника';

  Widget _buildRelativesPrimaryActionBar(
    String selectedTreeId,
    TreeProvider treeProvider,
  ) {
    final tokens = AppTheme.tokensOf(context);
    return Material(
      key: const Key('relatives-primary-action-bar'),
      color: tokens.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: [
              if (!_isFriendsTree(treeProvider)) ...[
                IconButton.outlined(
                  key: const Key('discover-relatives-action'),
                  onPressed: () => context.push('/discover/relatives'),
                  tooltip: 'Проверить родство с человеком',
                  icon: const Icon(Icons.travel_explore_rounded),
                ),
                const SizedBox(width: 10),
              ],
              if (!_isViewerOnly)
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: FilledButton.icon(
                      key: const Key('add-relative-action'),
                      onPressed: () {
                        unawaited(_startAddRelativeFlow(selectedTreeId));
                      },
                      icon: const Icon(Icons.add),
                      label: Text(_graphAddLabel(treeProvider)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _showSecondaryLoadingStrip =>
      !_isRelationsReady || !_isChatsReady || _isPendingRequestsLoading;

  Widget _buildRelativesSidePanel({
    required int relativesCount,
    required int chatReadyCount,
    required int inviteReadyCount,
    required String treeName,
    required bool isFriendsTree,
  }) {
    final treeProvider = Provider.of<TreeProvider>(context, listen: false);
    final isFriendsTree = _isFriendsTree(treeProvider);
    final peopleLabel = isFriendsTree ? 'в круге' : 'в дереве';
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Чанк 26: было Wrap — на 320–340dp панели 3-5 чипов почти всегда
          // переносились на вторую строку («статистика ... одной строкой»
          // в требованиях). Горизонтальный скролл гарантирует одну строку
          // (высота чипа ~32dp, естественно ≤40dp) вместо непредсказуемого
          // переноса.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildSideStatChip(
                  icon: isFriendsTree
                      ? Icons.diversity_3_outlined
                      : Icons.account_tree_outlined,
                  label: treeName,
                ),
                const SizedBox(width: 8),
                _buildSideStatChip(
                  icon: Icons.people_outline,
                  label: '$relativesCount $peopleLabel',
                ),
                if (chatReadyCount > 0) ...[
                  const SizedBox(width: 8),
                  _buildSideStatChip(
                    icon: Icons.chat_bubble_outline,
                    label: _countLabel(
                      chatReadyCount,
                      one: 'чат',
                      few: 'чата',
                      many: 'чатов',
                    ),
                  ),
                ],
                if (inviteReadyCount > 0) ...[
                  const SizedBox(width: 8),
                  _buildSideStatChip(
                    icon: Icons.person_add_alt_1_outlined,
                    label: 'Пригласить $inviteReadyCount',
                  ),
                ],
                if (_pendingRequestsCount > 0) ...[
                  const SizedBox(width: 8),
                  _buildSideStatChip(
                    icon: Icons.notifications_none,
                    label: 'Запросы $_pendingRequestsCount',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (!_isViewerOnly)
                FilledButton.icon(
                  onPressed: _currentTreeId == null
                      ? null
                      : () => unawaited(_startAddRelativeFlow(_currentTreeId!)),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Добавить'),
                ),
              OutlinedButton.icon(
                onPressed: _currentTreeId == null
                    ? null
                    : () => context.push('/relatives/find/${_currentTreeId!}'),
                icon: const Icon(Icons.search),
                label: const Text('Найти'),
              ),
              if (!isFriendsTree)
                OutlinedButton.icon(
                  onPressed: () => context.push('/discover/relatives'),
                  icon: const Icon(Icons.travel_explore_rounded),
                  label: const Text('Проверить родство'),
                ),
              if (_pendingRequestsCount > 0)
                OutlinedButton.icon(
                  onPressed: _currentTreeId == null
                      ? null
                      : () => context
                          .push('/relatives/requests/${_currentTreeId!}'),
                  icon: const Icon(Icons.mark_email_unread_outlined),
                  label: const Text('Запросы'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSideStatChip({
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Раскрытый поиск в топбаре: стрелка «назад» + поле во всю ширину.
  List<Widget> _buildTopbarSearchRow(RodnyaDesignTokens tokens) {
    return [
      IconButton(
        tooltip: 'Закрыть поиск',
        icon: const Icon(Icons.arrow_back),
        onPressed: _closeSearch,
      ),
      Expanded(
        child: TextField(
          key: const ValueKey<String>('relatives-search-field'),
          controller: _searchController,
          focusNode: _searchFocusNode,
          autofocus: true,
          textAlignVertical: TextAlignVertical.center,
          style: AppTheme.sans(
            color: tokens.ink,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          cursorColor: tokens.accent,
          decoration: InputDecoration(
            isCollapsed: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            hintText: 'Поиск среди родных',
            hintStyle: AppTheme.sans(
              color: tokens.inkMuted,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    tooltip: 'Очистить поиск',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _searchController.clear,
                  )
                : null,
          ),
        ),
      ),
    ];
  }

  Widget _buildRelativesSearchField({
    required ThemeData theme,
    required RodnyaDesignTokens tokens,
  }) {
    // Reference styles.css `.card.flat`: surface bg, 14px h-padding, 46 height,
    // search icon at left, no shadow.
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.surfaceLine),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 18, color: tokens.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                hintText: 'Поиск среди родных',
                // M3 (50+): было 14 — десктопная пилюля-поиск отстала от
                // мобильной строки в топбаре (та уже на 16, см. ниже).
                hintStyle: AppTheme.sans(
                  color: tokens.inkMuted,
                  fontSize: AppTheme.formInputFontSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: AppTheme.sans(
                color: tokens.ink,
                fontSize: AppTheme.formInputFontSize,
                fontWeight: FontWeight.w500,
              ),
              cursorColor: tokens.accent,
            ),
          ),
          if (_searchQuery.isNotEmpty)
            // MouseRegion + GestureDetector reads as a clickable icon on
            // desktop; an InkWell ripple inside a tight search row looks
            // out of place, so we just light up the cursor. Wrapped in
            // a 44dp SizedBox — гайдлайновый минимум тап-таргета (2c;
            // раньше 36dp «компактный край» — старшим мало).
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Semantics(
                button: true,
                label: 'Очистить поиск',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _searchController.clear();
                  },
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: tokens.inkMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGraphContextBanner({
    required String treeName,
    required bool isFriendsTree,
    required int relativesCount,
    required int inAppCount,
    required int totalTreePeopleCount,
  }) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final countSummary = totalTreePeopleCount > relativesCount
        ? '$inAppCount из $relativesCount в приложении · всего в дереве $totalTreePeopleCount'
        : '$inAppCount из $relativesCount в приложении';

    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceStrong,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tokens.surfaceLine),
        boxShadow: tokens.panelShadow(theme.brightness),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isFriendsTree
                  ? Icons.diversity_3_outlined
                  : Icons.account_tree_outlined,
              color: tokens.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isFriendsTree ? 'АКТИВНЫЙ КРУГ' : 'АКТИВНОЕ ДЕРЕВО',
                  style: AppTheme.sans(
                    color: tokens.inkMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  treeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.serif(
                    color: tokens.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.18,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  countSummary,
                  style: AppTheme.sans(
                    color: tokens.inkMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRelativesTopbar({
    required ThemeData theme,
    required RodnyaDesignTokens tokens,
    required TreeProvider treeProvider,
    required String? selectedTreeId,
    required bool isFriendsTree,
  }) {
    // Skip BackdropFilter on Android (perf) — same pattern as
    // home/profile/chats topbars.
    final useBlur = defaultTargetPlatform != TargetPlatform.android;
    final body = Container(
      decoration: BoxDecoration(
        color: tokens.surface.withValues(
          alpha: theme.brightness == Brightness.dark
              ? (useBlur ? 0.74 : 0.96)
              : (useBlur ? 0.78 : 0.97),
        ),
        border: Border(
          bottom: BorderSide(
            color: tokens.surfaceLine.withValues(alpha: 0.5),
            width: 0.6,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: AppTheme.topbarContentHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 3, 4, 3),
            child: Row(
              children: [
                if (_isSearchOpen && !_isWideLayout(context))
                  ..._buildTopbarSearchRow(tokens)
                else ...[
                  // Заголовок и чип дерева — во вложенном Row внутри
                  // Expanded: рядом со Spacer два Flexible делили бы
                  // свободное место на троих, и заголовок резался в «Родн…».
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            isFriendsTree ? 'Круг' : 'Родные',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.serif(
                              color: tokens.ink,
                              fontSize: AppTheme.tabTitleFontSize,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.22,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Phase 6.1: branch switcher chip in the relatives
                        // top bar so the user can flip "родители папа /
                        // папина / семья жены" without leaving the screen.
                        const Flexible(child: BranchSwitcherChip()),
                      ],
                    ),
                  ),
                  ..._buildRelativesAppBarActions(
                    treeProvider: treeProvider,
                    selectedTreeId: selectedTreeId,
                    isFriendsTree: isFriendsTree,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (!useBlur) return body;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: body,
      ),
    );
  }

  List<Widget> _buildRelativesAppBarActions({
    required TreeProvider treeProvider,
    required String? selectedTreeId,
    required bool isFriendsTree,
  }) {
    return [
      if (!_isWideLayout(context))
        IconButton(
          key: const ValueKey<String>('relatives-search-toggle'),
          icon: const Icon(Icons.search),
          tooltip: 'Поиск',
          onPressed: _openSearch,
        ),
      IconButton(
        icon: const Icon(Icons.account_tree_outlined),
        // Ведёт на вкладку с уже выбранным деревом — «выбрать другое»
        // тут не обещаем: за выбором ходят в /trees.
        tooltip: 'Открыть дерево',
        onPressed: () {
          // Дерево — соседняя вкладка (центр бара/рейла).
          context.go('/tree');
        },
      ),
      if (_pendingRequestsCount > 0)
        Badge(
          label: Text(_pendingRequestsCount.toString()),
          child: IconButton(
            icon: const Icon(Icons.notifications_none),
            tooltip: isFriendsTree
                ? 'Запросы на связи ($_pendingRequestsCount)'
                : 'Запросы на родство ($_pendingRequestsCount)',
            onPressed: selectedTreeId == null
                ? null
                : () {
                    context.push('/relatives/requests/$selectedTreeId');
                  },
          ),
        ),
      PopupMenuButton<String>(
        onSelected: (value) => _handleRelativesMenuSelection(
          value,
          selectedTreeId: selectedTreeId,
        ),
        itemBuilder: (context) => _buildRelativesMenuItems(
          treeProvider: treeProvider,
          selectedTreeId: selectedTreeId,
          isFriendsTree: isFriendsTree,
        ),
      ),
    ];
  }

  List<PopupMenuEntry<String>> _buildRelativesMenuItems({
    required TreeProvider treeProvider,
    required String? selectedTreeId,
    required bool isFriendsTree,
  }) {
    return [
      PopupMenuItem<String>(
        value: 'add',
        enabled: selectedTreeId != null,
        child: ListTile(
          leading: const Icon(Icons.person_add),
          title: Text(_graphAddLabel(treeProvider)),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem<String>(
        value: 'create_tree',
        child: ListTile(
          leading: const Icon(Icons.add_circle_outline),
          title: Text(
            isFriendsTree ? 'Создать новый круг' : 'Создать новое дерево',
          ),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      if (_pendingRequestsCount > 0)
        PopupMenuItem<String>(
          value: 'requests_menu',
          enabled: selectedTreeId != null,
          child: ListTile(
            leading: const Icon(Icons.notifications),
            title: Text(
              isFriendsTree
                  ? 'Запросы на связи ($_pendingRequestsCount)'
                  : 'Запросы на родство ($_pendingRequestsCount)',
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      PopupMenuItem<String>(
        value: 'find',
        enabled: selectedTreeId != null,
        child: ListTile(
          leading: const Icon(Icons.search),
          title: Text(_graphFindLabel(treeProvider)),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ];
  }
}
