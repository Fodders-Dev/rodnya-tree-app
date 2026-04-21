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

        final treeCanvas = _buildTreeCanvas();
        final selectedEditPerson = _selectedEditPerson;
        final branchRootPerson = _findBranchRootPerson();
        final warnings = _graphSnapshot?.warnings ?? const <TreeGraphWarning>[];
        final treeWarnings = branchRootPerson == null
            ? warnings
            : _graphSnapshot?.warningsForPerson(branchRootPerson.id) ??
                const <TreeGraphWarning>[];

        if (isWideDesktop) {
          return Center(
            child: SizedBox(
              width: constraints.maxWidth > 1680 ? 1680 : constraints.maxWidth,
              height: constraints.maxHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 336,
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
            ),
          );
        }

        final compactContextHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight * (isCompact ? 0.4 : 0.32))
                .clamp(220.0, isCompact ? 360.0 : 300.0)
                .toDouble()
            : (isCompact ? 320.0 : 260.0);

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
        const SizedBox(height: 12),
        _buildTreeQuickActionsPanel(
          selectedTreeId: selectedTreeId,
          branchRootPerson: branchRootPerson,
          compact: compact,
        ),
        const SizedBox(height: 12),
        _buildTreeFocusPanel(
          branchRootPerson: branchRootPerson,
          selectedEditPerson: selectedEditPerson,
          accent: accent,
          compact: compact,
        ),
        const SizedBox(height: 12),
        _buildTreeHealthPanel(
          warnings: warnings,
          compact: compact,
        ),
      ],
    );

    if (compact) {
      return body;
    }

    return SingleChildScrollView(
      child: body,
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
          const SizedBox(height: 12),
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
          const SizedBox(height: 8),
          Text(
            _isFriendsTree
                ? 'Живой центр круга: видно, кто рядом, кому написать сейчас и как быстро собрать нужных людей.'
                : 'Главное полотно семьи: поколения, ветки, память и быстрые действия собраны в одном месте.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
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
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer.withValues(
                  alpha: 0.46,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.person_search_outlined,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isFriendsTree
                          ? 'В этом круге ещё нет вашей карточки. Откройте нужного человека и добавьте себя через связь.'
                          : 'В этом дереве ещё нет вашей карточки. Откройте родственника и привяжите себя через связь.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
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
        label: _isFriendsTree ? 'Добавить в круг' : 'Добавить человека',
        emphasized: true,
        onPressed: () => _navigateToAddRelative(selectedTreeId),
      ),
      _buildTreeActionButton(
        icon: Icons.history_outlined,
        label: 'Изменения',
        onPressed: _showTreeHistorySheet,
      ),
      _buildTreeActionButton(
        icon: Icons.people_outline,
        label: _isFriendsTree ? 'Люди круга' : 'Карточки семьи',
        onPressed: () => context.go('/relatives'),
      ),
      _buildTreeActionButton(
        icon: Icons.forum_outlined,
        label: 'Открыть чаты',
        onPressed: () => context.go('/chats'),
      ),
      _buildTreeActionButton(
        icon: Icons.post_add_outlined,
        label: _isFriendsTree ? 'Написать в круг' : 'Новый пост',
        onPressed: () => context.push('/post/create'),
      ),
      _buildTreeActionButton(
        icon: _isEditMode ? Icons.edit_off_outlined : Icons.open_with_rounded,
        label: _isEditMode ? 'Закончить расстановку' : 'Расставить карточки',
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
          onPressed: () => _openBranchChat(selectedTreeId, branchRootPerson),
        ),
      if (_branchRootPersonId != null)
        _buildTreeActionButton(
          icon: Icons.clear_all,
          label: _isFriendsTree ? 'Показать весь граф' : 'Показать всё дерево',
          onPressed: _resetBranchFocus,
        ),
      if (_manualNodePositions.isNotEmpty)
        _buildTreeActionButton(
          icon: Icons.restart_alt,
          label: 'Сбросить раскладку',
          onPressed: () => _resetManualTreeLayout(selectedTreeId),
        ),
      if (_currentTreeMeta?.isPublic == true)
        _buildTreeActionButton(
          icon: Icons.link_outlined,
          label: 'Публичная ссылка',
          onPressed: _copyPublicTreeLink,
        ),
    ];

    return GlassPanel(
      padding: EdgeInsets.all(compact ? 14 : 16),
      borderRadius: BorderRadius.circular(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            compact ? 'Быстрые действия' : 'Сразу к делу',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: actions,
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
                ? (_isFriendsTree
                    ? 'В фокусе весь круг'
                    : 'В фокусе всё дерево')
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
            )
          else
            Text(
              _isFriendsTree
                  ? 'Сейчас виден весь граф общения. Выберите человека на canvas, чтобы сузить круг, открыть чат или быстро перейти к карточке.'
                  : 'Сейчас виден весь род. Выберите человека на canvas, чтобы выделить ветку, открыть её чат или перейти к карточке без лишних шагов.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.38,
              ),
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
            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
            child: photoUrl == null
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
  }) {
    if (emphasized) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
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
                onBranchFocusCleared: _resetBranchFocus,
                onPersonTap: (person) {
                  debugPrint('Нажатие на узел: ${person.name} (${person.id})');
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
                onAddRelativeTapWithType: _handleAddRelativeFromTree,
                currentUserIsInTree: _currentUserIsInTree,
                onAddSelfTapWithType: _handleAddSelfFromTree,
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
