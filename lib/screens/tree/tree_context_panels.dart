part of '../tree_view_screen.dart';

extension _TreeContextPanels on _TreeViewScreenState {
  Widget _wrapWithExtendedNetworkLayout(BuildContext context, Widget body) {
    final controller = _extendedNetworkController;
    if (controller == null) return body;
    return ChangeNotifierProvider<ExtendedNetworkController>.value(
      value: controller,
      child: Consumer<ExtendedNetworkController>(
        builder: (context, ctrl, _) {
          final isWide = MediaQuery.of(context).size.width >= 1500;
          final showSidebar = isWide &&
              ctrl.isCapable &&
              ctrl.mode == ExtendedNetworkMode.extended;
          final overlayedBody = _maybeOverlayExtendedEmptyState(ctrl, body);
          if (!showSidebar) return overlayedBody;
          return Row(
            children: [
              Expanded(child: overlayedBody),
              const ExtendedNetworkFilterSidebar(
                branchOptions: <BranchFilterOption>[],
              ),
            ],
          );
        },
      ),
    );
  }

  /// Phase 6 chunk 4c (PHASE-6-PROPOSAL.md §2.7): when extended mode
  /// is on + slice loaded + no foreign nodes (`ownerMap.isEmpty`) —
  /// show a future-positive empty-state banner before the tree canvas.
  /// It participates in layout so its CTAs never cover people or controls.
  /// Сессионная память крестика: карточка-заглушка висит ПОВЕРХ канваса
  /// и без дисмисса запирала просмотр дерева (жалоба владельца).
  /// Вернётся после перезапуска приложения — как onboarding-баннер.
  Widget _maybeOverlayExtendedEmptyState(
    ExtendedNetworkController ctrl,
    Widget body,
  ) {
    final slice = ctrl.slice;
    final showBanner = ctrl.isCapable &&
        ctrl.mode == ExtendedNetworkMode.extended &&
        slice != null &&
        slice.ownerMap.isEmpty &&
        !_TreeViewScreenState._extendedEmptyDismissedThisSession;
    if (!showBanner) return body;
    return Column(
      children: [
        SafeArea(
          top: false,
          bottom: false,
          child: ExtendedNetworkEmptyState(
            onShareInvitation: _handleShareInvitation,
            onFindRelatives: () => context.push('/discover/relatives'),
            onDismiss: () => _updateSectionState(
              () => _TreeViewScreenState._extendedEmptyDismissedThisSession =
                  true,
            ),
            // Главный «выход»: на телефоне тумблер «Моё дерево|Все»
            // спрятан в фильтрах — даём прямой путь назад.
            onBackToMine: () => ctrl.setMode(ExtendedNetworkMode.mine),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  /// Phase 6 chunk 4c: empty-state «invite family» CTA. Routes к
  /// relatives screen (existing invite flow lives там per-person).
  /// Не используем buildInvitationLink здесь — invitation API binds
  /// link к конкретному personId; pick'ить relative requires UI.
  /// Cheaper UX: send user туда where invite flow already polished.
  void _handleShareInvitation() {
    // Вкладка «Родные» — там живёт отточенный per-person invite flow.
    context.go('/family');
  }

  void _dismissGuidedCta() {
    if (_TreeViewScreenState._guidedCtaDismissedThisSession) return;
    _updateSectionState(
        () => _TreeViewScreenState._guidedCtaDismissedThisSession = true);
  }

  /// A-CTA: занимает ли тело экрана онбординг-гид пустого/только-себя
  /// дерева. Пока он показан, баннер «Не бойся сломать» прятать — он
  /// (а) бессмыслен (ломать ещё нечего) и (б) перекрывал собой верх гида
  /// вместе с крестиком «скрыть». Зеркалит ветки в [_buildTreeBody].
  bool get _isGuidedCtaActive {
    if (_TreeViewScreenState._guidedCtaDismissedThisSession) return false;
    if (_isLoading) return false;
    if (_errorMessage.isNotEmpty) return false;
    final isEmptyTree = _relativesData.isEmpty && _relationsData.isEmpty;
    if (isEmptyTree) return true;
    final selfPerson = _findSelfPerson();
    return _relativesData.length == 1 && selfPerson != null && !_isFriendsTree;
  }

  Widget _buildTreeBody({required String selectedTreeId}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 720;
        final isWideDesktop = constraints.maxWidth >= 1180;
        final isEmptyTree = _relativesData.isEmpty &&
            _relationsData.isEmpty &&
            _errorMessage.isEmpty;

        if (_isLoading) {
          return _buildTreeState(
            icon: Icons.sync,
            title: 'Загружаем дерево',
            message: 'Подтягиваем людей и связи.',
            showProgress: true,
          );
        }

        // Ship 2026-05-26 (UX audit Screen 4.1): replaced single «Добавить»
        // button с relation-first guided CTA per audit «mama-fear»
        // observation. Also surfaces guided CTA когда tree has только
        // self person (canvas с tiny lone card в empty space — audit's
        // primary complaint).
        // A-CTA: блокирующий гид показываем только пока юзер его не
        // закрыл. После dismiss — обычный канвас с FAB «Добавить».
        final showGuidedCta =
            !_TreeViewScreenState._guidedCtaDismissedThisSession;

        if (isEmptyTree && showGuidedCta) {
          if (_isFriendsTree) {
            // Friends tree (Круг) — relation-first CTAs don't apply
            // (no «mama/papa» concept). Keep original single-button state.
            return _buildTreeState(
              icon: Icons.account_tree_outlined,
              title: 'Круг пока пустой',
              message: _isViewerOnly
                  ? 'В этом круге пока нет участников.'
                  : 'Добавьте первого человека в этот круг.',
              actions: [
                if (!_isViewerOnly)
                  FilledButton.icon(
                    onPressed: () => _navigateToAddRelative(selectedTreeId),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Добавить'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _retryCurrentTree(selectedTreeId),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Обновить'),
                ),
              ],
            );
          }
          // Ship FE4 (2026-05-26): viewer-role empty state shows
          // informational copy (no add CTAs) — viewer cannot mutate
          // tree, поэтому surfacing buttons would mislead.
          return EmptyTreeGuidedCta(
            hasSelfPerson: false,
            viewerMode: _isViewerOnly,
            onAddRelative: (relation, gender) => _navigateToAddRelativeWithHint(
              selectedTreeId,
              relation: relation,
              gender: gender,
            ),
            onAddOther: () => _navigateToAddRelative(selectedTreeId),
            onDismiss: _dismissGuidedCta,
          );
        }

        final selfPerson = _findSelfPerson();
        final treeHasOnlySelf =
            _relativesData.length == 1 && selfPerson != null && !_isFriendsTree;
        if (treeHasOnlySelf && showGuidedCta) {
          return EmptyTreeGuidedCta(
            hasSelfPerson: true,
            viewerMode: _isViewerOnly,
            onAddRelative: (relation, gender) => _navigateToAddRelativeWithHint(
              selectedTreeId,
              relation: relation,
              gender: gender,
              contextPersonId: selfPerson.id,
            ),
            onAddOther: () => _navigateToAddRelative(selectedTreeId),
            onDismiss: _dismissGuidedCta,
          );
        }

        if (_errorMessage.isNotEmpty) {
          return _buildTreeState(
            icon: Icons.error_outline,
            title: 'Дерево сейчас недоступно',
            message: _errorMessage,
            actions: [
              OutlinedButton.icon(
                onPressed: () => _retryCurrentTree(selectedTreeId),
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
              ),
            ],
          );
        }

        final selectedEditPerson = _selectedEditPerson;
        final branchRootPerson = _findBranchRootPerson();
        final warnings = _graphSnapshot?.warnings ?? const <TreeGraphWarning>[];
        final treeWarnings = branchRootPerson == null
            ? warnings
            : _graphSnapshot?.warningsForPerson(branchRootPerson.id) ??
                const <TreeGraphWarning>[];
        final treeCanvas = _buildTreeCanvas();
        final topToolbar = _buildTreeTopToolbar(
          selectedTreeId: selectedTreeId,
          branchRootPerson: branchRootPerson,
          compact: isCompact,
        );

        if (isWideDesktop) {
          // Desktop: tree canvas fills the whole body (full-bleed), the
          // toolbar sits across the top, and "Карта рода" sidebar floats
          // pinned to the left edge as a 312px column. Tree pans behind
          // both, matching the reference design where the family graph
          // is the page surface.
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: treeCanvas),
              Positioned(
                top: 10,
                left: 14,
                right: 14,
                child: topToolbar,
              ),
              Positioned(
                top: 80,
                bottom: 14,
                left: 14,
                width: 312,
                child: _buildTreeContextColumn(
                  selectedTreeId: selectedTreeId,
                  branchRootPerson: branchRootPerson,
                  selectedEditPerson: selectedEditPerson,
                  warnings: treeWarnings,
                  compact: false,
                ),
              ),
            ],
          );
        }

        final compactContextHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight * (isCompact ? 0.18 : 0.24))
                .clamp(128.0, isCompact ? 202.0 : 260.0)
                .toDouble()
            : (isCompact ? 210.0 : 260.0);

        // Mobile / compact: tree canvas fills the whole body and the
        // toolbar / context column float above it. The user asked for the
        // tree to read as the page background, not as a contained card —
        // matching the Claude Design reference where the family graph IS
        // the canvas and only thin chrome floats over it.
        //
        // Context column (info card + quick actions + health) starts
        // COLLAPSED so the canvas gets ~85% of the viewport (was ~60%
        // — user feedback "дерево всего лишь 60% экрана занимает").
        // Toggling via the chevron in the top toolbar slides it down.
        final showContextColumn = !_compactChromeCollapsed;
        return Stack(
          fit: StackFit.expand,
          children: [
            // Tree canvas painted behind everything else, edge-to-edge.
            Positioned.fill(child: treeCanvas),
            // Floating chrome on top of the canvas. The headers sit in
            // their own column at the top, leaving the canvas clear in
            // the bottom 70% of the screen for the actual graph.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isCompact ? 10 : 16,
                  isCompact ? 8 : 12,
                  isCompact ? 10 : 16,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    topToolbar,
                    // UX-T1.2 FR-b: видимый handle (как у нижнего листа) —
                    // раскрытие хрома больше не прячется за неочевидным
                    // шевроном; подпись со счётчиком намекает, что там детали.
                    if (isCompact) _buildTreeChromeHandle(),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          return ClipRect(
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, -0.25),
                                end: Offset.zero,
                              ).animate(animation),
                              child: FadeTransition(
                                  opacity: animation, child: child),
                            ),
                          );
                        },
                        child: showContextColumn
                            ? Padding(
                                key: const ValueKey('tree-chrome-shown'),
                                padding: const EdgeInsets.only(top: 10),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: compactContextHeight,
                                  ),
                                  child: SingleChildScrollView(
                                    child: _buildTreeContextColumn(
                                      selectedTreeId: selectedTreeId,
                                      branchRootPerson: branchRootPerson,
                                      selectedEditPerson: selectedEditPerson,
                                      warnings: treeWarnings,
                                      compact: true,
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox(
                                key: ValueKey('tree-chrome-hidden'),
                                height: 0,
                                width: double.infinity,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTreeContextColumn({
    required String selectedTreeId,
    required FamilyPerson? branchRootPerson,
    required FamilyPerson? selectedEditPerson,
    required List<TreeGraphWarning> warnings,
    required bool compact,
  }) {
    final theme = Theme.of(context);
    final treeName =
        _currentTreeMeta?.name ?? widget.routeTreeName ?? 'Семейное дерево';
    final accent =
        _isFriendsTree ? const Color(0xFF0F9D8A) : theme.colorScheme.primary;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTreeHeroPanel(
          treeName: treeName,
          accent: accent,
          compact: compact,
        ),
        SizedBox(height: compact ? 8 : 12),
        _buildTreeQuickActionsPanel(
          selectedTreeId: selectedTreeId,
          branchRootPerson: branchRootPerson,
          compact: compact,
        ),
        if (branchRootPerson != null || selectedEditPerson != null) ...[
          SizedBox(height: compact ? 8 : 12),
          _buildTreeFocusPanel(
            branchRootPerson: branchRootPerson,
            selectedEditPerson: selectedEditPerson,
            accent: accent,
            compact: compact,
          ),
        ],
        if (!compact ||
            warnings.isNotEmpty ||
            _appStatusService.hasVisibleStatus ||
            _errorMessage.isNotEmpty) ...[
          SizedBox(height: compact ? 8 : 12),
          _buildTreeHealthPanel(
            warnings: warnings,
            compact: compact,
          ),
        ],
      ],
    );

    if (compact) {
      return body;
    }

    return SingleChildScrollView(
      child: body,
    );
  }

  /// UX-T1.2 FR-b: дискаверабилити-handle компактного хрома. Вместо
  /// неочевидного шеврона — видимый «потяни за деталями» в стиле drag-handle
  /// нижнего листа: грип-полоска + подпись (FR-a: единственный счётчик-тизер
  /// статов) + шеврон. Тап разворачивает hero-панель (единственный дом
  /// статов) и обратно.
  Widget _buildTreeHeroPanel({
    required String treeName,
    required Color accent,
    required bool compact,
  }) {
    final theme = Theme.of(context);
    final graphSnapshot = _graphSnapshot;
    final personCount = _relativesData.length;
    final relationCount = _relationsData.length;
    final generationCount = graphSnapshot?.generationRows.length ?? 0;
    final branchCount = graphSnapshot?.branchBlocks.length ?? 0;

    if (compact) {
      final stats = <String>[
        '$personCount ${russianPluralForm(
          personCount,
          one: 'человек',
          few: 'человека',
          many: 'человек',
        )}',
        relationCount == 1 ? '1 связь' : '$relationCount связей',
        if (generationCount > 0)
          generationCount == 1 ? '1 поколение' : '$generationCount поколений',
        if (branchCount > 0)
          branchCount == 1 ? '1 ветка' : '$branchCount веток',
      ].join(' · ');

      return GlassPanel(
        padding: const EdgeInsets.all(12),
        borderRadius: BorderRadius.circular(22),
        color: theme.colorScheme.surface.withValues(alpha: 0.82),
        borderColor: accent.withValues(alpha: 0.14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                _isFriendsTree
                    ? Icons.diversity_3_outlined
                    : Icons.account_tree_outlined,
                size: 20,
                color: accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    treeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stats,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return GlassPanel(
      padding: EdgeInsets.all(compact ? 16 : 20),
      borderRadius: BorderRadius.circular(30),
      color: theme.colorScheme.surface.withValues(alpha: 0.8),
      borderColor: accent.withValues(alpha: 0.16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isFriendsTree
                      ? Icons.diversity_3_outlined
                      : Icons.account_tree_outlined,
                  size: 18,
                  color: accent,
                ),
                const SizedBox(width: 8),
                Text(
                  _isFriendsTree ? 'Круг общения' : 'Карта рода',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            treeName,
            style: (compact
                    ? theme.textTheme.titleLarge
                    : theme.textTheme.headlineSmall)
                ?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildTreeStatChip(
                icon: Icons.people_outline,
                label: '$personCount ${russianPluralForm(
                  personCount,
                  one: 'человек',
                  few: 'человека',
                  many: 'человек',
                )}',
              ),
              _buildTreeStatChip(
                icon: Icons.alt_route_outlined,
                label: relationCount == 1 ? '1 связь' : '$relationCount связей',
              ),
              _buildTreeStatChip(
                icon: Icons.layers_outlined,
                label: generationCount == 0
                    ? 'Без уровней'
                    : generationCount == 1
                        ? '1 поколение'
                        : '$generationCount поколений',
              ),
              if (branchCount > 0)
                _buildTreeStatChip(
                  icon: Icons.hub_outlined,
                  label: branchCount == 1 ? '1 ветка' : '$branchCount веток',
                ),
              if (_manualNodePositions.isNotEmpty)
                _buildTreeStatChip(
                  icon: Icons.open_with_rounded,
                  label: 'Ручная раскладка',
                ),
            ],
          ),
          if (!_currentUserIsInTree) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.person_search_outlined,
                  size: 15,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _isFriendsTree
                        ? 'Вашей карточки нет в круге — добавьте себя через связь.'
                        : 'Вашей карточки нет в дереве — добавьте себя через связь.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTreeQuickActionsPanel({
    required String selectedTreeId,
    required FamilyPerson? branchRootPerson,
    required bool compact,
  }) {
    // The "Добавить" tile that used to live here was a third copy of the
    // same action — top toolbar already has its own "+ Add person" green
    // circle, which is the primary entry point. The Quick Actions card
    // now starts with Чаты / Пост / Расставить — actions that DON'T
    // duplicate buttons from the toolbar.
    final actions = <Widget>[
      _buildTreeActionButton(
        icon: Icons.forum_outlined,
        label: 'Чаты',
        compact: compact,
        onPressed: () => context.go('/chats'),
      ),
      _buildTreeActionButton(
        icon: Icons.post_add_outlined,
        label: 'Пост',
        compact: compact,
        onPressed: () => context.push('/post/create'),
      ),
      if (!_isViewerOnly)
        _buildTreeActionButton(
          icon: _isEditMode ? Icons.edit_off_outlined : Icons.open_with_rounded,
          label: _isEditMode ? 'Готово' : 'Расставить',
          compact: compact,
          onPressed: () {
            _updateSectionState(() {
              _isEditMode = !_isEditMode;
              if (!_isEditMode) {
                _selectedEditPersonId = null;
              }
            });
          },
        ),
      if (branchRootPerson != null)
        _buildTreeActionButton(
          icon: Icons.alt_route_outlined,
          label: _isFriendsTree ? 'Чат круга' : 'Чат ветки',
          compact: compact,
          onPressed: () => _openBranchChat(selectedTreeId, branchRootPerson),
        ),
      if (_branchRootPersonId != null)
        _buildTreeActionButton(
          icon: Icons.clear_all,
          label: compact
              ? 'Всё'
              : (_isFriendsTree ? 'Показать весь граф' : 'Показать всё дерево'),
          compact: compact,
          onPressed: _resetBranchFocus,
        ),
      if (_manualNodePositions.isNotEmpty)
        _buildTreeActionButton(
          icon: Icons.restart_alt,
          label: compact ? 'Сброс' : 'Сбросить раскладку',
          compact: compact,
          onPressed: () => _resetManualTreeLayout(selectedTreeId),
        ),
      if (_currentTreeMeta?.isPublic == true)
        _buildTreeActionButton(
          icon: Icons.link_outlined,
          label: compact ? 'Ссылка' : 'Публичная ссылка',
          compact: compact,
          onPressed: _copyPublicTreeLink,
        ),
    ];

    return GlassPanel(
      padding: EdgeInsets.all(compact ? 8 : 16),
      borderRadius: BorderRadius.circular(compact ? 22 : 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!compact) ...[
            Text(
              'Сразу к делу',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 10),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < actions.length; index++) ...[
                  actions[index],
                  if (index != actions.length - 1)
                    SizedBox(width: compact ? 8 : 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreeFocusPanel({
    required FamilyPerson? branchRootPerson,
    required FamilyPerson? selectedEditPerson,
    required Color accent,
    required bool compact,
  }) {
    // No branch selected → don't waste screen space with a description panel;
    // the canvas itself already shows the full tree.  Show the panel only when
    // a branch is in focus or a person is being repositioned (edit mode).
    final hasFocusContent =
        branchRootPerson != null || selectedEditPerson != null;
    if (!hasFocusContent) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final branchVisibleCount = branchRootPerson == null
        ? _relativesData.length
        : _buildBranchVisiblePersonIds(branchRootPerson.id).length;

    return GlassPanel(
      padding: EdgeInsets.all(compact ? 14 : 16),
      borderRadius: BorderRadius.circular(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            branchRootPerson == null
                ? (_isFriendsTree ? 'Расстановка' : 'Расстановка')
                : (_isFriendsTree ? 'Фокус на круге' : 'Фокус на ветке'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          if (branchRootPerson != null)
            _buildTreePersonHighlight(
              person: branchRootPerson,
              eyebrow: _isFriendsTree ? 'Корень круга' : 'Корень ветки',
              accent: accent,
              trailing: _buildMiniCountBadge('$branchVisibleCount узлов'),
            ),
          if (selectedEditPerson != null) ...[
            const SizedBox(height: 14),
            Divider(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 12),
            Text(
              _isEditMode ? 'Карточка для расстановки' : 'Выбранная карточка',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _buildTreePersonHighlight(
              person: selectedEditPerson,
              eyebrow: _isEditMode ? 'Режим перемещения' : 'Текущий выбор',
              accent: accent,
              trailing: _isEditMode
                  ? _buildMiniCountBadge('Двигайте по поколению')
                  : null,
            ),
          ] else if (_isEditMode) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withValues(alpha: 0.14)),
              ),
              child: Text(
                'Режим расстановки включён. Нажмите на карточку в дереве, чтобы подвигать её по своему поколению.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTreeHealthPanel({
    required List<TreeGraphWarning> warnings,
    required bool compact,
  }) {
    final theme = Theme.of(context);
    final warningPreview = warnings.take(compact ? 1 : 2).toList();
    final hasOperationalIssue =
        _appStatusService.hasVisibleStatus || _errorMessage.isNotEmpty;

    return GlassPanel(
      padding: EdgeInsets.all(compact ? 14 : 16),
      borderRadius: BorderRadius.circular(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Состояние дерева',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _buildMiniCountBadge(
                warnings.isEmpty
                    ? 'без предупреждений'
                    : warnings.length == 1
                        ? '1 предупреждение'
                        : '${warnings.length} предупреждений',
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (hasOperationalIssue) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer
                    .withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.14),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _appStatusService.hasSessionIssue
                        ? 'Сессия требует внимания'
                        : _appStatusService.isOffline
                            ? 'Есть проблемы с сетью'
                            : 'Есть что перепроверить',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _appStatusService.issue?.message ??
                        (_errorMessage.isNotEmpty
                            ? _errorMessage
                            : _appStatusService.isOffline
                                ? 'Дерево можно просматривать, но обновления и часть действий сейчас нестабильны.'
                                : 'Попробуйте обновить дерево, чтобы вернуть актуальное состояние.'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.32,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _appStatusService.hasSessionIssue
                            ? () => context.go('/login')
                            : () {
                                _appStatusService.requestRetry();
                                if (_currentTreeId != null) {
                                  _retryCurrentTree(_currentTreeId!);
                                }
                              },
                        icon: Icon(
                          _appStatusService.hasSessionIssue
                              ? Icons.login_outlined
                              : Icons.refresh_rounded,
                        ),
                        label: Text(
                          _appStatusService.hasSessionIssue
                              ? 'Войти снова'
                              : 'Обновить дерево',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (warnings.isEmpty)
            Text(
              _isFriendsTree
                  ? 'Граф выглядит чисто: можно открывать карточки, смотреть связи и писать людям без лишней навигации.'
                  : 'Схема выглядит чисто: поколения и связи собраны, дерево готово к работе и просмотру.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.38,
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: warningPreview
                  .map(
                    (warning) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer
                              .withValues(alpha: 0.38),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: theme.colorScheme.error.withValues(
                              alpha: 0.14,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              warning.message,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                            if ((warning.hint ?? '').isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                warning.hint!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onErrorContainer
                                      .withValues(alpha: 0.88),
                                  height: 1.32,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildTreePersonHighlight({
    required FamilyPerson person,
    required String eyebrow,
    required Color accent,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final photoUrl = person.primaryPhotoUrl;
    final avatarImage = buildAvatarImageProvider(photoUrl);
    final subtitleParts = <String>[
      if ((person.birthDate?.year ?? 0) > 0) 'р. ${person.birthDate!.year}',
      if (person.isAlive == false && (person.deathDate?.year ?? 0) > 0)
        'память ${person.deathDate!.year}',
      if ((person.birthPlace ?? '').trim().isNotEmpty)
        person.birthPlace!.trim(),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: accent.withValues(alpha: 0.14),
            backgroundImage: avatarImage,
            child: avatarImage == null
                ? Text(
                    person.initials,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  person.displayName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitleParts.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ],
        ],
      ),
    );
  }

  Widget _buildTreeStatChip({
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniCountBadge(String label) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildTreeActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool emphasized = false,
    bool compact = false,
  }) {
    final minimumSize = compact ? const Size(0, 38) : null;
    final padding = EdgeInsets.symmetric(
      horizontal: compact ? 12 : 16,
      vertical: compact ? 9 : 12,
    );
    if (emphasized) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: minimumSize,
          padding: padding,
          visualDensity: compact ? VisualDensity.compact : null,
          tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: minimumSize,
        padding: padding,
        visualDensity: compact ? VisualDensity.compact : null,
        tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  void _retryCurrentTree(String treeId) {
    _appStatusService.requestRetry();
    unawaited(_loadData(treeId));
  }

  Widget _buildTreeState({
    required IconData icon,
    required String title,
    required String message,
    List<Widget> actions = const [],
    bool showProgress = false,
  }) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GlassPanel(
            padding: const EdgeInsets.all(20),
            borderRadius: BorderRadius.circular(26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showProgress)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: CircularProgressIndicator(),
                  )
                else
                  Icon(icon, size: 48, color: theme.colorScheme.primary),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
