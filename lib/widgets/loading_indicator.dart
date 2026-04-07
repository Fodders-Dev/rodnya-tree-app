import 'package:flutter/material.dart';

class LoadingIndicator extends StatelessWidget {
  final double strokeWidth;
  final Color? color;

  const LoadingIndicator({super.key, this.strokeWidth = 4.0, this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor:
            color != null ? AlwaysStoppedAnimation<Color>(color!) : null,
      ),
    );
  }
}
