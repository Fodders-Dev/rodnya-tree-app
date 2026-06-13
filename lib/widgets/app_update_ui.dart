import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../services/app_update_service.dart';
import '../theme/app_theme.dart';

/// U2: UI самообновления sideload-сборок.
///   • [AppUpdateBanner] — ненавязчивый баннер «Доступно обновление»
///     (необязательное обновление, дисмисс на сессию).
///   • [AppUpdateGate] — оборачивает приложение и при несовместимой
///     старой версии (mandatory) показывает блокирующий экран.
/// Крупно/контрастно/≥44dp — аудитория 50+.

RodnyaDesignTokens _tokensOf(BuildContext context) {
  final theme = Theme.of(context);
  return theme.extension<RodnyaDesignTokens>() ??
      (theme.brightness == Brightness.dark
          ? RodnyaDesignTokens.dark
          : RodnyaDesignTokens.light);
}

class AppUpdateBanner extends StatelessWidget {
  const AppUpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!GetIt.I.isRegistered<AppUpdateService>()) {
      return const SizedBox.shrink();
    }
    final service = GetIt.I<AppUpdateService>();
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final state = service.state;
        final latest = state.latest;
        if (state.availability != AppUpdateAvailability.optional ||
            latest == null ||
            service.isOptionalDismissed) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final tokens = _tokensOf(context);
        final download = service.downloadProgress;

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Material(
            key: const Key('app-update-banner'),
            color: tokens.surfaceStrong.withValues(alpha: isDark ? 0.92 : 0.96),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusMd),
              side: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.45),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.system_update_rounded,
                        size: 22,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Доступно обновление',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: tokens.ink,
                          ),
                        ),
                      ),
                      if (latest.versionName != null)
                        Text(
                          'версия ${latest.versionName}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tokens.inkSecondary,
                          ),
                        ),
                    ],
                  ),
                  if (latest.notes != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      latest.notes!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: tokens.inkSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _AppUpdateActions(
                    service: service,
                    download: download,
                    showLater: true,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Оборачивает приложение: при mandatory-обновлении показывает
/// блокирующий экран поверх [child], иначе отдаёт [child] как есть.
class AppUpdateGate extends StatelessWidget {
  const AppUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!GetIt.I.isRegistered<AppUpdateService>()) {
      return child;
    }
    final service = GetIt.I<AppUpdateService>();
    return AnimatedBuilder(
      animation: service,
      child: child,
      builder: (context, child) {
        final state = service.state;
        final latest = state.latest;
        if (state.availability != AppUpdateAvailability.mandatory ||
            latest == null) {
          return child!;
        }
        return _MandatoryUpdateScreen(service: service, latest: latest);
      },
    );
  }
}

class _MandatoryUpdateScreen extends StatelessWidget {
  const _MandatoryUpdateScreen({required this.service, required this.latest});

  final AppUpdateService service;
  final AppLatestVersion latest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = _tokensOf(context);
    return Material(
      key: const Key('app-update-mandatory-screen'),
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.system_update_rounded,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Нужно обновить приложение',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: tokens.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Эта версия больше не поддерживается. Чтобы продолжить '
                    'пользоваться «Роднёй», установите свежую версию.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: tokens.inkSecondary,
                      height: 1.45,
                    ),
                  ),
                  if (latest.notes != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      latest.notes!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: tokens.inkSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  _AppUpdateActions(
                    service: service,
                    download: service.downloadProgress,
                    showLater: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Общий блок действий «Обновить» / «Позже» + прогресс/ошибка
/// скачивания. Кнопки ≥48dp.
class _AppUpdateActions extends StatelessWidget {
  const _AppUpdateActions({
    required this.service,
    required this.download,
    required this.showLater,
  });

  final AppUpdateService service;
  final AppUpdateDownloadProgress download;
  final bool showLater;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = _tokensOf(context);

    if (download.isBusy) {
      final fraction = download.fraction;
      final percent = fraction == null ? null : (fraction * 100).round();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              key: const Key('app-update-progress'),
              minHeight: 8,
              value: download.stage == AppUpdateDownloadStage.opening
                  ? null
                  : fraction,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            download.stage == AppUpdateDownloadStage.opening
                ? 'Открываем установщик…'
                : percent == null
                    ? 'Скачиваем обновление…'
                    : 'Скачиваем обновление… $percent%',
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.inkSecondary,
            ),
          ),
        ],
      );
    }

    final isFailed = download.stage == AppUpdateDownloadStage.failed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isFailed && download.error != null) ...[
          Text(
            download.error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            key: const Key('app-update-install-button'),
            onPressed: service.downloadAndInstall,
            icon: const Icon(Icons.download_rounded),
            label: Text(isFailed ? 'Повторить' : 'Обновить'),
          ),
        ),
        if (showLater) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 44,
            child: TextButton(
              key: const Key('app-update-later-button'),
              onPressed: service.dismissOptionalForSession,
              child: const Text('Позже'),
            ),
          ),
        ],
      ],
    );
  }
}
