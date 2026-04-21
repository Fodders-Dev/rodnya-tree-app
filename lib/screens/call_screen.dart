import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/call_invite.dart';
import '../models/call_media_mode.dart';
import '../models/call_state.dart';
import '../services/call_coordinator_service.dart';
import '../widgets/glass_panel.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.initialCall,
    required this.title,
    required this.coordinator,
    this.photoUrl,
  });

  final CallInvite initialCall;
  final String title;
  final String? photoUrl;
  final CallCoordinatorService coordinator;

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

  Future<void> _toggleMicrophone() async {
    await widget.coordinator.toggleMicrophone();
  }

  Future<void> _toggleCamera() async {
    await widget.coordinator.toggleCamera();
  }

  void _openSystemSettings() {
    unawaited(openAppSettings());
  }

  RemoteParticipant? get _remoteParticipant =>
      widget.coordinator.room?.remoteParticipants.values.firstOrNull;

  VideoTrack? get _remoteVideoTrack {
    final publication = _remoteParticipant?.videoTrackPublications
        .firstWhereOrNull((entry) => entry.source == TrackSource.camera);
    return publication?.track;
  }

  VideoTrack? get _localVideoTrack {
    final publication = widget
        .coordinator.room?.localParticipant?.videoTrackPublications
        .firstWhereOrNull((entry) => entry.source == TrackSource.camera);
    return publication?.track;
  }

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

  Widget _buildAvatar() {
    return Container(
      width: 124,
      height: 124,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.12),
        image: widget.photoUrl != null && widget.photoUrl!.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(widget.photoUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: widget.photoUrl == null || widget.photoUrl!.isEmpty
          ? Center(
              child: Text(
                widget.title.isNotEmpty ? widget.title[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final remoteVideoTrack = _remoteVideoTrack;
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
            child: remoteVideoTrack != null
                ? VideoTrackRenderer(
                    remoteVideoTrack,
                    fit: VideoViewFit.cover,
                  )
                : DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF1A202C),
                          Color(0xFF0F1722),
                          Color(0xFF201A27),
                        ],
                      ),
                    ),
                    child: Center(child: _buildAvatar()),
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
                      onPressed: () =>
                          Navigator.of(context).maybePop(_resolvedCall),
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
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_resolvedCall.state == CallState.active &&
                          hasConnectedRoom) ...[
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
                        if (_isVideoCall) const SizedBox(width: 16),
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
                        const SizedBox(width: 16),
                      ],
                      _CallActionButton(
                        onPressed: _finishCall,
                        backgroundColor: const Color(0xFFE5484D),
                        icon: Icons.call_end_rounded,
                        tooltip: 'Завершить звонок',
                      ),
                      if (_resolvedCall.state == CallState.ringing &&
                          _isIncoming)
                        const SizedBox(width: 16),
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

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.onPressed,
    required this.backgroundColor,
    required this.icon,
    required this.tooltip,
  });

  final VoidCallback onPressed;
  final Color backgroundColor;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
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
