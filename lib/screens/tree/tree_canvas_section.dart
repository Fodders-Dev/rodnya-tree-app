part of '../tree_view_screen.dart';

extension _TreeCanvasSection on _TreeViewScreenState {
  void _publishTreeE2EState(String? selectedTreeId) {
    if (!E2EStateBridge.isEnabled) {
      return;
    }

    final people = _treePeople;
    final selectedPerson = _selectedEditPerson;
    final selectedSheetPerson = _selectedPersonSheetPerson;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      E2EStateBridge.publish(
        screen: 'tree',
        state: <String, dynamic>{
          'selectedTreeId': selectedTreeId,
          'currentTreeId': _currentTreeId,
          'treeName': _currentTreeMeta?.name ?? widget.routeTreeName,
          'isLoading': _isLoading,
          'isEditMode': _isEditMode,
          'branchRootPersonId': _branchRootPersonId,
          'selectedPersonSheetId': _selectedPersonSheetId,
          'selectedEditPersonId': _selectedEditPersonId,
          'selectedPersonSheet': selectedSheetPerson == null
              ? null
              : <String, dynamic>{
                  'id': selectedSheetPerson.id,
                  'name': selectedSheetPerson.name,
                  'photoCount': selectedSheetPerson.photoGallery.length,
                  'hasPrimaryPhoto':
                      selectedSheetPerson.primaryPhotoUrl != null,
                },
          'selectedEditPerson': selectedPerson == null
              ? null
              : <String, dynamic>{
                  'id': selectedPerson.id,
                  'name': selectedPerson.name,
                  'photoCount': selectedPerson.photoGallery.length,
                  'hasPrimaryPhoto': selectedPerson.primaryPhotoUrl != null,
                },
          'people': people
              .map(
                (person) => <String, dynamic>{
                  'id': person.id,
                  'name': person.name,
                  'photoCount': person.photoGallery.length,
                  'hasPrimaryPhoto': person.primaryPhotoUrl != null,
                },
              )
              .toList(),
        },
      );
    });
  }

  Future<void> _handleNodePositionsChanged(
    Map<String, Offset> updatedPositions,
  ) async {
    final treeId = _currentTreeId;
    if (treeId == null) {
      return;
    }

    _updateSectionState(() {
      _manualNodePositions = updatedPositions;
    });
    await _localStorageService.saveTreeNodePositions(treeId, updatedPositions);
  }

  Future<void> _resetManualTreeLayout(String treeId) async {
    await _localStorageService.clearTreeNodePositions(treeId);
    if (!mounted) {
      return;
    }
    _updateSectionState(() {
      _manualNodePositions = <String, Offset>{};
    });
    await _loadData(treeId);
  }

  Widget _buildTreeCanvas() {
    final theme = Theme.of(context);
    final selectedPerson = _selectedPersonSheetPerson;
    final canvasAccent =
        _isFriendsTree ? const Color(0xFF0F9D8A) : theme.colorScheme.primary;
    // Full-bleed canvas: drop the GlassPanel wrapper that used to box the
    // tree inside a 30-radius card. The tree now paints directly on the
    // app backdrop (warm cream + radial highlights from `AppBackdrop`),
    // matching the reference design where the family graph IS the
    // background, not a contained widget. Toolbar / sidebar / sheet
    // float over this canvas.
    return Stack(
      fit: StackFit.expand,
      children: [
        // Soft accent halo behind the tree — pulls focus to the canvas
        // center without putting a hard frame around it.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.05),
                radius: 0.95,
                colors: [
                  canvasAccent.withValues(
                    alpha: _isFriendsTree ? 0.07 : 0.05,
                  ),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.75],
              ),
            ),
          ),
        ),
        Stack(
          fit: StackFit.expand,
          children: [
            InteractiveFamilyTree(
              peopleData: _relativesData,
              relations: _relationsData,
              graphSnapshot: _graphSnapshot,
              currentUserId: _authService.currentUserId,
              branchRootPersonId: _branchRootPersonId,
              selectedPersonId: _selectedPersonSheetId,
              onBranchFocusCleared: _resetBranchFocus,
              onPersonTap: (person) {
                debugPrint('Нажатие на узел: ${person.name} (${person.id})');
                _selectTreePerson(person);
                // In edit mode the same single tap also routes through
                // the inline edit selection so the bottom sheet's edit
                // action row knows which node to operate on.
                if (_isEditMode) {
                  _updateSectionState(() {
                    _selectedEditPersonId = person.id;
                    _personSheetExpanded = true;
                  });
                } else {
                  // Ship Q4 (2026-05-26): UX audit 2026-05-25 Critical #4 —
                  // tap on tree person теперь surface'ит modal action sheet
                  // (Профиль / Редактировать / Добавить / Связать / Удалить).
                  // Inline person sheet остаётся active для contextual
                  // selection в edit mode и для drag/zoom/PiP interactions.
                  _showTreePersonActionSheet(person);
                }
              },
              onPersonDoubleTap: (person) {
                // Double-click on a card = drill into full profile.
                // Single tap still opens the bottom sheet peek; double
                // is the shortcut for users who want the full page.
                _openPersonDetails(person);
              },
              onShowRelationPath: (person) =>
                  _openPersonDetails(person, action: 'path'),
              onShowOtherParents: (person) =>
                  _openPersonDetails(person, action: 'parents'),
              onFixPersonRelations: (person) =>
                  _openPersonDetails(person, action: 'relations'),
              onBranchFocusRequested: _focusBranch,
              isEditMode: _isEditMode,
              selectedEditPersonId: _selectedEditPersonId,
              onEditPersonSelected: (person) {
                _updateSectionState(() {
                  _selectedEditPersonId = person.id;
                });
              },
              onOpenPersonHistory: _showPersonHistorySheet,
              manualNodePositions: _manualNodePositions,
              onNodePositionsChanged: (positions) {
                _handleNodePositionsChanged(positions);
              },
              showGenerationGuides: !_isFriendsTree,
              graphLabel: _isFriendsTree ? 'дружеского графа' : 'дерева',
              hasManualLayout: _manualNodePositions.isNotEmpty,
              onResetLayout:
                  _manualNodePositions.isNotEmpty && _currentTreeId != null
                      ? () => _resetManualTreeLayout(_currentTreeId!)
                      : null,
              onAddRelativeTapWithType:
                  _isViewerOnly ? (_, __) {} : _handleAddRelativeFromTree,
              currentUserIsInTree: _currentUserIsInTree,
              onAddSelfTapWithType:
                  _isViewerOnly ? (_, __) {} : _handleAddSelfFromTree,
              // Edge-first connector — long-press a card, drag to
              // another, pick a relation type from the inline
              // 4-icon picker. The handler talks to family service
              // directly and reloads on success; no form involved.
              onConnectExistingPersons:
                  _isViewerOnly ? null : _handleConnectExistingFromTree,
              // Blank-card creator — drop a person on the canvas
              // with no relation. The user fills name + gender in
              // a small dialog, we create them via the service,
              // and they then connect via the connector above.
              onAddBlankPerson:
                  _isViewerOnly ? null : _handleAddBlankPersonFromTree,
              // Auto-recenter trigger: after addRelative succeeds
              // we stamp the new person id here, the tree picks
              // it up via didUpdateWidget and snaps to center.
              recenterOnPersonId: _recenterOnPersonIdAfterReload,
              // Phase 1.2 voltage indicator: counts come from the
              // background fetch in _loadData; tap callback opens
              // the suggestions sheet.
              identitySuggestionCounts: _identitySuggestionCounts,
              onShowIdentitySuggestions:
                  _handleShowIdentitySuggestionsForPerson,
              // Phase 1.3 conflict surfacing: same model as 💡 —
              // counts populated in the background, tap opens
              // the resolve sheet keyed off this person.
              identityConflictCounts: _identityConflictCounts,
              onShowIdentityConflicts: _handleShowIdentityConflictsForPerson,
              // UX-T1 FR3: на телефоне резерв отражает РЕАЛЬНУЮ высоту
              // хрома над канвасом. По умолчанию контекст-колонка свёрнута
              // (_compactChromeCollapsed=true) → над канвасом только
              // плавающий тулбар + handle, а не устаревшие 290 (они
              // зарезервированы под раскрытую колонку). Это и есть
              // canvas-first: дерево фитится в >=85% высоты. При раскрытии
              // колонки резерв снова ~290. Десктоп (>=1180) — 96, не трогаем.
              //
              // Плотность, чанк 16 (05.09.2026): тулбар-карточка (чип
              // ветки + бейдж семьи) и handle стали компактнее (замер
              // widget-тестом: 8 отступ + 36 тулбар + 6 отступ + 24 handle
              // = 74dp факт) — держать резерв 120 значило бы отдавать
              // канвасу ту же площадь, что и до ужатия хрома, сводя чанк
              // на нет. 90 = факт + запас ~16dp под масштаб шрифта/другие
              // плотности экрана.
              viewportReservedTop: MediaQuery.of(context).size.width >= 1180
                  ? 96
                  : (_compactChromeCollapsed ? 90 : 290),
              viewportReservedBottom:
                  MediaQuery.of(context).size.width >= 1180 ? 28 : 120,
              viewportReservedLeft:
                  MediaQuery.of(context).size.width >= 1180 ? 336 : 0,
              viewportReservedRight:
                  MediaQuery.of(context).size.width >= 1180 ? 64 : 0,
              // Edit actions live in the bottom sheet now — suppress
              // the floating inline panel so we don't have two action
              // surfaces over the same node.
              showInlineEditPanel: false,
              // Multi-select for bulk actions (Step 2). When the
              // host opens selection mode through the toolbar, the
              // canvas owns tap-to-toggle and shows accent rings;
              // a separate bottom toolbar (below) drives the
              // bulk-action choice.
              selectionMode: _isSelectionMode,
              selectedPersonIds: _selectedPersonIds,
              onPersonSelectionToggle: (person) {
                if (!_isSelectionMode) return;
                _updateSectionState(() {
                  if (_selectedPersonIds.contains(person.id)) {
                    _selectedPersonIds.remove(person.id);
                  } else {
                    _selectedPersonIds.add(person.id);
                  }
                });
              },
              viewMode:
                  _extendedNetworkController?.mode ?? ExtendedNetworkMode.mine,
              networkSlice: _extendedNetworkController?.slice,
              // Phase 4 chunk 4a: foreign node tap intercept.
              // Host owns sheet — `_handleForeignNodeTap` opens
              // ForeignNodeSheet через showModalBottomSheet.
              onForeignNodeTap: _extendedNetworkController?.isCapable == true
                  ? _handleForeignNodeTap
                  : null,
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _isSelectionMode
                    ? _buildSelectionToolbar(
                        key: const ValueKey<String>('selection-toolbar'),
                        accent: canvasAccent,
                      )
                    : selectedPerson == null
                        ? const SizedBox.shrink()
                        : _buildTreePersonBottomSheet(
                            key: ValueKey<String>(
                              'tree-person-sheet-${selectedPerson.id}',
                            ),
                            person: selectedPerson,
                            accent: canvasAccent,
                          ),
              ),
            ),
            IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Align(
                  alignment: Alignment.topRight,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: !_isEditMode
                        ? const SizedBox.shrink()
                        : Container(
                            key: const ValueKey<String>(
                              'tree-manual-layout-hint',
                            ),
                            constraints: const BoxConstraints(maxWidth: 280),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface.withValues(
                                alpha: 0.96,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: canvasAccent.withValues(alpha: 0.18),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.shadow.withValues(
                                    alpha: 0.08,
                                  ),
                                  blurRadius: 18,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.open_with_rounded,
                                  size: 18,
                                  color: canvasAccent,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Режим перемещения: зажмите карточку и тяните по своему поколению.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurfaceVariant,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
