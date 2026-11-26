part of '../interactive_family_tree.dart';

extension _InteractiveTreeNodes on _InteractiveFamilyTreeState {
  List<Widget> _buildGenerationGuideWidgets({
    required double stackWidth,
  }) {
    if (nodePositions.isEmpty) {
      return const <Widget>[];
    }

    final levels = nodePositions.values
        .map((offset) => offset.dy)
        .toSet()
        .toList()
      ..sort();
    final peopleById = {
      for (final entry in widget.peopleData)
        (entry['person'] as FamilyPerson).id: entry['person'] as FamilyPerson,
    };
    final contentLeft = nodePositions.values
        .map((offset) => offset.dx - InteractiveFamilyTree.nodeWidth / 2)
        .reduce(min);
    // Anchor the gutter badge to the left edge of the reserved
    // strip. With contentInsetHorizontal at 200 the leftmost card
    // is at x=200 in canvas space, so a 188-wide badge that starts
    // at x=14 ends at x=202 with a 12px buffer to spare. If the
    // user manually drags a card further left, the badge clamps
    // its width via ConstrainedBox below so it still won't overlap.
    final labelLeft = max(
      14.0,
      contentLeft - InteractiveFamilyTree.generationGutterWidth + 12,
    );
    final badgeAvailableWidth = max(60.0, contentLeft - labelLeft - 12);
    final dividerLeft = min(
      labelLeft + InteractiveFamilyTree.generationGutterWidth - 16,
      stackWidth - 56,
    );
    final dividerWidth = max(0.0, stackWidth - dividerLeft - 32);
    final guides = <Widget>[];

    for (var index = 0; index < levels.length; index++) {
      final levelY = levels[index];
      // Lift the badge fully above the card row so even if the
      // card and badge happen to share a horizontal slice the
      // badge doesn't dip into the card area. nodeHeight/2 + 8
      // puts the badge bottom edge ~8px above the card top.
      final labelTop = max(
        8.0,
        levelY - InteractiveFamilyTree.nodeHeight / 2 - 44,
      );
      guides.add(
        Positioned(
          left: labelLeft,
          top: labelTop,
          child: IgnorePointer(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: badgeAvailableWidth),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: _GenerationGuideBadge(
                  title: _generationLabel(index, levels.length),
                  subtitle: _generationCohortLabel(
                    _peopleForGenerationLevel(
                      levelY: levelY,
                      peopleById: peopleById,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      if (index < levels.length - 1) {
        final nextLevelY = levels[index + 1];
        final dividerY = (levelY + nextLevelY) / 2;
        guides.add(
          Positioned(
            left: dividerLeft,
            top: dividerY,
            width: dividerWidth,
            child: IgnorePointer(
              child: Container(
                height: 1,
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.28),
              ),
            ),
          ),
        );
      }
    }

    return guides;
  }

  String _generationLabel(int index, int totalLevels) {
    if (totalLevels == 1) {
      return 'Центр дерева';
    }
    if (index == 0) {
      return 'Старшее поколение';
    }
    if (index == totalLevels - 1) {
      return 'Младшее поколение';
    }
    return 'Поколение ${index + 1}';
  }

  List<FamilyPerson> _peopleForGenerationLevel({
    required double levelY,
    required Map<String, FamilyPerson> peopleById,
  }) {
    return nodePositions.entries
        .where((entry) => (entry.value.dy - levelY).abs() < 0.1)
        .map((entry) => peopleById[entry.key])
        .whereType<FamilyPerson>()
        .toList(growable: false);
  }

  String? _generationCohortLabel(List<FamilyPerson> people) {
    final cohortLabels = people
        .map((person) => person.birthDate?.year)
        .whereType<int>()
        .map(_cohortLabelForBirthYear)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort(_compareCohortLabels);

    if (cohortLabels.isEmpty) {
      return null;
    }
    if (cohortLabels.length <= 2) {
      return cohortLabels.join(' / ');
    }
    return 'Смешанные поколения';
  }

  String? _cohortLabelForBirthYear(int year) {
    if (year <= 1927) {
      return 'Величайшее';
    }
    if (year <= 1945) {
      return 'Молчаливое';
    }
    if (year <= 1964) {
      return 'Бумеры';
    }
    if (year <= 1980) {
      return 'Поколение X';
    }
    if (year <= 1996) {
      return 'Миллениалы';
    }
    if (year <= 2012) {
      return 'Зумеры';
    }
    if (year <= 2028) {
      return 'Альфа';
    }
    return 'Бета';
  }

  int _compareCohortLabels(String left, String right) {
    const order = <String, int>{
      'Величайшее': 0,
      'Молчаливое': 1,
      'Бумеры': 2,
      'Поколение X': 3,
      'Миллениалы': 4,
      'Зумеры': 5,
      'Альфа': 6,
      'Бета': 7,
    };
    return (order[left] ?? 999).compareTo(order[right] ?? 999);
  }

  bool _supportsHoverNodeActions() {
    if (RendererBinding.instance.mouseTracker.mouseIsConnected) {
      return true;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  Widget _buildInlineEditPanel({
    required double stackWidth,
    required double stackHeight,
  }) {
    final selectedId = _selectedEditPersonId;
    if (selectedId == null) {
      return const SizedBox.shrink();
    }

    final position = nodePositions[selectedId];
    if (position == null) {
      return const SizedBox.shrink();
    }

    final person = widget.peopleData
        .map((entry) => entry['person'])
        .whereType<FamilyPerson>()
        .firstWhere(
          (candidate) => candidate.id == selectedId,
          orElse: () => FamilyPerson.empty,
        );
    if (person == FamilyPerson.empty) {
      return const SizedBox.shrink();
    }

    const panelWidth = 310.0;
    const panelHeight = 272.0;
    final preferredRight =
        position.dx + InteractiveFamilyTree.nodeWidth / 2 + 18;
    final preferredLeft =
        position.dx - InteractiveFamilyTree.nodeWidth / 2 - panelWidth - 18;
    final canPlaceRight = preferredRight + panelWidth <= stackWidth - 16;
    final canPlaceLeft = preferredLeft >= 16;

    late final double left;
    late final double top;
    if (canPlaceRight) {
      left = preferredRight;
      top = max(
        16.0,
        min(position.dy - panelHeight / 2, stackHeight - panelHeight - 16),
      );
    } else if (canPlaceLeft) {
      left = preferredLeft;
      top = max(
        16.0,
        min(position.dy - panelHeight / 2, stackHeight - panelHeight - 16),
      );
    } else {
      left = max(
        16.0,
        min(
          position.dx - panelWidth / 2,
          stackWidth - panelWidth - 16,
        ),
      );
      top = min(
        position.dy + InteractiveFamilyTree.nodeHeight / 2 + 14,
        stackHeight - panelHeight - 16,
      );
    }

    return Positioned(
      left: left,
      top: top,
      width: panelWidth,
      child: Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      person.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      _updateTreeState(() {
                        _selectedEditPersonId = null;
                      });
                    },
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close),
                    tooltip: 'Скрыть быстрые действия',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildInspectorStatusChip(
                    icon: Icons.photo_library_outlined,
                    label: person.photoGallery.isEmpty
                        ? 'Без фото'
                        : '${person.photoGallery.length} фото',
                  ),
                  _buildInspectorStatusChip(
                    icon: person.primaryPhotoUrl != null
                        ? Icons.star_outline
                        : Icons.image_not_supported_outlined,
                    label: person.primaryPhotoUrl != null
                        ? 'Основное фото есть'
                        : 'Основное фото не выбрано',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildInlineActionButton(
                    icon: Icons.north_outlined,
                    label: 'Родитель',
                    onTap: () => widget.onAddRelativeTapWithType(
                      person,
                      RelationType.parent,
                    ),
                  ),
                  _buildInlineActionButton(
                    icon: Icons.favorite_border,
                    label: 'Супруг',
                    onTap: () => widget.onAddRelativeTapWithType(
                      person,
                      RelationType.spouse,
                    ),
                  ),
                  _buildInlineActionButton(
                    icon: Icons.south_outlined,
                    label: 'Ребёнок',
                    onTap: () => widget.onAddRelativeTapWithType(
                      person,
                      RelationType.child,
                    ),
                  ),
                  _buildInlineActionButton(
                    icon: Icons.people_outline,
                    label: 'Сиблинг',
                    onTap: () => widget.onAddRelativeTapWithType(
                      person,
                      RelationType.sibling,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildInspectorQuickActionChip(
                    icon: Icons.open_in_new,
                    label: 'Карточка',
                    semanticsLabel: 'tree-inspector-open-card',
                    onTap: () => widget.onPersonTap(person),
                  ),
                  _buildInspectorQuickActionChip(
                    icon: Icons.photo_library_outlined,
                    label: person.photoGallery.isEmpty
                        ? 'Фото'
                        : 'Фото (${person.photoGallery.length})',
                    semanticsLabel: 'tree-inspector-open-gallery',
                    onTap: person.photoGallery.isEmpty
                        ? null
                        : () => _showPersonGalleryDialog(context, person),
                  ),
                  _buildInspectorQuickActionChip(
                    icon: Icons.history_outlined,
                    label: 'История',
                    semanticsLabel: 'tree-inspector-open-history',
                    onTap: widget.onOpenPersonHistory == null
                        ? null
                        : () => widget.onOpenPersonHistory!(person),
                  ),
                  _buildInspectorQuickActionChip(
                    icon: Icons.more_horiz,
                    label: 'Ещё',
                    semanticsLabel: 'tree-inspector-more-actions',
                    onTap: () => _showEditActionsSheet(context, person),
                  ),
                  if (!widget.currentUserIsInTree)
                    _buildInspectorQuickActionChip(
                      icon: Icons.person_add_alt_1,
                      label: 'Вписать себя',
                      semanticsLabel: 'tree-inspector-add-self',
                      onTap: () =>
                          _showAddSelfRelationTypeDialog(context, person),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ActionChip(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      avatar: Icon(
        icon,
        size: 16,
        color: theme.colorScheme.primary,
      ),
      label: Text(label),
      side: BorderSide(color: theme.colorScheme.outlineVariant),
      backgroundColor:
          theme.colorScheme.secondaryContainer.withValues(alpha: 0.55),
      padding: const EdgeInsets.symmetric(horizontal: 6),
    );
  }

  Widget _buildInspectorQuickActionChip({
    required IconData icon,
    required String label,
    String? semanticsLabel,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return Semantics(
      label: semanticsLabel,
      button: true,
      enabled: onTap != null,
      child: ActionChip(
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        avatar: Icon(icon, size: 16),
        label: Text(label),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        backgroundColor:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.82),
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
    );
  }

  Widget _buildInspectorStatusChip({
    required IconData icon,
    required String label,
  }) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(label),
    );
  }

  void _showPersonGalleryDialog(BuildContext context, FamilyPerson person) {
    final gallery = person.photoGallery;
    if (gallery.isEmpty) {
      return;
    }

    final pageController = PageController();
    var currentIndex = 0;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final media = gallery[currentIndex];
            final caption = media['caption']?.toString();

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              backgroundColor: Colors.black,
              child: SizedBox(
                width: 520,
                height: 520,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              media['isPrimary'] == true
                                  ? 'Основное фото'
                                  : 'Фото родственника',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Закрыть галерею',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: pageController,
                        itemCount: gallery.length,
                        onPageChanged: (index) {
                          setDialogState(() {
                            currentIndex = index;
                          });
                        },
                        itemBuilder: (context, index) {
                          final itemUrl =
                              gallery[index]['url']?.toString() ?? '';
                          final normalizedItemUrl = normalizePhotoUrl(itemUrl);
                          return InteractiveViewer(
                            child: normalizedItemUrl == null
                                ? const Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.white,
                                      size: 40,
                                    ),
                                  )
                                : CachedNetworkImage(
                                    imageUrl: normalizedItemUrl,
                                    fit: BoxFit.contain,
                                    placeholder: (context, url) => const Center(
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                      ),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        const Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: Colors.white,
                                        size: 40,
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        children: [
                          Text(
                            '${currentIndex + 1} из ${gallery.length}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          if (caption != null && caption.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              caption,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<TreeGraphWarning> _sortedGraphWarnings(
    Iterable<TreeGraphWarning> warnings,
  ) {
    final items = warnings.toList();
    items.sort((left, right) {
      final severityComparison = _graphWarningPriority(right.severity)
          .compareTo(_graphWarningPriority(left.severity));
      if (severityComparison != 0) {
        return severityComparison;
      }
      return left.message.compareTo(right.message);
    });
    return items;
  }

  int _graphWarningPriority(String? severity) {
    switch ((severity ?? '').trim().toLowerCase()) {
      case 'error':
        return 3;
      case 'warning':
        return 2;
      case 'info':
        return 1;
      default:
        return 0;
    }
  }

  String _graphWarningTitle(TreeGraphWarning warning) {
    switch (warning.code) {
      case 'multiple_primary_parent_sets':
        return 'Несколько основных родителей';
      case 'auto_repaired_parent_link':
        return 'Связь достроена автоматически';
      case 'conflicting_direct_links':
        return 'Конфликт прямых связей';
      default:
        return 'Нужна проверка дерева';
    }
  }

  Color _graphWarningAccent(TreeGraphWarning warning) {
    final colorScheme = Theme.of(context).colorScheme;
    switch ((warning.severity).trim().toLowerCase()) {
      case 'error':
        return colorScheme.error;
      case 'info':
        return colorScheme.primary;
      default:
        return colorScheme.tertiary;
    }
  }

  IconData _graphWarningIcon(TreeGraphWarning warning) {
    switch ((warning.severity).trim().toLowerCase()) {
      case 'error':
        return Icons.error_outline_rounded;
      case 'info':
        return Icons.info_outline_rounded;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  Widget _buildGraphWarningCard(
    TreeGraphWarning warning, {
    bool compact = false,
  }) {
    final accent = _graphWarningAccent(warning);
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(compact ? 14 : 16),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _graphWarningIcon(warning),
            size: compact ? 18 : 20,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _graphWarningTitle(warning),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  warning.message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.3,
                        color: colorScheme.onSurface,
                      ),
                ),
                if (warning.hint != null &&
                    warning.hint!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    warning.hint!.trim(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.3,
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _hasAdditionalParentSets(String personId) {
    final snapshot = widget.graphSnapshot;
    if (snapshot == null) {
      return false;
    }
    return snapshot.parentFamilyUnitsForChild(personId).any(
          (unit) => unit.isPrimaryParentSet == false,
        );
  }

  void _showPersonInsightSheet(
    BuildContext context,
    FamilyPerson person, {
    required List<TreeGraphWarning> warnings,
    TreeGraphViewerDescriptor? viewerDescriptor,
  }) {
    final relationPathEnabled = widget.onShowRelationPath != null;
    final otherParentsEnabled = widget.onShowOtherParents != null &&
        _hasAdditionalParentSets(person.id);
    final fixRelationsEnabled = widget.onFixPersonRelations != null;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.86,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    person.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    warnings.isEmpty
                        ? 'Здесь собраны быстрые инструменты по этой ветке.'
                        : 'Проверьте предупреждения и при необходимости откройте нужный инструмент.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (viewerDescriptor?.primaryRelationLabel
                              ?.trim()
                              .isNotEmpty ==
                          true)
                        _buildInspectorStatusChip(
                          icon: viewerDescriptor!.isBlood
                              ? Icons.family_restroom
                              : Icons.handshake_outlined,
                          label: viewerDescriptor.primaryRelationLabel!.trim(),
                        ),
                      _buildInspectorStatusChip(
                        icon: warnings.isEmpty
                            ? Icons.task_alt_outlined
                            : Icons.warning_amber_rounded,
                        label: warnings.isEmpty
                            ? 'Без конфликтов'
                            : warnings.length == 1
                                ? '1 предупреждение'
                                : '${warnings.length} предупреждения',
                      ),
                    ],
                  ),
                  if (warnings.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      'Предупреждения',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    ...warnings.map(
                      (warning) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildGraphWarningCard(warning, compact: true),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Быстрые действия',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _buildEditActionTile(
                    sheetContext: sheetContext,
                    icon: Icons.person_add_alt_1_outlined,
                    title: 'Добавить родственника',
                    semanticsLabel: 'tree-sheet-open-add-relative',
                    subtitle: 'Сразу привязать нового человека к этой карточке',
                    onTap: () => _showQuickAddRelativeSheet(context, person),
                  ),
                  if (relationPathEnabled)
                    _buildEditActionTile(
                      sheetContext: sheetContext,
                      icon: Icons.route_outlined,
                      title: 'Путь родства',
                      semanticsLabel: 'tree-sheet-open-relation-path',
                      subtitle: 'Показать цепочку людей между вами',
                      onTap: () => widget.onShowRelationPath!(person),
                    ),
                  if (otherParentsEnabled)
                    _buildEditActionTile(
                      sheetContext: sheetContext,
                      icon: Icons.account_tree_outlined,
                      title: 'Другие родители',
                      semanticsLabel: 'tree-sheet-open-other-parents',
                      subtitle: 'Проверить альтернативные наборы родителей',
                      onTap: () => widget.onShowOtherParents!(person),
                    ),
                  if (fixRelationsEnabled)
                    _buildEditActionTile(
                      sheetContext: sheetContext,
                      icon: Icons.hub_outlined,
                      title: 'Исправить связи',
                      semanticsLabel: 'tree-sheet-open-fix-relations',
                      subtitle: 'Открыть редактор прямых связей',
                      onTap: () => widget.onFixPersonRelations!(person),
                    ),
                  _buildEditActionTile(
                    sheetContext: sheetContext,
                    icon: Icons.open_in_new,
                    title: 'Открыть карточку',
                    semanticsLabel: 'tree-sheet-open-card',
                    subtitle: 'Полная карточка, заметки и история',
                    onTap: () => widget.onPersonTap(person),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showQuickAddRelativeSheet(BuildContext context, FamilyPerson person) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Добавить к карточке',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Новый человек будет сразу привязан к ${person.name}.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 12),
                _buildEditActionTile(
                  sheetContext: sheetContext,
                  icon: Icons.arrow_upward,
                  title: 'Добавить родителя',
                  semanticsLabel: 'tree-sheet-add-parent',
                  onTap: () => widget.onAddRelativeTapWithType(
                      person, RelationType.parent),
                ),
                _buildEditActionTile(
                  sheetContext: sheetContext,
                  icon: Icons.favorite_border,
                  title: 'Добавить супруга или партнёра',
                  semanticsLabel: 'tree-sheet-add-partner',
                  onTap: () => widget.onAddRelativeTapWithType(
                      person, RelationType.spouse),
                ),
                _buildEditActionTile(
                  sheetContext: sheetContext,
                  icon: Icons.arrow_downward,
                  title: 'Добавить ребёнка',
                  semanticsLabel: 'tree-sheet-add-child',
                  onTap: () => widget.onAddRelativeTapWithType(
                      person, RelationType.child),
                ),
                _buildEditActionTile(
                  sheetContext: sheetContext,
                  icon: Icons.people_outline,
                  title: 'Добавить брата или сестру',
                  semanticsLabel: 'tree-sheet-add-sibling',
                  onTap: () => widget.onAddRelativeTapWithType(
                    person,
                    RelationType.sibling,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildPersonWidgets() {
    final nodeDataByPersonId = <String, Map<String, dynamic>>{
      for (final data in widget.peopleData)
        (data['person'] as FamilyPerson).id: data,
    };
    final warningCache = <String, List<TreeGraphWarning>>{};

    // K (culling): drop person-node subtrees whose card is fully outside the
    // viewport + ~1-viewport margin so 100+-node trees stay smooth on pan/zoom.
    // Render-only — the edge / guide / active-path / lasso CustomPaint layers
    // read the FULL nodePositions map and are untouched, so nothing visual
    // disappears; only which Positioned card widgets are emitted changes.
    final visible = _visibleSceneRect();
    Rect? cullRect;
    if (visible != null) {
      cullRect = visible.inflate(max(visible.width, visible.height));
    }
    _lastCulledRect = cullRect;
    final forceBuild = <String>{};
    void pin(String? id) {
      final trimmed = id?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        forceBuild.add(trimmed);
      }
    }

    // Never cull a node that focus / recenter / fit / edit might target, so
    // those actions never point at an unbuilt node even for one frame.
    pin(_findCurrentUserNodeId());
    pin(widget.selectedPersonId);
    pin(_selectedEditPersonId);
    pin(widget.branchRootPersonId);
    pin(widget.recenterOnPersonId);

    return nodePositions.entries.where((entry) {
      if (cullRect == null || forceBuild.contains(entry.key)) {
        return true;
      }
      final cardRect = Rect.fromCenter(
        center: entry.value,
        width: InteractiveFamilyTree.nodeWidth,
        height: InteractiveFamilyTree.nodeHeight,
      );
      return cullRect.overlaps(cardRect);
    }).map((entry) {
      final personId = entry.key;
      final position = entry.value;
      final nodeData = nodeDataByPersonId[personId];

      if (nodeData == null) return const SizedBox.shrink();

      final topLeftX = position.dx - InteractiveFamilyTree.nodeWidth / 2;
      final topLeftY = position.dy - InteractiveFamilyTree.nodeHeight / 2;
      final personWarnings = warningCache.putIfAbsent(
        personId,
        () => _sortedGraphWarnings(
          widget.graphSnapshot?.warningsForPerson(personId) ??
              const <TreeGraphWarning>[],
        ),
      );

      return Positioned(
        key: ValueKey<String>('tree-node-position-$personId'),
        left: topLeftX,
        top: topLeftY,
        width: InteractiveFamilyTree.nodeWidth,
        child: _buildPersonNode(
          nodeData,
          personWarnings: personWarnings,
        ),
      );
    }).toList();
  }

  Widget _buildPersonNode(
    Map<String, dynamic> nodeData, {
    required List<TreeGraphWarning> personWarnings,
  }) {
    final FamilyPerson person = nodeData['person'];
    final UserProfile? userProfile = nodeData['userProfile'];
    final TreeGraphViewerDescriptor? viewerDescriptor =
        nodeData['viewerDescriptor'] as TreeGraphViewerDescriptor?;

    final String displayName = userProfile != null
        ? '${userProfile.firstName} ${userProfile.lastName}'.trim()
        : person.name;
    final String? displayPhotoUrl = userProfile?.photoURL ?? person.photoUrl;
    final Gender displayGender = person.gender;
    final isCurrentUserNode =
        widget.currentUserId != null && person.userId == widget.currentUserId;
    final isSelectedPerson = widget.selectedPersonId == person.id;
    final isSelectedInEditMode =
        widget.isEditMode && _selectedEditPersonId == person.id;
    final isDraggingNode = _draggingPersonId == person.id;
    final supportsHoverActions = _supportsHoverNodeActions();
    final isHoveredNode = !widget.isEditMode && _hoveredPersonId == person.id;
    // Backend gives us role labels from the viewer's perspective
    // ("Мать"/"Дядя"/"Двоюродная сестра"). We just normalize them
    // for the pill — folding "Мать"→"Мама" and similar — and skip
    // the pill entirely on the current-user node (it already shows
    // a "Это вы" chip). The "Ваш/Ваша" pronoun used to live here
    // but felt redundant on every card and ate horizontal space
    // for long roles; the whole tree is rooted in the viewer so
    // the bare role is unambiguous.
    final relationChipLabel = viewerDescriptor?.primaryRelationLabel == null ||
            viewerDescriptor!.primaryRelationLabel!.trim().isEmpty ||
            isCurrentUserNode
        ? null
        : _normalizeRelationLabel(
              viewerDescriptor.primaryRelationLabel!.trim(),
            ) +
            (viewerDescriptor.alternatePathCount > 0
                ? ' +${viewerDescriptor.alternatePathCount}'
                : '');
    final prefersTouchQuickAdd = !supportsHoverActions && !widget.isEditMode;
    final canUseLongPressQuickAdd = prefersTouchQuickAdd;

    // Reference design states for the card:
    // - deceased = saturate-down + † overlay on avatar
    // - pending  = warm dot on avatar (no userId linked yet)
    // - dimmed   = a different node is selected and this one is not on the
    //              active path → fade to ~32% so the path stands out
    final isDeceasedPerson =
        person.deathDate != null || person.isAlive == false;
    final isPendingPerson =
        (person.userId == null || person.userId!.isEmpty) && !isDeceasedPerson;
    final hasActivePath = widget.selectedPersonId != null;
    final isOnActivePath =
        hasActivePath && (_activePathPersonIds?.contains(person.id) ?? false);
    final isDimmed = hasActivePath && !isOnActivePath && !isSelectedPerson;

    final cardContent = FamilyTreeNodeCard(
      key: ValueKey<String>('tree-node-${person.id}'),
      displayName: displayName,
      lifeDates: _getLifeDates(person),
      displayGender: displayGender,
      displayPhotoUrl: displayPhotoUrl,
      relationChipLabel: relationChipLabel,
      isBloodRelation: viewerDescriptor?.isBlood == true,
      isCurrentUserNode: isCurrentUserNode,
      isSelectedInEditMode: isSelectedInEditMode || isSelectedPerson,
      isDraggingNode: isDraggingNode,
      isHovered: isHoveredNode,
      isDeceased: isDeceasedPerson,
      isPending: isPendingPerson,
      isDimmed: isDimmed,
      // Phase 4 chunk 3b: foreign tint signal. _isPersonForeign
      // returns false когда `_isExtendedRenderActive` (flag/mode/
      // slice gates) → legacy bit-identical.
      isForeignNode: _isPersonForeign(person.id),
    );

    // Edge-first connector is enabled when (a) the host wired the
    // onConnectExistingPersons callback (the public read-only viewer
    // does NOT) AND (b) we're not in edit mode (where long-press is
    // already used to drag cards into manual positions).
    final connectorEnabled = widget.onConnectExistingPersons != null &&
        !widget.isEditMode &&
        !widget.selectionMode;
    final isConnectHoverTarget = connectorEnabled &&
        _connectingHoverTargetId == person.id &&
        _connectingFromPersonId != person.id;
    final isConnectSource =
        connectorEnabled && _connectingFromPersonId == person.id;

    // Selection-mode visual: accent ring + check badge when the
    // card is in the host's `selectedPersonIds`. Drawn over the
    // base card so it's visible regardless of selected/dimmed/
    // deceased states. The ring is intentionally chunky (3px,
    // primary-color) so it reads from a panned-out canvas where
    // the card is shrunk by the InteractiveViewer transform.
    final isMultiSelected =
        widget.selectionMode && widget.selectedPersonIds.contains(person.id);
    // Live lasso preview — while the user is dragging the
    // rectangle, every card the rect overlaps gets a softer
    // dashed-look ring so they can see what'll be added on
    // release. We treat already-selected cards the same as the
    // committed-selection state so the ring doesn't double up.
    final isLassoPreview = widget.selectionMode &&
        _lassoPreviewIds.contains(person.id) &&
        !isMultiSelected;

    // Card with optional "drop-target glow" for connector hover state.
    final cardWithConnectAffordance = Stack(
      clipBehavior: Clip.none,
      children: [
        cardContent,
        // Selection-mode ring around the whole card.
        if (isMultiSelected)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                ),
              ),
            ),
          ),
        // Lasso-preview ring — softer than the committed-select
        // ring (1.6px, 65% alpha) so the user can see the
        // difference between "definitely picked, won't change"
        // (multi-select) and "currently inside lasso, will be
        // added on release" (preview).
        if (isLassoPreview)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.65),
                    width: 1.6,
                  ),
                ),
              ),
            ),
          ),
        // Selection check badge in the top-right corner.
        if (isMultiSelected)
          Positioned(
            top: -6,
            right: -6,
            child: IgnorePointer(
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        // Glow ring shown when another card is being dragged onto
        // this one during edge-first connection.
        if (isConnectHoverTarget)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.35),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );

    // Selection mode owns tap + suppresses long-press / double-tap
    // (which would either open the inspector or start connector
    // creation — both confusing during multi-select). Tap toggles
    // membership in the host's selection set; the visual ring is
    // drawn in the layered card builder above.
    final inSelectionMode =
        widget.selectionMode && widget.onPersonSelectionToggle != null;

    final tapAndDoubleTapDetector = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: widget.isEditMode && !inSelectionMode
          ? (_) {
              HapticFeedback.mediumImpact();
              _handleNodeDragStart(person);
            }
          : null,
      onLongPressMoveUpdate: widget.isEditMode && !inSelectionMode
          ? (details) => _handleNodeDragUpdate(
                person,
                details.offsetFromOrigin,
              )
          : null,
      onLongPressEnd: widget.isEditMode && !inSelectionMode
          ? (_) => _handleNodeDragEnd()
          : null,
      onTap: () {
        if (inSelectionMode) {
          HapticFeedback.selectionClick();
          widget.onPersonSelectionToggle!(person);
          return;
        }
        if (widget.isEditMode) {
          _selectEditPerson(person);
          return;
        }
        // Phase 4 chunk 4a: foreign node intercept ПЕРЕД legacy.
        // Order: selection > edit > foreign-sheet > legacy. Edit
        // mode wins over foreign (per A reasoning — foreign carды
        // нельзя edit без grants, но если user в edit mode явно
        // — он сам разберётся).
        if (_isPersonForeign(person.id) && widget.onForeignNodeTap != null) {
          widget.onForeignNodeTap!(person);
          return;
        }
        widget.onPersonTap(person);
      },
      onDoubleTap: widget.isEditMode ||
              widget.onPersonDoubleTap == null ||
              inSelectionMode
          ? null
          : () => widget.onPersonDoubleTap!(person),
      // Legacy long-press → quick-add bottom sheet. Suppressed when
      // the connector is enabled (the LongPressDraggable below
      // takes that gesture for drag-to-connect instead) or in
      // selection mode (tap-to-toggle owns the gesture).
      onLongPress: widget.isEditMode ||
              !canUseLongPressQuickAdd ||
              connectorEnabled ||
              inSelectionMode
          ? null
          : () => _showQuickAddRelativeSheet(context, person),
      child: cardWithConnectAffordance,
    );

    final cardInteractionLayer = connectorEnabled
        ? DragTarget<String>(
            onWillAcceptWithDetails: (details) =>
                // Don't accept self-drops — would create A↔A relations.
                details.data != person.id,
            onMove: (_) => _setHoverTargetForConnect(person.id),
            onLeave: (_) => _clearHoverTargetIfMatches(person.id),
            onAcceptWithDetails: (details) =>
                _completeConnection(details.data, person.id),
            builder: (context, candidates, rejected) {
              return LongPressDraggable<String>(
                data: person.id,
                // Slightly tighter than Flutter's 500 ms default — feels
                // immediate to the user without firing on accidental
                // taps. Matches the Material LongPress recognizer's
                // recommended haptic-confirmation window.
                delay: const Duration(milliseconds: 320),
                onDragStarted: () => _startConnecting(person.id),
                onDragEnd: (details) {
                  // The DragTarget.onAccept path drives _completeConnection
                  // which eventually clears state via _cancelConnecting.
                  // If we reach DragEnd without a drop having been
                  // accepted (released over empty canvas), tear down
                  // here so the preview line doesn't get stuck.
                  if (_isConnecting && !_showingRelationPicker) {
                    _cancelConnecting();
                  }
                },
                feedback: Material(
                  color: Colors.transparent,
                  // We deliberately DO NOT use the full
                  // FamilyTreeNodeCard as feedback — the card has a
                  // flexible internal Column that doesn't survive
                  // the Overlay's unbounded constraints (overflows
                  // vertically). A small named pill is plenty —
                  // the actual source card pulses at its origin
                  // and the dashed preview line connects them.
                  child: _ConnectorDragFeedbackChip(
                    label: displayName,
                    color: Theme.of(context).colorScheme.primary,
                    foreground: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.35,
                  child: tapAndDoubleTapDetector,
                ),
                child: tapAndDoubleTapDetector,
              );
            },
          )
        : tapAndDoubleTapDetector;

    return MouseRegion(
      onEnter: widget.isEditMode
          ? null
          : (_) => _updateTreeState(() => _hoveredPersonId = person.id),
      onExit: widget.isEditMode
          ? null
          : (_) {
              if (_hoveredPersonId == person.id) {
                _updateTreeState(() => _hoveredPersonId = null);
              }
            },
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Subtle source-card pulse so the user remembers WHERE the
          // drag started while their finger is mid-flight elsewhere.
          if (isConnectSource)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                      style: BorderStyle.solid,
                    ),
                  ),
                ),
              ),
            ),
          cardInteractionLayer,
          // Phase 1.2 voltage-indicator: 💡 dot on the top-LEFT of
          // any card the matcher found cross-tree duplicate
          // candidates for. Position deliberately distinct from
          // the "+" badge on top-RIGHT so they don't compete.
          // Visible on hover/select (parity with the existing "+"
          // badge), and ALWAYS visible when the count is high.
          if (!widget.isEditMode &&
              (widget.identitySuggestionCounts?[person.id] ?? 0) > 0)
            Positioned(
              top: 8,
              left: 8,
              child: _IdentitySuggestionsBadge(
                count: widget.identitySuggestionCounts![person.id]!,
                onTap: () => widget.onShowIdentitySuggestions?.call(person.id),
              ),
            ),
          // Phase 1.3 edit-time conflict surfacing: ⚠️ dot on the
          // bottom-RIGHT (deliberately opposite the 💡 badge so
          // both can coexist on a card without overlapping).
          // Always visible — unlike 💡 this is "your data is
          // diverging, please review" rather than a passive hint,
          // and hiding it would defeat the point.
          if (!widget.isEditMode &&
              (widget.identityConflictCounts?[person.id] ?? 0) > 0)
            Positioned(
              bottom: 8,
              right: 8,
              child: _IdentityConflictsBadge(
                count: widget.identityConflictCounts![person.id]!,
                onTap: () => widget.onShowIdentityConflicts?.call(person.id),
              ),
            ),
          // Show the "+" quick-add badge on hover (desktop) AND on the
          // currently-selected node (so mobile users with no hover can
          // still trigger the add-relative sheet without going through
          // the bottom sheet's Связь tab).
          if (!widget.isEditMode && (isHoveredNode || isSelectedPerson))
            Positioned(
              top: 8,
              right: 8,
              child: Tooltip(
                message: 'Добавить родственника',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key:
                        ValueKey<String>('tree-node-add-relative-${person.id}'),
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _showQuickAddRelativeSheet(context, person),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOut,
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surface
                            .withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context)
                                .colorScheme
                                .shadow
                                .withValues(alpha: 0.12),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.add,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (widget.isEditMode)
            Positioned(
              top: -8,
              right: -8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelectedInEditMode
                      ? Theme.of(context).colorScheme.secondary
                      : Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: (isSelectedInEditMode
                              ? Theme.of(context).colorScheme.secondary
                              : Theme.of(context).colorScheme.primary)
                          .withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isDraggingNode
                          ? Icons.open_with
                          : isSelectedInEditMode
                              ? Icons.check
                              : Icons.touch_app_outlined,
                      size: 12,
                      color: isDraggingNode
                          ? Theme.of(context).colorScheme.onPrimary
                          : isSelectedInEditMode
                              ? Theme.of(context).colorScheme.onSecondary
                              : Theme.of(context).colorScheme.onPrimary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isDraggingNode
                          ? 'Тяните'
                          : isSelectedInEditMode
                              ? 'Выбрано'
                              : 'Зажмите',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: isDraggingNode
                            ? Theme.of(context).colorScheme.onPrimary
                            : isSelectedInEditMode
                                ? Theme.of(context).colorScheme.onSecondary
                                : Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!widget.isEditMode && personWarnings.isNotEmpty)
            Positioned(
              top: -10,
              right: -10,
              child: Tooltip(
                message: personWarnings.length == 1
                    ? 'Есть предупреждение'
                    : 'Есть предупреждения',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: ValueKey<String>('tree-warning-badge-${person.id}'),
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _showPersonInsightSheet(
                      context,
                      person,
                      warnings: personWarnings,
                      viewerDescriptor: viewerDescriptor,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: _graphWarningAccent(personWarnings.first),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: _graphWarningAccent(personWarnings.first)
                                .withValues(alpha: 0.22),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _graphWarningIcon(personWarnings.first),
                            size: 14,
                            color: Colors.white,
                          ),
                          if (personWarnings.length > 1) ...[
                            const SizedBox(width: 4),
                            Text(
                              '${personWarnings.length}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showEditActionsSheet(BuildContext context, FamilyPerson person) {
    final hasGallery = person.photoGallery.isNotEmpty;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Выберите действие для этого человека.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildInspectorStatusChip(
                        icon: Icons.photo_library_outlined,
                        label: hasGallery
                            ? '${person.photoGallery.length} фото'
                            : 'Без фото',
                      ),
                      _buildInspectorStatusChip(
                        icon: person.primaryPhotoUrl != null
                            ? Icons.star_outline
                            : Icons.image_not_supported_outlined,
                        label: person.primaryPhotoUrl != null
                            ? 'Основное фото есть'
                            : 'Основное фото не выбрано',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Быстрые переходы',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _buildEditActionTile(
                    sheetContext: sheetContext,
                    icon: Icons.open_in_new,
                    title: 'Открыть профиль',
                    semanticsLabel: 'tree-sheet-open-card',
                    subtitle: 'Полная карточка, связи и заметки',
                    onTap: () => widget.onPersonTap(person),
                  ),
                  _buildEditActionTile(
                    sheetContext: sheetContext,
                    icon: Icons.photo_library_outlined,
                    title: hasGallery ? 'Открыть фото' : 'Перейти к фото',
                    semanticsLabel: 'tree-sheet-open-gallery',
                    subtitle: hasGallery
                        ? 'В галерее ${person.photoGallery.length} фото'
                        : 'Откройте карточку и добавьте фото',
                    onTap: hasGallery
                        ? () => _showPersonGalleryDialog(context, person)
                        : () => widget.onPersonTap(person),
                  ),
                  if (widget.onOpenPersonHistory != null)
                    _buildEditActionTile(
                      sheetContext: sheetContext,
                      icon: Icons.history_outlined,
                      title: 'История изменений',
                      semanticsLabel: 'tree-sheet-open-history',
                      subtitle: 'Журнал правок этой карточки',
                      onTap: () => widget.onOpenPersonHistory!(person),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Добавить связь',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _buildEditActionTile(
                    sheetContext: sheetContext,
                    icon: Icons.arrow_upward,
                    title: 'Добавить родителя',
                    onTap: () => widget.onAddRelativeTapWithType(
                        person, RelationType.parent),
                  ),
                  _buildEditActionTile(
                    sheetContext: sheetContext,
                    icon: Icons.favorite_border,
                    title: 'Добавить супруга или партнёра',
                    onTap: () => widget.onAddRelativeTapWithType(
                        person, RelationType.spouse),
                  ),
                  _buildEditActionTile(
                    sheetContext: sheetContext,
                    icon: Icons.arrow_downward,
                    title: 'Добавить ребёнка',
                    onTap: () => widget.onAddRelativeTapWithType(
                        person, RelationType.child),
                  ),
                  _buildEditActionTile(
                    sheetContext: sheetContext,
                    icon: Icons.people_outline,
                    title: 'Добавить брата или сестру',
                    onTap: () => widget.onAddRelativeTapWithType(
                      person,
                      RelationType.sibling,
                    ),
                  ),
                  if (!widget.currentUserIsInTree)
                    _buildEditActionTile(
                      sheetContext: sheetContext,
                      icon: Icons.person_add_alt_1,
                      title: 'Добавить себя в это дерево',
                      onTap: () =>
                          _showAddSelfRelationTypeDialog(context, person),
                    ),
                  // F2: о connect-жесте никто не знал — однострочная
                  // подсказка там, где пользователь уже думает о связях.
                  if (widget.onConnectExistingPersons != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      key: const Key('tree-sheet-connect-hint'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.touch_app_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Связать с человеком, который уже есть на дереве, — нажмите на карточку и подержите.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      height: 1.3,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditActionTile({
    required BuildContext sheetContext,
    required IconData icon,
    required String title,
    String? semanticsLabel,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return Semantics(
      label: semanticsLabel,
      button: true,
      enabled: onTap != null,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        enabled: onTap != null,
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        onTap: onTap == null
            ? null
            : () {
                Navigator.of(sheetContext).pop();
                onTap();
              },
      ),
    );
  }

  void _showAddSelfRelationTypeDialog(
    BuildContext context,
    FamilyPerson targetPerson,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Добавить себя как...'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: RelationType.values
                  .where(
                (type) =>
                    /* type != RelationType.unknown && */ type !=
                        RelationType.other &&
                    // <<< Дополнительный фильтр: Убираем слишком далекие/сложные связи для этого диалога >>>
                    ![
                      RelationType.greatGrandparent,
                      RelationType.greatGrandchild,
                      RelationType.cousin,
                      RelationType.parentInLaw,
                      RelationType.childInLaw,
                      RelationType.siblingInLaw,
                      RelationType.stepparent,
                      RelationType.stepchild,
                      RelationType.inlaw,
                      RelationType.ex_spouse,
                      RelationType.ex_partner,
                      RelationType.friend,
                      RelationType.colleague,
                    ].contains(type),
              ) // Фильтруем ненужные и сложные
                  .map((type) {
                // Определяем текст кнопки на основе типа связи
                String buttonText =
                    'Как ${FamilyRelation.getGenericRelationTypeStringRu(type).toLowerCase()}';
                IconData iconData = Icons.person; // Иконка по умолчанию
                switch (type) {
                  case RelationType.parent:
                    iconData = Icons.arrow_upward;
                    break;
                  case RelationType.child:
                    iconData = Icons.arrow_downward;
                    break;
                  case RelationType.spouse:
                    iconData = Icons.favorite;
                    break;
                  case RelationType.sibling:
                    iconData = Icons.people;
                    break;
                  default:
                    break;
                }

                return ListTile(
                  leading: Icon(iconData),
                  title: Text(buttonText),
                  onTap: () {
                    Navigator.of(dialogContext).pop(); // Закрываем диалог
                    // <<< ИСПРАВЛЕНИЕ: Вызываем коллбэк с ЗЕРКАЛЬНЫМ типом связи >>>
                    // Передаем отношение ОТ targetPerson К новому пользователю
                    widget.onAddSelfTapWithType(
                      targetPerson,
                      FamilyRelation.getMirrorRelation(type),
                    );
                  },
                );
              }).toList(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Отмена'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  String _getLifeDates(FamilyPerson person) {
    final birthYear = person.birthDate?.year;
    final deathYear = person.deathDate?.year;

    if (birthYear == null && person.isAlive) {
      return 'Годы не указаны';
    }
    if (birthYear == null && deathYear != null) {
      return 'ум. $deathYear';
    }
    if (birthYear != null && person.isAlive) {
      return '$birthYear - н.в.';
    }
    if (birthYear != null && deathYear == null) {
      return '$birthYear - ?';
    }
    return '${birthYear ?? '?'} - ${deathYear ?? '?'}';
  }
}
