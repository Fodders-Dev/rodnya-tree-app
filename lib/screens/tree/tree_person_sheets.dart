part of '../tree_view_screen.dart';

extension _TreePersonSheets on _TreeViewScreenState {
  void _selectTreePerson(FamilyPerson person) {
    _updateSectionState(() {
      if (_selectedPersonSheetId == person.id) {
        // Same node tapped twice — close sheet entirely.
        _selectedPersonSheetId = null;
        _personSheetExpanded = false;
      } else {
        _selectedPersonSheetId = person.id;
        _personSheetExpanded = false; // Always start collapsed.
      }
    });
  }

  void _clearSelectedTreePerson() {
    _updateSectionState(() {
      _selectedPersonSheetId = null;
      _personSheetExpanded = false;
    });
  }

  void _togglePersonSheetExpansion() {
    _updateSectionState(() {
      _personSheetExpanded = !_personSheetExpanded;
    });
  }

  void _showTreePersonActionSheet(FamilyPerson person) {
    final treeId = _currentTreeId;
    if (treeId == null) return;
    // Ship FE7 (2026-05-26): hide-toggle tile gating. Available when:
    //   • tree bound к семя (semyaContext resolved)
    //   • caller is member (any role — viewer can hide too)
    //   • person ≠ caller's own person (don't let user hide self —
    //     would lock them out of their own tree row visibility)
    final semyaContext = _currentSemyaContext;
    final viewerPersonId = _graphSnapshot?.viewerPersonId;
    final canToggleHide = semyaContext != null && person.id != viewerPersonId;
    final isCurrentlyHidden = _hiddenPersonIds.contains(person.id);
    // B3 (FR3): «Добавить второго родителя» — контекстный пункт, видимый
    // только когда у узла РОВНО один родитель. Ведёт в add-флоу
    // (relation: parent, contextPersonId — этот ребёнок) с предвыбранным
    // недостающим полом: пользователь ЯВНО привязывает второго родителя
    // ребром parent→child. Это безопасный путь — после редизайна B3 бэк
    // больше НЕ авто-связывает супруга на браке/backfill (корраптило
    // сводные семьи), так что ручное добавление — единственный путь для
    // повторных браков и починки старых деревьев.
    final parentIds = <String>{};
    for (final relation in _relationsData) {
      if (relation.person2Id == person.id &&
          relation.relation1to2 == RelationType.parent) {
        parentIds.add(relation.person1Id);
      } else if (relation.person1Id == person.id &&
          relation.relation2to1 == RelationType.parent) {
        parentIds.add(relation.person2Id);
      }
    }
    VoidCallback? onAddSecondParent;
    if (!_isViewerOnly && parentIds.length == 1) {
      FamilyPerson? existingParent;
      for (final candidate in _treePeople) {
        if (candidate.id == parentIds.first) {
          existingParent = candidate;
          break;
        }
      }
      final missingGender = existingParent?.gender == Gender.female
          ? Gender.male
          : existingParent?.gender == Gender.male
              ? Gender.female
              : null;
      onAddSecondParent = () => _navigateToAddRelativeWithHint(
            treeId,
            relation: RelationType.parent,
            gender: missingGender,
            contextPersonId: person.id,
          );
    }
    showTreePersonActionSheet(
      context,
      person: person,
      onAddSecondParent: onAddSecondParent,
      // Ship FE4 (2026-05-26): viewer-role gating — only «Открыть профиль»
      // tile surfaces, editorial actions hidden. Backend independently
      // rejects mutations с 403; UI gate just keeps виду cleaner.
      viewerMode: _isViewerOnly,
      isHidden: isCurrentlyHidden,
      onToggleHide: canToggleHide
          ? () => _toggleHidePerson(person, isCurrentlyHidden)
          : null,
      onOpenProfile: () => _openPersonDetails(person),
      // UX-аудит P1: «Спросить историю» с канваса в один тап — экран
      // деталей сам поднимет шит вопросов (initialAction: 'story').
      onAskStory: () => _openPersonDetails(person, action: 'story'),
      onEdit: () {
        context
            .push<dynamic>(
          '/relatives/edit/$treeId/${person.id}',
          extra: person,
        )
            .then((_) {
          if (!mounted) return;
          _loadData(treeId);
        });
      },
      onAddRelative: () {
        // Audit Screen 4.2 (2026-05-28): explicit «Кем приходится?»
        // step ПЕРЕД name form. Picker → push с predefinedRelation
        // extra → AddRelativeScreen reads already-supported param.
        showRelationPickerAndNavigateAdd(
          context,
          treeId: treeId,
          contextPersonId: person.id,
          anchorName: person.name,
        ).then((result) {
          if (!mounted) return;
          if (result == true ||
              (result is Map<String, dynamic> && result['updated'] == true)) {
            _loadData(treeId);
          }
        });
      },
      onConnect: () => _openPersonDetails(person, action: 'relations'),
      onDelete: () => _showDeletePersonConfirmation(person),
    );
  }

  /// Ship FE7 (2026-05-26): toggle person hide state. Hide = add к
  /// caller's hideFilter; unhide = remove. Backend filters tree-routes
  /// per the canonical list, so after toggle we just re-fetch tree (it
  /// auto-applies filter). Snackbar feedback. Errors surface inline.
  Future<void> _toggleHidePerson(
    FamilyPerson person,
    bool isCurrentlyHidden,
  ) async {
    final semyaContext = _currentSemyaContext;
    final treeId = _currentTreeId;
    if (semyaContext == null || treeId == null) return;
    final service = _familyService;
    if (service is! SemyaCapableFamilyTreeService) return;
    final capable = service as SemyaCapableFamilyTreeService;
    try {
      final updated = await capable.updateHideFilter(
        semyaId: semyaContext.semya.id,
        addPersonIds: isCurrentlyHidden ? const <String>[] : [person.id],
        removePersonIds: isCurrentlyHidden ? [person.id] : const <String>[],
      );
      if (!mounted) return;
      _updateSectionState(() {
        _hiddenPersonIds = updated;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCurrentlyHidden
                ? '${person.name} снова отображается'
                : '${person.name} скрыт${person.gender == Gender.female ? 'а' : ''} от вас',
          ),
        ),
      );
      // Re-fetch tree — backend now applies filter с updated list.
      await _loadData(treeId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              humanizeError(error, fallback: 'Не удалось изменить видимость.')),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  // Ship Q4: destructive delete с consequence copy (audit recommendation:
  // «Удалить карточку из дерева? Связи с родственниками будут удалены»).
  //
  // Ship 2026-05-26 (Post delete polish): refactored inline dialog к
  // shared SafeDeleteConfirmationDialog widget — same pattern reused
  // для post delete (audit Screen 3.5).
  //
  // Ship Q4a frontend (2026-05-28, Ship 31): backend now soft-deletes
  // через deletedPersons collection с 30-day retention + Settings →
  // Корзина restore. Copy обновлён — «нельзя отменить» был ложью.
  Future<void> _showDeletePersonConfirmation(FamilyPerson person) async {
    final treeId = _currentTreeId;
    if (treeId == null) return;
    final confirmed = await showSafeDeleteConfirmation(
      context,
      title: 'Удалить ${person.name}?',
      body: 'Карточка и связи с родственниками переедут в корзину. '
          'Восстановить можно в течение 30 дней в Настройки → Корзина.',
    );
    if (!confirmed || !mounted) return;
    try {
      await _familyService.deleteRelative(treeId, person.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${person.name} удалён${person.gender == Gender.female ? 'а' : ''} из дерева'),
        ),
      );
      _clearSelectedTreePerson();
      await _loadData(treeId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(humanizeError(error, fallback: 'Не удалось удалить.')),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  Future<void> _openPersonDetails(
    FamilyPerson person, {
    String? action,
  }) async {
    // P0: канвас знает дерево человека — прокидываем его в карточку.
    final route = relativeDetailsRoute(
      person.id,
      treeId: person.treeId.isNotEmpty ? person.treeId : _currentTreeId,
      action: action,
    );
    // Awaiting the push lets us refresh the tree once the user
    // navigates back. The detail screen edits person fields /
    // photos in place — without this refresh the tree keeps
    // showing the stale avatar / labels until the user hits
    // hard-reload. With this, swipe-back / tap-back transparently
    // pulls the updated state and Phase 1.1 propagation effects
    // (e.g., photos that fanned out to linked records on other
    // trees) come along for the ride.
    await context.push<dynamic>(route);
    if (!mounted) return;
    final treeId = _currentTreeId;
    if (treeId == null) return;
    await _loadData(treeId);
  }

  // === НОВЫЙ МЕТОД-КОЛЛБЭК для InteractiveFamilyTree ===
  Future<void> _showTreeHistorySheet({FamilyPerson? person}) async {
    final treeId = _currentTreeId;
    if (treeId == null) {
      return;
    }

    final historyFuture = _familyService.getTreeHistory(
      treeId: treeId,
      personId: person?.id,
    );
    final sheetTitle = person == null ? 'История дерева' : 'История изменений';
    final sheetSubtitle = person?.name ??
        _currentTreeMeta?.name ??
        widget.routeTreeName ??
        'Текущее дерево';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return TreeHistorySheet(
          historyFuture: historyFuture,
          title: sheetTitle,
          subtitle: sheetSubtitle,
          currentUserId: _authService.currentUserId,
          emptyMessage: person == null
              ? 'В журнале дерева пока нет записей.'
              : 'Для этой карточки пока нет записей в журнале.',
          errorBuilder: (error) => _describeTreeActionError(
            error,
            fallbackMessage: 'Не удалось загрузить историю.',
          ),
          onOpenPerson: (personId) async {
            Navigator.of(sheetContext).pop();
            if (!mounted) return;
            await context.push<dynamic>(
              relativeDetailsRoute(personId, treeId: _currentTreeId),
            );
            if (!mounted) return;
            // Refresh tree on return so edits made on the detail
            // screen (photo, name parts, dates) show up immediately
            // instead of requiring a hard-reload.
            final treeId = _currentTreeId;
            if (treeId != null) {
              await _loadData(treeId);
            }
          },
        );
      },
    );
  }

  Future<void> _showPersonHistorySheet(FamilyPerson person) {
    return _showTreeHistorySheet(person: person);
  }

  /// A-CTA: пользователь закрыл блокирующий гид — на сессию. Канвас с
  /// FAB остаётся доступен; гид не вернётся до перезапуска.
  Future<void> _showTreePersonBloodRelation(FamilyPerson person) async {
    final viewerPersonId = _graphSnapshot?.viewerPersonId;
    if (viewerPersonId == null) {
      _showSnack(
        'Чтобы найти родство, добавьте свою карточку в дерево.',
      );
      return;
    }
    if (viewerPersonId == person.id) {
      _showSnack('Это вы.');
      return;
    }
    final viewerPerson = _treePeople.firstWhere(
      (p) => p.id == viewerPersonId,
      orElse: () => person, // unreachable — viewerPersonId is in tree
    );
    final viewerIdentityId = _personIdentityIdFor(viewerPerson);
    final targetIdentityId = _personIdentityIdFor(person);
    if (viewerIdentityId == null || targetIdentityId == null) {
      _showSnack(
        'Карточки ещё не синхронизированы с графом — попробуйте через минуту.',
      );
      return;
    }

    final service = _familyService;
    if (service is! BloodRelationCapableFamilyTreeService) {
      _showSnack('Эта функция пока недоступна на бэкенде.');
      return;
    }
    final capable = service as BloodRelationCapableFamilyTreeService;

    BloodRelation? relation;
    try {
      relation = await capable.findBloodRelation(
        fromGraphPersonId: viewerIdentityId,
        toGraphPersonId: targetIdentityId,
      );
    } catch (error) {
      if (!mounted) return;
      _showSnack(humanizeError(error, fallback: 'Не удалось найти родство.'));
      return;
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _BloodRelationSheet(
        target: person,
        relation: relation!,
      ),
    );
  }

  String? _personIdentityIdFor(FamilyPerson person) {
    final identityId = person.identityId;
    if (identityId != null && identityId.trim().isNotEmpty) {
      return identityId.trim();
    }
    return null;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _handleForeignNodeTap(FamilyPerson person) async {
    final controller = _extendedNetworkController;
    if (controller == null) return;
    final slice = controller.slice;
    if (slice == null) return;
    final bloodService = _familyService;
    if (bloodService is! BloodRelationCapableFamilyTreeService) return;
    final blood = bloodService as BloodRelationCapableFamilyTreeService;
    await showForeignNodeSheet(
      context,
      person: person,
      slice: slice,
      bloodRelationService: blood,
      onOpenCard: () {
        if (!mounted) return;
        // P0: foreign-узел живёт в чужом дереве — person.treeId указывает
        // именно его; read-доступ гейтится бэком (Phase 3.2).
        context.push(
          relativeDetailsRoute(
            person.id,
            treeId: person.treeId.isNotEmpty ? person.treeId : null,
          ),
        );
      },
      onWriteToOwner: (ownerUserId) async {
        if (!mounted) return;
        try {
          final chatId = await _chatService.getOrCreateChat(ownerUserId);
          if (chatId == null || chatId.isEmpty) {
            throw StateError('Не удалось открыть чат');
          }
          if (!mounted) return;
          // Найти display name из slice ownerMap для title.
          final ownerInfo = slice.getOwnerInfo(person.identityId ?? person.id);
          final title = ownerInfo?.displayName?.trim().isNotEmpty == true
              ? ownerInfo!.displayName!
              : 'Чат';
          context.push(
            '/chats/view/$chatId?type=direct&title=${Uri.encodeComponent(title)}&userId=$ownerUserId',
          );
        } catch (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _describeTreeActionError(
                  error,
                  fallbackMessage: 'Не удалось открыть чат.',
                ),
              ),
            ),
          );
        }
      },
    );
  }

  // ── Phase 4 chunk 4b: search sheet handler ──────────────────────

  Widget _buildTreePersonBottomSheet({
    Key? key,
    required FamilyPerson person,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final avatarImage = buildAvatarImageProvider(person.primaryPhotoUrl);

    // Reference style sheet: collapsed peek bar (avatar + Lora fname + small
    // meta + chevron) that expands on tap to reveal full info + action row.
    final birthYear = person.birthDate?.year;
    final deathYear = person.deathDate?.year;
    final age = (birthYear != null && birthYear > 0)
        ? ((deathYear != null && deathYear > 0
                ? deathYear
                : DateTime.now().year) -
            birthYear)
        : null;
    final lifeRange = birthYear != null && birthYear > 0
        ? (deathYear != null && deathYear > 0
            ? '$birthYear–$deathYear'
            : '$birthYear · ${age ?? '?'} лет')
        : null;
    final place = (person.birthPlace ?? '').trim();
    final hasWarnings =
        _graphSnapshot?.warningsForPerson(person.id).isNotEmpty == true;

    final nameParts = person.displayName.trim().split(RegExp(r'\s+'));
    final fname = nameParts.isNotEmpty ? nameParts.first : person.displayName;
    final lname = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : null;

    // Peek row — always visible. Tapping it toggles expansion. Drag handle
    // sits centered above so the surface reads as a sheet, not a card.
    final peekRow = Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: accent.withValues(alpha: 0.14),
            backgroundImage: avatarImage,
            child: avatarImage == null
                ? Text(
                    person.initials,
                    style: AppTheme.sans(
                      color: accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: fname,
                        style: AppTheme.serif(
                          color: tokens.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (lname != null)
                        TextSpan(
                          text: ' $lname',
                          style: AppTheme.sans(
                            color: tokens.inkSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (lifeRange != null) lifeRange,
                    if (place.isNotEmpty) place,
                    if (hasWarnings && lifeRange == null && place.isEmpty)
                      'Нужна проверка',
                  ].whereType<String>().take(2).join(' · ').isEmpty
                      ? (_isFriendsTree ? 'Карточка круга' : 'Карточка дерева')
                      : [
                          if (lifeRange != null) lifeRange,
                          if (place.isNotEmpty) place,
                        ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.sans(
                    color: tokens.inkMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          AnimatedRotation(
            turns: _personSheetExpanded ? 0.5 : 0.0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: Icon(
              Icons.keyboard_arrow_up_rounded,
              size: 20,
              color: tokens.inkSecondary,
            ),
          ),
          IconButton(
            tooltip: 'Закрыть карточку',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, color: tokens.inkSecondary),
            onPressed: _clearSelectedTreePerson,
          ),
        ],
      ),
    );

    // Expanded body — shown when sheet is expanded. Action row + sundries.
    final expandedBody = AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: !_personSheetExpanded
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 0.6,
                    color: tokens.surfaceLine.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 12),
                  if (age != null) ...[
                    Text(
                      person.isAlive == false
                          ? 'Прожил${person.gender == Gender.female ? 'а' : ''} $age ${_yearsLabel(age)}'
                          : '$age ${_yearsLabel(age)}',
                      style: AppTheme.sans(
                        color: tokens.inkSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Edit-mode shows a different action set focused on
                  // tree-editor flows: add parent / spouse / child / sibling
                  // shortcuts, plus profile + history. View-mode keeps the
                  // social actions (Профиль / Написать / История / Ветка /
                  // Связь). The split keeps each context surface clean.
                  if (_isEditMode) ...[
                    _buildEditModeActionBlock(
                      person: person,
                      hasWarnings: hasWarnings,
                    ),
                  ] else ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildTreeSheetAction(
                            icon: Icons.open_in_new,
                            label: 'Профиль',
                            onPressed: () => _openPersonDetails(person),
                            emphasized: true,
                          ),
                          if (person.userId != null &&
                              person.userId!.isNotEmpty &&
                              person.userId != _authService.currentUserId &&
                              person.isAlive &&
                              person.deathDate == null) ...[
                            const SizedBox(width: 8),
                            _buildTreeSheetAction(
                              icon: Icons.chat_bubble_outline_rounded,
                              label: 'Написать',
                              onPressed: () =>
                                  context.push('/chat/${person.userId}'),
                            ),
                          ],
                          const SizedBox(width: 8),
                          _buildTreeSheetAction(
                            icon: Icons.history_outlined,
                            label: 'История',
                            onPressed: () => _showPersonHistorySheet(person),
                          ),
                          const SizedBox(width: 8),
                          _buildTreeSheetAction(
                            icon: Icons.alt_route_outlined,
                            label: _isFriendsTree ? 'Круг' : 'Ветка',
                            onPressed: () => _focusBranch(person),
                          ),
                          if (!_isViewerOnly) ...[
                            const SizedBox(width: 8),
                            _buildTreeSheetAction(
                              icon: Icons.person_add_alt_1_outlined,
                              label: 'Связь',
                              onPressed: () =>
                                  _showTreePersonRelationSheet(person),
                            ),
                          ],
                          const SizedBox(width: 8),
                          // Phase 4: «Кем мы приходимся?» — BFS over the
                          // unified-graph blood-relation edges. Hidden
                          // when the viewer is selected (it's "you") or
                          // the viewer card isn't in the tree.
                          if (person.id != _graphSnapshot?.viewerPersonId &&
                              _graphSnapshot?.viewerPersonId != null)
                            _buildTreeSheetAction(
                              icon: Icons.account_tree_rounded,
                              label: 'Родство',
                              onPressed: () =>
                                  _showTreePersonBloodRelation(person),
                            ),
                          if (hasWarnings) ...[
                            const SizedBox(width: 8),
                            _buildTreeSheetAction(
                              icon: Icons.report_problem_outlined,
                              label: 'Проверить',
                              onPressed: () => _openPersonDetails(person,
                                  action: 'relations'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );

    // Drag handle pill — minimal indicator that the sheet is interactive.
    final dragHandle = Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: tokens.inkMuted.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );

    return Align(
      key: key,
      alignment: Alignment.bottomCenter,
      child: Semantics(
        label: 'tree-person-sheet',
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: GlassPanel(
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(tokens.radiusLg),
            color: tokens.surfaceStrong.withValues(alpha: 0.94),
            borderColor: accent.withValues(alpha: 0.20),
            boxShadow: tokens.panelShadow(theme.brightness, floating: true),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tap-to-toggle header (handle + peek row).
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(tokens.radiusLg),
                    bottom: Radius.circular(
                        _personSheetExpanded ? 0 : tokens.radiusLg),
                  ),
                  child: InkWell(
                    onTap: _togglePersonSheetExpansion,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(tokens.radiusLg),
                      bottom: Radius.circular(
                          _personSheetExpanded ? 0 : tokens.radiusLg),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        dragHandle,
                        peekRow,
                      ],
                    ),
                  ),
                ),
                expandedBody,
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _yearsLabel(int years) {
    final mod10 = years % 10;
    final mod100 = years % 100;
    if (mod10 == 1 && mod100 != 11) return 'год';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'года';
    }
    return 'лет';
  }

  /// Edit-mode action block: when the user has tapped "Расставить" in the
  /// toolbar, the bottom sheet replaces the social action row with this
  /// edit-focused view. The four primary relation-add buttons sit on top,
  /// then a row of secondary actions (profile / photos / history / fix).
  /// Replaces the floating inline edit panel that used to live next to
  /// each card and consumed canvas real-estate.
  Widget _buildEditModeActionBlock({
    required FamilyPerson person,
    required bool hasWarnings,
  }) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final hasGallery = person.photoGallery.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Добавить связь',
          style: AppTheme.sans(
            color: tokens.inkSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildTreeSheetAction(
                icon: Icons.north_outlined,
                label: 'Родитель',
                emphasized: true,
                onPressed: () =>
                    _handleAddRelativeFromTree(person, RelationType.parent),
              ),
              const SizedBox(width: 8),
              _buildTreeSheetAction(
                icon: Icons.favorite_border,
                label: 'Супруг',
                onPressed: () =>
                    _handleAddRelativeFromTree(person, RelationType.spouse),
              ),
              const SizedBox(width: 8),
              _buildTreeSheetAction(
                icon: Icons.south_outlined,
                label: 'Ребёнок',
                onPressed: () =>
                    _handleAddRelativeFromTree(person, RelationType.child),
              ),
              const SizedBox(width: 8),
              _buildTreeSheetAction(
                icon: Icons.people_outline,
                label: 'Сиблинг',
                onPressed: () =>
                    _handleAddRelativeFromTree(person, RelationType.sibling),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Карточка',
          style: AppTheme.sans(
            color: tokens.inkSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildTreeSheetAction(
                icon: Icons.open_in_new,
                label: 'Открыть',
                onPressed: () => _openPersonDetails(person),
              ),
              const SizedBox(width: 8),
              _buildTreeSheetAction(
                icon: Icons.photo_library_outlined,
                label: hasGallery
                    ? 'Фото (${person.photoGallery.length})'
                    : 'Фото',
                onPressed: hasGallery ? () => _openPersonDetails(person) : null,
              ),
              const SizedBox(width: 8),
              _buildTreeSheetAction(
                icon: Icons.history_outlined,
                label: 'История',
                onPressed: () => _showPersonHistorySheet(person),
              ),
              if (hasWarnings) ...[
                const SizedBox(width: 8),
                _buildTreeSheetAction(
                  icon: Icons.report_problem_outlined,
                  label: 'Починить',
                  onPressed: () =>
                      _openPersonDetails(person, action: 'relations'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTreeSheetAction({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool emphasized = false,
  }) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final isEnabled = onPressed != null;
    final background = emphasized
        ? tokens.accent
        : tokens.surface.withValues(alpha: isEnabled ? 0.95 : 0.5);
    final foreground = emphasized
        ? tokens.accentInk
        : (isEnabled
            ? tokens.accentStrong
            : tokens.accentStrong.withValues(alpha: 0.5));

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minWidth: 86),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 7),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showTreePersonRelationSheet(FamilyPerson person) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Добавить связь',
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  person.displayName,
                  style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                        color:
                            Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                _buildRelationSheetTile(
                  sheetContext: sheetContext,
                  person: person,
                  icon: Icons.arrow_upward,
                  label: 'Родителя',
                  type: RelationType.parent,
                ),
                _buildRelationSheetTile(
                  sheetContext: sheetContext,
                  person: person,
                  icon: Icons.favorite_border,
                  label: 'Супруга или партнёра',
                  type: RelationType.spouse,
                ),
                _buildRelationSheetTile(
                  sheetContext: sheetContext,
                  person: person,
                  icon: Icons.arrow_downward,
                  label: 'Ребёнка',
                  type: RelationType.child,
                ),
                _buildRelationSheetTile(
                  sheetContext: sheetContext,
                  person: person,
                  icon: Icons.people_outline,
                  label: 'Брата или сестру',
                  type: RelationType.sibling,
                ),
                if (!_currentUserIsInTree)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_add_alt_1),
                    title: const Text('Добавить себя рядом с этим человеком'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _handleAddSelfFromTree(person, RelationType.sibling);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRelationSheetTile({
    required BuildContext sheetContext,
    required FamilyPerson person,
    required IconData icon,
    required String label,
    required RelationType type,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      onTap: () {
        Navigator.of(sheetContext).pop();
        _handleAddRelativeFromTree(person, type);
      },
    );
  }
}
