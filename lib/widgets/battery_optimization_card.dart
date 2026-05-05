import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../services/battery_optimization_advisor.dart';
import '../theme/app_theme.dart';

/// Dismissible advisory card shown once on Xiaomi/Honor/Huawei/Oppo
/// /OnePlus/Vivo devices that ship aggressive battery savers. These
/// vendors silently kill background services (including the push
/// listener) until the user explicitly whitelists the app in
/// Autostart + battery exception lists. Without that the user just
/// stops getting notifications and incoming-call rings, and they
/// have no way to know why.
///
/// Renders nothing on devices that don't need the warning, on web,
/// or after the user has dismissed it once.
class BatteryOptimizationCard extends StatefulWidget {
  const BatteryOptimizationCard({super.key});

  @override
  State<BatteryOptimizationCard> createState() =>
      _BatteryOptimizationCardState();
}

class _BatteryOptimizationCardState extends State<BatteryOptimizationCard> {
  bool _shouldShow = false;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _resolveVisibility();
  }

  Future<void> _resolveVisibility() async {
    if (!GetIt.I.isRegistered<BatteryOptimizationAdvisor>()) {
      if (mounted) {
        setState(() {
          _resolved = true;
          _shouldShow = false;
        });
      }
      return;
    }
    final advisor = GetIt.I<BatteryOptimizationAdvisor>();
    final visible = await advisor.shouldShowOnboardingTip();
    if (!mounted) return;
    setState(() {
      _resolved = true;
      _shouldShow = visible;
    });
  }

  Future<void> _dismiss() async {
    if (GetIt.I.isRegistered<BatteryOptimizationAdvisor>()) {
      await GetIt.I<BatteryOptimizationAdvisor>().markOnboardingTipShown();
    }
    if (!mounted) return;
    setState(() => _shouldShow = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolved || !_shouldShow) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (isDark ? RodnyaDesignTokens.dark : RodnyaDesignTokens.light);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Material(
        color: tokens.surfaceStrong.withValues(alpha: isDark ? 0.92 : 0.96),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          side: BorderSide(color: tokens.warm.withValues(alpha: 0.45)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.battery_alert_rounded,
                  size: 20,
                  color: tokens.warm,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Чтобы звонки доходили в фоне',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: tokens.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ваш производитель агрессивно усыпляет приложения. '
                      'Откройте настройки → Батарея и включите автозапуск '
                      'Родни и снимите ограничения фоновой активности — '
                      'иначе входящие звонки и сообщения не приходят при '
                      'выключенном экране.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.inkSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Скрыть',
                color: tokens.inkSecondary,
                onPressed: _dismiss,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
