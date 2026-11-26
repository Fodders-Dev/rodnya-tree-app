part of '../chat_screen.dart';

class _GroupCallParticipantPicker extends StatefulWidget {
  const _GroupCallParticipantPicker({
    required this.mediaMode,
    required this.participants,
  });

  final CallMediaMode mediaMode;
  final List<ChatParticipantSummary> participants;

  @override
  State<_GroupCallParticipantPicker> createState() =>
      _GroupCallParticipantPickerState();
}

class _GroupCallParticipantPickerState
    extends State<_GroupCallParticipantPicker> {
  final Set<String> _selectedIds = <String>{};

  bool get _isVideo => widget.mediaMode.isVideo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final selectedCount = _selectedIds.length;
    final canStart = selectedCount > 0;
    final actionLabel = selectedCount == 1
        ? 'Позвонить 1 участнику'
        : 'Позвонить выбранным ($selectedCount)';

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: size.height * 0.86),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            8,
            18,
            18 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isVideo ? Icons.videocam_outlined : Icons.call_outlined,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Кого позвать?',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isVideo
                              ? 'Видеозвонок пойдёт только выбранным.'
                              : 'Аудиозвонок пойдёт только выбранным.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedIds
                          ..clear()
                          ..addAll(widget.participants.map((p) => p.userId));
                      });
                    },
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: const Text('Все'),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : () => setState(_selectedIds.clear),
                    child: const Text('Сбросить'),
                  ),
                  const Spacer(),
                  Text(
                    selectedCount == 0
                        ? 'Никто не выбран'
                        : 'Выбрано: $selectedCount',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.participants.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final participant = widget.participants[index];
                    final selected = _selectedIds.contains(participant.userId);
                    final avatarImage =
                        buildAvatarImageProvider(participant.photoUrl);
                    final initial = participant.displayName.trim().isNotEmpty
                        ? participant.displayName.trim()[0].toUpperCase()
                        : '?';
                    return CheckboxListTile(
                      value: selected,
                      onChanged: (_) => setState(() {
                        if (selected) {
                          _selectedIds.remove(participant.userId);
                        } else {
                          _selectedIds.add(participant.userId);
                        }
                      }),
                      controlAffinity: ListTileControlAffinity.trailing,
                      secondary: CircleAvatar(
                        backgroundImage: avatarImage,
                        child: avatarImage == null ? Text(initial) : null,
                      ),
                      title: Text(
                        participant.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        participant.isOnline ? 'в сети' : 'участник чата',
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: canStart
                          ? () => Navigator.of(context).pop(
                                _selectedIds.toList(growable: false),
                              )
                          : null,
                      icon: Icon(
                        _isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                      ),
                      label: Text(actionLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
