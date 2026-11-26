part of '../relatives_screen.dart';

extension _RelativesActions on _RelativesScreenState {
  /// Открывает sheet с conflicts конкретного person'а — тот же
  /// reusable widget что и на canvas.
  Future<void> _showConflictsSheet(String personId) async {
    final treeId = _currentTreeId;
    final service = _familyService;
    if (treeId == null ||
        service is! IdentityConflictsCapableFamilyTreeService) {
      return;
    }
    final personConflicts = _treeConflictsCache
        .where((c) => c.targetPersonId == personId && !c.isResolved)
        .toList(growable: false);
    if (personConflicts.isEmpty) {
      // Cache stale — refresh и выходим (badge исчезнет на следующем
      // setState).
      await _refreshConflictCounts(treeId);
      return;
    }
    final capable = service as IdentityConflictsCapableFamilyTreeService;
    await showIdentityConflictsSheet(
      context: context,
      conflicts: personConflicts,
      onChoice: (sheetContext, conflict, choice) async {
        try {
          await capable.resolveIdentityConflict(
            treeId: treeId,
            conflictId: conflict.id,
            choice: choice,
          );
        } catch (error) {
          if (sheetContext.mounted) {
            ScaffoldMessenger.of(sheetContext).showSnackBar(
              SnackBar(
                  content: Text(humanizeError(error,
                      fallback: 'Не удалось применить выбор.'))),
            );
          }
          return;
        }
        if (sheetContext.mounted) {
          Navigator.of(sheetContext).pop();
        }
        await _refreshConflictCounts(treeId);
      },
    );
  }

  /// Открывает summary sheet'е со ВСЕМИ unresolved conflict'ами
  /// дерева — без разбивки по person'у. Используется header
  /// banner'ом «N карточек требуют внимания».
  Future<void> _showAllTreeConflicts() async {
    final treeId = _currentTreeId;
    final service = _familyService;
    if (treeId == null ||
        service is! IdentityConflictsCapableFamilyTreeService ||
        _treeConflictsCache.isEmpty) {
      return;
    }
    final capable = service as IdentityConflictsCapableFamilyTreeService;
    await showIdentityConflictsSheet(
      context: context,
      conflicts: _treeConflictsCache,
      onChoice: (sheetContext, conflict, choice) async {
        try {
          await capable.resolveIdentityConflict(
            treeId: treeId,
            conflictId: conflict.id,
            choice: choice,
          );
        } catch (error) {
          if (sheetContext.mounted) {
            ScaffoldMessenger.of(sheetContext).showSnackBar(
              SnackBar(
                  content: Text(humanizeError(error,
                      fallback: 'Не удалось применить выбор.'))),
            );
          }
          return;
        }
        if (sheetContext.mounted) {
          Navigator.of(sheetContext).pop();
        }
        await _refreshConflictCounts(treeId);
      },
    );
  }

  void _openSearch() {
    if (_isSearchOpen) return;
    _updateRelativesState(() => _isSearchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    if (!_isSearchOpen) return;
    _searchFocusNode.unfocus();
    _searchController.clear();
    _updateRelativesState(() => _isSearchOpen = false);
  }

  void _openChatWithRelative(FamilyPerson relative) {
    final userId = relative.userId;
    if (userId == null || userId.isEmpty) {
      return;
    }

    final nameParam = Uri.encodeComponent(relative.displayName);
    final photoUrl = relative.primaryPhotoUrl;
    final photoParam = (photoUrl != null && photoUrl.isNotEmpty)
        ? Uri.encodeComponent(photoUrl)
        : '';
    debugPrint(
      'Navigating to chat with ${relative.displayName} (ID: $userId)',
    );
    context.push(
      '/relatives/chat/$userId?name=$nameParam&photo=$photoParam&relativeId=${relative.id}',
    );
  }

  Future<void> _shareInviteForRelative(FamilyPerson relative) async {
    if (!_canInviteRelative(relative) || _currentTreeId == null) {
      return;
    }

    try {
      final inviteUrl = _invitationLinkService.buildInvitationLink(
        treeId: _currentTreeId!,
        personId: relative.id,
      );
      final isFriendsTree =
          _treeProviderInstance?.selectedTreeKind == TreeKind.friends;
      if (!mounted) return;
      await showInviteShareSheet(
        context,
        inviteUrl: inviteUrl,
        message: isFriendsTree
            ? 'Присоединяйтесь к нашему кругу друзей в Родне: ${inviteUrl.toString()}'
            : 'Присоединяйтесь к нашему семейному дереву в Родне: ${inviteUrl.toString()}',
        subject:
            isFriendsTree ? 'Приглашение в круг друзей' : 'Приглашение в Родню',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось подготовить приглашение.'),
        ),
      );
    }
  }

  /// Смоук 2026-07-04 (дважды): «Сохранено ✓», а карточки в списке нет
  /// до полной перезагрузки. Данные экрана — one-shot fetch
  /// (getRelativesStream = Stream.fromFuture), а все точки «Добавить»
  /// выбрасывали результат add-флоу. Паттерн tree_view_screen: ждём
  /// результат и перезагружаем. Перезагружаем и на null-результате
  /// (back из quick-add цикла сохраняет людей БЕЗ pop-результата —
  /// лишний fetch на отмене безвреден, пропущенная карточка — нет).
  Future<void> _startAddRelativeFlow(String treeId) async {
    final isFriendsCircle =
        context.read<TreeProvider>().selectedTreeKind == TreeKind.friends;
    await showRelationPickerAndNavigateAdd(
      context,
      treeId: treeId,
      isFriendsCircle: isFriendsCircle,
    );
    if (!mounted) {
      return;
    }
    await _loadDataForSelectedTree(treeId);
  }

  void _handleRelativesMenuSelection(
    String value, {
    required String? selectedTreeId,
  }) {
    if (selectedTreeId == null) {
      showAppSnackBar(context, 'Сначала выберите дерево');
      return;
    }

    if (value == 'add') {
      // Audit Screen 4.2 (2026-05-28): explicit «Кем приходится?»
      // step ПЕРЕД name form. Через _startAddRelativeFlow — список
      // перезагружается после сохранения (stale-list смоук 2026-07-04).
      unawaited(_startAddRelativeFlow(selectedTreeId));
    } else if (value == 'find') {
      context.push('/relatives/find/$selectedTreeId');
    } else if (value == 'create_tree') {
      context.push('/trees/create').then((result) {
        // Можно опционально перейти на новый экран дерева после создания.
      });
    } else if (value == 'requests_menu') {
      context.push('/relatives/requests/$selectedTreeId');
    }
  }
}
