import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../backend/interfaces/chat_service_interface.dart';
import '../models/call_invite.dart';
import '../models/call_media_mode.dart';
import '../models/call_state.dart';
import '../services/audio_route_service.dart';
import '../services/call_coordinator_service.dart';
import '../services/call_pip_service.dart';
import '../utils/photo_url.dart';
import '../widgets/call_connection_quality_badge.dart';
import '../widgets/call_device_picker_sheet.dart';
import '../widgets/glass_panel.dart';
import '../widgets/in_call_chat_sheet.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.initialCall,
    required this.title,
    required this.coordinator,
    this.photoUrl,
    this.pipService = const MethodChannelCallPipService(),
    this.chatService,
  });

  final CallInvite initialCall;
  final String title;
  final String? photoUrl;
  final CallCoordinatorService coordinator;
  final CallPipService pipService;
  final ChatServiceInterface? chatService;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  CallInvite? _call;

  String? get _currentUserId => widget.coordinator.currentUserId;
  CallInvite get _resolvedCall => _call ?? widget.initialCall;
  bool get _isIncoming =>
      _currentUserId != null && _resolvedCall.isIncomingFor(_currentUserId!);
  bool get _isVideoCall => _resolvedCall.mediaMode == CallMediaMode.video;
  AudioRouteService get _audioRouteService =>
      widget.coordinator.audioRouteService;
  ChatServiceInterface? get _chatService =>
      widget.chatService ??
      (GetIt.I.isRegistered<ChatServiceInterface>()
          ? GetIt.I<ChatServiceInterface>()
          : null);

  @override
  void initState() {
    super.initState();
    _call = widget.coordinator.currentCall?.id == widget.initialCall.id
        ? widget.coordinator.currentCall
        : widget.initialCall;
    widget.coordinator.setCallScreenVisible(
      widget.initialCall.id,
      isVisible: true,
    );
    widget.coordinator.addListener(_handleCoordinatorChanged);
    unawaited(widget.coordinator.activateCall(_resolvedCall));
  }

  @override
  void dispose() {
    widget.coordinator.removeListener(_handleCoordinatorChanged);
    widget.coordinator.setCallScreenVisible(
      widget.initialCall.id,
      isVisible: false,
    );
    super.dispose();
  }

  void _handleCoordinatorChanged() {
    final coordinatorCall = widget.coordinator.currentCall;
    if (coordinatorCall == null) {
      if (mounted) {
        Future<void>.microtask(() {
          if (mounted) {
            Navigator.of(context).maybePop();
          }
        });
      }
      return;
    }
    if (coordinatorCall.id != _resolvedCall.id) {
      return;
    }
    setState(() {
      _call = coordinatorCall;
    });
    if (coordinatorCall.joinedOnAnotherDevice &&
        coordinatorCall.state == CallState.active) {
      Future<void>.microtask(() {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Звонок принят на другом устройстве'),
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.of(context).maybePop(coordinatorCall);
      });
    }
  }

  Future<void> _acceptIncomingCall() async {
    try {
      final acceptedCall =
          await widget.coordinator.acceptCall(_resolvedCall.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _call = acceptedCall;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _finishCall() async {
    try {
      final result = await widget.coordinator.finishCall(_resolvedCall.id);
      if (!mounted) {
        return;
      }
      Navigator.of(context).maybePop(result ?? _resolvedCall);
    } catch (_) {}
  }

  void _minimizeCall() {
    if (_resolvedCall.state == CallState.active) {
      unawaited(widget.pipService.enterPictureInPicture());
    }
    Navigator.of(context).maybePop(_resolvedCall);
  }

  Future<void> _toggleMicrophone() async {
    await widget.coordinator.toggleMicrophone();
  }

  Future<void> _toggleCamera() async {
    await widget.coordinator.toggleCamera();
  }

  Future<void> _switchCamera() async {
    try {
      await widget.coordinator.switchCamera();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось переключить камеру.')),
      );
    }
  }

  Future<void> _openAudioRouteSheet() async {
    unawaited(_audioRouteService.refreshRoutes());
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _AudioRouteSheet(service: _audioRouteService),
    );
  }

  Future<void> _openDevicePickerSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => CallDevicePickerSheet(
        coordinator: widget.coordinator,
      ),
    );
  }

  Future<void> _openInCallChatSheet() async {
    final chatService = _chatService;
    if (chatService == null) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => InCallChatSheet(
        chatId: _resolvedCall.chatId,
        chatService: chatService,
      ),
    );
  }

  void _openSystemSettings() {
    unawaited(openAppSettings());
  }

  bool get _isGroupCall => _resolvedCall.isGroupCall;

  List<RemoteParticipant> get _remoteParticipants =>
      widget.coordinator.room?.remoteParticipants.values.toList() ??
      const <RemoteParticipant>[];

  RemoteParticipant? get _remoteParticipant => _remoteParticipants.firstOrNull;

  VideoTrack? get _remoteVideoTrack {
    final publication = _remoteParticipant?.videoTrackPublications
        .firstWhereOrNull((entry) => entry.source == TrackSource.camera);
    return publication?.track;
  }

  List<VideoTrack?> get _remoteVideoTracks {
    return _remoteParticipants.map((participant) {
      final publication = participant.videoTrackPublications
          .firstWhereOrNull((entry) => entry.source == TrackSource.camera);
      return publication?.track;
    }).toList();
  }

  VideoTrack? get _localVideoTrack {
    final publication = widget
        .coordinator.room?.localParticipant?.videoTrackPublications
        .firstWhereOrNull((entry) => entry.source == TrackSource.camera);
    return publication?.track;
  }

  bool get _showReconnectBanner =>
      _resolvedCall.state == CallState.active &&
      !widget.coordinator.hasMediaPermissionIssue &&
      (widget.coordinator.isReconnectingRoom ||
          widget.coordinator.showReconnectRestoredBanner ||
          widget.coordinator.connectionError != null);

  String _statusLabel() {
    if (widget.coordinator.isReconnectingRoom) {
      return 'Восстанавливаем соединение...';
    }
    if (widget.coordinator.isConnectingRoom) {
      return 'Подключаем звонок...';
    }
    if (widget.coordinator.connectionError != null &&
        _resolvedCall.state == CallState.active) {
      return widget.coordinator.connectionError!;
    }
    switch (_resolvedCall.state) {
      case CallState.ringing:
        return _isIncoming ? 'Входящий звонок' : 'Вызываем...';
      case CallState.active:
        if (widget.coordinator.room == null) {
          return 'Подключаем медиаканал...';
        }
        if (_isGroupCall) {
          if (_remoteParticipants.isEmpty) {
            return 'Ожидаем участников звонка...';
          }
          final connectedCount = _remoteParticipants.length + 1;
          return '${_formatParticipantCount(connectedCount)} в звонке';
        }
        return _remoteParticipant == null
            ? 'Ожидаем подключение собеседника...'
            : (_isVideoCall ? 'Видеозвонок' : 'Аудиозвонок');
      case CallState.rejected:
        return 'Звонок отклонен';
      case CallState.cancelled:
        return 'Звонок отменен';
      case CallState.ended:
        return 'Звонок завершен';
      case CallState.missed:
        return 'Пропущенный звонок';
      case CallState.failed:
        return 'Не удалось начать звонок';
    }
  }

  String _formatParticipantCount(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    final suffix = mod10 == 1 && mod100 != 11
        ? 'участник'
        : (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
            ? 'участника'
            : 'участников');
    return '$count $suffix';
  }

  Widget _buildAvatar() {
    final avatarImage = buildAvatarImageProvider(widget.photoUrl);
    final quality = widget.coordinator.displayedConnectionQuality;
    final qualityColor = callConnectionQualityColor(
      quality,
      isReconnecting: widget.coordinator.isReconnectingRoom,
    );
    return SizedBox(
      width: 138,
      height: 138,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: qualityColor.withValues(alpha: 0.92),
                width: 3,
              ),
            ),
          ),
          Container(
            width: 124,
            height: 124,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.12),
              image: avatarImage != null
                  ? DecorationImage(
                      image: avatarImage,
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: avatarImage == null
                ? Center(
                    child: Text(
                      widget.title.isNotEmpty
                          ? widget.title[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  )
                : null,
          ),
          Positioned(
            right: 2,
            bottom: 10,
            child: CallConnectionQualityBadge(
              quality: quality,
              isReconnecting: widget.coordinator.isReconnectingRoom,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remoteVideoTrack = _remoteVideoTrack;
    final remoteVideoTracks = _remoteVideoTracks;
    final localVideoTrack = _localVideoTrack;
    final hasConnectedRoom = widget.coordinator.room != null;
    final showPermissionSettingsCta = _resolvedCall.state == CallState.active &&
        widget.coordinator.hasMediaPermissionIssue &&
        !hasConnectedRoom;

    return Scaffold(
      backgroundColor: const Color(0xFF111318),
      body: Stack(
        children: [
          Positioned.fill(
            child: _CallStage(
              isGroupCall: _isGroupCall,
              remoteVideoTrack: remoteVideoTrack,
              remoteVideoTracks: remoteVideoTracks,
              fallbackAvatar: _buildAvatar(),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      onPressed: _minimizeCall,
                      color: Colors.white,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      tooltip: 'Свернуть звонок',
                    ),
                  ),
                  const SizedBox(height: 20),
                  GlassPanel(
                    borderRadius: BorderRadius.circular(28),
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    child: Column(
                      children: [
                        Text(
                          widget.title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _statusLabel(),
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.82),
                                  ),
                          textAlign: TextAlign.center,
                        ),
                        if (_resolvedCall.state == CallState.active) ...[
                          const SizedBox(height: 12),
                          CallConnectionQualityBadge(
                            quality:
                                widget.coordinator.displayedConnectionQuality,
                            isReconnecting:
                                widget.coordinator.isReconnectingRoom,
                          ),
                        ],
                        if (_showReconnectBanner) ...[
                          const SizedBox(height: 12),
                          _ReconnectBanner(
                            isReconnecting:
                                widget.coordinator.isReconnectingRoom,
                            isRestored:
                                widget.coordinator.showReconnectRestoredBanner,
                            message: widget.coordinator.connectionError,
                          ),
                        ],
                        if (showPermissionSettingsCta) ...[
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _openSystemSettings,
                            icon: const Icon(Icons.settings_rounded),
                            label: const Text('Открыть настройки'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (localVideoTrack != null && _isVideoCall)
                    Align(
                      alignment: Alignment.bottomRight,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: SizedBox(
                          width: 120,
                          height: 180,
                          child: VideoTrackRenderer(
                            localVideoTrack,
                            fit: VideoViewFit.cover,
                            mirrorMode: widget.coordinator.cameraPosition ==
                                    CameraPosition.front
                                ? VideoViewMirrorMode.mirror
                                : VideoViewMirrorMode.off,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      if (_resolvedCall.state == CallState.active &&
                          hasConnectedRoom) ...[
                        AnimatedBuilder(
                          animation: _audioRouteService,
                          builder: (context, _) => _CallActionButton(
                            onPressed: _openAudioRouteSheet,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.14),
                            icon: _audioRouteIcon(
                              _audioRouteService.selectedRoute?.type,
                            ),
                            tooltip: _audioRouteTooltip(
                              _audioRouteService.selectedRoute,
                            ),
                          ),
                        ),
                        _CallActionButton(
                          onPressed: _toggleMicrophone,
                          backgroundColor: Colors.white.withValues(alpha: 0.14),
                          icon: widget.coordinator.microphoneEnabled
                              ? Icons.mic_rounded
                              : Icons.mic_off_rounded,
                          tooltip: widget.coordinator.microphoneEnabled
                              ? 'Выключить микрофон'
                              : 'Включить микрофон',
                        ),
                        _CallActionButton(
                          onPressed: _openDevicePickerSheet,
                          backgroundColor: Colors.white.withValues(alpha: 0.14),
                          icon: Icons.tune_rounded,
                          tooltip: 'Источники звука и видео',
                        ),
                        if (_chatService != null)
                          _CallActionButton(
                            onPressed: _openInCallChatSheet,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.14),
                            icon: Icons.chat_bubble_outline_rounded,
                            tooltip: 'Чат во время звонка',
                          ),
                        if (_isVideoCall)
                          _CallActionButton(
                            onPressed: _toggleCamera,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.14),
                            icon: widget.coordinator.cameraEnabled
                                ? Icons.videocam_rounded
                                : Icons.videocam_off_rounded,
                            tooltip: widget.coordinator.cameraEnabled
                                ? 'Выключить камеру'
                                : 'Включить камеру',
                          ),
                        if (_isVideoCall && widget.coordinator.cameraEnabled)
                          _CallActionButton(
                            onPressed: widget.coordinator.isSwitchingCamera
                                ? null
                                : _switchCamera,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.14),
                            icon: Icons.cameraswitch_rounded,
                            tooltip: 'Переключить камеру',
                          ),
                      ],
                      _CallActionButton(
                        onPressed: _finishCall,
                        backgroundColor: const Color(0xFFE5484D),
                        icon: Icons.call_end_rounded,
                        tooltip: 'Завершить звонок',
                      ),
                      if (_resolvedCall.state == CallState.ringing &&
                          _isIncoming)
                        _CallActionButton(
                          onPressed: _acceptIncomingCall,
                          backgroundColor: const Color(0xFF2F9E44),
                          icon: _isVideoCall
                              ? Icons.videocam_rounded
                              : Icons.call_rounded,
                          tooltip: _isVideoCall
                              ? 'Принять видеозвонок'
                              : 'Принять аудиозвонок',
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _audioRouteIcon(AudioRouteType? type) {
  switch (type) {
    case AudioRouteType.speaker:
      return Icons.volume_up_rounded;
    case AudioRouteType.earpiece:
      return Icons.phone_in_talk_rounded;
    case AudioRouteType.bluetooth:
      return Icons.bluetooth_audio_rounded;
    case AudioRouteType.wired:
      return Icons.headphones_rounded;
    case AudioRouteType.device:
    case null:
      return Icons.spatial_audio_off_rounded;
  }
}

String _audioRouteTooltip(AudioRouteOption? route) {
  final label = route?.label;
  if (label == null || label.isEmpty) {
    return 'Аудиовыход';
  }
  return 'Аудиовыход: $label';
}

class _CallStage extends StatelessWidget {
  const _CallStage({
    required this.isGroupCall,
    required this.remoteVideoTrack,
    required this.remoteVideoTracks,
    required this.fallbackAvatar,
  });

  final bool isGroupCall;
  final VideoTrack? remoteVideoTrack;
  final List<VideoTrack?> remoteVideoTracks;
  final Widget fallbackAvatar;

  @override
  Widget build(BuildContext context) {
    if (isGroupCall && remoteVideoTracks.length > 1) {
      return DecoratedBox(
        decoration: _stageDecoration,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 84, 12, 220),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: remoteVideoTracks.length <= 2 ? 1 : 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: remoteVideoTracks.length <= 2 ? 1.7 : 0.88,
              ),
              itemCount: remoteVideoTracks.length,
              itemBuilder: (context, index) => _RemoteVideoTile(
                track: remoteVideoTracks[index],
                index: index,
              ),
            ),
          ),
        ),
      );
    }

    if (remoteVideoTrack != null) {
      return VideoTrackRenderer(
        remoteVideoTrack!,
        fit: VideoViewFit.cover,
      );
    }

    return DecoratedBox(
      decoration: _stageDecoration,
      child: Center(child: fallbackAvatar),
    );
  }

  static const BoxDecoration _stageDecoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF1A202C),
        Color(0xFF0F1722),
        Color(0xFF201A27),
      ],
    ),
  );
}

class _RemoteVideoTile extends StatelessWidget {
  const _RemoteVideoTile({
    required this.track,
    required this.index,
  });

  final VideoTrack? track;
  final int index;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (track != null)
              VideoTrackRenderer(
                track!,
                fit: VideoViewFit.cover,
              )
            else
              Center(
                child: Icon(
                  Icons.person_rounded,
                  color: Colors.white.withValues(alpha: 0.78),
                  size: 40,
                ),
              ),
            Positioned(
              left: 10,
              bottom: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.36),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    'Участник ${index + 1}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioRouteSheet extends StatelessWidget {
  const _AudioRouteSheet({required this.service});

  final AudioRouteService service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: AnimatedBuilder(
        animation: service,
        builder: (context, _) {
          final routes = service.routes;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.spatial_audio_off_rounded),
                    const SizedBox(width: 10),
                    Text(
                      'Аудиовыход',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (service.isRefreshing && routes.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (routes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Аудиовыходы не найдены.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  ...routes.map(
                    (route) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_audioRouteIcon(route.type)),
                      title: Text(route.label),
                      trailing: service.isSelecting &&
                              service.selectedRouteId == route.id
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : service.selectedRouteId == route.id
                              ? Icon(
                                  Icons.check_rounded,
                                  color: theme.colorScheme.primary,
                                )
                              : null,
                      onTap: service.isSelecting
                          ? null
                          : () async {
                              await service.selectRoute(route);
                              if (context.mounted &&
                                  service.errorMessage == null) {
                                Navigator.of(context).pop();
                              }
                            },
                    ),
                  ),
                if (service.errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    service.errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ReconnectBanner extends StatelessWidget {
  const _ReconnectBanner({
    required this.isReconnecting,
    required this.isRestored,
    this.message,
  });

  final bool isReconnecting;
  final bool isRestored;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = isReconnecting
        ? 'Восстанавливаем звонок. Звук вернётся автоматически.'
        : isRestored
            ? 'Соединение восстановлено.'
            : message ?? 'Проверяем соединение.';
    final color = isRestored
        ? const Color(0xFF4ADE80)
        : isReconnecting
            ? const Color(0xFFFFC857)
            : const Color(0xFFEF4444);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.56)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isRestored ? Icons.check_circle_rounded : Icons.sync_rounded,
                  color: color,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            if (isReconnecting) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  color: color,
                  backgroundColor: Colors.white.withValues(alpha: 0.16),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.onPressed,
    required this.backgroundColor,
    required this.icon,
    required this.tooltip,
  });

  final VoidCallback? onPressed;
  final Color backgroundColor;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: onPressed == null
            ? backgroundColor.withValues(alpha: 0.45)
            : backgroundColor,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        color: Colors.white,
        iconSize: 28,
        padding: const EdgeInsets.all(18),
        tooltip: tooltip,
      ),
    );
  }
}
