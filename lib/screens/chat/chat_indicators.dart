part of '../chat_screen.dart';

class _AttachmentPlaceholder extends StatelessWidget {
  const _AttachmentPlaceholder({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0x11000000),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReactionGroup {
  const _ReactionGroup({
    required this.emoji,
    required this.count,
    required this.isMine,
  });

  final String emoji;
  final int count;
  final bool isMine;
}

class _ReactionPill extends StatelessWidget {
  const _ReactionPill({
    required this.reaction,
    required this.isMe,
    this.onTap,
  });

  final _ReactionGroup reaction;
  final bool isMe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textColor =
        isMe ? scheme.onPrimary.withValues(alpha: 0.95) : scheme.onSurface;
    final selectedColor = isMe
        ? Colors.white.withValues(alpha: 0.22)
        : scheme.primary.withValues(alpha: 0.18);
    final defaultColor = isMe
        ? Colors.white.withValues(alpha: 0.12)
        : scheme.surface.withValues(alpha: 0.78);
    final borderColor = reaction.isMine
        ? (isMe
            ? Colors.white.withValues(alpha: 0.5)
            : scheme.primary.withValues(alpha: 0.32))
        : (isMe
            ? Colors.white.withValues(alpha: 0.18)
            : scheme.outlineVariant.withValues(alpha: 0.6));

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: reaction.isMine ? selectedColor : defaultColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor, width: 0.7),
        ),
        child: Text(
          '${reaction.emoji} ${reaction.count}',
          // Плотность (чанк 22): 13sp явно (labelSmall=11 по умолчанию) —
          // спека: «ряд чипов ... текст 13sp», чип держит ~24dp высоты.
          style: theme.textTheme.labelSmall?.copyWith(
            color: textColor,
            fontSize: 13,
            fontWeight: reaction.isMine ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _OnlinePulseDot extends StatefulWidget {
  const _OnlinePulseDot({
    required this.color,
    required this.surfaceColor,
  });

  final Color color;
  final Color surfaceColor;

  @override
  State<_OnlinePulseDot> createState() => _OnlinePulseDotState();
}

class _OnlinePulseDotState extends State<_OnlinePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    final inTest = bindingName.contains('TestWidgetsFlutterBinding');
    if (!inTest) _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        // Halo expands + fades over the cycle; core dot stays solid.
        final haloScale = 1.0 + 0.7 * t;
        final haloOpacity = (1.0 - t) * 0.55;
        return SizedBox(
          width: 14,
          height: 14,
          child: Stack(
            alignment: Alignment.center,
            children: [
              IgnorePointer(
                child: Opacity(
                  opacity: haloOpacity,
                  child: Transform.scale(
                    scale: haloScale,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: widget.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.surfaceColor,
                    width: 1.6,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Animated three-dot typing indicator. Each dot fades + scales in a
/// 1.2s loop with 200ms phase offset so the row reads as a live
/// "..." pulse — same pattern Telegram / iMessage use under the
/// peer's name when they're composing. Lives in the chat AppBar
/// subtitle row, sized to fit a 12px text line.
class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});
  final Color color;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 14,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                _Dot(
                  color: widget.color,
                  // Phase each dot 1/6 of the cycle apart so the
                  // sequence reads left-to-right.
                  phase: (_ctrl.value - i / 6) % 1.0,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.phase});
  final Color color;
  final double phase;

  @override
  Widget build(BuildContext context) {
    // Sine-driven opacity + scale so each dot eases up and back down
    // smoothly. Range 0.35 → 1.0 on opacity keeps the dot always
    // visible (the row never goes blank), 0.7 → 1.0 on scale gives a
    // subtle "breathing" feel without jumping.
    final eased = 0.5 + 0.5 * math.sin(phase * 2 * math.pi);
    final opacity = (0.35 + 0.65 * eased).clamp(0.0, 1.0);
    final scale = (0.7 + 0.3 * eased).clamp(0.0, 2.0);
    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// Telegram-style read receipt that animates as the message walks the
/// status ladder: pending (no tick — handled in caller) → sent (single
/// ✓) → delivered (✓✓ faded) → read (✓✓ blue). [AnimatedSwitcher]
/// cross-fades + scales whenever the state actually changes; identical
/// repaints (same status) keep the existing icon mounted.
class _ReadReceiptTick extends StatelessWidget {
  const _ReadReceiptTick({
    required this.isRead,
    required this.isDelivered,
    required this.readColor,
    required this.dimColor,
  });

  final bool isRead;
  final bool isDelivered;
  final Color readColor;
  final Color dimColor;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    final String stateKey;
    if (isRead) {
      icon = Icons.done_all;
      color = readColor;
      stateKey = 'read';
    } else if (isDelivered) {
      icon = Icons.done_all;
      color = dimColor;
      stateKey = 'delivered';
    } else {
      icon = Icons.done;
      color = dimColor;
      stateKey = 'sent';
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        // Scale-in from 0.6 + fade so the upgrade from ✓ → ✓✓ /
        // delivered → read reads as a deliberate beat. We set
        // AlignmentGeometry.center so the icon doesn't slide.
        return ScaleTransition(
          scale: Tween<double>(begin: 0.6, end: 1.0).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: Icon(
        icon,
        key: ValueKey<String>('read-receipt-$stateKey'),
        size: 14,
        color: color,
      ),
    );
  }
}

/// Telegram-style "long-press → context menu" route: backdrop blur
/// grows from 0 to 14, dim grows from 0 to 32% black, the action card
/// slides up 25% + fades in. Used for both incoming and outgoing
/// message-action sheets so the touch interaction reads as premium
/// instead of "yet another bottom sheet".
///
/// API mirrors [showModalBottomSheet] — pass a builder, dismiss via
/// `Navigator.of(context).pop(value)` from inside, await the future.
/// `padding` controls the gap from the bottom edge so the card lifts
/// above the system safe-area / bottom nav.
class _AnimatedComposerSlot extends StatelessWidget {
  const _AnimatedComposerSlot({required this.show, required this.child});

  final bool show;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final slide = Tween<Offset>(
            begin: const Offset(0, -0.18),
            end: Offset.zero,
          ).animate(animation);
          return ClipRect(
            child: SlideTransition(
              position: slide,
              child: FadeTransition(opacity: animation, child: child),
            ),
          );
        },
        child: show && child != null
            ? Padding(
                key: const ValueKey('composer-slot-shown'),
                padding: const EdgeInsets.only(bottom: 8),
                child: child,
              )
            : const SizedBox.shrink(key: ValueKey('composer-slot-hidden')),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});

  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _scale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _opacity = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(
          scale: _scale.value,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Mic icon wrapped in a pulsing red ring glow — shown while recording.
class _PulsingMicButton extends StatefulWidget {
  const _PulsingMicButton({required this.color});

  final Color color;

  @override
  State<_PulsingMicButton> createState() => _PulsingMicButtonState();
}

class _PulsingMicButtonState extends State<_PulsingMicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _ring;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _ring = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Stack(
        alignment: Alignment.center,
        children: [
          // Expanding ring
          Container(
            width: 44 + _ring.value * 16,
            height: 44 + _ring.value * 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(
                alpha: (1.0 - _ring.value) * 0.28,
              ),
            ),
          ),
          child!,
        ],
      ),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.mic_rounded, color: Colors.white, size: 22),
      ),
    );
  }
}

// ── Chat bubbles ─────────────────────────────────────────────────────────────

/// Flat surface-pill icon button used in the composer for attach + secondary
/// actions. Mirrors the reference `.iconbtn` style (38x38, surface bg, hairline
/// border, ink color icon). Lighter visual weight than IconButton.filledTonal.
class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isEnabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Container(
            // M3 (50+): 44dp тач-таргет; без фона и рамки — плоская иконка
            // внутри капсулы композера.
            width: 44,
            height: 44,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 22,
              color: isEnabled
                  ? scheme.onSurface.withValues(alpha: 0.78)
                  : scheme.onSurface.withValues(alpha: 0.32),
            ),
          ),
        ),
      ),
    );
  }
}

/// Accent-filled circle for the composer send action. Reference
/// `.composer .send`: 42x42 round, accent gradient, drop shadow that
/// reads as "the primary action lives here".
class _ComposerSendButton extends StatelessWidget {
  const _ComposerSendButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Container(
            // M3 (50+): 48dp вместо 42 — send-кнопка по гайдлайну, как
            // mic-кнопка рядом.
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.primary,
                  Color.alphaBlend(
                    Colors.black.withValues(alpha: 0.10),
                    scheme.primary,
                  ),
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.40),
                  blurRadius: 14,
                  spreadRadius: -4,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 21, color: scheme.onPrimary),
          ),
        ),
      ),
    );
  }
}
