part of '../tree_view_screen.dart';

extension _TreeSelectionBulkSection on _TreeViewScreenState {
  Set<String> _expandSelectionWithAncestors(Iterable<String> seedIds) {
    final parentsOf = _buildParentEdges();
    final result = <String>{...seedIds};
    final queue = <String>[...seedIds];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final parents = parentsOf[current];
      if (parents == null) continue;
      for (final parent in parents) {
        if (result.add(parent)) {
          queue.add(parent);
        }
      }
    }
    return result;
  }

  Set<String> _expandSelectionWithDescendants(Iterable<String> seedIds) {
    final childrenOf = _buildChildEdges();
    final result = <String>{...seedIds};
    final queue = <String>[...seedIds];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final children = childrenOf[current];
      if (children == null) continue;
      for (final child in children) {
        if (result.add(child)) {
          queue.add(child);
        }
      }
    }
    return result;
  }

  Set<String> _expandSelectionWithLineage(Iterable<String> seedIds) {
    final withAncestors = _expandSelectionWithAncestors(seedIds);
    return _expandSelectionWithDescendants(withAncestors);
  }

  Map<String, Set<String>> _buildParentEdges() {
    final edges = <String, Set<String>>{};
    void link(String childId, String parentId) {
      edges.putIfAbsent(childId, () => <String>{}).add(parentId);
    }

    for (final relation in _relationsData) {
      if (relation.relation1to2 == RelationType.parent) {
        link(relation.person2Id, relation.person1Id);
      } else if (relation.relation1to2 == RelationType.child) {
        link(relation.person1Id, relation.person2Id);
      }
    }
    return edges;
  }

  Map<String, Set<String>> _buildChildEdges() {
    final edges = <String, Set<String>>{};
    void link(String parentId, String childId) {
      edges.putIfAbsent(parentId, () => <String>{}).add(childId);
    }

    for (final relation in _relationsData) {
      if (relation.relation1to2 == RelationType.parent) {
        link(relation.person1Id, relation.person2Id);
      } else if (relation.relation1to2 == RelationType.child) {
        link(relation.person2Id, relation.person1Id);
      }
    }
    return edges;
  }

  void _handleSelectionExpand(_SelectionExpand option) {
    if (_selectedPersonIds.isEmpty) return;
    final beforeCount = _selectedPersonIds.length;
    Set<String> expanded;
    String descriptor;
    switch (option) {
      case _SelectionExpand.ancestors:
        expanded = _expandSelectionWithAncestors(_selectedPersonIds);
        descriptor = 'предки';
        break;
      case _SelectionExpand.descendants:
        expanded = _expandSelectionWithDescendants(_selectedPersonIds);
        descriptor = 'потомки';
        break;
      case _SelectionExpand.lineage:
        expanded = _expandSelectionWithLineage(_selectedPersonIds);
        descriptor = 'вся линия';
        break;
    }
    final added = expanded.length - beforeCount;
    _updateSectionState(() {
      _selectedPersonIds
        ..clear()
        ..addAll(expanded);
    });
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          added > 0
              ? 'Добавлено в выбор ($descriptor): $added'
              : 'Никого нового не нашлось — связи уже выбраны.',
        ),
      ),
    );
  }

  Future<void> _openBulkAddToBranchSheet() async {
    if (!_isSelectionMode) return;
    if (_selectedPersonIds.isEmpty) return;
    final sourceTreeId = _currentTreeId;
    if (sourceTreeId == null) return;

    final messenger = ScaffoldMessenger.of(context);
    // Fetch the user's trees fresh from the service. TreeProvider
    // caches availableTrees but only fills the cache after the
    // user explicitly opens the BranchSwitcher / hits the
    // selector — and bulk-add can fire before either of those,
    // which would falsely report "Нужна вторая ветка". Going
    // straight to the service guarantees we see every branch the
    // viewer actually owns.
    List<FamilyTree> allTrees;
    try {
      allTrees = await _familyService.getUserTrees();
    } catch (error) {
      debugPrint('Bulk add-to-branch: failed to fetch user trees: $error');
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content:
              Text('Не удалось загрузить список веток. Попробуйте ещё раз.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    // Side-effect: keep TreeProvider's cache in sync so the next
    // BranchSwitcher open is instant.
    Provider.of<TreeProvider>(context, listen: false).refreshAvailableTrees();
    final candidates = allTrees
        .where((tree) => tree.id != sourceTreeId)
        .toList(growable: false);
    if (candidates.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Нужна вторая ветка — создайте её сначала.'),
        ),
      );
      return;
    }

    final FamilyTree? target = await showModalBottomSheet<FamilyTree>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(sheetContext).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Добавить ${_selectedPersonIds.length} в ветку',
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Эти люди появятся в выбранной ветке как карточки. '
                  'Связи между ними нужно будет соединить вручную.',
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final tree in candidates)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor:
                                  Theme.of(sheetContext).colorScheme.primary,
                              child: Icon(
                                tree.isFriendsTree
                                    ? Icons.diversity_3_outlined
                                    : Icons.account_tree,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              tree.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              tree.isPrivate ? 'Приватная' : 'Публичная',
                              style: Theme.of(sheetContext).textTheme.bodySmall,
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.of(sheetContext).pop(tree),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (target == null || !mounted) return;
    await _runBulkAddToBranch(targetTree: target);
  }

  Future<void> _runBulkAddToBranch({required FamilyTree targetTree}) async {
    final messenger = ScaffoldMessenger.of(context);
    final sourceTreeId = _currentTreeId;
    if (sourceTreeId == null) return;
    final selectedIds = List<String>.from(_selectedPersonIds);

    final service = _familyService;
    if (service is! BulkImportCapableFamilyTreeService) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Этот сервис пока не умеет переносить нескольких людей сразу.',
          ),
        ),
      );
      return;
    }
    // Explicit local cast — the `is!` check above is enough at the
    // type-system level, but extension-method scopes don't always
    // promote a final-field reference, so an explicit binding makes
    // the call sites work uniformly across compilers.
    final bulkImporter = service as BulkImportCapableFamilyTreeService;

    try {
      final result = await bulkImporter.bulkImportPersonsToTree(
        sourceTreeId: sourceTreeId,
        targetTreeId: targetTree.id,
        sourcePersonIds: selectedIds,
      );
      if (!mounted) return;
      _updateSectionState(() {
        _selectedPersonIds.clear();
        _isSelectionMode = false;
      });
      final relations = result.bridgedRelationCount;
      final personsLanded = result.persons.length;
      // Two cases worth distinguishing:
      // - Everyone was already in target via identity (personsLanded
      //   == 0): say so explicitly. Otherwise the user pokes the
      //   button, sees "0", and assumes failure.
      // - Some landed and some relations bridged: surface both
      //   counts so the «связь со мной» case feels visible.
      String message;
      if (personsLanded == 0 && relations == 0) {
        message = 'Эти люди уже есть в «${targetTree.name}» — там та же родня.';
      } else if (relations > 0) {
        message =
            'Добавлено в «${targetTree.name}»: $personsLanded • связей подтянулось: $relations';
      } else {
        message = 'Добавлено в «${targetTree.name}»: $personsLanded';
      }
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      debugPrint('Bulk import to ${targetTree.id} failed: $error');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Не удалось перенести людей в «${targetTree.name}». Попробуйте ещё раз.',
          ),
        ),
      );
    }
  }

  /// Bottom toolbar shown over the canvas while the user is in
  /// multi-select mode. Surfaces the selection count and the bulk
  /// action ("Add to branch…") + a "Done" exit button. Replaces the
  /// regular per-person bottom sheet so the user always sees a
  /// single coherent action surface — never both at once.
  Widget _buildSelectionToolbar({
    required Key key,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final count = _selectedPersonIds.length;
    final hasSelection = count > 0;
    return Material(
      key: key,
      elevation: 6,
      borderRadius: BorderRadius.circular(20),
      color: tokens.surface.withValues(alpha: 0.96),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(Icons.check_box_outlined, size: 20, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasSelection ? 'Выбрано: $count' : 'Режим выбора',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: tokens.ink,
                    ),
                  ),
                  Text(
                    hasSelection
                        ? 'Тап — добавить/убрать. Палочка — расширить по линии.'
                        : 'Тап — выбрать одну карточку. Drag по пустому холсту — выделить лассо.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.inkSecondary,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // «Расширить» — smart selection. Tap once on Mama,
            // tap «По её линии» → toolbar swallows all of mama's
            // ancestors + their descendants into the selection
            // set. Saves the user from individually tapping ~30
            // relatives when they want a slice like «мамина линия».
            // Disabled when the selection is empty (nothing to
            // expand from); always enabled when ≥1 person picked.
            PopupMenuButton<_SelectionExpand>(
              tooltip: 'Расширить выбор',
              enabled: hasSelection,
              onSelected: _handleSelectionExpand,
              itemBuilder: (_) => const <PopupMenuEntry<_SelectionExpand>>[
                PopupMenuItem<_SelectionExpand>(
                  value: _SelectionExpand.ancestors,
                  child: Row(
                    children: [
                      Icon(Icons.arrow_upward_rounded, size: 18),
                      SizedBox(width: 10),
                      Expanded(child: Text('Все предки выделенных')),
                    ],
                  ),
                ),
                PopupMenuItem<_SelectionExpand>(
                  value: _SelectionExpand.descendants,
                  child: Row(
                    children: [
                      Icon(Icons.arrow_downward_rounded, size: 18),
                      SizedBox(width: 10),
                      Expanded(child: Text('Все потомки выделенных')),
                    ],
                  ),
                ),
                PopupMenuItem<_SelectionExpand>(
                  value: _SelectionExpand.lineage,
                  child: Row(
                    children: [
                      Icon(Icons.account_tree_outlined, size: 18),
                      SizedBox(width: 10),
                      Expanded(child: Text('Вся эта линия')),
                    ],
                  ),
                ),
              ],
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: hasSelection
                      ? accent.withValues(alpha: 0.18)
                      : tokens.surfaceLine,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.auto_fix_high_outlined,
                  size: 20,
                  color: hasSelection ? accent : tokens.inkMuted,
                ),
              ),
            ),
            const SizedBox(width: 6),
            FilledButton.icon(
              onPressed: hasSelection ? _openBulkAddToBranchSheet : null,
              icon: const Icon(Icons.account_tree_outlined, size: 18),
              label: const Text('В ветку…'),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Закрыть режим выбора',
              onPressed: () {
                _updateSectionState(() {
                  _isSelectionMode = false;
                  _selectedPersonIds.clear();
                });
              },
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
