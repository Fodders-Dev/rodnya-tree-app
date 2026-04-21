import 'package:flutter/material.dart';

Widget buildGoogleSignInAction({
  required ThemeData theme,
  required bool isLoading,
  required bool enabled,
  required VoidCallback onPressed,
}) {
  if (!enabled || isLoading) {
    return OutlinedButton.icon(
      onPressed: null,
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

  return OutlinedButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.g_mobiledata, size: 28),
    label: const Text('Google'),
  );
}
