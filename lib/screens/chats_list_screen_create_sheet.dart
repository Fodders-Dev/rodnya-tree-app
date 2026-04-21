part of 'chats_list_screen.dart';

class _CreateChatDraft {
  const _CreateChatDraft({
    required this.mode,
    this.participantIds = const <String>[],
    this.branchRootPersonIds = const <String>[],
    this.branchRootNames = const <String>[],
    this.directUserId,
    this.directUserName,
    this.title,
  });

  final _ChatComposerMode mode;
  final List<String> participantIds;
  final List<String> branchRootPersonIds;
  final List<String> branchRootNames;
  final String? directUserId;
  final String? directUserName;
  final String? title;
}

class _GroupChatParticipant {
  const _GroupChatParticipant({
    required this.userId,
    required this.name,
    required this.photoUrl,
    required this.relationLabel,
  });

  final String userId;
  final String name;
  final String? photoUrl;
  final String relationLabel;
}

class _BranchChatCandidate {
  const _BranchChatCandidate({
    required this.personId,
    required this.name,
    required this.photoUrl,
    required this.relationLabel,
    required this.linkedParticipantIds,
  });

  final String personId;
  final String name;
  final String? photoUrl;
  final String relationLabel;
  final Set<String> linkedParticipantIds;

  int get linkedParticipantCount => linkedParticipantIds.length;
}

class _CreateChatSheet extends StatefulWidget {
  const _CreateChatSheet({
    required this.treeId,
    required this.currentUserId,
  });

  final String treeId;
  final String currentUserId;

  @override
  State<_CreateChatSheet> createState() => _CreateChatSheetState();
}

class _CreateChatSheetState extends State<_CreateChatSheet> {
  final FamilyTreeServiceInterface _familyTreeService =
      GetIt.I<FamilyTreeServiceInterface>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedUserIds = <String>{};
  final Set<String> _selectedBranchRootIds = <String>{};

  _ChatComposerMode _mode = _ChatComposerMode.direct;

  bool _isLoading = true;
  String? _errorMessage;
  List<_GroupChatParticipant> _participants = const <_GroupChatParticipant>[];
  List<_BranchChatCandidate> _branchCandidates = const <_BranchChatCandidate>[];

  @override
  void initState() {
    super.initState();
    _loadParticipants();
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // DefaultTabController handles state, but we might want to listen to it
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _titleController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadParticipants() async {
    try {
      final results = await Future.wait([
        _familyTreeService.getRelatives(widget.treeId),
        _familyTreeService.getRelations(widget.treeId),
      ]);
      final relatives = results[0] as List<FamilyPerson>;
      final relations = results[1] as List<FamilyRelation>;
      final participantsByUserId = <String, _GroupChatParticipant>{};

      for (final relative in relatives) {
        final userId = relative.userId;
        if (userId == null ||
            userId.isEmpty ||
            userId == widget.currentUserId ||
            participantsByUserId.containsKey(userId)) {
          continue;
        }

        participantsByUserId[userId] = _GroupChatParticipant(
          userId: userId,
          name:
              relative.name.trim().isNotEmpty ? relative.name : 'Пользователь',
          photoUrl: relative.photoUrl,
          relationLabel: _relationLabel(relative),
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _participants = participantsByUserId.values.toList()
          ..sort((left, right) => left.name.compareTo(right.name));
        _branchCandidates = _buildBranchCandidates(relatives, relations);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Не удалось загрузить участников дерева.';
        _isLoading = false;
      });
    }
  }

  String _relationLabel(FamilyPerson person) {
    final relation = (person.relation ?? '').trim();
    return relation.isNotEmpty ? relation : 'Родственник';
  }

  List<_BranchChatCandidate> _buildBranchCandidates(
    List<FamilyPerson> relatives,
    List<FamilyRelation> relations,
  ) {
    final candidates = relatives.map((person) {
      final linkedUserIds = _buildLinkedBranchParticipantIds(
        branchRootPersonId: person.id,
        relatives: relatives,
        relations: relations,
      );
      linkedUserIds.remove(widget.currentUserId);

      return _BranchChatCandidate(
        personId: person.id,
        name: person.name.trim().isNotEmpty ? person.name : 'Без имени',
        photoUrl: person.photoUrl,
        relationLabel: _relationLabel(person),
        linkedParticipantIds: linkedUserIds,
      );
    }).toList()
      ..sort((left, right) {
        final availability = right.linkedParticipantCount.compareTo(
          left.linkedParticipantCount,
        );
        if (availability != 0) {
          return availability;
        }
        return left.name.compareTo(right.name);
      });
    return candidates;
  }

  Set<String> _buildLinkedBranchParticipantIds({
    required String branchRootPersonId,
    required List<FamilyPerson> relatives,
    required List<FamilyRelation> relations,
  }) {
    final visibleIds = _buildBranchVisiblePersonIds(
      branchRootPersonId: branchRootPersonId,
      relatives: relatives,
      relations: relations,
    );
    final linkedUserIds = <String>{};
    for (final person in relatives) {
      if (!visibleIds.contains(person.id)) {
        continue;
      }
      final linkedUserId = person.userId?.trim();
      if (linkedUserId != null && linkedUserId.isNotEmpty) {
        linkedUserIds.add(linkedUserId);
      }
    }
    return linkedUserIds;
  }

  Set<String> _buildBranchVisiblePersonIds({
    required String branchRootPersonId,
    required List<FamilyPerson> relatives,
    required List<FamilyRelation> relations,
  }) {
    final personIds = relatives.map((person) => person.id).toSet();
    if (!personIds.contains(branchRootPersonId)) {
      return personIds;
    }

    final childrenByParent = <String, Set<String>>{};
    final spousesByPerson = <String, Set<String>>{};
    for (final relation in relations) {
      final parentId = _parentIdFromRelation(relation);
      final childId = _childIdFromRelation(relation);
      if (parentId != null && childId != null) {
        childrenByParent.putIfAbsent(parentId, () => <String>{}).add(childId);
      }
      if (_isSpouseRelation(relation)) {
        spousesByPerson
            .putIfAbsent(relation.person1Id, () => <String>{})
            .add(relation.person2Id);
        spousesByPerson
            .putIfAbsent(relation.person2Id, () => <String>{})
            .add(relation.person1Id);
      }
    }

    final visibleIds = <String>{branchRootPersonId};
    final queue = <String>[branchRootPersonId];
    while (queue.isNotEmpty) {
      final currentId = queue.removeAt(0);
      for (final spouseId in spousesByPerson[currentId] ?? const <String>{}) {
        if (visibleIds.add(spouseId)) {
          queue.add(spouseId);
        }
      }
      for (final childId in childrenByParent[currentId] ?? const <String>{}) {
        if (visibleIds.add(childId)) {
          queue.add(childId);
        }
      }
    }

    return visibleIds;
  }

  bool _isSpouseRelation(FamilyRelation relation) {
    return relation.relation1to2 == RelationType.spouse ||
        relation.relation2to1 == RelationType.spouse ||
        relation.relation1to2 == RelationType.partner ||
        relation.relation2to1 == RelationType.partner ||
        relation.relation1to2 == RelationType.ex_spouse ||
        relation.relation2to1 == RelationType.ex_spouse ||
        relation.relation1to2 == RelationType.ex_partner ||
        relation.relation2to1 == RelationType.ex_partner;
  }

  String? _parentIdFromRelation(FamilyRelation relation) {
    if (relation.relation1to2 == RelationType.parent ||
        relation.relation2to1 == RelationType.child) {
      return relation.person1Id;
    }
    if (relation.relation2to1 == RelationType.parent ||
        relation.relation1to2 == RelationType.child) {
      return relation.person2Id;
    }
    return null;
  }

  String? _childIdFromRelation(FamilyRelation relation) {
    if (relation.relation1to2 == RelationType.child ||
        relation.relation2to1 == RelationType.parent) {
      return relation.person1Id;
    }
    if (relation.relation2to1 == RelationType.child ||
        relation.relation1to2 == RelationType.parent) {
      return relation.person2Id;
    }
    return null;
  }

  Set<String> _selectedBranchParticipantIds() {
    final linkedUserIds = <String>{};
    for (final candidate in _branchCandidates) {
      if (_selectedBranchRootIds.contains(candidate.personId)) {
        linkedUserIds.addAll(candidate.linkedParticipantIds);
      }
    }
    return linkedUserIds;
  }

  bool get _canSubmitDirect => _selectedUserIds.length == 1;

  bool get _canSubmitGroup => _selectedUserIds.length >= 2;

  bool get _canSubmitBranch =>
      _selectedBranchRootIds.isNotEmpty &&
      _selectedBranchParticipantIds().isNotEmpty;

  bool get _canSubmitSingleBranch =>
      _selectedBranchRootIds.length == 1 &&
      _selectedBranchParticipantIds().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFriendsTree =
        context.read<TreeProvider>().selectedTreeKind == TreeKind.friends;
    final search = _searchController.text.trim().toLowerCase();
    final filteredParticipants = _participants.where((participant) {
      if (search.isEmpty) {
        return true;
      }
      return participant.name.toLowerCase().contains(search) ||
          participant.relationLabel.toLowerCase().contains(search);
    }).toList();
    final filteredBranches = _branchCandidates.where((candidate) {
      if (search.isEmpty) {
        return true;
      }
      return candidate.name.toLowerCase().contains(search) ||
          candidate.relationLabel.toLowerCase().contains(search);
    }).toList();

    return DefaultTabController(
      length: 4,
      initialIndex: _mode.index,
      child: Builder(
        builder: (context) {
          final tabController = DefaultTabController.of(context);
          tabController.addListener(() {
            if (tabController.indexIsChanging) {
              setState(() {
                _mode = _ChatComposerMode.values[tabController.index];
              });
            }
          });

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SizedBox(
                height: 620,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Новый чат',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                          style: IconButton.styleFrom(
                            backgroundColor: theme
                                .colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GlassPanel(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      child: TabBar(
                        dividerColor: Colors.transparent,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: theme.colorScheme.primary,
                        ),
                        labelColor: theme.colorScheme.onPrimary,
                        unselectedLabelColor:
                            theme.colorScheme.onSurfaceVariant,
                        labelStyle: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                        tabs: const [
                          Tab(text: 'Личный'),
                          Tab(text: 'Группа'),
                          Tab(text: 'Ветка'),
                          Tab(text: 'Ветки'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildComposerPill(
                          icon: isFriendsTree
                              ? Icons.diversity_3_outlined
                              : Icons.account_tree_outlined,
                          label:
                              context.read<TreeProvider>().selectedTreeName ??
                                  (isFriendsTree ? 'Круг' : 'Дерево'),
                        ),
                        _buildComposerPill(
                          icon: Icons.people_outline,
                          label: _selectionStatusLabel,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    GlassPanel(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search, size: 20),
                          hintText: _mode == _ChatComposerMode.direct ||
                                  _mode == _ChatComposerMode.group
                              ? (isFriendsTree
                                  ? 'Найти человека'
                                  : 'Найти родственника')
                              : 'Найти ветку',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_mode != _ChatComposerMode.direct) ...[
                      GlassPanel(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: TextField(
                          controller: _titleController,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: _mode == _ChatComposerMode.group
                                ? (isFriendsTree
                                    ? 'Название группы'
                                    : 'Название семьи')
                                : 'Название',
                            prefixIcon: const Icon(Icons.title, size: 20),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _errorMessage != null
                              ? Center(
                                  child: Text(
                                    _errorMessage!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: theme.colorScheme.error),
                                  ),
                                )
                              : TabBarView(
                                  physics: const NeverScrollableScrollPhysics(),
                                  children: [
                                    _buildParticipantSelector(
                                        filteredParticipants,
                                        multi: false),
                                    _buildParticipantSelector(
                                        filteredParticipants,
                                        multi: true),
                                    _buildBranchSelector(filteredBranches,
                                        multi: false),
                                    _buildBranchSelector(filteredBranches,
                                        multi: true),
                                  ],
                                ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed:
                            _canSubmitCurrentMode ? _submitCurrentMode : null,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: Icon(_submitIcon),
                        label: Text(_submitLabel),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  bool get _canSubmitCurrentMode {
    switch (_mode) {
      case _ChatComposerMode.direct:
        return _canSubmitDirect;
      case _ChatComposerMode.group:
        return _canSubmitGroup;
      case _ChatComposerMode.branch:
        return _canSubmitSingleBranch;
      case _ChatComposerMode.branches:
        return _canSubmitBranch;
    }
  }

  void _submitCurrentMode() {
    switch (_mode) {
      case _ChatComposerMode.direct:
        _submitDirectDraft();
        break;
      case _ChatComposerMode.group:
        _submitGroupDraft();
        break;
      case _ChatComposerMode.branch:
        _submitSingleBranchDraft();
        break;
      case _ChatComposerMode.branches:
        _submitBranchDraft();
        break;
    }
  }

  IconData get _submitIcon {
    switch (_mode) {
      case _ChatComposerMode.direct:
        return Icons.chat_bubble_outline;
      case _ChatComposerMode.group:
        return Icons.groups_2_outlined;
      case _ChatComposerMode.branch:
      case _ChatComposerMode.branches:
        return Icons.account_tree_outlined;
    }
  }

  String get _submitLabel {
    switch (_mode) {
      case _ChatComposerMode.direct:
        return _canSubmitDirect ? 'Открыть чат' : 'Выберите собеседника';
      case _ChatComposerMode.group:
        return _canSubmitGroup ? 'Создать группу' : 'Выберите участников';
      case _ChatComposerMode.branch:
        return _canSubmitSingleBranch ? 'Открыть чат ветки' : 'Выберите ветку';
      case _ChatComposerMode.branches:
        return _canSubmitBranch ? 'Открыть чат веток' : 'Выберите ветки';
    }
  }

  String get _selectionStatusLabel {
    switch (_mode) {
      case _ChatComposerMode.direct:
        return _selectedUserIds.isEmpty ? '1 собеседник' : 'Собеседник выбран';
      case _ChatComposerMode.group:
        return _selectedUserIds.isEmpty
            ? 'Выберите участников'
            : _countLabel(
                _selectedUserIds.length,
                one: 'участник',
                few: 'участника',
                many: 'участников',
              );
      case _ChatComposerMode.branch:
      case _ChatComposerMode.branches:
        return _selectedBranchRootIds.isEmpty
            ? 'Выберите ветки'
            : _countLabel(
                _selectedBranchRootIds.length,
                one: 'ветка',
                few: 'ветки',
                many: 'веток',
              );
    }
  }

  Widget _buildComposerPill({
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.65,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParticipantSelector(List<_GroupChatParticipant> participants,
      {required bool multi}) {
    if (participants.isEmpty) {
      return Center(
        child: GlassPanel(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_search_outlined,
                size: 36,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 10),
              Text(
                context.read<TreeProvider>().selectedTreeKind ==
                        TreeKind.friends
                    ? 'Людей пока нет'
                    : 'Родных пока нет',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Нужен аккаунт в дереве.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: participants.length,
      itemBuilder: (context, index) {
        final participant = participants[index];
        final isSelected = _selectedUserIds.contains(participant.userId);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassPanel(
            padding: EdgeInsets.zero,
            child: ListTile(
              onTap: () {
                setState(() {
                  if (!multi) {
                    _selectedUserIds
                      ..clear()
                      ..add(participant.userId);
                    return;
                  }
                  if (isSelected) {
                    _selectedUserIds.remove(participant.userId);
                  } else {
                    _selectedUserIds.add(participant.userId);
                  }
                });
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              leading: CircleAvatar(
                radius: 20,
                backgroundImage: participant.photoUrl != null &&
                        participant.photoUrl!.isNotEmpty
                    ? NetworkImage(participant.photoUrl!)
                    : null,
                child: participant.photoUrl == null ||
                        participant.photoUrl!.isEmpty
                    ? Text(
                        participant.name.isNotEmpty
                            ? participant.name[0].toUpperCase()
                            : '?',
                      )
                    : null,
              ),
              title: Text(
                participant.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(participant.relationLabel),
              trailing: multi
                  ? Checkbox(
                      value: isSelected,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedUserIds.add(participant.userId);
                          } else {
                            _selectedUserIds.remove(participant.userId);
                          }
                        });
                      },
                    )
                  : (isSelected
                      ? Icon(
                          Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBranchSelector(List<_BranchChatCandidate> candidates,
      {required bool multi}) {
    if (candidates.isEmpty) {
      return Center(
        child: GlassPanel(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_tree_outlined,
                size: 36,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 10),
              Text(
                'Веток пока нет',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: candidates.length,
      itemBuilder: (context, index) {
        final candidate = candidates[index];
        final isSelected = _selectedBranchRootIds.contains(candidate.personId);
        final linkedCount = candidate.linkedParticipantCount;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassPanel(
            padding: EdgeInsets.zero,
            child: ListTile(
              onTap: () {
                setState(() {
                  if (!multi) {
                    _selectedBranchRootIds
                      ..clear()
                      ..add(candidate.personId);
                    return;
                  }
                  if (isSelected) {
                    _selectedBranchRootIds.remove(candidate.personId);
                  } else {
                    _selectedBranchRootIds.add(candidate.personId);
                  }
                });
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              leading: CircleAvatar(
                radius: 20,
                backgroundImage:
                    candidate.photoUrl != null && candidate.photoUrl!.isNotEmpty
                        ? NetworkImage(candidate.photoUrl!)
                        : null,
                child: candidate.photoUrl == null || candidate.photoUrl!.isEmpty
                    ? Text(
                        candidate.name.isNotEmpty
                            ? candidate.name[0].toUpperCase()
                            : '?',
                      )
                    : null,
              ),
              title: Text(
                candidate.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                linkedCount > 0
                    ? '${candidate.relationLabel} · $linkedCount ${_participantLabel(linkedCount)}'
                    : '${candidate.relationLabel} · Пока пусто',
              ),
              trailing: multi
                  ? Checkbox(
                      value: isSelected,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedBranchRootIds.add(candidate.personId);
                          } else {
                            _selectedBranchRootIds.remove(candidate.personId);
                          }
                        });
                      },
                    )
                  : (isSelected
                      ? Icon(
                          Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null),
            ),
          ),
        );
      },
    );
  }

  String _participantLabel(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) {
      return 'участник';
    }
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'участника';
    }
    return 'участников';
  }

  void _submitDirectDraft() {
    final participant = _participants.firstWhere(
      (entry) => _selectedUserIds.contains(entry.userId),
    );
    Navigator.of(context).pop(
      _CreateChatDraft(
        mode: _ChatComposerMode.direct,
        directUserId: participant.userId,
        directUserName: participant.name,
      ),
    );
  }

  void _submitGroupDraft() {
    Navigator.of(context).pop(
      _CreateChatDraft(
        mode: _ChatComposerMode.group,
        participantIds: _selectedUserIds.toList(),
        title: _titleController.text.trim(),
      ),
    );
  }

  void _submitSingleBranchDraft() {
    final selectedCandidate = _branchCandidates.firstWhere(
      (candidate) => _selectedBranchRootIds.contains(candidate.personId),
    );
    Navigator.of(context).pop(
      _CreateChatDraft(
        mode: _ChatComposerMode.branch,
        branchRootPersonIds: [selectedCandidate.personId],
        branchRootNames: [selectedCandidate.name],
        title: _titleController.text.trim(),
      ),
    );
  }

  void _submitBranchDraft() {
    final selectedCandidates = _branchCandidates
        .where(
            (candidate) => _selectedBranchRootIds.contains(candidate.personId))
        .toList()
      ..sort((left, right) => left.name.compareTo(right.name));
    Navigator.of(context).pop(
      _CreateChatDraft(
        mode: _ChatComposerMode.branch,
        branchRootPersonIds:
            selectedCandidates.map((candidate) => candidate.personId).toList(),
        branchRootNames:
            selectedCandidates.map((candidate) => candidate.name).toList(),
        title: _titleController.text.trim(),
      ),
    );
  }
}
