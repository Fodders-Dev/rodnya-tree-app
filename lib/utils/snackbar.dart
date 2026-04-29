import 'package:flutter/material.dart';

void showAppSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
  Duration? duration,
  SnackBarAction? action,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: isError ? colorScheme.error : null,
      duration: duration ?? const Duration(seconds: 4),
      action: action,
      content: Text(
        message,
        style: isError ? TextStyle(color: colorScheme.onError) : null,
      ),
    ),
  );
}
