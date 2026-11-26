part of '../chat_screen.dart';

class _ChatInfoSheet extends StatefulWidget {
  const _ChatInfoSheet({
    required this.initialDetails,
    required this.currentUserId,
    this.onlineUserIds = const <String>{},
    this.lastSeenByUserId = const <String, DateTime>{},
    required this.hasPinnedMessage,
    required this.initialNotificationLevel,
    required this.initialAutoDeleteOption,
    required this.onRename,
    required this.onUpdatePhoto,
    required this.onAddParticipants,
    required this.onRemoveParticipant,
    required this.onOpenDirectChat,
    required this.onLeaveGroup,
    required this.onOpenSearch,
    required this.onNotificationLevelChanged,
    required this.onAutoDeleteChanged,
    this.onOpenPinnedMessage,
    this.onOpenTree,
    this.onOpenRelatives,
    this.onOpenMedia,
    this.onOpenFiles,
  });

  final ChatDetails initialDetails;
  final String currentUserId;

  /// Снапшот присутствия на момент открытия шита (см. _openChatInfo).
  final Set<String> onlineUserIds;
  final Map<String, DateTime> lastSeenByUserId;
  final bool hasPinnedMessage;
  final ChatNotificationLevel initialNotificationLevel;
  final ChatAutoDeleteOption initialAutoDeleteOption;
  final Future<ChatDetails> Function(String title) onRename;
  final Future<ChatDetails> Function(XFile photo) onUpdatePhoto;
  final Future<ChatDetails> Function(List<String> participantIds)
      onAddParticipants;
  final Future<ChatDetails> Function(String participantId) onRemoveParticipant;
  final void Function(ChatParticipantSummary participant) onOpenDirectChat;
  final Future<void> Function() onLeaveGroup;
  final VoidCallback onOpenSearch;
  final Future<void> Function(ChatNotificationLevel level)
      onNotificationLevelChanged;
  final Future<void> Function(ChatAutoDeleteOption option) onAutoDeleteChanged;
  final VoidCallback? onOpenPinnedMessage;
  final VoidCallback? onOpenTree;
  final VoidCallback? onOpenRelatives;
  final VoidCallback? onOpenMedia;
  final VoidCallback? onOpenFiles;

  @override
  State<_ChatInfoSheet> createState() => _ChatInfoSheetState();
}

/// Компактное «когда был(а) в сети» для строк участников — нейтральная
/// форма без гендерной эвристики (в отличие от заголовка личного чата,
/// где имя одно и _formatLastSeen может позволить себе «была»).
class _ChatInfoSheetState extends State<_ChatInfoSheet> {
  late ChatDetails _details;
  late ChatNotificationLevel _notificationLevel;
  late ChatAutoDeleteOption _autoDeleteOption;
  bool _isSaving = false;
  bool _isUpdatingNotifications = false;
  bool _isUpdatingAutoDelete = false;

  @override
  void initState() {
    super.initState();
    _details = widget.initialDetails;
    _notificationLevel = widget.initialNotificationLevel;
    _autoDeleteOption = widget.initialAutoDeleteOption;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFriendsTree =
        context.read<TreeProvider>().selectedTreeKind == TreeKind.friends;
    final screenHeight = MediaQuery.of(context).size.height;
    final hasTreeContext =
        _details.treeId != null && _details.treeId!.trim().isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SizedBox(
          height: screenHeight * 0.84,
          child: ListView(
            children: [
              Row(
                children: [
                  Text(
                    'О чате',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildChatIdentityCard(theme),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    icon: _details.isBranch
                        ? Icons.account_tree_outlined
                        : (_details.isDirect
                            ? Icons.chat_bubble_outline
                            : Icons.groups_2_outlined),
                    label: _details.isBranch
                        ? 'Чат ветки'
                        : _details.isDirect
                            ? 'Личный чат'
                            : (isFriendsTree ? 'Группа круга' : 'Группа'),
                  ),
                  _InfoChip(
                    icon: Icons.people_outline,
                    label: _details.memberCount == 1
                        ? '1 участник'
                        : '${_details.memberCount} участников',
                  ),
                  _InfoChip(
                    icon: isFriendsTree
                        ? Icons.diversity_3_outlined
                        : Icons.account_tree_outlined,
                    label: isFriendsTree ? 'Контекст круга' : 'Контекст дерева',
                  ),
                ],
              ),
              // UX-аудит: в группе участники — самое востребованное в «О
              // чате», а лежали в самом низу за ~5 экранами настроек.
              if (_details.isGroup) ..._buildParticipantsSectionWidgets(theme),
              const SizedBox(height: 16),
              GlassPanel(
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(
                      icon: Icons.mark_chat_unread_outlined,
                      label: _details.isEditableGroup
                          ? 'Можно редактировать'
                          : 'Состав фиксируется',
                    ),
                    _InfoChip(
                      icon: Icons.badge_outlined,
                      label: _details.participants.any((participant) =>
                              participant.userId == widget.currentUserId)
                          ? 'Вы в составе'
                          : 'Без вашего профиля',
                    ),
                    if (widget.hasPinnedMessage)
                      const _InfoChip(
                        icon: Icons.push_pin_outlined,
                        label: 'Есть закрепленное',
                      ),
                    _InfoChip(
                      icon: _notificationLevel == ChatNotificationLevel.muted
                          ? Icons.notifications_off_outlined
                          : (_notificationLevel == ChatNotificationLevel.silent
                              ? Icons.notifications_none_outlined
                              : Icons.notifications_active_outlined),
                      label: _notificationLevel.label,
                    ),
                    _InfoChip(
                      icon: _autoDeleteOption == ChatAutoDeleteOption.off
                          ? Icons.timer_off_outlined
                          : Icons.timer_outlined,
                      label: _autoDeleteOption == ChatAutoDeleteOption.off
                          ? 'Без автоудаления'
                          : 'TTL: ${_autoDeleteOption.label}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Быстрые действия',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _QuickActionCard(
                    icon: Icons.search,
                    title: 'Поиск в чате',
                    subtitle: 'По слову или фразе',
                    onTap: widget.onOpenSearch,
                  ),
                  if (widget.onOpenMedia != null)
                    _QuickActionCard(
                      icon: Icons.perm_media_outlined,
                      title: 'Медиа',
                      subtitle: 'Фото, видео и кружки',
                      onTap: widget.onOpenMedia!,
                    ),
                  if (widget.onOpenFiles != null)
                    _QuickActionCard(
                      icon: Icons.folder_open_outlined,
                      title: 'Файлы',
                      subtitle: 'Документы и голосовые',
                      onTap: widget.onOpenFiles!,
                    ),
                  if (widget.onOpenPinnedMessage != null)
                    _QuickActionCard(
                      icon: Icons.push_pin_outlined,
                      title: 'К закрепленному',
                      subtitle: 'Открыть закрепленное',
                      onTap: widget.onOpenPinnedMessage!,
                    ),
                  if (hasTreeContext && widget.onOpenTree != null)
                    _QuickActionCard(
                      icon: Icons.account_tree_outlined,
                      title: 'Открыть дерево',
                      subtitle: 'Перейти к дереву',
                      onTap: widget.onOpenTree!,
                    ),
                  if (hasTreeContext && widget.onOpenRelatives != null)
                    _QuickActionCard(
                      icon: Icons.people_alt_outlined,
                      title: 'Открыть родных',
                      subtitle: 'Перейти к списку',
                      onTap: widget.onOpenRelatives!,
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Уведомления',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              GlassPanel(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _notificationLevel.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _notificationLevel.summary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ChatNotificationLevel.values.map((level) {
                        final isSelected = _notificationLevel == level;
                        return ChoiceChip(
                          label: Text(level.label),
                          selected: isSelected,
                          onSelected: _isUpdatingNotifications || isSelected
                              ? null
                              : (_) => _setNotificationLevel(level),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Автоудаление',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              GlassPanel(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _autoDeleteOption.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _autoDeleteOption.summary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ChatAutoDeleteOption.values.map((option) {
                        final isSelected = _autoDeleteOption == option;
                        return ChoiceChip(
                          label: Text(option.label),
                          selected: isSelected,
                          onSelected: _isUpdatingAutoDelete || isSelected
                              ? null
                              : (_) => _setAutoDeleteOption(option),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              if (_details.branchRoots.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  isFriendsTree ? 'Круги' : 'Ветки',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _details.branchRoots
                      .map(
                        (root) => _InfoChip(
                          icon: isFriendsTree
                              ? Icons.diversity_3_outlined
                              : Icons.account_tree_outlined,
                          label: root.name,
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 18),
              Text(
                'Управление',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              if (_details.isEditableGroup)
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _renameChat,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Переименовать'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isSaving ? null : _addParticipants,
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: const Text('Добавить'),
                      ),
                    ),
                  ],
                )
              else
                GlassPanel(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    _details.isBranch
                        ? 'Состав идет из дерева.'
                        : _details.isDirect
                            ? 'Состав личного чата фиксирован.'
                            : 'Состав сейчас не меняется.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              // Для групп секция «Участники» уехала наверх (сразу после
              // чипов) — здесь остаётся только для личных/branch чатов.
              if (!_details.isGroup) ..._buildParticipantsSectionWidgets(theme),
              // G2: самовыход из группы. Доступен только в обычном
              // групповом чате (как и кнопка «убрать»); личные/branch не
              // покидают этим путём.
              if (_details.isEditableGroup) ...[
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  key: const Key('chat-info-leave-group'),
                  onPressed: _isSaving ? null : _leaveGroup,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Покинуть чат'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(
                      color: theme.colorScheme.error.withValues(alpha: 0.5),
                    ),
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Секция «Участники»: у групп рендерится сразу после чипов, у
  /// личных/branch — на прежнем месте внизу. Строки кликабельны целиком
  /// (тап → личка, тот же путь, что и иконка) и показывают присутствие
  /// из снапшота на момент открытия шита.
  List<Widget> _buildParticipantsSectionWidgets(ThemeData theme) {
    return [
      const SizedBox(height: 18),
      Text(
        'Участники',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          children: _details.participants.asMap().entries.map((entry) {
            final index = entry.key;
            final participant = entry.value;
            final isCurrentUser = participant.userId == widget.currentUserId;
            final avatarImage = buildAvatarImageProvider(participant.photoUrl);
            final isOnline = !isCurrentUser &&
                widget.onlineUserIds.contains(participant.userId);
            final lastSeen = widget.lastSeenByUserId[participant.userId] ??
                participant.lastSeenAt;
            final subtitle = isCurrentUser
                ? 'Вы'
                : isOnline
                    ? 'в сети'
                    : (lastSeen != null
                        ? _relativeLastSeenLabel(lastSeen)
                        : 'Участник');
            return Column(
              children: [
                if (index > 0) const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  // Вся строка — таргет для «в личку» (иконки справа
                  // были единственной, слишком мелкой целью). Только в
                  // группе: в личном чате тап по собеседнику открыл бы
                  // дубль того же чата (ревью батча).
                  onTap: isCurrentUser || _isSaving || !_details.isGroup
                      ? null
                      : () => widget.onOpenDirectChat(participant),
                  leading: CircleAvatar(
                    backgroundImage: avatarImage,
                    child: avatarImage == null
                        ? Text(
                            participant.displayName.isNotEmpty
                                ? participant.displayName[0]
                                : '?',
                          )
                        : null,
                  ),
                  title: Text(participant.displayName),
                  subtitle: Text(
                    subtitle,
                    style: isOnline
                        ? const TextStyle(
                            color: Color(0xFF2EBD68),
                            fontWeight: FontWeight.w600,
                          )
                        : null,
                  ),
                  trailing: isCurrentUser || !_details.isGroup
                      ? null
                      : Wrap(
                          spacing: 2,
                          children: [
                            IconButton(
                              onPressed: _isSaving
                                  ? null
                                  : () => widget.onOpenDirectChat(participant),
                              tooltip: 'Написать в личку',
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                              ),
                            ),
                            if (_details.isEditableGroup)
                              IconButton(
                                onPressed: _isSaving
                                    ? null
                                    : () => _removeParticipant(participant),
                                tooltip: 'Убрать из чата',
                                icon: const Icon(
                                  Icons.person_remove_outlined,
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    ];
  }

  Widget _buildChatIdentityCard(ThemeData theme) {
    String? avatarUrl;
    final chatPhotoUrl = _details.photoUrl?.trim();
    if (chatPhotoUrl != null && chatPhotoUrl.isNotEmpty) {
      avatarUrl = chatPhotoUrl;
    } else if (_details.isBranch && _details.branchRoots.isNotEmpty) {
      avatarUrl = _details.branchRoots.first.photoUrl;
    } else if (_details.isDirect) {
      for (final participant in _details.participants) {
        if (participant.userId != widget.currentUserId) {
          avatarUrl = participant.photoUrl;
          break;
        }
      }
    }

    final avatarImage = buildAvatarImageProvider(avatarUrl);
    final title = _details.displayTitleFor(widget.currentUserId);
    final subtitle = _details.isDirect
        ? 'Личные сообщения'
        : (_details.memberCount == 1
            ? '1 участник'
            : '${_details.memberCount} участников');

    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundImage: avatarImage,
            child: avatarImage == null
                ? Icon(
                    _details.isDirect
                        ? Icons.person_outline
                        : Icons.groups_2_outlined,
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (_details.isEditableGroup) ...[
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _isSaving ? null : _changeChatPhoto,
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: const Text('Фото'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _changeChatPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 86,
      maxWidth: 1600,
    );
    if (!mounted || picked == null) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      final details = await widget.onUpdatePhoto(picked);
      if (!mounted) {
        return;
      }
      setState(() {
        _details = details;
      });
      showAppSnackBar(context, 'Фото чата обновлено.');
    } catch (_) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        'Не удалось обновить фото чата.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Покинуть чат'),
        content: const Text(
          'Вы выйдете из этого группового чата. Чтобы вернуться, кто-то из '
          'участников должен добавить вас снова.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      await widget.onLeaveGroup();
      // Успех: вызывающий закрывает шит и уводит к списку чатов — здесь
      // больше ничего делать не нужно (виджет уже размонтирован).
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
      });
      showAppSnackBar(
        context,
        'Не удалось покинуть чат.',
        isError: true,
      );
    }
  }

  Future<void> _setNotificationLevel(ChatNotificationLevel level) async {
    if (_notificationLevel == level) {
      return;
    }
    final previousLevel = _notificationLevel;
    setState(() {
      _isUpdatingNotifications = true;
      _notificationLevel = level;
    });
    try {
      await widget.onNotificationLevelChanged(level);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _notificationLevel = previousLevel;
      });
      showAppSnackBar(
        context,
        'Не удалось обновить настройки уведомлений.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingNotifications = false;
        });
      }
    }
  }

  Future<void> _setAutoDeleteOption(ChatAutoDeleteOption option) async {
    if (_autoDeleteOption == option) {
      return;
    }
    final previousOption = _autoDeleteOption;
    setState(() {
      _isUpdatingAutoDelete = true;
      _autoDeleteOption = option;
    });
    try {
      await widget.onAutoDeleteChanged(option);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _autoDeleteOption = previousOption;
      });
      showAppSnackBar(
        context,
        'Не удалось обновить автоудаление сообщений.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingAutoDelete = false;
        });
      }
    }
  }

  Future<void> _renameChat() async {
    final controller = TextEditingController(
      text: _details.displayTitleFor(widget.currentUserId),
    );
    final nextTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Переименовать чат'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Название',
            hintText: 'Например, Семья Кузнецовых',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (!mounted || nextTitle == null || nextTitle.trim().isEmpty) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      final details = await widget.onRename(nextTitle.trim());
      if (!mounted) {
        return;
      }
      setState(() {
        _details = details;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, 'Не удалось переименовать чат.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _addParticipants() async {
    final treeId = _details.treeId;
    if (treeId == null || treeId.isEmpty) {
      showAppSnackBar(context, 'Для этого чата не найдено дерево.',
          isError: true);
      return;
    }
    if (!GetIt.I.isRegistered<FamilyTreeServiceInterface>()) {
      showAppSnackBar(
        context,
        'Список родных временно недоступен.',
        isError: true,
      );
      return;
    }

    final familyTreeService = GetIt.I<FamilyTreeServiceInterface>();
    final relatives = await familyTreeService.getRelatives(treeId);
    if (!mounted) {
      return;
    }

    final existingParticipantIds = _details.participantIds.toSet();
    final candidates = relatives
        .where((person) {
          final userId = person.userId?.trim();
          return userId != null &&
              userId.isNotEmpty &&
              userId != widget.currentUserId &&
              !existingParticipantIds.contains(userId);
        })
        .map(
          (person) => _GroupChatCandidate(
            userId: person.userId!.trim(),
            displayName:
                person.name.trim().isNotEmpty ? person.name : 'Пользователь',
            photoUrl: person.photoUrl,
            relationLabel: (person.relation ?? '').trim().isNotEmpty
                ? person.relation!.trim()
                : 'Родственник',
          ),
        )
        .toList()
      ..sort((left, right) => left.displayName.compareTo(right.displayName));

    if (candidates.isEmpty) {
      showAppSnackBar(context, 'В этом дереве больше некого добавить.');
      return;
    }

    final selectedIds = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _AddParticipantsSheet(candidates: candidates),
    );

    if (!mounted || selectedIds == null || selectedIds.isEmpty) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      final details = await widget.onAddParticipants(selectedIds);
      if (!mounted) {
        return;
      }
      setState(() {
        _details = details;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, 'Не удалось добавить участников.',
          isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _removeParticipant(
    ChatParticipantSummary participant,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Убрать участника'),
        content: Text(
          'Убрать ${participant.displayName} из этого чата?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Убрать'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      final details = await widget.onRemoveParticipant(participant.userId);
      if (!mounted) {
        return;
      }
      setState(() {
        _details = details;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        'Не удалось обновить состав чата.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
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
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      child: GlassPanel(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddParticipantsSheet extends StatefulWidget {
  const _AddParticipantsSheet({required this.candidates});

  final List<_GroupChatCandidate> candidates;

  @override
  State<_AddParticipantsSheet> createState() => _AddParticipantsSheetState();
}

class _AddParticipantsSheetState extends State<_AddParticipantsSheet> {
  final Set<String> _selectedIds = <String>{};
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = _searchController.text.trim().toLowerCase();
    final filteredCandidates = widget.candidates.where((candidate) {
      if (search.isEmpty) {
        return true;
      }
      return candidate.displayName.toLowerCase().contains(search) ||
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
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Добавить участников',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    _selectedIds.isEmpty ? '0' : '${_selectedIds.length}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GlassPanel(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Найти по имени',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: filteredCandidates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final candidate = filteredCandidates[index];
                    final isSelected = _selectedIds.contains(candidate.userId);
                    final avatarImage =
                        buildAvatarImageProvider(candidate.photoUrl);
                    return GlassPanel(
                      padding: EdgeInsets.zero,
                      child: CheckboxListTile(
                        value: isSelected,
                        onChanged: (_) {
                          setState(() {
                            if (isSelected) {
                              _selectedIds.remove(candidate.userId);
                            } else {
                              _selectedIds.add(candidate.userId);
                            }
                          });
                        },
                        secondary: CircleAvatar(
                          backgroundImage: avatarImage,
                          child: avatarImage == null
                              ? Text(
                                  candidate.displayName.isNotEmpty
                                      ? candidate.displayName[0]
                                      : '?',
                                )
                              : null,
                        ),
                        title: Text(candidate.displayName),
                        subtitle: Text(candidate.relationLabel),
                        controlAffinity: ListTileControlAffinity.trailing,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _selectedIds.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_selectedIds.toList()),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(
                    _selectedIds.isEmpty
                        ? 'Выберите участников'
                        : 'Добавить ${_selectedIds.length}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// _AttachmentPickerChoice enum removed — the picker now returns the
// AttachmentPickerAction.id string directly, so the call site switches
// on plain `'images'` / `'video'` / `'video_note'` / `'file'`.
