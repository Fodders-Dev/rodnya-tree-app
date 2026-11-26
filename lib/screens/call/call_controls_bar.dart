import 'package:flutter/material.dart';

import '../../models/call_state.dart';
import '../../services/audio_route_service.dart';
import 'call_formatters.dart';

/// Bottom call controls bar with collapsible secondary actions, end-call CTA,
/// and pulsing incoming accept / late-join button.
class CallControlsBar extends StatelessWidget {
  const CallControlsBar({
    super.key,
    required this.callState,
    required this.hasConnectedRoom,
    required this.actionsCollapsed,
    required this.onToggleCollapse,
    required this.audioRouteService,
    required this.onToggleSpeakerRoute,
    required this.microphoneEnabled,
    required this.onToggleMicrophone,
    required this.onOpenDevicePickerSheet,
    required this.hasChatService,
    required this.onOpenInCallChatSheet,
    required this.cameraEnabled,
    required this.isVideoCall,
    required this.onToggleCamera,
    required this.isSwitchingCamera,
    required this.onSwitchCamera,
    required this.onFinishCall,
    required this.isIncoming,
    required this.canJoinActive,
    required this.onJoinActiveCall,
    required this.onAcceptIncomingCall,
  });

  final CallState callState;
  final bool hasConnectedRoom;
  final bool actionsCollapsed;
  final VoidCallback onToggleCollapse;
  final AudioRouteService audioRouteService;
  final VoidCallback onToggleSpeakerRoute;
  final bool microphoneEnabled;
  final VoidCallback onToggleMicrophone;
  final VoidCallback onOpenDevicePickerSheet;
  final bool hasChatService;
  final VoidCallback onOpenInCallChatSheet;
  final bool cameraEnabled;
  final bool isVideoCall;
  final VoidCallback onToggleCamera;
  final bool isSwitchingCamera;
  final VoidCallback onSwitchCamera;
  final VoidCallback onFinishCall;
  final bool isIncoming;
  final bool canJoinActive;
  final VoidCallback onJoinActiveCall;
  final VoidCallback onAcceptIncomingCall;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Collapse / expand affordance — only relevant when the
        // call is active and we actually have secondary controls
        // to fold away. Tap toggles actionsCollapsed; the
        // AnimatedSize below cross-fades the row.
        if (callState == CallState.active && hasConnectedRoom)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: CallCollapseToggle(
              collapsed: actionsCollapsed,
              onTap: onToggleCollapse,
            ),
          ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              if (callState == CallState.active &&
                  hasConnectedRoom &&
                  !actionsCollapsed) ...[
                // Вторичные кнопки управления — 54dp (иконка 24 +
                // паддинг 15), не 64: тач-таргет ≥52dp по гайду,
                // но крупный размер оставлен только «Принять» /
                // «Завершить» ниже — на них отвечают одной рукой.
                AnimatedBuilder(
                  animation: audioRouteService,
                  builder: (context, _) => CallActionButton(
                    onPressed: onToggleSpeakerRoute,
                    backgroundColor: Colors.white.withValues(alpha: 0.14),
                    icon: audioRouteIcon(
                      audioRouteService.selectedRoute?.type,
                    ),
                    tooltip: audioRouteTooltip(
                      audioRouteService.selectedRoute,
                    ),
                    iconSize: 24,
                    buttonPadding: 15,
                  ),
                ),
                CallActionButton(
                  onPressed: onToggleMicrophone,
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                  icon: microphoneEnabled
                      ? Icons.mic_rounded
                      : Icons.mic_off_rounded,
                  tooltip: microphoneEnabled
                      ? 'Выключить микрофон'
                      : 'Включить микрофон',
                  iconSize: 24,
                  buttonPadding: 15,
                ),
                CallActionButton(
                  onPressed: onOpenDevicePickerSheet,
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                  icon: Icons.tune_rounded,
                  tooltip: 'Источники звука и видео',
                  iconSize: 24,
                  buttonPadding: 15,
                ),
                if (hasChatService)
                  CallActionButton(
                    onPressed: onOpenInCallChatSheet,
                    backgroundColor: Colors.white.withValues(alpha: 0.14),
                    icon: Icons.chat_bubble_outline_rounded,
                    tooltip: 'Чат во время звонка',
                    iconSize: 24,
                    buttonPadding: 15,
                  ),
                // Camera toggle exposed for both audio AND
                // video calls — pressing it inside an audio
                // call enables the user's camera, effectively
                // upgrading the call to video on their side.
                // Same one-tap "switch to video" UX TG / WA
                // have. Tooltip wording differs to make the
                // intent clear in audio mode.
                CallActionButton(
                  onPressed: onToggleCamera,
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                  icon: cameraEnabled
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                  tooltip: cameraEnabled
                      ? 'Выключить камеру'
                      : (isVideoCall ? 'Включить камеру' : 'Включить видео'),
                  iconSize: 24,
                  buttonPadding: 15,
                ),
                if (cameraEnabled)
                  CallActionButton(
                    onPressed: isSwitchingCamera ? null : onSwitchCamera,
                    backgroundColor: Colors.white.withValues(alpha: 0.14),
                    icon: Icons.cameraswitch_rounded,
                    tooltip: 'Переключить камеру',
                    iconSize: 24,
                    buttonPadding: 15,
                  ),
              ],
              CallActionButton(
                onPressed: onFinishCall,
                backgroundColor: const Color(0xFFE5484D),
                icon: Icons.call_end_rounded,
                tooltip: 'Завершить звонок',
              ),
              if ((callState == CallState.ringing && isIncoming) ||
                  canJoinActive)
                CallActionButton(
                  // «Принять» a ringing invite, «Войти» an
                  // already-active call you belong to (late-join).
                  onPressed:
                      canJoinActive ? onJoinActiveCall : onAcceptIncomingCall,
                  backgroundColor: const Color(0xFF2F9E44),
                  icon:
                      isVideoCall ? Icons.videocam_rounded : Icons.call_rounded,
                  tooltip: canJoinActive
                      ? 'Войти в звонок'
                      : (isVideoCall
                          ? 'Принять видеозвонок'
                          : 'Принять аудиозвонок'),
                  // Ringing → pulsing halos around accept so the
                  // primary CTA grabs attention without needing
                  // a separate "🟢 ВХОДЯЩИЙ" banner.
                  pulse: true,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Round call-action button with two animation polish layers:
///
/// 1. Icon cross-fade + scale when [icon] changes — used for mic /
///    camera / speaker toggles so the change reads as a state flip
///    instead of a hard swap.
/// 2. Subtle scale-on-press feedback (1.0 → 0.92 → 1.0) so the round
///    surface feels "pressable" without needing a Material ripple
///    (which doesn't read as well on a translucent dark background).
///
/// Optional [pulse] flag makes the surrounding container breathe — used
/// on the incoming-call accept button so it grabs attention while the
/// call is ringing.
class CallActionButton extends StatefulWidget {
  const CallActionButton({
    super.key,
    required this.onPressed,
    required this.backgroundColor,
    required this.icon,
    required this.tooltip,
    this.pulse = false,
    this.iconSize = 28,
    this.buttonPadding = 18,
  });

  final VoidCallback? onPressed;
  final Color backgroundColor;
  final IconData icon;
  final String tooltip;
  final bool pulse;
  // Дефолты (28 + 18*2 = 64dp) — обязательный тач-таргет для «Принять» /
  // «Завершить» (на звонок отвечают одной рукой, часто старшие). Вторичные
  // кнопки (микрофон, динамик, камера и т.п.) передают меньшие значения —
  // см. вызовы ниже — но не опускаются ниже 52dp.
  final double iconSize;
  final double buttonPadding;

  @override
  State<CallActionButton> createState() => _CallActionButtonState();
}

class _CallActionButtonState extends State<CallActionButton>
    with TickerProviderStateMixin {
  late final AnimationController _press;
  AnimationController? _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    if (widget.pulse) {
      _pulseCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant CallActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && _pulseCtrl == null) {
      _pulseCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      );
    } else if (!widget.pulse && _pulseCtrl != null) {
      _pulseCtrl!.dispose();
      _pulseCtrl = null;
    }
    _syncPulse();
  }

  /// Start / stop the pulse loop. We skip the loop entirely under
  /// flutter_test's `AutomatedTestWidgetsFlutterBinding` because an
  /// infinite-`repeat()` keeps pumpAndSettle from ever settling. We
  /// also honour `MediaQuery.disableAnimations` for users with
  /// "reduce motion" enabled at the OS level. Comparing the binding
  /// type by name avoids importing flutter_test from production code.
  void _syncPulse() {
    final ctrl = _pulseCtrl;
    if (ctrl == null) return;
    final disable = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    final inTest = bindingName.contains('TestWidgetsFlutterBinding');
    if (disable || inTest) {
      ctrl.stop();
      ctrl.value = 0;
    } else if (!ctrl.isAnimating) {
      ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _press.dispose();
    _pulseCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    final bgColor = disabled
        ? widget.backgroundColor.withValues(alpha: 0.45)
        : widget.backgroundColor;
    final core = AnimatedBuilder(
      animation: _press,
      builder: (context, child) {
        // 1.0 → 0.92 on press, eased back. _press is driven via
        // Listener taps below.
        final scale = 1.0 - 0.08 * _press.value;
        return Transform.scale(scale: scale, child: child);
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          onPressed: widget.onPressed,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: Tween<double>(begin: 0.7, end: 1.0).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Icon(widget.icon, key: ValueKey<IconData>(widget.icon)),
          ),
          color: Colors.white,
          iconSize: widget.iconSize,
          padding: EdgeInsets.all(widget.buttonPadding),
          tooltip: widget.tooltip,
        ),
      ),
    );

    final pressable = Listener(
      onPointerDown: (_) {
        if (!disabled) _press.forward();
      },
      onPointerUp: (_) => _press.reverse(),
      onPointerCancel: (_) => _press.reverse(),
      child: core,
    );

    final pulseCtrl = _pulseCtrl;
    if (pulseCtrl == null) {
      return pressable;
    }
    return AnimatedBuilder(
      animation: pulseCtrl,
      builder: (context, child) {
        // 0 → 1 cycle. We layer two halos that fade out as they expand
        // so the button looks like it's pulsing rings outward — same
        // pattern Telegram / WhatsApp use on incoming-call accept.
        final t = pulseCtrl.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            for (final phase in const [0.0, 0.5])
              Builder(
                builder: (context) {
                  final localT = ((t + phase) % 1.0).clamp(0.0, 1.0);
                  final scale = 1.0 + 0.55 * localT;
                  final opacity = (1.0 - localT) * 0.48;
                  return IgnorePointer(
                    child: Opacity(
                      opacity: opacity,
                      child: Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: bgColor,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            child!,
          ],
        );
      },
      child: pressable,
    );
  }
}

/// Slim glassy chevron pill above the call action row. Tapping toggles
/// the actions row between full (mic / audio / camera / chat / device)
/// and minimal (just the end-call button + accept if ringing). Lets the
/// user reclaim canvas height during a video call without sacrificing
/// the ability to hang up.
class CallCollapseToggle extends StatelessWidget {
  const CallCollapseToggle({
    super.key,
    required this.collapsed,
    required this.onTap,
  });

  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: collapsed ? 'Показать управление' : 'Скрыть управление',
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  collapsed
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  collapsed ? 'Управление' : 'Свернуть',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
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
