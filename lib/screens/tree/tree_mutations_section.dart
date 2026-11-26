part of '../tree_view_screen.dart';

extension _TreeMutationsSection on _TreeViewScreenState {
  void _handleAddRelativeFromTree(FamilyPerson person, RelationType type) {
    if (_currentTreeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Не удалось определить активное дерево. Откройте его заново и повторите действие.',
          ),
        ),
      );
      return;
    }
    debugPrint(
      'Добавление родственника типа $type к ${person.name} (${person.id}) в дереве $_currentTreeId',
    );

    // Переходим на экран добавления, передавая контекст
    // AddRelativeScreen должен будет обработать эти параметры в 'extra'
    context.push(
      '/relatives/add/$_currentTreeId',
      extra: {
        'contextPersonId': person.id, // К кому добавляем
        'relationType':
            type, // Какого типа родственника добавляем (относительно contextPersonId)
        'quickAddMode': true,
      },
    ).then((result) {
      if (!mounted) {
        return;
      }
      if (result == true) {
        debugPrint('Возврат с экрана добавления (из дерева), перезагрузка...');
        _loadData(_currentTreeId!);
        return;
      }
      if (result is Map<String, dynamic> && result['updated'] == true) {
        final focusPersonId = result['focusPersonId']?.toString();
        _loadData(_currentTreeId!).then((_) {
          if (!mounted || focusPersonId == null) {
            return;
          }
          final focusedPerson = _relativesData
              .map((entry) => entry['person'])
              .whereType<FamilyPerson>()
              .firstWhere(
                (candidate) => candidate.id == focusPersonId,
                orElse: () => FamilyPerson.empty,
              );
          if (focusedPerson != FamilyPerson.empty) {
            _updateSectionState(() {
              _selectedEditPersonId = focusedPerson.id;
            });
          }
        });
      }
    });
  }

  // <<< НОВЫЙ МЕТОД-КОЛЛБЭК: Обработка добавления себя из дерева >>>
  // ── Phase 1.2 voltage-indicator matcher handlers ────────────────
  // The canvas reads `_identitySuggestionCounts` to decide where
  // to show the 💡 dot; tap on the dot calls `_handleShowIdentity
  // SuggestionsForPerson` which fetches details, opens a sheet
  // with the suggestion list, dispatches link/dismiss on the
  // service, and refreshes the counts.

  Future<void> _handleAddBlankPersonFromTree(
    Map<String, dynamic> personData,
  ) async {
    final treeId = _currentTreeId;
    if (treeId == null) return;
    try {
      // addRelative returns the new person id — we capture it so
      // the tree can auto-center on the new card after the
      // reload (nice UX detail: without this, a freshly-created
      // orphan ends up wherever the layout engine puts it,
      // possibly off-screen if the user is zoomed into another
      // branch).
      final newPersonId = await _familyService.addRelative(treeId, personData);
      if (!mounted) return;
      // Record for undo (this path didn't before) → «Отменить» deletes it.
      if (GetIt.I.isRegistered<TreeMutationHistory>()) {
        GetIt.I<TreeMutationHistory>().recordPersonAdded(
          treeId: treeId,
          personId: newPersonId,
          personData: personData,
        );
      }
      await _loadData(treeId);
      if (!mounted) return;
      _updateSectionState(() {
        _recenterOnPersonIdAfterReload = newPersonId;
      });
      _showTreeUndoToast('Карточка добавлена. Соедините её длинным нажатием.');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(humanizeError(error,
                fallback: 'Не удалось добавить карточку.'))),
      );
    }
  }

  // Edge-first connector handler. Called when the user has dragged
  // one card onto another and picked a relation type from the inline
  // 4-icon picker. Skips the AddRelativeScreen form entirely and
  // creates the relation directly via the family-tree service, then
  // reloads the tree so the new edge appears.
  //
  // The picker only offers four relation types (parent, spouse,
  // sibling, other). For "other" we open a small sheet to ask which
  // long-tail relation (cousin / nephew / step-* / etc.) — better
  // than guessing wrong and silently writing a bad edge.
  Future<void> _handleConnectExistingFromTree(
    String sourcePersonId,
    String targetPersonId,
    RelationType relation1to2,
  ) async {
    final treeId = _currentTreeId;
    if (treeId == null) return;
    if (sourcePersonId.isEmpty || targetPersonId.isEmpty) return;
    if (sourcePersonId == targetPersonId) return;

    // For "other" we DON'T have enough info to create a relation —
    // pop the legacy quick-add sheet pre-anchored on the target so
    // the user can pick the specific long-tail type. This is the
    // only branch where the form is still needed.
    if (relation1to2 == RelationType.other) {
      final sourcePerson = _relativesData
          .map((entry) => entry['person'])
          .whereType<FamilyPerson>()
          .firstWhere(
            (person) => person.id == sourcePersonId,
            orElse: () => FamilyPerson(
              id: sourcePersonId,
              treeId: treeId,
              name: '',
              gender: Gender.unknown,
              isAlive: true,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      _handleAddRelativeFromTree(sourcePerson, relation1to2);
      return;
    }

    try {
      final created = await _familyService.createRelation(
        treeId: treeId,
        person1Id: sourcePersonId,
        person2Id: targetPersonId,
        relation1to2: relation1to2,
        isConfirmed: true,
      );
      if (GetIt.I.isRegistered<TreeMutationHistory>()) {
        GetIt.I<TreeMutationHistory>().recordRelationCreated(
          treeId: treeId,
          created: created,
        );
      }
      if (!mounted) return;
      // Reload so the new edge renders + layout engine can rebalance.
      await _loadData(treeId);
      if (mounted) _showTreeUndoToast('Связь создана');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                humanizeError(error, fallback: 'Не удалось создать связь.'))),
      );
    }
  }

  // Phase B polish B: ~10s «Отменить» toast after an add (mama doesn't
  // know Ctrl+Z). «Отменить» → TreeMutationHistory.undoForUi() inverts the
  // most-recent mutation (recordPersonAdded → delete; recordRelationCreated
  // → disconnect) and reloads.
  void _showTreeUndoToast(String message) {
    if (!GetIt.I.isRegistered<TreeMutationHistory>()) {
      showAppSnackBar(context, message);
      return;
    }
    showAppSnackBar(
      context,
      message,
      duration: const Duration(seconds: 10),
      action: SnackBarAction(
        label: 'Отменить',
        onPressed: _undoLastTreeMutation,
      ),
    );
  }

  Future<void> _undoLastTreeMutation() async {
    if (!GetIt.I.isRegistered<TreeMutationHistory>()) return;
    final description =
        await GetIt.I<TreeMutationHistory>().undoForUi(_familyService);
    if (!mounted || description == null) return;
    final treeId = _currentTreeId;
    if (treeId != null) await _loadData(treeId);
    if (mounted) showAppSnackBar(context, 'Отменено: $description');
  }

  Future<void> _handleAddSelfFromTree(
    FamilyPerson targetPerson,
    RelationType relationType,
  ) async {
    if (_currentTreeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Не удалось определить активное дерево. Откройте его заново и повторите действие.',
          ),
        ),
      );
      return;
    }

    final currentUserId = _authService.currentUserId;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Сессия завершилась. Войдите снова.')),
      );
      context.go('/login'); // Перенаправляем на логин
      return;
    }

    // Показываем индикатор загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("Добавляем вас в дерево..."),
              ],
            ),
          ),
        );
      },
    );

    try {
      debugPrint(
        'Добавление ТЕКУЩЕГО ПОЛЬЗОВАТЕЛЯ ($currentUserId) типа $relationType к ${targetPerson.name} (${targetPerson.id}) в дереве $_currentTreeId',
      );

      // Вызываем новый метод сервиса
      await _familyService.addCurrentUserToTree(
        treeId: _currentTreeId!,
        targetPersonId: targetPerson.id,
        relationType: relationType,
      );
      if (!mounted) return;

      // Закрываем диалог загрузки
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Вы успешно добавлены в дерево!'),
          duration: Duration(seconds: 2),
        ),
      );

      // Обновляем данные дерева, чтобы отобразить изменения и скрыть кнопку
      debugPrint('Перезагрузка дерева после добавления себя...');
      _updateSectionState(() {
        _currentUserIsInTree = true;
      });
      await _loadData(_currentTreeId!);
    } catch (e, s) {
      // Закрываем диалог загрузки в случае ошибки
      if (mounted) Navigator.pop(context);

      debugPrint('Ошибка при добавлении себя в дерево: $e\\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _describeTreeActionError(
                e,
                fallbackMessage:
                    'Не удалось добавить вас в дерево. Попробуйте ещё раз.',
              ),
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
      debugPrint('Error in handleAddSelfFromTree: $e\n$s');
    }
  }

  // =============================================================

  Future<void> _navigateToAddRelative(String treeId) async {
    final result = await context.push('/relatives/add/$treeId');
    if ((result == true ||
            (result is Map<String, dynamic> && result['updated'] == true)) &&
        mounted) {
      await _loadData(treeId);
    }
  }

  /// Чанк C: единый вход generic-добавления с канваса — раньше FAB вёл в
  /// пикер «Кем приходится?», а toolbar-кнопка в прямую форму (два разных
  /// флоу на одно действие путали). Семья → пикер; Круг → сразу форма
  /// (ролей родства в круге нет — как в empty-state). После успешного
  /// добавления канвас перечитывается.
  Future<void> _startAddRelativeFlow(String treeId) async {
    if (_isFriendsTree) {
      await _navigateToAddRelative(treeId);
      return;
    }
    final result = await showRelationPickerAndNavigateAdd(
      context,
      treeId: treeId,
    );
    if ((result == true ||
            (result is Map<String, dynamic> && result['updated'] == true)) &&
        mounted) {
      await _loadData(treeId);
    }
  }

  /// Ship 2026-05-26 (UX audit Screen 4.1): relation-first guided CTA
  /// dispatch. Caller (EmptyTreeGuidedCta) passes RelationType +
  /// optional Gender + optional contextPersonId (self person when
  /// tree уже has caller's card). AddRelativeScreen reads extras
  /// и pre-fills relation dropdown + gender selector.
  Future<void> _navigateToAddRelativeWithHint(
    String treeId, {
    required RelationType relation,
    Gender? gender,
    String? contextPersonId,
  }) async {
    final extra = <String, dynamic>{
      'relationType': relation,
      'quickAddMode': true,
      if (gender != null) 'prefilledGender': gender,
      if (contextPersonId != null) 'contextPersonId': contextPersonId,
    };
    final result = await context.push(
      '/relatives/add/$treeId',
      extra: extra,
    );
    if (!mounted) return;
    if (result == true ||
        (result is Map<String, dynamic> && result['updated'] == true)) {
      await _loadData(treeId);
    }
  }

  /// Ship FE4 (2026-05-26): resolves семя binding for active tree (if
  /// any) using SemyaListController.semyi as lookup (already loaded
  /// app-wide). Reverse-match via Semya.treeId == treeId. Then fetches
  /// SemyaDetails to learn caller's role.
  ///
  /// Returns null когда:
  ///   • Tree not bound к семя (no Semya entry с matching treeId)
  ///   • Capability service unavailable (legacy backend)
  ///   • findSemyaById fails либо returns null (network / 403)
  ///
  /// Caller treats null as «unbound / legacy» — full mutation rights
  /// preserved для personal trees.
  /// Ship FE7 (2026-05-26): fetch caller's hide-filter list для семя.
  /// Best-effort — failures return empty list (action sheet's hide
  /// tile still works, default «Скрыть»; PATCH endpoint will accept
  /// либо surface error). Backend filters tree-routes по the canonical
  /// store list regardless of local state, so frontend can degrade
  /// gracefully.
  Future<List<String>> _fetchHiddenPersonIds(String semyaId) async {
    final service = _familyService;
    if (service is! SemyaCapableFamilyTreeService) return const <String>[];
    final capable = service as SemyaCapableFamilyTreeService;
    try {
      return await capable.listHiddenPersonIds(semyaId: semyaId);
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _refreshHiddenPersonIdsForLoadedSemya({
    required String treeId,
    required SemyaDetails? semyaContext,
  }) async {
    final semyaId = semyaContext?.semya.id;
    if (semyaId == null || semyaId.isEmpty) {
      if (!mounted || _currentTreeId != treeId) return;
      if (_hiddenPersonIds.isNotEmpty) {
        _updateSectionState(() {
          _hiddenPersonIds = const <String>[];
        });
      }
      return;
    }
    final hiddenIds = await _fetchHiddenPersonIds(semyaId);
    if (!mounted ||
        _currentTreeId != treeId ||
        _currentSemyaContext?.semya.id != semyaId) {
      return;
    }
    _updateSectionState(() {
      _hiddenPersonIds = hiddenIds;
    });
  }

  Future<void> _refreshSemyaContext(String treeId) async {
    final refreshed = await _resolveSemyaContextForTree(treeId);
    if (!mounted || _currentTreeId != treeId) return;
    _updateSectionState(() {
      _currentSemyaContext = refreshed;
    });
    await _refreshHiddenPersonIdsForLoadedSemya(
      treeId: treeId,
      semyaContext: refreshed,
    );
  }

  Future<void> _openOrBindSemyaForTree(String treeId) async {
    final existing = _currentSemyaContext;
    if (existing != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SemyaDetailsScreen(semyaId: existing.semya.id),
        ),
      );
      await _refreshSemyaContext(treeId);
      return;
    }

    final service = _familyService;
    if (service is! SemyaManageCapableFamilyTreeService) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Управление семьёй временно недоступно')),
      );
      return;
    }

    final rawName = _currentTreeMeta?.name.trim() ?? '';
    final semyaName = rawName.isNotEmpty ? rawName : 'Моя семья';
    try {
      final created = await (service as SemyaManageCapableFamilyTreeService)
          .createSemya(name: semyaName, treeId: treeId);
      await _refreshSemyaContext(treeId);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SemyaDetailsScreen(semyaId: created.id),
        ),
      );
      await _refreshSemyaContext(treeId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            humanizeError(
              error,
              fallback: 'Не удалось настроить семью для этого дерева',
            ),
          ),
        ),
      );
    }
  }

  Future<SemyaDetails?> _resolveSemyaContextForTree(String treeId) async {
    final service = _familyService;
    if (service is! SemyaCapableFamilyTreeService) return null;
    final capable = service as SemyaCapableFamilyTreeService;
    try {
      // Pull all семья caller belongs to и reverse-match by treeId.
      // SemyaListController caches this list app-wide; calling listMySemya
      // directly keeps tree_view_screen independent от Provider plumbing
      // плюс ensures we have fresh data (any семя created after app boot
      // would still be visible since listMySemya hits backend).
      final mySemyi = await capable.listMySemya();
      Semya? bound;
      for (final entry in mySemyi) {
        if (entry.treeId == treeId) {
          bound = entry;
          break;
        }
      }
      if (bound == null) return null;
      // Found семя — fetch details (includes caller's membership row).
      return await capable.findSemyaById(bound.id);
    } catch (_) {
      // Graceful degradation — на network failure treат tree as unbound
      // (legacy full-access). Backend mutation gates still enforce
      // serverside per ship pattern, поэтому viewer случайно
      // не сломает чужое дерево даже если UI ошибочно показал кнопки.
      return null;
    }
  }

  /// Returns current user's person card in the active tree, либо null
  /// when not present. Used by empty-tree guided CTA to determine
  /// «only self» state (≠ truly empty tree).
  FamilyPerson? _findSelfPerson() {
    final currentUserId = _authService.currentUserId;
    if (currentUserId == null) return null;
    for (final entry in _relativesData) {
      final person = entry['person'];
      if (person is FamilyPerson && person.userId == currentUserId) {
        return person;
      }
    }
    return null;
  }

  Set<String> _buildBranchVisiblePersonIds(String branchRootPersonId) {
    final graphSnapshot = _graphSnapshot;
    final personIds = _relativesData
        .map((entry) => entry['person'])
        .whereType<FamilyPerson>()
        .map((person) => person.id)
        .toSet();
    if (graphSnapshot != null) {
      final branchBlock =
          graphSnapshot.findBranchBlockForPerson(branchRootPersonId);
      if (branchBlock != null) {
        return branchBlock.memberPersonIds.toSet();
      }
    }
    return personIds;
  }

  List<String> _buildBranchChatParticipantIds(String branchRootPersonId) {
    final participantIds = <String>{};
    final currentUserId = _authService.currentUserId;
    if (currentUserId != null && currentUserId.isNotEmpty) {
      participantIds.add(currentUserId);
    }

    final visibleIds = _buildBranchVisiblePersonIds(branchRootPersonId);
    for (final entry in _relativesData) {
      final person = entry['person'];
      if (person is! FamilyPerson || !visibleIds.contains(person.id)) {
        continue;
      }
      final linkedUserId = person.userId?.trim();
      if (linkedUserId != null && linkedUserId.isNotEmpty) {
        participantIds.add(linkedUserId);
      }
    }

    final sortedIds = participantIds.toList();
    sortedIds.sort();
    return sortedIds;
  }

  Future<FamilyTree?> _loadCurrentTreeMeta(String treeId) async {
    try {
      final trees = await _familyService.getUserTrees();
      for (final tree in trees) {
        if (tree.id == treeId) {
          return tree;
        }
      }
    } catch (_) {}
    return _currentTreeMeta?.id == treeId ? _currentTreeMeta : null;
  }

  void _focusBranch(FamilyPerson person) {
    if (!mounted) {
      return;
    }
    _updateSectionState(() {
      _branchRootPersonId = person.id;
      _selectedPersonSheetId = person.id;
    });
  }

  // ── Phase 4: «Кем мы приходимся?» ──────────────────────────────────
  // Walks the unified-graph blood-relation path from the viewer's
  // own card to the selected person and shows a sheet with the
  // Russian relationship label + the chain of intermediate people
  // ("you → mom → her brother → his daughter"). Tap on the action
  // chip in the person sheet — _showTreePersonBloodRelation — wires
  // straight into this.
  void _resetBranchFocus() {
    if (!mounted) {
      return;
    }
    _updateSectionState(() {
      _branchRootPersonId = null;
    });
  }

  FamilyPerson? _findBranchRootPerson() {
    final branchRootPersonId = _branchRootPersonId;
    if (branchRootPersonId == null) {
      return null;
    }

    for (final entry in _relativesData) {
      final person = entry['person'];
      if (person is FamilyPerson && person.id == branchRootPersonId) {
        return person;
      }
    }
    return null;
  }

  Future<void> _openBranchChat(
    String treeId,
    FamilyPerson? branchRootPerson,
  ) async {
    if (branchRootPerson == null) {
      return;
    }

    final participantIds = _buildBranchChatParticipantIds(branchRootPerson.id);
    if (participantIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('В этой ветке пока некому писать в общий чат.'),
        ),
      );
      return;
    }

    final graphBranchBlock =
        _graphSnapshot?.findBranchBlockForPerson(branchRootPerson.id);
    final title = graphBranchBlock?.label ?? 'Ветка ${branchRootPerson.name}';
    try {
      final chatId = await _chatService.createBranchChat(
        treeId: treeId,
        branchRootPersonIds: <String>[branchRootPerson.id],
        title: title,
      );
      if (!mounted) {
        return;
      }
      if (chatId == null || chatId.isEmpty) {
        throw StateError('Не удалось создать чат ветки');
      }

      context.push(
        '/chats/view/$chatId?type=branch&title=${Uri.encodeComponent(title)}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _describeTreeActionError(
              error,
              fallbackMessage: 'Не удалось открыть чат ветки.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _copyPublicTreeLink() async {
    final treeMeta = _currentTreeMeta;
    if (treeMeta == null || !treeMeta.isPublic) {
      return;
    }

    final publicUri = PublicTreeLinkService.buildPublicTreeUri(
      treeMeta.publicRouteId,
      publicAppUrl: BackendRuntimeConfig.current.publicAppUrl,
    );

    await Clipboard.setData(ClipboardData(text: publicUri.toString()));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Публичная ссылка скопирована.')),
    );
  }
}
