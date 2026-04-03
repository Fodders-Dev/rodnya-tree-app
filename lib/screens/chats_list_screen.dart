import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/chat_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../models/chat_preview.dart';
import '../models/family_person.dart';
import '../models/family_relation.dart';
import '../providers/tree_provider.dart';

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  final ChatServiceInterface _chatService = GetIt.I<ChatServiceInterface>();
  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();

  StreamSubscription<List<ChatPreview>>? _chatsSubscription;
  List<ChatPreview> _chatPreviews = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  @override
  void dispose() {
    _chatsSubscription?.cancel();
    super.dispose();
  }

  void _loadChats() {
    final currentUserId = _authService.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Пользователь не авторизован.';
      });
      return;
    }

    _chatsSubscription?.cancel();
    _chatsSubscription = _chatService.getUserChatsStream(currentUserId).listen(
      (chatPreviews) {
        if (!mounted) {
          return;
        }
        setState(() {
          _chatPreviews = chatPreviews;
          _isLoading = false;
          _errorMessage = null;
        });
      },
      onError: (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isLoading = false;
          _errorMessage = 'Не удалось загрузить чаты.';
        });
      },
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate =
        DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (messageDate == today) {
      return DateFormat.Hm('ru').format(timestamp);
    }

    final yesterday = today.subtract(const Duration(days: 1));
    if (messageDate == yesterday) {
      return 'Вчера';
    }

    if (now.difference(timestamp).inDays < 7) {
      const weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
      return weekdays[timestamp.weekday - 1];
    }

    return DateFormat('d MMM', 'ru').format(timestamp);
  }

  Future<void> _openChatComposer() async {
    final currentUserId = _authService.currentUserId;
    final messenger = ScaffoldMessenger.of(context);
    final treeProvider = context.read<TreeProvider>();
    final selectedTreeId = treeProvider.selectedTreeId;

    if (currentUserId == null || currentUserId.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Сначала войдите в аккаунт.')),
      );
      return;
    }

    if (selectedTreeId == null || selectedTreeId.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Сначала выберите семейное дерево.'),
          action: SnackBarAction(
            label: 'Открыть',
            onPressed: () => context.go('/tree?selector=1'),
          ),
        ),
      );
      return;
    }

    if (!GetIt.I.isRegistered<FamilyTreeServiceInterface>()) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Список родных временно недоступен.')),
      );
      return;
    }

    final draft = await showModalBottomSheet<_CreateChatDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CreateChatSheet(
        treeId: selectedTreeId,
        currentUserId: currentUserId,
      ),
    );

    if (!mounted || draft == null) {
      return;
    }

    try {
      late final String? chatId;
      late final String title;
      late final String chatType;
      if (draft.mode == _ChatComposerMode.branch) {
        title = _resolveBranchChatTitle(draft);
        chatType = 'branch';
        chatId = await _chatService.createBranchChat(
          treeId: selectedTreeId,
          branchRootPersonIds: draft.branchRootPersonIds,
          title: title,
        );
      } else {
        title = (draft.title?.trim().isNotEmpty ?? false)
            ? draft.title!.trim()
            : 'Групповой чат';
        chatType = 'group';
        chatId = await _chatService.createGroupChat(
          participantIds: draft.participantIds,
          title: draft.title,
          treeId: selectedTreeId,
        );
      }

      if (chatId == null || chatId.isEmpty) {
        throw StateError('Не удалось создать чат');
      }

      final encodedTitle = Uri.encodeComponent(title);
      if (!mounted) {
        return;
      }
      context.push('/chats/view/$chatId?type=$chatType&title=$encodedTitle');
    } catch (_) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            draft.mode == _ChatComposerMode.branch
                ? 'Не удалось создать чат ветки.'
                : 'Не удалось создать групповой чат.',
          ),
        ),
      );
    }
  }

  String _resolveBranchChatTitle(_CreateChatDraft draft) {
    final explicitTitle = draft.title?.trim();
    if (explicitTitle != null && explicitTitle.isNotEmpty) {
      return explicitTitle;
    }

    if (draft.branchRootNames.length == 1) {
      return 'Ветка ${draft.branchRootNames.first}';
    }

    if (draft.branchRootNames.isEmpty) {
      return 'Чат веток';
    }

    final previewNames = draft.branchRootNames.take(2).join(', ');
    final suffix = draft.branchRootNames.length > 2 ? ' и ещё' : '';
    return 'Ветки: $previewNames$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUserId = _authService.currentUserId ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Чаты'),
        centerTitle: false,
        titleTextStyle: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        actions: [
          IconButton(
            onPressed: _openChatComposer,
            tooltip: 'Новый чат',
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : _chatPreviews.isEmpty
                  ? _buildEmptyState(theme)
                  : _buildChatList(theme, currentUserId),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
                _loadChats();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 40,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Пока нет чатов',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Начните личный диалог или соберите семейный групповой чат '
              'для текущего дерева.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _openChatComposer,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Создать чат'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => context.go('/relatives'),
              icon: const Icon(Icons.people_outline),
              label: const Text('Открыть родных'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.go('/tree'),
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('Открыть дерево'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatList(ThemeData theme, String currentUserId) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _chatPreviews.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        indent: 76,
        color: theme.dividerColor.withValues(alpha: 0.3),
      ),
      itemBuilder: (context, index) {
        final chat = _chatPreviews[index];
        final hasUnread = chat.unreadCount > 0;
        final isLastFromMe = chat.lastMessageSenderId == currentUserId;
        final messageTime = chat.lastMessageTime.toDate();
        final timeLabel = _formatTimestamp(messageTime);

        return InkWell(
          onTap: () {
            final titleParam = Uri.encodeComponent(chat.displayName);
            final photoParam =
                chat.displayPhotoUrl != null && chat.displayPhotoUrl!.isNotEmpty
                    ? '&photo=${Uri.encodeComponent(chat.displayPhotoUrl!)}'
                    : '';
            final userParam = !chat.isGroup && chat.otherUserId.isNotEmpty
                ? '&userId=${Uri.encodeComponent(chat.otherUserId)}'
                : '';
            context.push(
              '/chats/view/${chat.chatId}?type=${Uri.encodeComponent(chat.type)}&title=$titleParam$photoParam$userParam',
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundImage: chat.displayPhotoUrl != null &&
                          chat.displayPhotoUrl!.isNotEmpty
                      ? NetworkImage(chat.displayPhotoUrl!)
                      : null,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: chat.displayPhotoUrl == null ||
                          chat.displayPhotoUrl!.isEmpty
                      ? chat.isGroup
                          ? Icon(
                              chat.isBranch
                                  ? Icons.account_tree_outlined
                                  : Icons.group_outlined,
                              color: theme.colorScheme.onPrimaryContainer,
                            )
                          : Text(
                              chat.displayName.isNotEmpty
                                  ? chat.displayName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              chat.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: hasUnread
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            timeLabel,
                            style: TextStyle(
                              fontSize: 13,
                              color: hasUnread
                                  ? theme.colorScheme.primary
                                  : Colors.grey[500],
                              fontWeight: hasUnread
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (chat.isGroup) ...[
                            Icon(
                              chat.isBranch
                                  ? Icons.account_tree_outlined
                                  : Icons.groups_2_outlined,
                              size: 15,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                          ],
                          if (isLastFromMe)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.done_all,
                                size: 16,
                                color: Colors.grey[400],
                              ),
                            ),
                          Expanded(
                            child: Text(
                              chat.lastMessage.isNotEmpty
                                  ? chat.lastMessage
                                  : 'Нет сообщений',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: hasUnread
                                    ? Colors.black87
                                    : Colors.grey[600],
                                fontWeight: hasUnread
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                fontStyle: chat.lastMessage.isEmpty
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                              ),
                            ),
                          ),
                          if (hasUnread) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                chat.unreadCount > 99
                                    ? '99+'
                                    : chat.unreadCount.toString(),
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _ChatComposerMode { group, branch }

class _CreateChatDraft {
  const _CreateChatDraft({
    required this.mode,
    this.participantIds = const <String>[],
    this.branchRootPersonIds = const <String>[],
    this.branchRootNames = const <String>[],
    this.title,
  });

  final _ChatComposerMode mode;
  final List<String> participantIds;
  final List<String> branchRootPersonIds;
  final List<String> branchRootNames;
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

  _ChatComposerMode _mode = _ChatComposerMode.group;

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

  bool get _canSubmitGroup => _selectedUserIds.length >= 2;

  bool get _canSubmitBranch =>
      _selectedBranchRootIds.isNotEmpty &&
      _selectedBranchParticipantIds().isNotEmpty;

  String get _branchSelectionLabel {
    if (_selectedBranchRootIds.isEmpty) {
      return 'Выберите хотя бы одну ветку';
    }
    final linkedCount = _selectedBranchParticipantIds().length;
    if (linkedCount <= 0) {
      return 'В выбранных ветках пока некому писать';
    }
    return linkedCount == 1 ? 'Открыть чат ветки' : 'Открыть чат веток';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SizedBox(
          height: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Новый чат',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _mode == _ChatComposerMode.group
                    ? 'Соберите семейную группу из родственников текущего дерева.'
                    : 'Выберите одну или несколько веток дерева и откройте общий чат для них.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Группа'),
                    selected: _mode == _ChatComposerMode.group,
                    onSelected: (selected) {
                      if (!selected) {
                        return;
                      }
                      setState(() {
                        _mode = _ChatComposerMode.group;
                      });
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Ветка семьи'),
                    selected: _mode == _ChatComposerMode.branch,
                    onSelected: (selected) {
                      if (!selected) {
                        return;
                      }
                      setState(() {
                        _mode = _ChatComposerMode.branch;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Название чата',
                  hintText: _mode == _ChatComposerMode.group
                      ? 'Например, Семья Кузнецовых'
                      : 'Например, Кузнецовы и Понькины',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Найти по имени',
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage != null
                        ? Center(
                            child: Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                            ),
                          )
                        : _mode == _ChatComposerMode.group
                            ? _buildGroupSelectionList(filteredParticipants)
                            : _buildBranchSelectionList(filteredBranches),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _mode == _ChatComposerMode.group
                      ? (_canSubmitGroup ? _submitGroupDraft : null)
                      : (_canSubmitBranch ? _submitBranchDraft : null),
                  icon: Icon(
                    _mode == _ChatComposerMode.group
                        ? Icons.groups_2_outlined
                        : Icons.account_tree_outlined,
                  ),
                  label: Text(
                    _mode == _ChatComposerMode.group
                        ? (_canSubmitGroup
                            ? 'Создать чат'
                            : 'Выберите ещё участников')
                        : _branchSelectionLabel,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupSelectionList(List<_GroupChatParticipant> participants) {
    if (participants.isEmpty) {
      return const Center(
        child: Text(
          'В этом дереве пока нет родственников с аккаунтом.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      itemCount: participants.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final participant = participants[index];
        final isSelected = _selectedUserIds.contains(participant.userId);
        return CheckboxListTile(
          value: isSelected,
          onChanged: (_) {
            setState(() {
              if (isSelected) {
                _selectedUserIds.remove(participant.userId);
              } else {
                _selectedUserIds.add(participant.userId);
              }
            });
          },
          secondary: CircleAvatar(
            backgroundImage:
                participant.photoUrl != null && participant.photoUrl!.isNotEmpty
                    ? NetworkImage(participant.photoUrl!)
                    : null,
            child: participant.photoUrl == null || participant.photoUrl!.isEmpty
                ? Text(
                    participant.name.isNotEmpty ? participant.name[0] : '?',
                  )
                : null,
          ),
          title: Text(participant.name),
          subtitle: Text(participant.relationLabel),
          controlAffinity: ListTileControlAffinity.trailing,
          contentPadding: EdgeInsets.zero,
        );
      },
    );
  }

  Widget _buildBranchSelectionList(List<_BranchChatCandidate> candidates) {
    if (candidates.isEmpty) {
      return const Center(
        child: Text(
          'В этом дереве пока нет людей для чата ветки.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      itemCount: candidates.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final candidate = candidates[index];
        final isSelected = _selectedBranchRootIds.contains(candidate.personId);
        final linkedCount = candidate.linkedParticipantCount;
        return CheckboxListTile(
          value: isSelected,
          onChanged: (_) {
            setState(() {
              if (isSelected) {
                _selectedBranchRootIds.remove(candidate.personId);
              } else {
                _selectedBranchRootIds.add(candidate.personId);
              }
            });
          },
          secondary: CircleAvatar(
            backgroundImage:
                candidate.photoUrl != null && candidate.photoUrl!.isNotEmpty
                    ? NetworkImage(candidate.photoUrl!)
                    : null,
            child: candidate.photoUrl == null || candidate.photoUrl!.isEmpty
                ? Text(candidate.name.isNotEmpty ? candidate.name[0] : '?')
                : null,
          ),
          title: Text(candidate.name),
          subtitle: Text(
            linkedCount > 0
                ? '${candidate.relationLabel} · $linkedCount ${_participantLabel(linkedCount)}'
                : '${candidate.relationLabel} · Пока без участников с аккаунтом',
          ),
          controlAffinity: ListTileControlAffinity.trailing,
          contentPadding: EdgeInsets.zero,
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

  void _submitGroupDraft() {
    Navigator.of(context).pop(
      _CreateChatDraft(
        mode: _ChatComposerMode.group,
        participantIds: _selectedUserIds.toList(),
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
