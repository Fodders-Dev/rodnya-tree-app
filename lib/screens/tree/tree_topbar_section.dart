part of '../tree_view_screen.dart';

extension _TreeTopbarSection on _TreeViewScreenState {
  Widget _buildTreeTopbar({
    required ThemeData theme,
    required RodnyaDesignTokens tokens,
    required String? selectedTreeId,
  }) {
    // Same Android perf bypass as the other topbars — TreeView is
    // the most expensive screen anyway (canvas physics + many node
    // renders), so dropping the topbar's per-frame blur matters
    // even more here than on lighter screens.
    final useBlur = defaultTargetPlatform != TargetPlatform.android;
    // UX-T1 FR1: на телефоне (<1180) топ-бар несёт компактный icon-сегмент
    // Список/Дерево вместо дублирующего слова «Дерево»; десктоп не трогаем.
    final isPhone = MediaQuery.of(context).size.width < 1180;
    final body = Container(
      decoration: BoxDecoration(
        color: tokens.surface.withValues(
          alpha: theme.brightness == Brightness.dark
              ? (useBlur ? 0.74 : 0.96)
              : (useBlur ? 0.78 : 0.97),
        ),
        border: Border(
          bottom: BorderSide(
            color: tokens.surfaceLine.withValues(alpha: 0.5),
            width: 0.6,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: AppTheme.topbarContentHeight,
          child: Padding(
            // Левый отступ 14 (был 8 — под иконку «выбрать дерево», которую
            // убрали) — совпадает с /family, /chats: те же 14 слева, чтобы
            // ряд заголовок+чип не прыгал при переключении вкладок таб-бара.
            padding: const EdgeInsets.fromLTRB(14, 3, 12, 3),
            child: Row(
              children: [
                // Плотность, чанк 16 (05.09.2026): раньше здесь жили ДВЕ
                // самостоятельные реализации «дерево» — своя нередактируемая
                // пилюля с именем + отдельная иконка слева «выбрать дерево»
                // (context.go('/trees')). Обе делали, по сути, одно и то же
                // (сменить/выбрать ветку), только пилюля — только смотреть,
                // а иконка — уходом с экрана. Унифицируем с остальными
                // вкладками (Родные/Чаты/Главная): один BranchSwitcherChip,
                // тап открывает шторку со списком веток + «Создать/управлять
                // ветками» (тот же /trees) — отдельная иконка больше не
                // нужна, функция осталась в одном месте.
                //
                // Иконка «дерево» справа (ExtendedNetworkToggle, компакт)
                // — НЕ дубль: переключает режим «Моё дерево / расширенная
                // сеть», отдельная функция, оставлена как есть.
                if (!isPhone) ...[
                  Text(
                    _isFriendsTree ? 'Круг' : 'Дерево',
                    style: AppTheme.serif(
                      color: tokens.ink,
                      fontSize: AppTheme.tabTitleFontSize,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.22,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Flexible(
                        child: BranchSwitcherChip(),
                      ),
                      if (selectedTreeId != null &&
                          _extendedNetworkController != null) ...[
                        const SizedBox(width: 8),
                        // Phase 4 chunk 2: mode toggle right beside the
                        // active tree switcher so the viewer scope is obvious.
                        ChangeNotifierProvider<ExtendedNetworkController>.value(
                          value: _extendedNetworkController!,
                          child: ExtendedNetworkToggle(compact: isPhone),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Bug fix (S20 FE: RenderFlex overflowed by 191px on a
                // narrow phone). The trailing action controls now live
                // in a constrained horizontal scroll view, so the topbar
                // never overflows at any width and leaves no dead Spacer
                // gap.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width *
                        (isPhone ? 0.52 : 0.62),
                  ),
                  child: SingleChildScrollView(
                    key: const Key('tree-topbar-actions-scroll'),
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Undo / redo пилюли — на десктопе всегда видны (disabled
                        // если стек пуст), чтобы юзер сразу понимал что эта
                        // функциональность есть. На телефоне (UX-T1.2 FR-c) они
                        // переехали в overflow «•••» ради минимального хрома.
                        // ListenableBuilder подписан на TreeMutationHistory,
                        // перерисовывается на push/pop стека (enabled state
                        // меняется в реальном времени).
                        if (!isPhone &&
                            selectedTreeId != null &&
                            GetIt.I.isRegistered<TreeMutationHistory>())
                          ListenableBuilder(
                            listenable: GetIt.I<TreeMutationHistory>(),
                            builder: (context, _) {
                              final history = GetIt.I<TreeMutationHistory>();
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(width: 8),
                                  _TreeTopbarPill(
                                    tokens: tokens,
                                    tooltip: history.canUndo
                                        ? 'Отменить · Ctrl+Z'
                                        : 'Нечего отменять',
                                    onTap: history.canUndo
                                        ? () => unawaited(_performUndo())
                                        : null,
                                    child: Icon(
                                      Icons.undo_rounded,
                                      size: 19,
                                      color: history.canUndo
                                          ? tokens.ink
                                          : tokens.inkSecondary
                                              .withValues(alpha: 0.4),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _TreeTopbarPill(
                                    tokens: tokens,
                                    tooltip: history.canRedo
                                        ? 'Повторить · Ctrl+Shift+Z'
                                        : 'Нечего повторять',
                                    onTap: history.canRedo
                                        ? () => unawaited(_performRedo())
                                        : null,
                                    child: Icon(
                                      Icons.redo_rounded,
                                      size: 19,
                                      color: history.canRedo
                                          ? tokens.ink
                                          : tokens.inkSecondary
                                              .withValues(alpha: 0.4),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        // UX-T1.2 FR-c: поиск/фильтры расширенной сети — вторичные,
                        // на телефоне живут в «•••» (см. _buildTreeToolbarMenuItems),
                        // отдельные пилюли показываем только на десктопе.
                        if (!isPhone &&
                            selectedTreeId != null &&
                            _shouldShowSearchButton()) ...[
                          const SizedBox(width: 4),
                          _ExtendedSearchButton(
                            tokens: tokens,
                            onTap: () => _openSearchSheet(),
                          ),
                        ],
                        if (!isPhone &&
                            selectedTreeId != null &&
                            _shouldShowFiltersButton()) ...[
                          const SizedBox(width: 4),
                          ChangeNotifierProvider<
                              ExtendedNetworkController>.value(
                            value: _extendedNetworkController!,
                            child: _FiltersButton(
                              tokens: tokens,
                              onTap: () => _openFilterSheet(),
                            ),
                          ),
                        ],
                        if (selectedTreeId != null &&
                            !_isViewerOnly &&
                            !_isSelectionMode &&
                            !_isEditMode) ...[
                          const SizedBox(width: 8),
                          _TreeTopbarPill(
                            tokens: tokens,
                            tooltip: _isFriendsTree
                                ? 'Добавить человека'
                                : 'Добавить родственника',
                            onTap: () => _startAddRelativeFlow(selectedTreeId),
                            child: Icon(
                              Icons.person_add_alt_1_rounded,
                              size: 19,
                              color: tokens.ink,
                            ),
                          ),
                        ],
                        if (selectedTreeId != null) ...[
                          const SizedBox(width: 8),
                          PopupMenuButton<_TreeToolbarAction>(
                            tooltip: 'Действия дерева',
                            onSelected: (action) => _handleTreeToolbarAction(
                                selectedTreeId, action),
                            itemBuilder: (context) =>
                                _buildTreeToolbarMenuItems(isPhone: isPhone),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: tokens.surfaceStrong,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: tokens.surfaceLine),
                              ),
                              child: Icon(
                                Icons.more_horiz_rounded,
                                size: 19,
                                color: tokens.ink,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!useBlur) return body;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: body,
      ),
    );
  }

  Future<void> _handleTreeToolbarAction(
    String selectedTreeId,
    _TreeToolbarAction action,
  ) async {
    final branchRootPerson = _findBranchRootPerson();

    switch (action) {
      case _TreeToolbarAction.refresh:
        await _loadData(selectedTreeId);
        return;
      case _TreeToolbarAction.openHistory:
        await _showTreeHistorySheet();
        return;
      case _TreeToolbarAction.sendDiagnostics:
        await _sendTreeDiagnostics();
        return;
      case _TreeToolbarAction.openChats:
        context.go('/chats');
        return;
      case _TreeToolbarAction.createPost:
        context.push('/post/create');
        return;
      case _TreeToolbarAction.undo:
        unawaited(_performUndo());
        return;
      case _TreeToolbarAction.redo:
        unawaited(_performRedo());
        return;
      case _TreeToolbarAction.openSearch:
        await _openSearchSheet();
        return;
      case _TreeToolbarAction.openFilters:
        await _openFilterSheet();
        return;
      case _TreeToolbarAction.toggleEditMode:
        if (!mounted) {
          return;
        }
        _updateSectionState(() {
          _isEditMode = !_isEditMode;
          if (!_isEditMode) {
            _selectedEditPersonId = null;
          }
          // Edit and selection are mutually exclusive — both want
          // long-press / tap. Entering one closes the other.
          if (_isEditMode && _isSelectionMode) {
            _isSelectionMode = false;
            _selectedPersonIds.clear();
          }
        });
        return;
      case _TreeToolbarAction.toggleSelectionMode:
        if (!mounted) {
          return;
        }
        _updateSectionState(() {
          _isSelectionMode = !_isSelectionMode;
          if (!_isSelectionMode) {
            _selectedPersonIds.clear();
          }
          // Symmetric guard — entering selection closes edit mode.
          if (_isSelectionMode && _isEditMode) {
            _isEditMode = false;
            _selectedEditPersonId = null;
          }
        });
        return;
      case _TreeToolbarAction.openBranchChat:
        await _openBranchChat(selectedTreeId, branchRootPerson);
        return;
      case _TreeToolbarAction.openBranchDetails:
        if (branchRootPerson != null) {
          _openPersonDetails(branchRootPerson);
        }
        return;
      case _TreeToolbarAction.copyPublicLink:
        await _copyPublicTreeLink();
        return;
      case _TreeToolbarAction.resetBranchFocus:
        _resetBranchFocus();
        return;
      case _TreeToolbarAction.resetLayout:
        await _resetManualTreeLayout(selectedTreeId);
        return;
    }
  }

  // Ship Q4 (2026-05-26): action sheet pops on tap (non-edit mode).
  // UX audit 2026-05-25 Critical #4 — make Профиль / Edit / Add /
  // Connect / Delete discoverable from single tap, не через скрытые
  // gestures либо chevron-to-expand peek panel.

  Widget _buildTreeChromeHandle() {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final collapsed = _compactChromeCollapsed;
    final peopleCount = _relativesData.length;
    final peopleLabel = '$peopleCount ${russianPluralForm(
      peopleCount,
      one: 'человек',
      few: 'человека',
      many: 'человек',
    )}';
    final label = collapsed ? '$peopleLabel · подробнее' : 'Свернуть';

    // Плотность, чанк 16 (05.09.2026): грип и подпись раньше стояли друг
    // над другом в Column (паддинг 16/6 + грип 3 + зазор 5 + строка ~18 =
    // ~36dp). Один Row с тем же грипом инлайн перед текстом даёт тот же
    // «потяни за деталями» жест за ~28dp — паддинг ужат до 4, все ключи и
    // текст (включая « · подробнее» — на нём завязан tree_view_screen_test)
    // не менялись.
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Center(
        child: Material(
          color: tokens.surfaceStrong.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: const Key('tree-chrome-handle'),
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              _updateSectionState(() {
                _compactChromeCollapsed = !_compactChromeCollapsed;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Грип-полоска — узнаваемый «потяни меня» нижнего листа,
                  // теперь инлайн слева от подписи вместо отдельной строки.
                  Container(
                    width: 16,
                    height: 3,
                    decoration: BoxDecoration(
                      color: tokens.inkMuted.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: tokens.inkSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    collapsed
                        ? Icons.expand_more_rounded
                        : Icons.expand_less_rounded,
                    size: 16,
                    color: tokens.inkSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTreeTopToolbar({
    required String selectedTreeId,
    required FamilyPerson? branchRootPerson,
    required bool compact,
  }) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final accent =
        _isFriendsTree ? const Color(0xFF0F9D8A) : tokens.accentStrong;

    // UX-T1.2 FR-a: пилюли-статы (люди·связи·поколения·флаги) больше не
    // маячат в тулбаре — это был второй дом статов в дополнение к hero-
    // панели. Единственный дом теперь — hero-панель, которая раскрывается
    // по тапу (handle снизу / название дерева). Тулбар несёт только
    // контекст: чип-фильтр ветки + бейдж семьи.
    //
    // Плотность, чанк 16 (05.09.2026): на телефоне эта карточка читалась
    // как «переключатель Всё дерево / Моё дерево» — фильтр-чип («Всё
    // дерево») + бейдж семьи (легаси-подпись «Моё дерево») рядом, в рамке
    // GlassPanel, при этом у самого чипа ЕЩЁ рамка — рамка в рамке, и
    // ~54dp по факту. На компакте убираем внешнюю рамку (граница чипа
    // остаётся — она несёт смысл: подсвечивает фокус на ветке) и режем
    // вертикальные паддинги; десктоп (compact:false) не трогаем.
    return GlassPanel(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 8,
      ),
      borderRadius: BorderRadius.circular(compact ? 14 : tokens.radiusLg),
      color: tokens.surfaceStrong.withValues(alpha: 0.9),
      borderColor: compact ? Colors.transparent : tokens.surfaceLine,
      child: Row(
        children: [
          // Bug fix (S20 FE: body toolbar overflowed past the trailing
          // icons at 360-393dp). The informational cluster (branch filter
          // chip + семя badge + stat pills) now lives in ONE horizontal
          // scroll bounded by Expanded, so it always yields space to the
          // fixed, always-visible action icons — the Row can't overflow at
          // any width (it scrolls instead). Responsive; no hardcoded width.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTreeBranchFilterChip(
                    branchRootPerson: branchRootPerson,
                    accent: accent,
                    compact: compact,
                  ),
                  if (!_isFriendsTree) ...[
                    SizedBox(width: compact ? 8 : 10),
                    // семя context badge. Bounded so its internal ellipsis
                    // works inside the (otherwise unbounded) horizontal scroll.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: SemyaContextBadge(
                        semya: _currentSemyaContext?.semya,
                        callerRole: _currentSemyaContext?.callerRole,
                        legacyLabel: 'Настроить семью',
                        onTap: _currentSemyaContext != null
                            ? () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => SemyaDetailsScreen(
                                      semyaId: _currentSemyaContext!.semya.id,
                                    ),
                                  ),
                                );
                                await _refreshSemyaContext(selectedTreeId);
                              }
                            : () => _openOrBindSemyaForTree(selectedTreeId),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // UX-T1 FR2: на телефоне (compact) единственная кнопка добавления —
          // FAB «Добавить» (Telegram-стиль). Дубль-кнопку из тулбара убираем
          // (оба входа звали один _startAddRelativeFlow). На десктопе
          // (!compact) тулбар-кнопку оставляем как есть.
          if (!compact && !_isViewerOnly) ...[
            const SizedBox(width: 10),
            _buildTreeToolbarIconButton(
              icon: Icons.person_add_alt_1_outlined,
              tooltip: _isFriendsTree
                  ? 'Добавить из панели круга'
                  : 'Добавить из панели дерева',
              // Чанк C: тот же флоу, что у FAB (семья → пикер «Кем
              // приходится?», круг → форма) — два верхних входа больше не
              // расходятся.
              onPressed: () => _startAddRelativeFlow(selectedTreeId),
              emphasized: true,
            ),
          ],
          if (!compact && !_isViewerOnly)
            _buildTreeToolbarIconButton(
              icon: _isSelectionMode
                  ? Icons.close_rounded
                  : Icons.check_box_outlined,
              tooltip: _isSelectionMode
                  ? 'Выйти из режима выбора'
                  : 'Выбрать несколько человек',
              emphasized: _isSelectionMode,
              onPressed: () {
                _updateSectionState(() {
                  _isSelectionMode = !_isSelectionMode;
                  if (!_isSelectionMode) {
                    _selectedPersonIds.clear();
                  } else if (_isEditMode) {
                    // Selection and edit fight over the same gesture
                    // (long-press / drag); switch atomically.
                    _isEditMode = false;
                    _selectedEditPersonId = null;
                  }
                });
              },
            ),
          // UX-T1.2 FR-c: «Расставить карточки» (репозиция) — вторичное
          // действие; на телефоне живёт в overflow «•••» (toggleEditMode),
          // на десктопе остаётся видимой кнопкой тулбара.
          if (!compact && !_isViewerOnly)
            _buildTreeToolbarIconButton(
              icon: _isEditMode ? Icons.visibility_outlined : Icons.open_with,
              tooltip:
                  _isEditMode ? 'Вернуться к просмотру' : 'Расставить карточки',
              onPressed: () {
                _updateSectionState(() {
                  _isEditMode = !_isEditMode;
                  if (!_isEditMode) {
                    _selectedEditPersonId = null;
                  } else if (_isSelectionMode) {
                    _isSelectionMode = false;
                    _selectedPersonIds.clear();
                  }
                });
              },
            ),
          // UX-T1.2 FR-b: раскрытие компактного хрома больше не прячется за
          // незаметным шевроном в тулбаре — на телефоне его заменил видимый
          // handle с подписью под тулбаром (см. _buildTreeChromeHandle).
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
            // Плотность, чанк 16: вертикальный паддинг на телефоне 8 → 3 —
            // карточка-тулбар вокруг больше не тянет ~54dp на один
            // информационный чип. Десктоп (compact:false) не трогаем.
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 3 : 9,
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

  List<PopupMenuEntry<_TreeToolbarAction>> _buildTreeToolbarMenuItems({
    bool isPhone = false,
  }) {
    final branchRootPerson = _findBranchRootPerson();
    final items = <PopupMenuEntry<_TreeToolbarAction>>[];

    // UX-T1.2 FR-c: на телефоне вторичные контролы (undo/redo/поиск/фильтры)
    // переехали из постоянных пилюль топ-бара сюда, в overflow «•••».
    // На десктопе они остаются видимыми пилюлями, поэтому здесь их не дублируем.
    if (isPhone) {
      if (GetIt.I.isRegistered<TreeMutationHistory>()) {
        final history = GetIt.I<TreeMutationHistory>();
        items.add(_buildTreeToolbarMenuItem(
          value: _TreeToolbarAction.undo,
          icon: Icons.undo_rounded,
          label: 'Отменить',
          enabled: history.canUndo,
        ));
        items.add(_buildTreeToolbarMenuItem(
          value: _TreeToolbarAction.redo,
          icon: Icons.redo_rounded,
          label: 'Повторить',
          enabled: history.canRedo,
        ));
      }
      if (_shouldShowSearchButton()) {
        items.add(_buildTreeToolbarMenuItem(
          value: _TreeToolbarAction.openSearch,
          icon: Icons.search_rounded,
          label: 'Поиск в расширенной сети',
        ));
      }
      if (_shouldShowFiltersButton()) {
        items.add(_buildTreeToolbarMenuItem(
          value: _TreeToolbarAction.openFilters,
          icon: Icons.tune_rounded,
          label: 'Фильтры расширенной сети',
        ));
      }
      if (items.isNotEmpty) {
        items.add(const PopupMenuDivider());
      }
    }

    items.addAll([
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
        value: _TreeToolbarAction.sendDiagnostics,
        icon: Icons.bug_report_outlined,
        label: 'Отправить диагностику дерева',
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
      if (!_isViewerOnly) ...[
        _buildTreeToolbarMenuItem(
          value: _TreeToolbarAction.toggleEditMode,
          icon: _isEditMode ? Icons.edit_off_outlined : Icons.edit_outlined,
          label: _isEditMode
              ? 'Выключить перемещение карточек'
              : 'Включить перемещение карточек',
        ),
        _buildTreeToolbarMenuItem(
          value: _TreeToolbarAction.toggleSelectionMode,
          icon: _isSelectionMode
              ? Icons.check_box_outlined
              : Icons.check_box_outline_blank,
          label: _isSelectionMode
              ? 'Выйти из режима выбора'
              : 'Выбрать несколько человек',
        ),
      ],
    ]);

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
    bool enabled = true,
  }) {
    return PopupMenuItem<_TreeToolbarAction>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }

  /// Bulk «Add to branch» action: opens a bottom sheet listing every
  /// other branch the user belongs to, lets them pick one, and then
  /// copies each selected person into that branch via the existing
  /// cross-tree create-person flow (one POST per person, each with
  /// `sourcePersonId` so the new card shares an `identityId` with
  /// the original — we get identity propagation across trees as a
  /// side-effect of copying).
  ///
  /// Failures fall through to a snackbar with a count of successes
  /// so the user knows what landed and what didn't. Selection is
  /// cleared on success only — partial failures keep the unfinished
  /// people selected so the user can retry.
}
