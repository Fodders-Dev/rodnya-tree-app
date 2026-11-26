import 'package:flutter/material.dart';

import '../../utils/photo_url.dart';

enum GroupCallParticipantConnectionState {
  connected,
  waiting,
  notConnected,
}

class GroupCallParticipantStatus {
  const GroupCallParticipantStatus({
    required this.userId,
    required this.displayName,
    required this.state,
    required this.isCurrentUser,
    this.photoUrl,
  });

  final String userId;
  final String displayName;
  final String? photoUrl;
  final GroupCallParticipantConnectionState state;
  final bool isCurrentUser;
}

class GroupCallRoster extends StatelessWidget {
  const GroupCallRoster({
    super.key,
    required this.participants,
    required this.isNudging,
    this.onNudgeWaiting,
    this.onNudgeParticipant,
  });

  final List<GroupCallParticipantStatus> participants;
  final bool isNudging;
  final VoidCallback? onNudgeWaiting;
  final ValueChanged<String>? onNudgeParticipant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connectedCount = participants
        .where(
          (participant) =>
              participant.state ==
              GroupCallParticipantConnectionState.connected,
        )
        .length;
    final waitingCount = participants
        .where(
          (participant) =>
              participant.state == GroupCallParticipantConnectionState.waiting,
        )
        .length;
    final visibleParticipants = participants.take(8).toList(growable: false);
    final hiddenCount = participants.length - visibleParticipants.length;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.groups_2_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.88),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    waitingCount == 0
                        ? '$connectedCount в звонке'
                        : '$connectedCount в звонке · $waitingCount ждут',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (waitingCount > 0) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: isNudging ? null : onNudgeWaiting,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: isNudging
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.notifications_active_rounded),
                    label: const Text('Позвать ещё'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...visibleParticipants.map(
                  (participant) => _GroupCallParticipantChip(
                    participant,
                    isNudging: isNudging,
                    onNudge: participant.state ==
                                GroupCallParticipantConnectionState.waiting &&
                            !participant.isCurrentUser
                        ? onNudgeParticipant
                        : null,
                  ),
                ),
                if (hiddenCount > 0)
                  _GroupCallOverflowChip(hiddenCount: hiddenCount),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupCallParticipantChip extends StatelessWidget {
  const _GroupCallParticipantChip(
    this.participant, {
    required this.isNudging,
    this.onNudge,
  });

  final GroupCallParticipantStatus participant;
  final bool isNudging;
  final ValueChanged<String>? onNudge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stateColor = _stateColor(participant.state);
    final avatarImage = buildAvatarImageProvider(participant.photoUrl);
    final initial = participant.displayName.trim().isNotEmpty
        ? participant.displayName.trim()[0].toUpperCase()
        : '?';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 188),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.36),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    backgroundImage: avatarImage,
                    child: avatarImage == null
                        ? Text(
                            initial,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: stateColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF111318),
                          width: 1.5,
                        ),
                      ),
                      child: const SizedBox(width: 8, height: 8),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      participant.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _stateLabel(participant.state),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (onNudge != null) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Позвать ${participant.displayName}',
                  child: InkResponse(
                    onTap:
                        isNudging ? null : () => onNudge!(participant.userId),
                    radius: 18,
                    child: Icon(
                      Icons.notifications_active_rounded,
                      size: 17,
                      color: isNudging
                          ? Colors.white.withValues(alpha: 0.38)
                          : Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _stateColor(GroupCallParticipantConnectionState state) {
    switch (state) {
      case GroupCallParticipantConnectionState.connected:
        return const Color(0xFF37B24D);
      case GroupCallParticipantConnectionState.waiting:
        return const Color(0xFFF59F00);
      case GroupCallParticipantConnectionState.notConnected:
        return const Color(0xFFADB5BD);
    }
  }

  String _stateLabel(GroupCallParticipantConnectionState state) {
    switch (state) {
      case GroupCallParticipantConnectionState.connected:
        return 'В звонке';
      case GroupCallParticipantConnectionState.waiting:
        return 'Ждём';
      case GroupCallParticipantConnectionState.notConnected:
        return 'Не подключился';
    }
  }
}

class _GroupCallOverflowChip extends StatelessWidget {
  const _GroupCallOverflowChip({required this.hiddenCount});

  final int hiddenCount;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Text(
          '+$hiddenCount',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}
