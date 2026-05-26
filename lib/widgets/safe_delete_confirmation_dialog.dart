import 'package:flutter/material.dart';

/// Shared destructive-action confirmation dialog. Extracted из Q4 tree
/// person delete pattern (50edd73) когда Post delete polish needed
/// the same shape (Ship 2026-05-26, audit Screen 3.5).
///
/// Telegram-grade safety bar:
///   • Severity icon в error tint
///   • Honest consequence copy (no false «recovery in 30 days» promise
///     если backend hard-deletes — caller passes accurate body)
///   • Destructive «confirm» button rendered как FilledButton.tonal с
///     errorContainer background + error foreground (visually weighted
///     vs Cancel)
///   • barrierDismissible=false — tap-outside не считается consent
///
/// Returns `true` когда user explicitly confirmed; `false` либо `null`
/// otherwise. Caller should treat anything except `true` as «не удалять».
///
/// ```dart
/// final ok = await showSafeDeleteConfirmation(
///   context,
///   title: 'Удалить публикацию?',
///   body: 'Пост исчезнет у всех родственников. Это действие нельзя отменить.',
///   confirmLabel: 'Удалить',
/// );
/// if (ok != true) return;
/// ```
Future<bool> showSafeDeleteConfirmation(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Удалить',
  String cancelLabel = 'Отмена',
  IconData icon = Icons.delete_outline_rounded,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return SafeDeleteConfirmationDialog(
        title: title,
        body: body,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        icon: icon,
      );
    },
  );
  return result == true;
}

class SafeDeleteConfirmationDialog extends StatelessWidget {
  const SafeDeleteConfirmationDialog({
    super.key,
    required this.title,
    required this.body,
    this.confirmLabel = 'Удалить',
    this.cancelLabel = 'Отмена',
    this.icon = Icons.delete_outline_rounded,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final String cancelLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: Icon(icon, color: theme.colorScheme.error),
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          key: const Key('safe-delete-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton.tonal(
          key: const Key('safe-delete-confirm'),
          style: FilledButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
            backgroundColor: theme.colorScheme.errorContainer,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
