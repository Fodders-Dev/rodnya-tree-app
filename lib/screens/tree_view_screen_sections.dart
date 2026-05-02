part of 'tree_view_screen.dart';

extension _TreeViewScreenSections on _TreeViewScreenState {
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

        if (isEmptyTree) {
          return _buildTreeState(
            icon: Icons.account_tree_outlined,
            title: 'Дерево пока пустое',
            message: _isFriendsTree
                ? 'Добавьте первого человека в этот круг.'
                : 'Добавьте первого человека в это дерево.',
            actions: [
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
          warnings: treeWarnings,
          compact: isCompact,
        );

        if (isWideDesktop) {
          return Center(
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    topToolbar,
                    const SizedBox(height: 12),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 312,
                            child: _buildTreeContextColumn(
                              selectedTreeId: selectedTreeId,
                              branchRootPerson: branchRootPerson,
                              selectedEditPerson: selectedEditPerson,
                              warnings: treeWarnings,
                              compact: false,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: treeCanvas),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final compactContextHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight * (isCompact ? 0.18 : 0.24))
                .clamp(128.0, isCompact ? 202.0 : 260.0)
                .toDouble()
            : (isCompact ? 210.0 : 260.0);

        return Padding(
          padding: EdgeInsets.fromLTRB(
            isCompact ? 10 : 16,
            isCompact ? 8 : 12,
            isCompact ? 10 : 16,
            isCompact ? 12 : 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              topToolbar,
              const SizedBox(height: 10),
              SizedBox(
                height: compactContextHeight,
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
              const SizedBox(height: 12),
              Expanded(child: treeCanvas),
            ],
          ),
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

  Widget _buildTreeTopToolbar({
    required String selectedTreeId,
    required FamilyPerson? branchRootPerson,
    required List<TreeGraphWarning> warnings,
    required bool compact,
  }) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final accent =
        _isFriendsTree ? const Color(0xFF0F9D8A) : tokens.accentStrong;
    final generationCount = _graphSnapshot?.generationRows.length ?? 0;

    return GlassPanel(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 7 : 8,
      ),
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      color: tokens.surfaceStrong.withValues(alpha: 0.9),
      borderColor: tokens.surfaceLine,
      child: Row(
        children: [
          _buildTreeBranchFilterChip(
            branchRootPerson: branchRootPerson,
            accent: accent,
            compact: compact,
          ),
          SizedBox(width: compact ? 8 : 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTreeToolbarStat(
                    icon: Icons.people_outline,
                    label: '${_relativesData.length}',
                    tooltip: 'Люди',
                    accent: accent,
                  ),
                  const SizedBox(width: 6),
                  _buildTreeToolbarStat(
                    icon: Icons.alt_route_outlined,
                    label: '${_relationsData.length}',
                    tooltip: 'Связи',
                    accent: accent,
                  ),
                  const SizedBox(width: 6),
                  _buildTreeToolbarStat(
                    icon: Icons.layers_outlined,
                    label: generationCount == 0 ? '-' : '$generationCount',
                    tooltip: 'Поколения',
                    accent: accent,
                  ),
                  const SizedBox(width: 6),
                  _buildTreeToolbarStat(
                    icon: Icons.flag_outlined,
                    label: '${warnings.length}',
                    tooltip: 'Ждут проверки',
                    accent: warnings.isEmpty ? accent : tokens.warm,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: compact ? 8 : 10),
          _buildTreeToolbarIconButton(
            icon: Icons.person_add_alt_1_outlined,
            tooltip: _isFriendsTree
                ? 'Добавить из панели круга'
                : 'Добавить из панели дерева',
            onPressed: () => _navigateToAddRelative(selectedTreeId),
            emphasized: true,
          ),
          _buildTreeToolbarIconButton(
            icon: Icons.search_rounded,
            tooltip: _isFriendsTree ? 'Найти связь' : 'Найти родственника',
            onPressed: () => context.go('/relatives'),
          ),
          _buildTreeToolbarIconButton(
            icon: _isEditMode ? Icons.visibility_outlined : Icons.open_with,
            tooltip:
                _isEditMode ? 'Вернуться к просмотру' : 'Расставить карточки',
            onPressed: () {
              _updateSectionState(() {
                _isEditMode = !_isEditMode;
                if (!_isEditMode) {
                  _selectedEditPersonId = null;
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTreeBranchFilterChip({
    required FamilyPerson? branchRootPerson,
    required Color accent,
    required bool compact,
  }) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final hasBranchFocus = branchRootPerson != null;
    final label = hasBranchFocus
        ? branchRootPerson.displayName
        : (_isFriendsTree ? 'Весь круг' : 'Всё дерево');

    return Tooltip(
      message: hasBranchFocus
          ? (_isFriendsTree ? 'Сбросить круг' : 'Сбросить ветку')
          : (_isFriendsTree ? 'Фильтр круга' : 'Фильтр ветки'),
      child: Material(
        color: hasBranchFocus ? accent.withValues(alpha: 0.12) : tokens.surface,
        borderRadius: tokens.chipRadius,
        child: InkWell(
          borderRadius: tokens.chipRadius,
          onTap: hasBranchFocus ? _resetBranchFocus : null,
          child: Container(
            constraints: BoxConstraints(maxWidth: compact ? 128 : 220),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 8 : 9,
            ),
            decoration: BoxDecoration(
              borderRadius: tokens.chipRadius,
              border: Border.all(
                color: hasBranchFocus
                    ? accent.withValues(alpha: 0.42)
                    : tokens.surfaceLine,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasBranchFocus
                      ? Icons.alt_route_outlined
                      : (_isFriendsTree
                          ? Icons.diversity_3_outlined
                          : Icons.account_tree_outlined),
                  size: 16,
                  color: hasBranchFocus ? accent : tokens.inkSecondary,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: hasBranchFocus ? accent : tokens.inkSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (hasBranchFocus) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.close, size: 14, color: accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTreeToolbarStat({
    required IconData icon,
    required String label,
    required String tooltip,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.surface.withValues(alpha: 0.92),
          borderRadius: tokens.chipRadius,
          border: Border.all(color: tokens.surfaceLine),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: tokens.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTreeToolbarIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool emphasized = false,
  }) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final background =
        emphasized ? tokens.accent : tokens.surface.withValues(alpha: 0.92);
    final foreground = emphasized ? tokens.accentInk : tokens.accentStrong;

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onPressed,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(icon, size: 20, color: foreground),
            ),
          ),
        ),
      ),
    );
  }

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
        personCount == 1 ? '1 человек' : '$personCount людей',
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
                label: personCount == 1 ? '1 человек' : '$personCount людей',
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
    final actions = <Widget>[
      _buildTreeActionButton(
        icon: Icons.person_add_alt_1_outlined,
        label: compact
            ? 'Добавить'
            : (_isFriendsTree ? 'Добавить в круг' : 'Добавить человека'),
        emphasized: true,
        compact: compact,
        onPressed: () => _navigateToAddRelative(selectedTreeId),
      ),
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

  Widget _buildTreeCanvas() {
    final theme = Theme.of(context);
    final selectedPerson = _selectedPersonSheetPerson;
    final canvasAccent =
        _isFriendsTree ? const Color(0xFF0F9D8A) : theme.colorScheme.primary;
    return GlassPanel(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(30),
      blur: 14,
      color: theme.colorScheme.surface.withValues(alpha: 0.72),
      borderColor: canvasAccent.withValues(alpha: 0.18),
      boxShadow: [
        BoxShadow(
          color: theme.colorScheme.shadow.withValues(alpha: 0.08),
          blurRadius: 28,
          offset: const Offset(0, 18),
        ),
      ],
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surface.withValues(alpha: 0.88),
              canvasAccent.withValues(alpha: _isFriendsTree ? 0.05 : 0.03),
            ],
          ),
          borderRadius: BorderRadius.circular(30),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, 0.04),
                      radius: 0.72,
                      colors: [
                        canvasAccent.withValues(
                          alpha: _isFriendsTree ? 0.14 : 0.10,
                        ),
                        theme.colorScheme.surface.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        theme.colorScheme.surface.withValues(alpha: 0.16),
                        theme.colorScheme.surface.withValues(alpha: 0),
                        canvasAccent.withValues(alpha: 0.04),
                      ],
                    ),
                  ),
                ),
              ),
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
                onAddRelativeTapWithType: _handleAddRelativeFromTree,
                currentUserIsInTree: _currentUserIsInTree,
                onAddSelfTapWithType: _handleAddSelfFromTree,
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: selectedPerson == null
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
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
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
        ),
      ),
    );
  }

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
    final lname =
        nameParts.length > 1 ? nameParts.sublist(1).join(' ') : null;

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
                      ? (_isFriendsTree
                          ? 'Карточка круга'
                          : 'Карточка дерева')
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
                        const SizedBox(width: 8),
                        _buildTreeSheetAction(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: 'Написать',
                          onPressed: () => _openPersonDetails(
                            person,
                            action: 'chat',
                          ),
                        ),
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
                        const SizedBox(width: 8),
                        _buildTreeSheetAction(
                          icon: Icons.person_add_alt_1_outlined,
                          label: 'Связь',
                          onPressed: () =>
                              _showTreePersonRelationSheet(person),
                        ),
                        if (hasWarnings) ...[
                          const SizedBox(width: 8),
                          _buildTreeSheetAction(
                            icon: Icons.report_problem_outlined,
                            label: 'Проверить',
                            onPressed: () =>
                                _openPersonDetails(person, action: 'relations'),
                          ),
                        ],
                      ],
                    ),
                  ),
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
                    bottom: Radius.circular(_personSheetExpanded
                        ? 0
                        : tokens.radiusLg),
                  ),
                  child: InkWell(
                    onTap: _togglePersonSheetExpansion,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(tokens.radiusLg),
                      bottom: Radius.circular(_personSheetExpanded
                          ? 0
                          : tokens.radiusLg),
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

  Widget _buildTreeSheetAction({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool emphasized = false,
  }) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final background =
        emphasized ? tokens.accent : tokens.surface.withValues(alpha: 0.95);
    final foreground = emphasized ? tokens.accentInk : tokens.accentStrong;

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
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GlassPanel(
            padding: const EdgeInsets.all(24),
            borderRadius: BorderRadius.circular(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showProgress)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: CircularProgressIndicator(),
                  )
                else
                  Icon(icon, size: 56, color: theme.colorScheme.primary),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 20),
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

  List<PopupMenuEntry<_TreeToolbarAction>> _buildTreeToolbarMenuItems() {
    final branchRootPerson = _findBranchRootPerson();
    final items = <PopupMenuEntry<_TreeToolbarAction>>[
      _buildTreeToolbarMenuItem(
        value: _TreeToolbarAction.refresh,
        icon: Icons.refresh,
        label: 'Обновить дерево',
      ),
      _buildTreeToolbarMenuItem(
        value: _TreeToolbarAction.openHistory,
        icon: Icons.history_outlined,
        label: 'История изменений',
      ),
      _buildTreeToolbarMenuItem(
        value: _TreeToolbarAction.openRelatives,
        icon: Icons.people_outline,
        label: _isFriendsTree ? 'Открыть связи' : 'Открыть родных',
      ),
      _buildTreeToolbarMenuItem(
        value: _TreeToolbarAction.openChats,
        icon: Icons.forum_outlined,
        label: 'Открыть чаты',
      ),
      _buildTreeToolbarMenuItem(
        value: _TreeToolbarAction.createPost,
        icon: Icons.post_add_outlined,
        label: _isFriendsTree ? 'Пост в круг' : 'Новый пост',
      ),
      _buildTreeToolbarMenuItem(
        value: _TreeToolbarAction.toggleEditMode,
        icon: _isEditMode ? Icons.edit_off_outlined : Icons.edit_outlined,
        label: _isEditMode
            ? 'Выключить перемещение карточек'
            : 'Включить перемещение карточек',
      ),
    ];

    if (branchRootPerson != null) {
      items.add(
        _buildTreeToolbarMenuItem(
          value: _TreeToolbarAction.openBranchChat,
          icon: Icons.alt_route_outlined,
          label: _isFriendsTree ? 'Написать кругу' : 'Написать ветке',
        ),
      );
      items.add(
        _buildTreeToolbarMenuItem(
          value: _TreeToolbarAction.openBranchDetails,
          icon: Icons.open_in_new,
          label: _isFriendsTree
              ? 'Открыть карточку круга'
              : 'Открыть карточку ветки',
        ),
      );
    }

    if (_branchRootPersonId != null) {
      items.add(
        _buildTreeToolbarMenuItem(
          value: _TreeToolbarAction.resetBranchFocus,
          icon: Icons.clear_all,
          label: _isFriendsTree ? 'Показать весь граф' : 'Показать всё дерево',
        ),
      );
    }

    if (_currentTreeMeta?.isPublic == true) {
      items.add(
        _buildTreeToolbarMenuItem(
          value: _TreeToolbarAction.copyPublicLink,
          icon: Icons.link_outlined,
          label: 'Скопировать публичную ссылку',
        ),
      );
    }

    if (_manualNodePositions.isNotEmpty) {
      items.add(
        _buildTreeToolbarMenuItem(
          value: _TreeToolbarAction.resetLayout,
          icon: Icons.restart_alt,
          label: 'Сбросить ручную раскладку',
        ),
      );
    }

    return items;
  }

  PopupMenuItem<_TreeToolbarAction> _buildTreeToolbarMenuItem({
    required _TreeToolbarAction value,
    required IconData icon,
    required String label,
  }) {
    return PopupMenuItem<_TreeToolbarAction>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
