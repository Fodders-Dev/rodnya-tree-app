import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../services/app_status_service.dart';

class OfflineIndicator extends StatelessWidget {
  const OfflineIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final appStatusService = GetIt.I<AppStatusService>();
    return AnimatedBuilder(
      animation: appStatusService,
      builder: (context, _) {
        final issue = appStatusService.issue;
        final showBanner = appStatusService.hasVisibleStatus;
        if (!showBanner) {
          return const SizedBox.shrink();
        }

        late final IconData icon;
        late final Color foregroundColor;
        late final Color backgroundColor;
        late final String message;
        final showLoginAction =
            issue?.type == AppStatusIssueType.sessionExpired;
        final showRetryAction = !showLoginAction &&
            (appStatusService.isOffline || issue?.retryable == true);

        if (showLoginAction) {
          icon = Icons.lock_clock_outlined;
          foregroundColor = const Color(0xFF7A2600);
          backgroundColor = const Color(0xFFFFE2D4);
          message = issue?.message ?? 'Сессия истекла. Войдите снова.';
        } else if (appStatusService.isOffline) {
          icon = Icons.cloud_off_outlined;
          foregroundColor = const Color(0xFF6A4A12);
          backgroundColor = const Color(0xFFFFF0CC);
          message =
              'Нет сети. Последние данные останутся на экране, пока соединение не вернётся.';
        } else {
          icon = Icons.error_outline;
          foregroundColor = const Color(0xFF7A2600);
          backgroundColor = const Color(0xFFFFE7D9);
          message = issue?.message ??
              'Не удалось обновить данные. Попробуйте ещё раз.';
        }

        return Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: foregroundColor.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: foregroundColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: foregroundColor,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ),
                if (showRetryAction)
                  TextButton(
                    onPressed: appStatusService.requestRetry,
                    child: const Text('Повторить'),
                  ),
                if (showLoginAction)
                  TextButton(
                    onPressed: () {
                      appStatusService.clearSessionIssue();
                      context.go('/login');
                    },
                    child: const Text('Войти'),
                  )
                else if (!appStatusService.isOffline)
                  IconButton(
                    tooltip: 'Скрыть',
                    onPressed: appStatusService.clearIssue,
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                    color: foregroundColor,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
