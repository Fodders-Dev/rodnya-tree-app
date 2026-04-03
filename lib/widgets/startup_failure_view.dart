import 'package:flutter/material.dart';

class StartupFailureView extends StatefulWidget {
  const StartupFailureView({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
    this.onResetSessionAndRetry,
    this.showTechnicalDetails = false,
    this.technicalDetails,
  });

  final String title;
  final String message;
  final Future<void> Function() onRetry;
  final Future<void> Function()? onResetSessionAndRetry;
  final bool showTechnicalDetails;
  final String? technicalDetails;

  @override
  State<StartupFailureView> createState() => _StartupFailureViewState();
}

class _StartupFailureViewState extends State<StartupFailureView> {
  bool _isRetrying = false;
  bool _isResetting = false;

  Future<void> _runAction({
    required bool isResetAction,
    required Future<void> Function() action,
  }) async {
    if (_isRetrying || _isResetting) {
      return;
    }

    setState(() {
      if (isResetAction) {
        _isResetting = true;
      } else {
        _isRetrying = true;
      }
    });

    try {
      await action();
    } finally {
      if (mounted) {
        setState(() {
          if (isResetAction) {
            _isResetting = false;
          } else {
            _isRetrying = false;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canShowDetails = widget.showTechnicalDetails &&
        widget.technicalDetails != null &&
        widget.technicalDetails!.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.message,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: (_isRetrying || _isResetting)
                    ? null
                    : () => _runAction(
                          isResetAction: false,
                          action: widget.onRetry,
                        ),
                child: _isRetrying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Попробовать снова'),
              ),
              if (widget.onResetSessionAndRetry != null)
                OutlinedButton(
                  onPressed: (_isRetrying || _isResetting)
                      ? null
                      : () => _runAction(
                            isResetAction: true,
                            action: widget.onResetSessionAndRetry!,
                          ),
                  child: _isResetting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Сбросить сессию и войти заново'),
                ),
            ],
          ),
          if (canShowDetails) ...[
            const SizedBox(height: 20),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(
                'Технические детали',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              children: [
                SelectableText(
                  widget.technicalDetails!,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
