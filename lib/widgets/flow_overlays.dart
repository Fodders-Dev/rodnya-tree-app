import 'package:flutter/material.dart';

import 'glass_panel.dart';

Future<DateTime?> showRodnyaDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  Locale locale = const Locale('ru', 'RU'),
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;

  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    locale: locale,
    builder: (context, child) {
      final dialogTheme = theme.copyWith(
        colorScheme: colorScheme.copyWith(
          primary: colorScheme.primary,
          onPrimary: colorScheme.onPrimary,
          surface: colorScheme.surface,
          onSurface: colorScheme.onSurface,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: colorScheme.surface.withValues(alpha: 0.96),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: colorScheme.surface.withValues(alpha: 0.98),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          headerBackgroundColor:
              colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
          headerForegroundColor: colorScheme.onSurface,
          dayStyle: theme.textTheme.bodyMedium,
          yearStyle: theme.textTheme.bodyMedium,
          todayForegroundColor: WidgetStatePropertyAll(colorScheme.primary),
          todayBorder: BorderSide(color: colorScheme.primary),
          confirmButtonStyle: TextButton.styleFrom(
            foregroundColor: colorScheme.primary,
          ),
          cancelButtonStyle: TextButton.styleFrom(
            foregroundColor: colorScheme.onSurfaceVariant,
          ),
        ),
      );

      return Theme(
        data: dialogTheme,
        child: child ?? const SizedBox.shrink(),
      );
    },
  );
}

Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext dialogContext) builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.16),
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: builder(dialogContext),
    ),
  );
}

class GlassDialogFrame extends StatelessWidget {
  const GlassDialogFrame({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.icon,
    this.tint,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;
  final IconData? icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = tint ?? theme.colorScheme.primary;

    return GlassPanel(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(28),
      color: theme.colorScheme.surface.withValues(alpha: 0.9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: tone),
            ),
            const SizedBox(height: 14),
          ],
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          content,
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 10,
            children: actions,
          ),
        ],
      ),
    );
  }
}
