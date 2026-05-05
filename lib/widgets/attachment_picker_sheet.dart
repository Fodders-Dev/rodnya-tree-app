import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One colored-icon action shown in the attachment picker bottom sheet.
///
/// Hosts construct one [AttachmentPickerAction] per available source
/// (camera, gallery, file, etc) and pass them to [showAttachmentPickerSheet].
/// The sheet renders them as a 4-column grid of vertical icon-tiles —
/// the Telegram / WhatsApp / Instagram pattern, replacing the previous
/// vertical ListTile menu.
class AttachmentPickerAction {
  const AttachmentPickerAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.color,
  });

  /// Unique id returned to the caller. Use a string enum-ish value
  /// (`'camera'`, `'gallery'`, `'file'`) so the call site can switch on it.
  final String id;
  final IconData icon;
  final String label;

  /// Tile background color. Big-app pickers use vivid hues to make the
  /// grid scan-able at a glance — `tokens.accent`, `Colors.indigo`,
  /// `tokens.warm`, `Colors.deepOrange` are typical.
  final Color color;
}

/// Show a Telegram-style attachment picker bottom sheet. Returns the
/// `id` of the action the user tapped, or `null` if the sheet was
/// dismissed.
///
/// `title` shows above the action grid as a small uppercase label —
/// optional, hosts can pass `'Прикрепить'` / `'Добавить медиа'` etc.
Future<String?> showAttachmentPickerSheet(
  BuildContext context, {
  required List<AttachmentPickerAction> actions,
  String? title,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => _AttachmentPickerSheet(
      actions: actions,
      title: title,
    ),
  );
}

class _AttachmentPickerSheet extends StatefulWidget {
  const _AttachmentPickerSheet({required this.actions, this.title});

  final List<AttachmentPickerAction> actions;
  final String? title;

  @override
  State<_AttachmentPickerSheet> createState() => _AttachmentPickerSheetState();
}

class _AttachmentPickerSheetState extends State<_AttachmentPickerSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;

  @override
  void initState() {
    super.initState();
    // Telegram-style staggered tile entry: tiles fade + scale + slide
    // from below in sequence. Total controller duration covers the
    // whole stagger so the LAST tile's animation lines up with the
    // controller end. Per-tile sub-tweens are derived in [_PickerTile]
    // via Interval so we drive everything off one controller.
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    // Forward on the next frame so the sheet's own slide-in animation
    // gets ~50ms of head start — tiles arrive after the panel has
    // landed, not while it's still moving.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entryController.forward();
    });
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if ((widget.title ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Text(
                  widget.title!,
                  style: AppTheme.sans(
                    color: tokens.inkSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            // 4-column grid. Each row holds 4 actions; if there are fewer
            // than 4 in the last row the trailing slots stay empty so the
            // existing actions don't stretch awkwardly.
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final tileWidth = (width / 4).clamp(72.0, 100.0);
                return Wrap(
                  alignment: WrapAlignment.start,
                  spacing: 0,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < widget.actions.length; i++)
                      SizedBox(
                        width: tileWidth,
                        child: _PickerTile(
                          action: widget.actions[i],
                          entry: _entryController,
                          index: i,
                          total: widget.actions.length,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.action,
    required this.entry,
    required this.index,
    required this.total,
  });

  final AttachmentPickerAction action;
  final Animation<double> entry;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    // Each tile starts ~80ms after its left neighbour so the row
    // "rolls in" left-to-right. We cap the per-tile duration at 0.55
    // of the overall window so the last tile still fits inside the
    // controller without rushing.
    final stride = total <= 1 ? 0.0 : 0.45 / (total - 1).clamp(1, 999);
    final start = (index * stride).clamp(0.0, 0.45);
    final tween = CurvedAnimation(
      parent: entry,
      curve: Interval(start, (start + 0.55).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).pop(action.id),
        child: AnimatedBuilder(
          animation: tween,
          builder: (context, child) {
            final t = tween.value;
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 14),
                child: Transform.scale(
                  scale: 0.86 + 0.14 * t,
                  child: child,
                ),
              ),
            );
          },
          child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Big-app picker convention: vivid filled circle 56x56 with
              // a soft drop shadow. Icon centered, white on color.
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      action.color,
                      Color.alphaBlend(
                        Colors.black.withValues(alpha: 0.10),
                        action.color,
                      ),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: action.color.withValues(alpha: 0.32),
                      blurRadius: 14,
                      spreadRadius: -4,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(action.icon, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 8),
              Text(
                action.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.sans(
                  color: tokens.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
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
