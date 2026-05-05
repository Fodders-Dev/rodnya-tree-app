import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// App-wide snackbar helper. Renders a floating, rounded toast that
/// reads as a discrete card rather than a flat material edge-to-edge
/// banner — matches the rest of the app's panel-driven aesthetic.
void showAppSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
  Duration? duration,
  SnackBarAction? action,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final tokens = theme.extension<RodnyaDesignTokens>() ??
      (theme.brightness == Brightness.dark
          ? RodnyaDesignTokens.dark
          : RodnyaDesignTokens.light);

  final fg = isError ? colorScheme.onError : tokens.ink;
  final bg = isError ? colorScheme.error : tokens.surfaceStrong;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: bg,
      duration: duration ?? const Duration(seconds: 4),
      action: action,
      behavior: SnackBarBehavior.floating,
      // Constrain on wide layouts so the toast doesn't span the full
      // 1500px of a desktop monitor — feels like a tooltip card, not
      // a wall.
      width: MediaQuery.of(context).size.width >= 720 ? 480 : null,
      // On edge-to-edge Android the system gesture-nav inset needs
      // to be added to the toast margin or the snackbar sits behind
      // the gesture pill. viewPadding.bottom is whatever the OS
      // reserves for nav UI; we add 12dp on top so the toast still
      // floats above it cleanly.
      margin: MediaQuery.of(context).size.width >= 720
          ? null
          : EdgeInsets.fromLTRB(
              12,
              0,
              12,
              MediaQuery.of(context).viewPadding.bottom + 12,
            ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        side: BorderSide(
          color: isError ? Colors.transparent : tokens.surfaceLine,
          width: 0.6,
        ),
      ),
      elevation: 4,
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.info_outline_rounded,
            size: 18,
            color: fg.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
