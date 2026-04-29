import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as google_web;

Widget buildGoogleSignInAction({
  required ThemeData theme,
  required bool isLoading,
  required bool enabled,
  required VoidCallback onPressed,
  bool useNativeWebButton = false,
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

  if (useNativeWebButton) {
    return SizedBox(
      width: 126,
      height: 40,
      child: google_web.renderButton(
        configuration: google_web.GSIButtonConfiguration(
          type: google_web.GSIButtonType.standard,
          theme: google_web.GSIButtonTheme.outline,
          size: google_web.GSIButtonSize.large,
          text: google_web.GSIButtonText.signinWith,
          shape: google_web.GSIButtonShape.pill,
          logoAlignment: google_web.GSIButtonLogoAlignment.left,
          minimumWidth: 126,
          locale: 'ru',
        ),
      ),
    );
  }

  return OutlinedButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.g_mobiledata, size: 28),
    label: const Text('Google'),
  );
}
