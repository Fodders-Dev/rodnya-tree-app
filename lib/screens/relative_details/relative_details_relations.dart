part of '../relative_details_screen.dart';

extension _RelativeDetailsRelations on _RelativeDetailsScreenState {
  Future<void> _showOtherParentsSheet() async {
    if (_person == null) {
      return;
    }
    final units = _parentFamilyUnitsForCurrentPerson();
    if (units.isEmpty || !mounted) {
      return;
    }

    final peopleById = {
      for (final person in (_graphSnapshot?.people ?? _treePeople))
        person.id: person,
    };

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Другие родители',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Здесь показаны все родительские наборы для этой карточки. На основном полотне дерево использует основной набор, остальные раскрываются здесь.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[700],
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 16),
                ...units.map((unit) {
                  final adultNames = unit.adultIds
                      .map((personId) =>
                          peopleById[personId]?.displayName ?? personId)
                      .toList();
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          adultNames.isEmpty
                              ? 'Родители не указаны'
                              : adultNames.join(' • '),
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          unit.label,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[700],
                                  ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildPathInfoChip(
                              icon: unit.isPrimaryParentSet
                                  ? Icons.star_outline
                                  : Icons.layers_outlined,
                              label: unit.isPrimaryParentSet
                                  ? 'Основной набор'
                                  : 'Дополнительный набор',
                            ),
                            if (_normalizeOptionalText(unit.parentSetType) !=
                                null)
                              _buildPathInfoChip(
                                icon: Icons.family_restroom_outlined,
                                label: FamilyRelation.getParentSetTypeLabel(
                                  unit.parentSetType,
                                ),
                              ),
                            if (_normalizeOptionalText(unit.unionType) != null)
                              _buildPathInfoChip(
                                icon: Icons.favorite_border,
                                label: FamilyRelation.getUnionTypeLabel(
                                    unit.unionType),
                              ),
                            if (_normalizeOptionalText(unit.unionStatus) !=
                                null)
                              _buildPathInfoChip(
                                icon: Icons.schedule_outlined,
                                label: FamilyRelation.getUnionStatusLabel(
                                    unit.unionStatus),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showRelationPathSheet() async {
    if (_currentTreeId == null ||
        _person == null ||
        _graphTreeService == null) {
      return;
    }

    final descriptor =
        _viewerDescriptor ?? _graphSnapshot?.findViewerDescriptor(_person!.id);
    final pathPersonIds = (descriptor?.primaryPathPersonIds.isNotEmpty ?? false)
        ? descriptor!.primaryPathPersonIds
        : await _graphTreeService!.getRelationPath(
            treeId: _currentTreeId!,
            targetPersonId: _person!.id,
          );
    final peopleById = {
      for (final person in (_graphSnapshot?.people ?? _treePeople))
        person.id: person,
    };

    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Путь родства',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_normalizeOptionalText(
                            descriptor?.primaryRelationLabel) !=
                        null)
                      _buildPathInfoChip(
                        icon: Icons.badge_outlined,
                        label: descriptor!.primaryRelationLabel!.trim(),
                      ),
                    if (descriptor != null)
                      _buildPathInfoChip(
                        icon: descriptor.isBlood
                            ? Icons.favorite_outline
                            : Icons.link_outlined,
                        label: descriptor.isBlood
                            ? 'Кровная связь'
                            : 'Родство по браку',
                      ),
                    if (pathPersonIds.isNotEmpty)
                      _buildPathInfoChip(
                        icon: Icons.stairs_outlined,
                        label: 'Шагов: ${pathPersonIds.length - 1}',
                      ),
                    if ((descriptor?.alternatePathCount ?? 0) > 0)
                      _buildPathInfoChip(
                        icon: Icons.alt_route_outlined,
                        label: 'Еще путей: ${descriptor!.alternatePathCount}',
                      ),
                  ],
                ),
                if (_normalizeOptionalText(descriptor?.pathSummary) !=
                    null) ...[
                  const SizedBox(height: 12),
                  Text(
                    descriptor!.pathSummary!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[700],
                          height: 1.35,
                        ),
                  ),
                ],
                const SizedBox(height: 16),
                if (pathPersonIds.isEmpty)
                  const Text(
                    'Backend пока не вернул путь родства для этого человека.',
                  )
                else
                  ...List<Widget>.generate(pathPersonIds.length, (index) {
                    final personId = pathPersonIds[index];
                    final person = peopleById[personId];
                    final isViewer = personId ==
                        (_graphSnapshot?.viewerPersonId ??
                            _currentUserPersonId);
                    final isTarget = personId == _person!.id;
                    final widgets = <Widget>[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 16,
                              child: Text('${index + 1}'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    person?.displayName ?? personId,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  if (isViewer || isTarget) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (isViewer)
                                          _buildPathInfoChip(
                                            icon: Icons.person_outline,
                                            label: 'Это вы',
                                          ),
                                        if (isTarget)
                                          _buildPathInfoChip(
                                            icon: Icons.adjust_outlined,
                                            label: 'Выбранный человек',
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ];
                    if (index < pathPersonIds.length - 1) {
                      final nextPersonId = pathPersonIds[index + 1];
                      final relation =
                          _findDirectRelation(personId, nextPersonId);
                      final relationContext = relation == null
                          ? null
                          : _describeRelationContext(relation);
                      widgets.add(
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(
                                width: 32,
                                child: Center(
                                  child: Icon(Icons.south, size: 18),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _buildPathStepLabel(
                                        fromPersonId: personId,
                                        toPersonId: nextPersonId,
                                        peopleById: peopleById,
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                    if (relationContext != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        relationContext,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: Colors.grey[700]),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: widgets,
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _disconnectRelation(_EditableRelationLink link) async {
    if (_currentTreeId == null || _graphTreeService == null) {
      return;
    }
    // Снапшот связи ДО удаления — нужен для undo (восстановить с
    // теми же person'ами и типом).
    final relationSnapshot = link.relation;
    await _graphTreeService!.disconnectRelation(
      treeId: _currentTreeId!,
      relationId: link.relation.id,
    );
    if (GetIt.I.isRegistered<TreeMutationHistory>()) {
      GetIt.I<TreeMutationHistory>().recordRelationDeleted(
        treeId: _currentTreeId!,
        deleted: relationSnapshot,
      );
    }
    if (!mounted) {
      return;
    }
    await _loadData();
  }

  Future<void> _changeRelationType(
    _EditableRelationLink link,
    RelationType relationType,
  ) async {
    if (_currentTreeId == null ||
        _graphTreeService == null ||
        _person == null) {
      return;
    }
    CustomRelationLabels? customLabels;
    if (relationType == RelationType.other) {
      customLabels = await showCustomRelationLabelDialog(
        context: context,
        person1Name: link.relatedPerson.displayName,
        person2Name: _person!.displayName,
        person1Gender: link.relatedPerson.gender,
        person2Gender: _person!.gender,
        initialRelation1to2: link.relation.customLabelToPerson(_person!.id),
        initialRelation2to1: link.relation.customLabelFromPerson(_person!.id),
      );
      if (customLabels == null) {
        return;
      }
    }
    await _graphTreeService!.setRelationType(
      treeId: _currentTreeId!,
      anchorPerson: _person!,
      targetPerson: link.relatedPerson,
      relationType: FamilyRelation.relationTypeToString(relationType),
      customRelationLabel1to2: customLabels?.relation1to2,
      customRelationLabel2to1: customLabels?.relation2to1,
    );
    if (!mounted) {
      return;
    }
    await _loadData();
  }

  Future<void> _showRelationManagementSheet() async {
    final links = _buildEditableRelationLinks();
    final warnings = _graphWarningsForRelationManagement(links);
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Исправить связи',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                if (warnings.isNotEmpty) ...[
                  ...warnings.map(
                    (warning) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildGraphWarningCard(warning, compact: true),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                if (links.isEmpty)
                  const Text(
                      'У этого человека пока нет прямых связей для редактирования.')
                else
                  ...links.map((link) {
                    final relationLabel =
                        link.relation.customLabelToPerson(_person!.id) ??
                            FamilyRelation.getRelationName(
                              link.relationFromRelatedPerson,
                              link.relatedPerson.gender,
                            );
                    final relationContext =
                        _describeRelationContext(link.relation);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(link.relatedPerson.displayName),
                      subtitle: relationContext == null
                          ? Text(relationLabel)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(relationLabel),
                                const SizedBox(height: 2),
                                Text(
                                  relationContext,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.grey[700]),
                                ),
                              ],
                            ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PopupMenuButton<RelationType>(
                            tooltip: 'Сменить тип родства',
                            onSelected: (value) async {
                              Navigator.of(context).pop();
                              await _changeRelationType(link, value);
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: RelationType.parent,
                                child: Text('Родитель'),
                              ),
                              PopupMenuItem(
                                value: RelationType.child,
                                child: Text('Ребенок'),
                              ),
                              PopupMenuItem(
                                value: RelationType.sibling,
                                child: Text('Брат / сестра'),
                              ),
                              PopupMenuItem(
                                value: RelationType.spouse,
                                child: Text('Супруг'),
                              ),
                              PopupMenuItem(
                                value: RelationType.partner,
                                child: Text('Партнер'),
                              ),
                              PopupMenuItem(
                                value: RelationType.other,
                                child: Text('Другое...'),
                              ),
                            ],
                            icon: const Icon(Icons.swap_horiz_outlined),
                          ),
                          IconButton(
                            tooltip: 'Разорвать связь',
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await _disconnectRelation(link);
                            },
                            icon: const Icon(Icons.link_off_outlined),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRelationToolsSection() {
    final personWarnings = _graphWarningsForCurrentPerson();
    return _buildInfoSection('Связи и родство', [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Проверка работает поверх нового графа дерева: можно посмотреть цепочку родства и быстро исправить прямые связи.',
              style: TextStyle(
                color: Colors.grey[800],
                height: 1.35,
              ),
            ),
            if (personWarnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...personWarnings.map(
                (warning) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildGraphWarningCard(warning),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_person != null && _currentTreeId != null)
                  FilledButton.icon(
                    onPressed: _showQuickAddRelativeSheet,
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                    label: const Text('Добавить родственника'),
                  ),
                if (_person!.id != _currentUserPersonId)
                  FilledButton.tonalIcon(
                    onPressed: _showRelationPathSheet,
                    icon: const Icon(Icons.route_outlined, size: 18),
                    label: const Text('Путь родства'),
                  ),
                if (_hasAdditionalParentSets())
                  OutlinedButton.icon(
                    onPressed: _showOtherParentsSheet,
                    icon: const Icon(Icons.account_tree_outlined, size: 18),
                    label: const Text('Другие родители'),
                  ),
                if (_canEditOrDelete())
                  OutlinedButton.icon(
                    onPressed: _showRelationManagementSheet,
                    icon: const Icon(Icons.hub_outlined, size: 18),
                    label: const Text('Исправить связи'),
                  ),
              ],
            ),
          ],
        ),
      ),
    ]);
  }

  String? _getDirectRelationLabel() {
    final exactViewerLabel = _viewerRelationLabel?.trim();
    if (exactViewerLabel != null && exactViewerLabel.isNotEmpty) {
      return exactViewerLabel;
    }
    if (_person == null ||
        _relationToCurrentUser == null ||
        _relationToCurrentUser == RelationType.other) {
      return null;
    }

    final relationRelativeToUser = FamilyRelation.getMirrorRelation(
      _relationToCurrentUser!,
    );
    return FamilyRelation.getRelationName(
      relationRelativeToUser,
      _person!.gender,
    );
  }

  List<_EditableRelationLink> _buildEditableRelationLinks() {
    if (_person == null) {
      return const <_EditableRelationLink>[];
    }

    final peopleById = {for (final person in _treePeople) person.id: person};
    final links = <_EditableRelationLink>[];
    for (final relation in _relations) {
      late final String relatedPersonId;
      late final RelationType relationFromRelatedPerson;
      if (relation.person1Id == _person!.id) {
        relatedPersonId = relation.person2Id;
        relationFromRelatedPerson = relation.relation2to1;
      } else if (relation.person2Id == _person!.id) {
        relatedPersonId = relation.person1Id;
        relationFromRelatedPerson = relation.relation1to2;
      } else {
        continue;
      }

      final relatedPerson = peopleById[relatedPersonId];
      if (relatedPerson == null) {
        continue;
      }
      links.add(
        _EditableRelationLink(
          relation: relation,
          relatedPerson: relatedPerson,
          relationFromRelatedPerson: relationFromRelatedPerson,
        ),
      );
    }
    return links;
  }

  List<TreeGraphFamilyUnit> _parentFamilyUnitsForCurrentPerson() {
    if (_person == null || _graphSnapshot == null) {
      return const <TreeGraphFamilyUnit>[];
    }
    return _graphSnapshot!.parentFamilyUnitsForChild(_person!.id);
  }

  bool _hasAdditionalParentSets() {
    final units = _parentFamilyUnitsForCurrentPerson();
    if (units.length > 1) {
      return true;
    }
    return units.any((unit) => unit.isPrimaryParentSet == false);
  }

  List<TreeGraphWarning> _graphWarningsForCurrentPerson() {
    if (_person == null || _graphSnapshot == null) {
      return const <TreeGraphWarning>[];
    }
    return _sortedGraphWarnings(_graphSnapshot!.warningsForPerson(_person!.id));
  }

  List<TreeGraphWarning> _graphWarningsForRelationManagement(
    List<_EditableRelationLink> links,
  ) {
    final snapshot = _graphSnapshot;
    if (snapshot == null) {
      return _graphWarningsForCurrentPerson();
    }

    final warningsById = <String, TreeGraphWarning>{
      for (final warning in _graphWarningsForCurrentPerson())
        warning.id: warning,
    };
    for (final link in links) {
      for (final warning in snapshot.warningsForRelation(link.relation.id)) {
        warningsById[warning.id] = warning;
      }
    }
    return _sortedGraphWarnings(warningsById.values);
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
        return 'Проверка дерева';
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accent.withValues(alpha: 0.24),
        ),
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
                        height: 1.35,
                        color: colorScheme.onSurface,
                      ),
                ),
                if (warning.hint != null &&
                    warning.hint!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    warning.hint!.trim(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.35,
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

  String? _describeRelationContext(FamilyRelation relation) {
    final parts = <String>[];
    final normalizedParentSetType =
        _normalizeOptionalText(relation.parentSetType);
    if (normalizedParentSetType != null) {
      var label = FamilyRelation.getParentSetTypeLabel(normalizedParentSetType);
      if (relation.isPrimaryParentSet == false) {
        label = '$label, дополнительный набор родителей';
      }
      parts.add(label);
    }

    final unionParts = <String>[];
    final normalizedUnionType = _normalizeOptionalText(relation.unionType);
    if (normalizedUnionType != null) {
      unionParts.add(FamilyRelation.getUnionTypeLabel(normalizedUnionType));
    }
    final normalizedUnionStatus = _normalizeOptionalText(relation.unionStatus);
    if (normalizedUnionStatus != null) {
      unionParts.add(FamilyRelation.getUnionStatusLabel(normalizedUnionStatus));
    }
    if (unionParts.isNotEmpty) {
      parts.add(unionParts.join(' • '));
    }

    return parts.isEmpty ? null : parts.join(' • ');
  }

  String _buildPathStepLabel({
    required String fromPersonId,
    required String toPersonId,
    required Map<String, FamilyPerson> peopleById,
  }) {
    final relation = _findDirectRelation(fromPersonId, toPersonId);
    if (relation == null) {
      return 'Связь';
    }
    final customLabel = relation.customLabelFromPerson(fromPersonId);
    if (customLabel != null) {
      return customLabel;
    }
    final relationType = relation.relationFromPerson(fromPersonId);
    if (relationType == null) {
      return 'Связь';
    }
    return FamilyRelation.getRelationName(
      relationType,
      peopleById[toPersonId]?.gender,
    );
  }

  Widget _buildPathInfoChip({
    required IconData icon,
    required String label,
  }) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(label),
    );
  }

  // _buildStatusChip used to render a contact-status chip in the
  // PersonDossierView header area. The new redesign hero card surfaces
  // the same information through `relBadge` + the status text rendered
  // directly under the hero — the chip helper is no longer needed.

  // Viewer §3.1 «## Семья»: read-first family section — serif heading,
  // the direct relatives (each tappable → their card) with relation
  // labels, and a «🌳 Открыть в дереве» button. Reuses _buildDirectFamilyRows.
  Widget _buildFamilySection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Семья',
          key: const Key('family-section-title'),
          style: AppTheme.serif(
            color: theme.colorScheme.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),
        ..._buildDirectFamilyRows(),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('family-open-tree'),
            onPressed: _currentTreeId == null ? null : _openInTree,
            icon: const Icon(Icons.account_tree_outlined, size: 18),
            label: const Text('Открыть в дереве'),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildDirectFamilyRows() {
    if (_person == null) {
      return const [];
    }

    final peopleById = {for (final person in _treePeople) person.id: person};
    final rows = <Widget>[];

    for (final relation in _relations) {
      late final String relatedPersonId;
      late final RelationType relationFromRelatedPerson;

      if (relation.person1Id == _person!.id) {
        relatedPersonId = relation.person2Id;
        relationFromRelatedPerson = relation.relation2to1;
      } else if (relation.person2Id == _person!.id) {
        relatedPersonId = relation.person1Id;
        relationFromRelatedPerson = relation.relation1to2;
      } else {
        continue;
      }

      final relatedPerson = peopleById[relatedPersonId];
      if (relatedPerson == null) {
        continue;
      }

      rows.add(
        InkWell(
          onTap: () => context.push(
            relativeDetailsRoute(relatedPerson.id, treeId: _currentTreeId),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    relatedPerson.displayName,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  relation.customLabelToPerson(_person!.id) ??
                      FamilyRelation.getRelationName(
                        relationFromRelatedPerson,
                        relatedPerson.gender,
                      ),
                  style: TextStyle(color: Colors.grey[700]),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      );
    }

    return rows;
  }
}
