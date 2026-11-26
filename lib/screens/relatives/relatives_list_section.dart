part of '../relatives_screen.dart';

extension _RelativesListSection on _RelativesScreenState {
  Widget _buildLoadingState() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: GlassPanel(
          padding: const EdgeInsets.all(24),
          borderRadius: BorderRadius.circular(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Загружаем родных',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Сначала подтянем список, остальное догрузим следом.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String selectedTreeId) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: GlassPanel(
            padding: const EdgeInsets.all(24),
            borderRadius: BorderRadius.circular(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _appStatusService.isOffline
                      ? Icons.cloud_off_outlined
                      : Icons.people_outline_rounded,
                  size: 40,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 14),
                Text(
                  _appStatusService.isOffline
                      ? 'Нет соединения'
                      : 'Родные временно недоступны',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    _appStatusService.requestRetry();
                    unawaited(_loadDataForSelectedTree(selectedTreeId));
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryLoadingStrip() {
    final theme = Theme.of(context);
    final labels = <String>[
      if (!_isRelationsReady) 'связи',
      if (!_isChatsReady) 'чаты',
      if (_isPendingRequestsLoading) 'запросы',
    ];
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      borderRadius: BorderRadius.circular(22),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Догружаем: ${labels.join(', ')}.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoTreeSelected() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: GlassPanel(
          padding: const EdgeInsets.all(24),
          borderRadius: BorderRadius.circular(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_tree_outlined,
                size: 42,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 14),
              Text(
                'Выберите дерево',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Здесь появятся люди и действия.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Открыть'),
                onPressed: () => context.go('/trees'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRelativesList({
    required Key key,
    required List<FamilyPerson> relativesForTab,
    required bool isOnlineTab,
  }) {
    debugPrint(
      '[_buildRelativesList called] isOnlineTab: $isOnlineTab, relatives count: ${relativesForTab.length}',
    );

    if (relativesForTab.isEmpty) {
      final treeProvider = Provider.of<TreeProvider>(context, listen: false);
      // Пустой ПОИСК ≠ пустое дерево: «Родных пока нет / Добавьте
      // первого человека» при 40 родных и неудачном запросе вводило в
      // заблуждение (смоук 2026-07-04).
      final searchQuery = _searchQuery.trim();
      if (searchQuery.isNotEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: GlassPanel(
              padding: const EdgeInsets.all(16),
              borderRadius: BorderRadius.circular(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 32,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Никого не нашли',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'По запросу «$searchQuery» совпадений нет.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassPanel(
            padding: const EdgeInsets.all(16),
            borderRadius: BorderRadius.circular(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isOnlineTab
                      ? Icons.chat_bubble_outline
                      : Icons.people_outline,
                  size: 32,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 10),
                Text(
                  isOnlineTab
                      ? 'Чатов нет'
                      : _isFriendsTree(Provider.of<TreeProvider>(
                          context,
                          listen: false,
                        ))
                          ? 'Людей пока нет'
                          : 'Родных пока нет',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (!isOnlineTab && !_isViewerOnly) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Добавьте первого человека.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _currentTreeId == null
                        ? null
                        : () =>
                            unawaited(_startAddRelativeFlow(_currentTreeId!)),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: Text(_graphAddLabel(treeProvider)),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    int byName(FamilyPerson a, FamilyPerson b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());

    final pendingPeople = <FamilyPerson>[];
    final joinedPeople = <FamilyPerson>[];
    final deceasedPeople = <FamilyPerson>[];
    for (final relative in relativesForTab) {
      if (_canInviteRelative(relative)) {
        pendingPeople.add(relative);
      } else if (_isDeceasedWithoutAccount(relative)) {
        deceasedPeople.add(relative);
      } else {
        joinedPeople.add(relative);
      }
    }
    pendingPeople.sort(byName);
    joinedPeople.sort(byName);
    deceasedPeople.sort(byName);

    // F3: живые пользователи — первыми («с ними взаимодействуют»),
    // «Нужно пригласить» — ниже и свёрнута по умолчанию. Поиск ищет по
    // всем: при непустом запросе секция раскрывается, чтобы совпадения
    // не пропали за свёрткой.
    final bool searchActive = _searchQuery.trim().isNotEmpty;
    final bool pendingExpanded =
        _RelativesScreenState._pendingSectionExpandedThisSession ||
            searchActive;

    final List<dynamic> flatList = [];
    if (joinedPeople.isNotEmpty) {
      flatList.add(_RelativesSectionHeader(
        title: isOnlineTab ? 'Чаты' : 'В приложении',
      ));
      flatList.addAll(joinedPeople);
    }
    if (!isOnlineTab && pendingPeople.isNotEmpty) {
      // Если зарегистрированных нет вовсе, сворачивать нечего — список
      // приглашений и есть весь экран.
      final bool collapsible =
          joinedPeople.isNotEmpty || deceasedPeople.isNotEmpty;
      final bool expanded = !collapsible || pendingExpanded;
      flatList.add(_RelativesSectionHeader(
        title: 'Нужно пригласить',
        count: pendingPeople.length,
        collapsible: collapsible,
        expanded: expanded,
        onToggle: collapsible
            ? () {
                _updateRelativesState(() {
                  _RelativesScreenState._pendingSectionExpandedThisSession =
                      !pendingExpanded;
                });
              }
            : null,
      ));
      if (expanded) {
        flatList.addAll(pendingPeople);
      }
    }
    if (!isOnlineTab && deceasedPeople.isNotEmpty) {
      flatList.add(_RelativesSectionHeader(
        title: 'Ушедшие близкие',
        count: deceasedPeople.length,
      ));
      flatList.addAll(deceasedPeople);
    }
    if (!isOnlineTab &&
        pendingPeople.isEmpty &&
        joinedPeople.isEmpty &&
        deceasedPeople.isEmpty) {
      flatList.addAll(relativesForTab);
    }

    // Pull-to-refresh: данные экрана — one-shot fetch без realtime, а
    // родню добавляют и ДРУГИЕ члены семьи, пока экран открыт. Паттерн
    // как у home_screen/chats_list.
    return RefreshIndicator(
      onRefresh: () async {
        final treeId = _currentTreeId;
        if (treeId != null) {
          await _loadDataForSelectedTree(treeId);
        }
      },
      child: ListView.builder(
        key: key,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 2, bottom: 12),
        itemCount: flatList.length,
        itemBuilder: (context, index) {
          final item = flatList[index];

          if (item is _RelativesSectionHeader) {
            final theme = Theme.of(context);
            final tokens = theme.extension<RodnyaDesignTokens>() ??
                (theme.brightness == Brightness.dark
                    ? RodnyaDesignTokens.dark
                    : RodnyaDesignTokens.light);
            final headerRow = Row(
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    style: AppTheme.serif(
                      color: tokens.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.18,
                    ),
                  ),
                ),
                if (item.count != null && item.count! > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.warmSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${item.count}',
                      style: AppTheme.sans(
                        color: tokens.warm,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                // F3: шеврон у сворачиваемой секции — видно, что строка
                // нажимается и что внутри ещё есть люди.
                if (item.collapsible) ...[
                  const SizedBox(width: 6),
                  Icon(
                    item.expanded ? Icons.expand_less : Icons.expand_more,
                    size: 22,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            );
            if (item.collapsible && item.onToggle != null) {
              return InkWell(
                key: const Key('relatives-pending-section-toggle'),
                borderRadius: BorderRadius.circular(12),
                onTap: item.onToggle,
                child: Padding(
                  // ≥44dp тап-цель: 18+8 вертикальных отступов + строка.
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                  child: headerRow,
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
              child: headerRow,
            );
          } else if (item is FamilyPerson) {
            final relative = item;
            final relationDescription = _getRelationDescription(relative);

            ChatPreview? chatPreview;
            if (isOnlineTab && relative.userId != null) {
              try {
                chatPreview = _chatPreviews.firstWhere(
                  (preview) => preview.otherUserId == relative.userId,
                );
              } catch (e) {
                chatPreview = null;
              }
            }

            final String lastMessageText = chatPreview?.lastMessage ?? '';
            final DateTime? lastMessageTimestamp = chatPreview?.lastMessageTime;
            final int unreadCount = chatPreview?.unreadCount ?? 0;
            final bool isLastMessageFromMe =
                chatPreview?.lastMessageSenderId == _currentUserId;
            final bool canStartChat = _canStartChat(relative);
            final bool canInvite = _canInviteRelative(relative);
            final contactStatus = _getContactStatus(relative);
            final int photoCount = relative.photoGallery.length;
            final bool hasGallery = photoCount > 0;
            final avatarImage =
                buildAvatarImageProvider(relative.primaryPhotoUrl);

            final theme = Theme.of(context);
            // Плотность (02.09.2026): строка списка — не карточка. Рамка,
            // скругление 24 и вертикальные поля давали ~100dp на человека;
            // плоская строка с волосяным разделителем — как в списке чатов
            // и в Telegram — вмещает в полтора раза больше родных на экран.
            return DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.35),
                    width: 0.6,
                  ),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.zero,
                child: ListTile(
                  visualDensity: const VisualDensity(vertical: -1),
                  leading: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () async {
                        debugPrint(
                          'Avatar tapped for ${relative.displayName}, navigating to details...',
                        );
                        await context.push(
                          relativeDetailsRoute(
                            relative.id,
                            treeId: relative.treeId,
                          ),
                        );
                        if (!mounted || _currentTreeId == null) return;
                        unawaited(_loadDataForSelectedTree(_currentTreeId!));
                      },
                      child: CircleAvatar(
                        radius: 22,
                        backgroundImage: avatarImage,
                        child: avatarImage == null
                            ? Text(relative.initials,
                                style: TextStyle(fontSize: 16))
                            : null,
                      ),
                    ),
                  ),
                  title: Text(
                    relative.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: unreadCount > 0
                          ? Theme.of(context).primaryColor
                          : null,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        relationDescription,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                      if (!isOnlineTab || hasGallery)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              // Skip the per-tile invite-status chip for the
                              // pending section since the section header already
                              // says "Нужно пригласить". Keep "Можно написать"
                              // and "Только просмотр" so chat-ready and view-only
                              // states stay scannable per row.
                              if (!isOnlineTab && !canInvite)
                                _buildRelativeInfoChip(
                                  context,
                                  icon: Icons.circle,
                                  label: contactStatus.label,
                                  color: contactStatus.color,
                                  iconSize: 8,
                                ),
                              if (hasGallery)
                                _buildRelativeInfoChip(
                                  context,
                                  icon: Icons.photo_library_outlined,
                                  label: _countLabel(
                                    photoCount,
                                    one: 'фото',
                                    few: 'фото',
                                    many: 'фото',
                                  ),
                                  color:
                                      Theme.of(context).colorScheme.secondary,
                                ),
                              // Чип «Основное фото» убран: наличие фото и так
                              // видно по аватару, а чип добавлял третью
                              // строку каждому человеку с фотографией.
                            ],
                          ),
                        ),
                      if (isOnlineTab && lastMessageText.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2.0),
                          child: Row(
                            children: [
                              if (isLastMessageFromMe)
                                Text(
                                  'Вы: ',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  lastMessageText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: unreadCount > 0
                                        ? Colors.black87
                                        : Colors.black54,
                                    fontWeight: unreadCount > 0
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (isOnlineTab &&
                          lastMessageText.isEmpty &&
                          relative.userId != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2.0),
                          child: Text(
                            'Нет сообщений',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                  trailing: isOnlineTab && lastMessageTimestamp != null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatTimestamp(lastMessageTimestamp),
                              style: TextStyle(
                                fontSize: 12,
                                color: unreadCount > 0
                                    ? Theme.of(context).primaryColor
                                    : Colors.grey,
                                fontWeight: unreadCount > 0
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            if (unreadCount > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: CircleAvatar(
                                  radius: 9,
                                  backgroundColor:
                                      Theme.of(context).primaryColor,
                                  child: Text(
                                    unreadCount.toString(),
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Phase 3.4 chunk 5: per-row conflict
                            // badge. Compact = icon-only (число
                            // уходит в Semantics label, чтобы не
                            // загромождать строку). Tap → sheet
                            // конкретного person'а.
                            if ((_conflictCounts[relative.id] ?? 0) > 0)
                              IdentityConflictsBadge(
                                count: _conflictCounts[relative.id]!,
                                compact: true,
                                onTap: () => _showConflictsSheet(relative.id),
                              ),
                            if (canStartChat)
                              IconButton(
                                icon: const Icon(Icons.message_outlined),
                                tooltip: 'Написать ${relative.displayName}',
                                visualDensity: VisualDensity.compact,
                                onPressed: () =>
                                    _openChatWithRelative(relative),
                              ),
                            if (canInvite)
                              IconButton(
                                icon:
                                    const Icon(Icons.person_add_alt_1_outlined),
                                tooltip: 'Пригласить ${relative.displayName}',
                                visualDensity: VisualDensity.compact,
                                onPressed: () =>
                                    _shareInviteForRelative(relative),
                              ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                  onTap: () async {
                    if (isOnlineTab) {
                      if (canStartChat) {
                        _openChatWithRelative(relative);
                      } else {
                        debugPrint(
                          'Cannot chat with self or invalid user, navigating to details for ${relative.displayName}',
                        );
                        await context.push(
                          relativeDetailsRoute(
                            relative.id,
                            treeId: relative.treeId,
                          ),
                        );
                        if (!mounted || _currentTreeId == null) return;
                        unawaited(_loadDataForSelectedTree(_currentTreeId!));
                      }
                    } else {
                      debugPrint(
                        'Offline tab, navigating to details for ${relative.displayName}',
                      );
                      await context.push(
                        relativeDetailsRoute(
                          relative.id,
                          treeId: relative.treeId,
                        ),
                      );
                      if (!mounted || _currentTreeId == null) return;
                      unawaited(_loadDataForSelectedTree(_currentTreeId!));
                    }
                  },
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  // Плоская строка: ink без скругления, как у чатов.
                  shape: const RoundedRectangleBorder(),
                ),
              ),
            );
          }
          return SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildRelativeInfoChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    double iconSize = 14,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: color),
          const SizedBox(width: 6),
          // Flexible+ellipsis: на узких строках (A50, 412dp) чип
          // «Можно написать» переполнял слот на 3px — текст обязан
          // сжиматься, а не рисовать striped-полосу.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
