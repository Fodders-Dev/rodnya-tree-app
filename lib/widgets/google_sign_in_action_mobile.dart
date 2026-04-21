import 'package:flutter/material.dart';

Widget buildGoogleSignInAction({
  required ThemeData theme,
  required bool isLoading,
  required bool enabled,
  required VoidCallback onPressed,
}) {
  return OutlinedButton.icon(
    onPressed: enabled ? onPressed : null,
    icon: isLoading
        ? SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          )
        : const Icon(Icons.g_mobiledata, size: 28),
    label: const Text('Google'),
  );
}
