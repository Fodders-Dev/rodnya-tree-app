part of 'chats_list_screen.dart';

extension _ChatsListScreenSections on _ChatsListScreenState {
  Widget _buildDesktopShell({
    required ThemeData theme,
    required String currentUserId,
    required bool isFriendsTree,
    required String? selectedTreeName,
    required bool showInitialLoading,
  }) {
    final listPanel = GlassPanel(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(22),
      color: theme.colorScheme.surface.withValues(alpha: 0.78),
      child: Column(
        children: [
          _buildChatsOverview(
            theme,
            isFriendsTree: isFriendsTree,
            selectedTreeName: selectedTreeName,
            showLoadingPulse: showInitialLoading,
          ),
          _buildSearchBar(theme),
          _buildFilterBar(theme),
          Expanded(
            child: showInitialLoading
                ? _buildInitialLoadingState(theme)
                : _chatPreviews.isEmpty && _searchQuery.isEmpty
                    ? _buildEmptyState(theme)
                    : _buildChatList(theme, currentUserId),
          ),
        ],
      ),
    );

    if (!_isWideLayout(context)) {
      return Column(
        children: [
          _buildChatsOverview(
            theme,
            isFriendsTree: isFriendsTree,
            selectedTreeName: selectedTreeName,
            showLoadingPulse: showInitialLoading,
          ),
          _buildSearchBar(theme),
          _buildFilterBar(theme),
          Expanded(
            child: showInitialLoading
                ? _buildInitialLoadingState(theme)
                : _chatPreviews.isEmpty && _searchQuery.isEmpty
                    ? _buildEmptyState(theme)
                    : _buildChatList(theme, currentUserId),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: SizedBox(height: double.infinity, child: listPanel),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 320,
          child: GlassPanel(
            padding: const EdgeInsets.all(18),
            borderRadius: BorderRadius.circular(30),
            color: theme.colorScheme.surface.withValues(alpha: 0.76),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Связь',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _buildContextPill(
                  theme,
                  isFriendsTree: isFriendsTree,
                  label: selectedTreeName ??
                      (isFriendsTree ? 'Круг друзей' : 'Семейное дерево'),
                ),
                const SizedBox(height: 16),
                // Quick actions. Live deploy showed the previous
                // FilledButton.icon + FilledButton.tonalIcon mix
                // rendering as three indistinguishable green
                // rectangles — the warm sage palette fuses primary
                // and secondaryContainer at low contrast against
                // the panel's tinted glass backdrop. One filled
                // accent CTA + two outlined buttons gives a clear
                // visual hierarchy and readable labels on both
                // light and dark themes.
                FilledButton.icon(
                  onPressed: _openChatComposer,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  icon: const Icon(Icons.add_comment_outlined, size: 18),
                  label: const Text('Создать чат'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => context.go('/relatives'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  icon: const Icon(Icons.people_outline, size: 18),
                  label: Text(
                    isFriendsTree ? 'Открыть связи' : 'Открыть родных',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => context.go('/tree'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  icon: const Icon(Icons.account_tree_outlined, size: 18),
                  label: const Text('Открыть дерево'),
                ),
                const SizedBox(height: 18),
                _buildDesktopHint(
                  theme,
                  icon: Icons.search,
                  title: 'Поиск',
                  subtitle:
                      isFriendsTree ? 'Чаты и люди круга' : 'Чаты и родные',
                ),
                const SizedBox(height: 12),
                _buildDesktopHint(
                  theme,
                  icon: Icons.group_add_outlined,
                  title: 'Новый чат',
                  subtitle: 'Личный, групповой или чат ветки',
                ),
                const SizedBox(height: 12),
                _buildDesktopHint(
                  theme,
                  icon: Icons.mark_chat_read_outlined,
                  title: 'Поток',
                  subtitle: 'Новые, архив и быстрые действия',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopHint(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: theme.colorScheme.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatsOverview(
    ThemeData theme, {
    required bool isFriendsTree,
    required String? selectedTreeName,
    required bool showLoadingPulse,
  }) {
    // Slim overview: just the active context pill plus a single unread/all
    // status chip. Detailed counts live further down inside individual list
    // entries — this header should help orient at a glance, not enumerate.
    final unreadCount = _chatPreviews.fold<int>(
      0,
      (sum, chat) => sum + chat.unreadCount,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildContextPill(
            theme,
            isFriendsTree: isFriendsTree,
            label: selectedTreeName ??
                (isFriendsTree ? 'Круг друзей' : 'Семейное дерево'),
          ),
          _buildChatStatChip(
            theme,
            icon: unreadCount > 0
                ? Icons.mark_chat_unread_outlined
                : Icons.mark_chat_read_outlined,
            label: unreadCount > 0
                ? _countLabel(
                    unreadCount,
                    one: 'непрочитанный',
                    few: 'непрочитанных',
                    many: 'непрочитанных',
                  )
                : 'Все прочитано',
            highlighted: unreadCount > 0,
          ),
        ],
      ),
    );
  }

  Widget _buildContextPill(
    ThemeData theme, {
    required bool isFriendsTree,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFriendsTree
                ? Icons.diversity_3_outlined
                : Icons.account_tree_outlined,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatStatChip(
    ThemeData theme, {
    required IconData icon,
    required String label,
    bool highlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlighted
            ? theme.colorScheme.primary.withValues(alpha: 0.10)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: highlighted ? theme.colorScheme.primary : null,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: GlassPanel(
        padding: EdgeInsets.zero,
        blur: 12,
        borderRadius: BorderRadius.circular(18),
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: (value) {
            _setSearchQuery(value.trim().toLowerCase());
          },
          decoration: InputDecoration(
            hintText: context.read<TreeProvider>().selectedTreeKind ==
                    TreeKind.friends
                ? 'Поиск чатов и людей круга'
                : 'Поиск чатов и людей',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    tooltip: 'Очистить поиск',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _clearSearchQuery();
                    },
                  )
                : null,
            filled: false,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar(ThemeData theme) {
    final archivedCount = _archivedPreviewCount();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Все'),
            selected: _activeFilter == _ChatsVisibilityFilter.all,
            onSelected: (_) {
              _setActiveFilter(_ChatsVisibilityFilter.all);
            },
          ),
          ChoiceChip(
            label: const Text('Непрочитанные'),
            selected: _activeFilter == _ChatsVisibilityFilter.unread,
            onSelected: (_) {
              _setActiveFilter(_ChatsVisibilityFilter.unread);
            },
          ),
          ChoiceChip(
            label: Text(
              archivedCount > 0 ? 'Архив ($archivedCount)' : 'Архив',
            ),
            selected: _activeFilter == _ChatsVisibilityFilter.archived,
            onSelected: (_) {
              _setActiveFilter(_ChatsVisibilityFilter.archived);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterEmptyState(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
    String? secondaryActionLabel,
    VoidCallback? onSecondaryAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: GlassPanel(
            borderRadius: BorderRadius.circular(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 34, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton(
                      onPressed: onAction,
                      child: Text(actionLabel),
                    ),
                    if (secondaryActionLabel != null &&
                        onSecondaryAction != null)
                      FilledButton.tonal(
                        onPressed: onSecondaryAction,
                        child: Text(secondaryActionLabel),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArchiveSummaryCard(ThemeData theme) {
    final archivedCount = _archivedPreviewCount();
    final unreadCount = _archivedUnreadCount();
    final archiveLabel = _countLabel(
      archivedCount,
      one: 'чат в архиве',
      few: 'чата в архиве',
      many: 'чатов в архиве',
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          _setActiveFilter(_ChatsVisibilityFilter.archived);
        },
        child: GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          borderRadius: BorderRadius.circular(22),
          blur: 10,
          color: theme.colorScheme.surface.withValues(alpha: 0.74),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.archive_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      archiveLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      unreadCount > 0
                          ? '$unreadCount непрочитанных'
                          : 'Чистый основной поток',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatMetaPill(
    ThemeData theme, {
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
