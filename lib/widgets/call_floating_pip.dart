import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../models/call_invite.dart';
import '../services/call_coordinator_service.dart';
import '../utils/photo_url.dart';
import 'call_connection_quality_badge.dart';

class CallFloatingPip extends StatefulWidget {
  const CallFloatingPip({
    super.key,
    required this.call,
    required this.title,
    required this.coordinator,
    required this.onRestore,
    this.photoUrl,
  });

  final CallInvite call;
  final String title;
  final String? photoUrl;
  final CallCoordinatorService coordinator;
  final VoidCallback onRestore;

  @override
  State<CallFloatingPip> createState() => _CallFloatingPipState();
}

class _CallFloatingPipState extends State<CallFloatingPip> {
  static const Size _cardSize = Size(220, 176);
  static const double _edgePadding = 16;
  Offset? _offset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackOffset = Offset(
          (constraints.maxWidth - _cardSize.width - _edgePadding)
              .clamp(_edgePadding, double.infinity),
          (constraints.maxHeight - _cardSize.height - _edgePadding)
              .clamp(_edgePadding, double.infinity),
        );
        final offset = _clampOffset(
          _offset ?? fallbackOffset,
          constraints.biggest,
        );

        return Stack(
          children: [
            Positioned(
              left: offset.dx,
              top: offset.dy,
              width: _cardSize.width,
              height: _cardSize.height,
              child: _buildCard(context, constraints.biggest),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCard(BuildContext context, Size bounds) {
    final theme = Theme.of(context);
    final remoteVideoTrack = _remoteVideoTrack(widget.coordinator.room);
    final isVideo = widget.call.mediaMode.isVideo;
    final connectionQuality = widget.coordinator.displayedConnectionQuality;
    final statusColor = callConnectionQualityColor(
      connectionQuality,
      isReconnecting: widget.coordinator.isReconnectingRoom,
    );
    final statusLabel = connectionQuality == ConnectionQuality.unknown &&
            !widget.coordinator.isReconnectingRoom
        ? 'Звонок идет'
        : callConnectionQualityLabel(
            connectionQuality,
            isReconnecting: widget.coordinator.isReconnectingRoom,
          );

    return Semantics(
      button: true,
      label: 'Мини-окно звонка',
      child: GestureDetector(
        onTap: widget.onRestore,
        onPanUpdate: (details) {
          setState(() {
            _offset = _clampOffset(
              (_offset ?? Offset.zero) + details.delta,
              bounds,
            );
          });
        },
        child: Material(
          color: Colors.transparent,
          elevation: 18,
          shadowColor: Colors.black.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF151A22),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (isVideo && remoteVideoTrack != null)
                  VideoTrackRenderer(
                    remoteVideoTrack,
                    fit: VideoViewFit.cover,
                  )
                else
                  _CallPipFallback(
                    title: widget.title,
                    photoUrl: widget.photoUrl,
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.08),
                        Colors.black.withValues(alpha: 0.62),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              statusLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Tooltip(
                            message: 'Вернуться к звонку',
                            child: IconButton(
                              onPressed: widget.onRestore,
                              color: Colors.white,
                              iconSize: 18,
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.open_in_full_rounded),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _PipActionButton(
                            tooltip: widget.coordinator.microphoneEnabled
                                ? 'Выключить микрофон'
                                : 'Включить микрофон',
                            icon: widget.coordinator.microphoneEnabled
                                ? Icons.mic_rounded
                                : Icons.mic_off_rounded,
                            onPressed: () => unawaited(
                              widget.coordinator.toggleMicrophone(),
                            ),
                          ),
                          if (isVideo) ...[
                            const SizedBox(width: 8),
                            _PipActionButton(
                              tooltip: widget.coordinator.cameraEnabled
                                  ? 'Выключить камеру'
                                  : 'Включить камеру',
                              icon: widget.coordinator.cameraEnabled
                                  ? Icons.videocam_rounded
                                  : Icons.videocam_off_rounded,
                              onPressed: () => unawaited(
                                widget.coordinator.toggleCamera(),
                              ),
                            ),
                          ],
                          const Spacer(),
                          _PipActionButton(
                            tooltip: 'Завершить звонок',
                            icon: Icons.call_end_rounded,
                            backgroundColor: const Color(0xFFE5484D),
                            onPressed: () => unawaited(
                              widget.coordinator.finishCall(widget.call.id),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Offset _clampOffset(Offset value, Size bounds) {
    final maxX = (bounds.width - _cardSize.width - _edgePadding)
        .clamp(_edgePadding, double.infinity);
    final maxY = (bounds.height - _cardSize.height - _edgePadding)
        .clamp(_edgePadding, double.infinity);
    return Offset(
      value.dx.clamp(_edgePadding, maxX),
      value.dy.clamp(_edgePadding, maxY),
    );
  }

  VideoTrack? _remoteVideoTrack(Room? room) {
    if (room == null) {
      return null;
    }
    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.videoTrackPublications) {
        if (publication.source == TrackSource.camera) {
          return publication.track;
        }
      }
    }
    return null;
  }
}

class _CallPipFallback extends StatelessWidget {
  const _CallPipFallback({
    required this.title,
    this.photoUrl,
  });

  final String title;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final avatarImage = buildAvatarImageProvider(photoUrl);
    final initial = title.trim().isEmpty ? '?' : title.trim()[0].toUpperCase();
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF172033),
            Color(0xFF0F1722),
            Color(0xFF24352E),
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.14),
            image: avatarImage == null
                ? null
                : DecorationImage(
                    image: avatarImage,
                    fit: BoxFit.cover,
                  ),
          ),
          child: avatarImage == null
              ? Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

class _PipActionButton extends StatelessWidget {
  const _PipActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.backgroundColor,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 22,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.white.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              icon,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}
