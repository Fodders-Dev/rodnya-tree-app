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

class _AttachmentPickerSheet extends StatelessWidget {
  const _AttachmentPickerSheet({required this.actions, this.title});

  final List<AttachmentPickerAction> actions;
  final String? title;

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
            if ((title ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Text(
                  title!,
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
                  children: actions
                      .map(
                        (action) => SizedBox(
                          width: tileWidth,
                          child: _PickerTile(action: action),
                        ),
                      )
                      .toList(),
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
  const _PickerTile({required this.action});

  final AttachmentPickerAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).pop(action.id),
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
    );
  }
}
