// ignore_for_file: constant_identifier_names, unused_field, use_build_context_synchronously
// ignore_for_file: library_private_types_in_public_api
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../services/rustore_service.dart';
// Импортируем типы для биллинга
import 'package:flutter_rustore_billing/pigeons/rustore.dart' as billing;
import 'package:get_it/get_it.dart'; // Для доступа к RustoreService
import 'package:go_router/go_router.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../providers/tree_provider.dart';
import '../services/custom_api_notification_service.dart';
import '../config/storefront_config.dart';
import '../widgets/glass_panel.dart';
import '../widgets/flow_overlays.dart';

// --- ID нашего тестового продукта ---
const String PREMIUM_PRODUCT_ID = 'lineage_premium';
// --- ID для разовой покупки ---
const String ONE_TIME_PRODUCT_ID = 'lineage_premium_product';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();
  // Получаем RustoreService из GetIt
  final RustoreService _rustoreService = GetIt.I<RustoreService>();
  final StorefrontConfig _storefrontConfig = StorefrontConfig.current;
  bool _isLoading = false;
  bool _isDarkMode = false;
  bool _notificationsEnabled = true;
  bool _profilePrivate = false;

  // Состояние для премиума
  bool _isPremium = false;
  String? _lastPurchaseId; // Для возможности удаления тестовой покупки
  bool _billingLoading = true; // Индикатор загрузки статуса покупки
  // --- Состояние для разовой покупки ---
  bool _oneTimePurchaseLoading = false;
  String _appVersionLabel = 'Версия загружается...';

  // --- Состояние для оценки приложения ---
  bool _hasRatedApp = false; // Изначально считаем, что не оценил
  bool _checkingRatingStatus = true; // Индикатор загрузки статуса оценки

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _loadNotificationSettings();
    if (_showPremiumSection) {
      _checkPremiumStatus();
    } else {
      _billingLoading = false;
    }
    if (_showReviewSection) {
      _checkAppRatingStatus();
    } else {
      _checkingRatingStatus = false;
    }
  }

  CustomApiNotificationService? get _customNotificationService =>
      GetIt.I.isRegistered<CustomApiNotificationService>()
          ? GetIt.I<CustomApiNotificationService>()
          : null;

  bool get _showPremiumSection =>
      _storefrontConfig.isRustore && _storefrontConfig.enableRustoreBilling;

  bool get _showReviewSection =>
      _storefrontConfig.isRustore && _storefrontConfig.enableRustoreReview;

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) {
      return;
    }
    setState(() {
      _appVersionLabel =
          'Версия ${packageInfo.version} (сборка ${packageInfo.buildNumber})';
    });
  }

  Future<void> _loadNotificationSettings() async {
    final notificationService = _customNotificationService;
    if (notificationService == null || !mounted) {
      return;
    }

    setState(() {
      _notificationsEnabled = notificationService.notificationsEnabled;
    });
  }

  Future<void> _toggleNotifications(bool value) async {
    final notificationService = _customNotificationService;
    var nextValue = value;

    if (notificationService != null) {
      nextValue = await notificationService.setNotificationsEnabled(
        value,
        promptForBrowserPermission: value,
      );

      if (!mounted) {
        return;
      }

      if (value && !nextValue) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Разрешите уведомления в браузере, чтобы Родня могла показать новые сообщения и приглашения.',
            ),
          ),
        );
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _notificationsEnabled = nextValue;
    });
  }

  // Функция для проверки статуса премиум
  Future<void> _checkPremiumStatus() async {
    setState(() {
      _billingLoading = true;
    });
    try {
      final purchases = await _rustoreService.checkPurchases();
      // Проверяем, есть ли среди покупок наш PREMIUM_PRODUCT_ID
      final premiumPurchase = purchases.firstWhere(
        (p) => p.productId == PREMIUM_PRODUCT_ID,
        // Возвращаем заглушку Purchase с purchaseState = null, если не найдено
        orElse: () => billing.Purchase(
          purchaseId: '',
          productId: '',
          purchaseTime: '',
          orderId: '',
          purchaseState: null,
        ),
      );

      setState(() {
        // Считаем премиумом, если покупка найдена и ее статус не null
        // (в API v8 статус может быть числом или отсутствовать? Проверяем на null)
        // Конкретные значения статусов (1=CREATED, 2=PAID, 3=CONFIRMED, 4=CANCELLED) предполагаются.
        // Пока будем считать активным, если статус не null (т.е. покупка существует).
        _isPremium = premiumPurchase.productId == PREMIUM_PRODUCT_ID &&
            premiumPurchase.purchaseState == '3';
        _lastPurchaseId = _isPremium ? premiumPurchase.purchaseId : null;
      });
    } catch (e) {
      debugPrint("Error checking premium status: $e");
      setState(() {
        _isPremium = false;
      }); // Считаем не премиумом при ошибке
    } finally {
      setState(() {
        _billingLoading = false;
      });
    }
  }

  // --- НОВАЯ ФУНКЦИЯ: Проверка, оставлял ли пользователь отзыв ---
  Future<void> _checkAppRatingStatus() async {
    setState(() {
      _checkingRatingStatus = true;
    });
    try {
      // Предполагаем, что в RustoreService есть метод, который может
      // косвенно определить, оставлял ли пользователь отзыв.
      // Например, если requestReview() больше не показывает диалог.
      // Или, если есть какой-то флаг в SharedPreferences, устанавливаемый после успешного запроса.
      // **ВАЖНО:** На данный момент у RuStore SDK нет прямого способа проверить,
      // был ли отзыв *фактически* оставлен. Мы можем только проверить,
      // был ли *запущен* процесс оценки (requestReview) и не вызвал ли он ошибку.
      // Будем использовать флаг в SharedPreferences как наиболее реалистичный вариант.
      final bool hasRequestedReview =
          await _rustoreService.checkIfReviewWasRequested(); // Пример метода
      // Исправлено: Проверяем mounted перед вызовом setState
      if (mounted) {
        setState(() {
          _hasRatedApp = hasRequestedReview;
        });
      }
    } catch (e) {
      debugPrint("Error checking app rating status: $e");
      // Оставляем _hasRatedApp = false при ошибке
    } finally {
      if (mounted) {
        setState(() {
          _checkingRatingStatus = false;
        });
      }
    }
  }

  // Функция покупки премиума
  Future<void> _purchasePremium() async {
    setState(() {
      _billingLoading = true;
    });
    try {
      // Сначала получим информацию о продукте
      final products = await _rustoreService.getProducts([PREMIUM_PRODUCT_ID]);
      if (products.isEmpty) {
        debugPrint("Product $PREMIUM_PRODUCT_ID not found in RuStore.");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Товар $PREMIUM_PRODUCT_ID не найден.')),
          );
        }
        setState(() {
          _billingLoading = false;
        });
        return;
      }

      final billing.PaymentResult? result =
          await _rustoreService.purchaseProduct(PREMIUM_PRODUCT_ID);

      // Временно упрощаем проверку из-за ошибок с полями PaymentResult
      if (result != null) {
        debugPrint("Purchase flow finished. Result: ${result.toString()}");
        debugPrint(
            "Purchase successful (assumed)! Now attempting to confirm...");

        // --- ДОБАВЛЯЕМ ПОДТВЕРЖДЕНИЕ ПОКУПКИ ---
        try {
          // Небольшая пауза, чтобы дать серверам RuStore обработать покупку
          await Future.delayed(const Duration(seconds: 2));

          debugPrint('Checking purchases again to find the one to confirm...');
          final purchases = await _rustoreService.checkPurchases();
          final purchaseToConfirm = purchases.firstWhere(
            (p) =>
                p.productId == PREMIUM_PRODUCT_ID &&
                p.purchaseState !=
                    '3', // Ищем НЕ подтвержденную (state 3 = CONFIRMED)
            orElse: () => billing.Purchase(
              purchaseId: '',
              productId: '',
              purchaseTime: '',
              orderId: '',
              purchaseState: null,
            ), // Заглушка
          );

          // --- ИСПРАВЛЕНИЕ NULL SAFETY ---
          final String? currentPurchaseId = purchaseToConfirm.purchaseId;
          if (currentPurchaseId != null && currentPurchaseId.isNotEmpty) {
            // Сначала проверка на null!
            debugPrint('Found purchase to confirm: $currentPurchaseId');
            await _rustoreService.confirmPurchase(
              currentPurchaseId,
            ); // Передаем не-null ID
            debugPrint('Purchase $currentPurchaseId confirmed successfully.');
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Покупка подтверждена!')));
            }
          } else {
            debugPrint(
              'Could not find the new purchase to confirm (it might be already confirmed or in error state). Status will be checked.',
            );
            // Не показываем ошибку пользователю, просто проверим статус позже
          }
        } catch (confirmError) {
          debugPrint('Error confirming purchase: $confirmError');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Ошибка при подтверждении покупки: $confirmError',
                ),
              ),
            );
          }
          // Продолжаем, чтобы обновить статус
        }
        // ------------------------------------

        await _checkPremiumStatus(); // Обновляем статус после покупки и попытки подтверждения
      } else {
        debugPrint(
          "Purchase flow returned null result (likely cancelled or failed).",
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Покупка не удалась или была отменена.')),
          );
        }
      }
    } catch (e) {
      debugPrint("Error during purchase process: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка покупки премиума: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _billingLoading = false;
        });
      }
    }
  }

  // --- НОВАЯ ФУНКЦИЯ покупки РАЗОВОГО товара ---
  Future<void> _purchaseOneTimeProduct() async {
    setState(() {
      _oneTimePurchaseLoading = true;
    });
    try {
      debugPrint(
          'Attempting to get one-time product info: $ONE_TIME_PRODUCT_ID');
      final products = await _rustoreService.getProducts([ONE_TIME_PRODUCT_ID]);
      if (products.isEmpty) {
        debugPrint("Product $ONE_TIME_PRODUCT_ID not found in RuStore.");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Товар $ONE_TIME_PRODUCT_ID не найден.')),
          );
        }
        setState(() {
          _oneTimePurchaseLoading = false;
        });
        return;
      }
      // Добавим лог с информацией о продукте
      debugPrint('Product info found: ${products.first.toString()}');

      debugPrint(
          'Attempting to purchase one-time product: $ONE_TIME_PRODUCT_ID');
      final billing.PaymentResult? result =
          await _rustoreService.purchaseProduct(ONE_TIME_PRODUCT_ID);

      if (result != null) {
        debugPrint(
            "One-time purchase flow finished. Result: ${result.toString()}");
        debugPrint(
          "One-time purchase successful (assumed)! Now attempting to confirm/consume...",
        );

        // Подтверждение/Потребление разовой покупки (логика та же, что и для подписки)
        try {
          await Future.delayed(const Duration(seconds: 2));
          debugPrint(
            'Checking purchases again to find the one-time purchase to confirm...',
          );
          final purchases = await _rustoreService.checkPurchases();
          // Ищем по ID разового продукта, НЕ подтвержденную
          final purchaseToConfirm = purchases.firstWhere(
            (p) => p.productId == ONE_TIME_PRODUCT_ID && p.purchaseState != '3',
            orElse: () => billing.Purchase(
              purchaseId: '',
              productId: '',
              purchaseTime: '',
              orderId: '',
              purchaseState: null,
            ),
          );

          final String? currentPurchaseId = purchaseToConfirm.purchaseId;
          if (currentPurchaseId != null && currentPurchaseId.isNotEmpty) {
            debugPrint(
              'Found one-time purchase to confirm/consume: $currentPurchaseId',
            );
            await _rustoreService.confirmPurchase(currentPurchaseId);
            debugPrint(
              'One-time purchase $currentPurchaseId confirmed/consumed successfully.',
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Разовая покупка подтверждена/потреблена!'),
                ),
              );
            }
          } else {
            debugPrint(
              'Could not find the new one-time purchase to confirm/consume.',
            );
          }
        } catch (confirmError) {
          debugPrint(
              'Error confirming/consuming one-time purchase: $confirmError');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Ошибка подтверждения/потребления разовой покупки: $confirmError',
                ),
              ),
            );
          }
        }
        // Статус премиума не обновляем, т.к. это разовая покупка
        // Можно добавить отдельную логику для отслеживания разовых покупок, если нужно
      } else {
        debugPrint(
          "One-time purchase flow returned null result (likely cancelled or failed).",
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Разовая покупка не удалась или была отменена.'),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error during one-time purchase process: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка разовой покупки: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _oneTimePurchaseLoading = false;
        });
      }
    }
  }

  // Функция удаления тестовой покупки
  Future<void> _deleteTestPurchase() async {
    if (_lastPurchaseId != null) {
      setState(() {
        _billingLoading = true;
      });
      final success = await _rustoreService.deletePurchase(_lastPurchaseId!);
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Тестовая покупка удалена.')));
        }
        _checkPremiumStatus(); // Обновляем статус
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось удалить тестовую покупку.')),
          );
        }
        setState(() {
          _billingLoading = false;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isDarkMode = Theme.of(context).brightness == Brightness.dark;
  }

  // Функция для отображения диалога подтверждения удаления аккаунта
  Future<void> _showDeleteAccountConfirmation() async {
    final TextEditingController passwordController = TextEditingController();
    bool isPasswordVisible = false;

    return showGlassDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final theme = Theme.of(context);

            return GlassDialogFrame(
              icon: Icons.delete_forever,
              tint: theme.colorScheme.error,
              title: 'Удалить аккаунт',
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Это действие нельзя отменить.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Введите пароль для подтверждения.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLowest
                          .withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextField(
                      controller: passwordController,
                      obscureText: !isPasswordVisible,
                      decoration: InputDecoration(
                        hintText: 'Пароль',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            isPasswordVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setDialogState(() {
                              isPasswordVisible = !isPasswordVisible;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Отмена'),
                ),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    if (passwordController.text.isNotEmpty) {
                      _deleteAccount(passwordController.text);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Введите пароль для удаления аккаунта'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  child: const Text('Удалить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Улучшенная функция для удаления аккаунта с надежным перенаправлением
  Future<void> _deleteAccount(String password) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.deleteAccount(password);
      if (GetIt.I.isRegistered<TreeProvider>()) {
        await GetIt.I<TreeProvider>().clearSelection();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ваш аккаунт был успешно удален'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/login');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при удалении аккаунта: $e'),
            backgroundColor: Colors.red,
          ),
        );

        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSettingsHeader(),
                      const SizedBox(height: 16),
                      _buildSectionCard('Внешний вид', [
                        _buildSwitchRow(
                          icon: themeProvider.isDarkMode
                              ? Icons.dark_mode
                              : Icons.light_mode,
                          title: 'Тёмная тема',
                          subtitle: themeProvider.isDarkMode
                              ? 'Тёмная схема'
                              : 'Светлая схема',
                          value: themeProvider.isDarkMode,
                          onChanged: (_) => themeProvider.toggleTheme(),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _buildSectionCard('Уведомления и доступ', [
                        _buildSwitchRow(
                          icon: Icons.notifications_outlined,
                          title: 'Уведомления',
                          subtitle:
                              _notificationsEnabled ? 'Включены' : 'Выключены',
                          value: _notificationsEnabled,
                          onChanged: _toggleNotifications,
                        ),
                        _buildSwitchRow(
                          icon: Icons.lock_outline,
                          title: 'Приватный профиль',
                          subtitle: _profilePrivate
                              ? 'Только по приглашению'
                              : 'Обычный доступ',
                          value: _profilePrivate,
                          onChanged: (value) {
                            setState(() {
                              _profilePrivate = value;
                            });
                          },
                        ),
                        _buildActionRow(
                          icon: Icons.block_outlined,
                          title: 'Заблокированные',
                          subtitle: 'Личные блокировки',
                          onTap: () =>
                              GoRouter.of(context).push('/profile/blocks'),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _buildSectionCard('Документы и поддержка', [
                        _buildActionRow(
                          icon: Icons.privacy_tip_outlined,
                          title: 'Политика',
                          subtitle: 'Конфиденциальность',
                          onTap: () => GoRouter.of(context).push('/privacy'),
                        ),
                        _buildActionRow(
                          icon: Icons.description_outlined,
                          title: 'Условия',
                          subtitle: 'Использование',
                          onTap: () => GoRouter.of(context).push('/terms'),
                        ),
                        _buildActionRow(
                          icon: Icons.support_agent_outlined,
                          title: 'Поддержка',
                          subtitle: 'Почта и страница',
                          onTap: () => GoRouter.of(context).push('/support'),
                        ),
                        _buildActionRow(
                          icon: Icons.delete_outline_rounded,
                          title: 'Как удалить аккаунт',
                          subtitle: 'Публичная инструкция',
                          onTap: () =>
                              GoRouter.of(context).push('/account-deletion'),
                        ),
                        _buildActionRow(
                          icon: Icons.info_outline,
                          title: 'О приложении',
                          subtitle: _appVersionLabel,
                          onTap: () => context.push('/profile/about'),
                        ),
                      ]),
                      if (_showPremiumSection) ...[
                        const SizedBox(height: 16),
                        _buildSectionCard('RuStore', [
                          _billingLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              : _buildPremiumRow(),
                          if (_isPremium && _lastPurchaseId != null)
                            _buildActionRow(
                              icon: Icons.restart_alt_rounded,
                              title: 'Сбросить тестовую покупку',
                              subtitle: 'Только для dev-проверки',
                              onTap: _deleteTestPurchase,
                            ),
                          _buildOneTimePurchaseRow(),
                        ]),
                      ],
                      const SizedBox(height: 16),
                      _buildSectionCard('Обратная связь', [
                        if (_showReviewSection)
                          _checkingRatingStatus
                              ? const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              : _buildReviewRow(),
                        _buildActionRow(
                          icon: Icons.support_agent_outlined,
                          title: 'Связаться с поддержкой',
                          subtitle: 'ahjkuio@gmail.com',
                          onTap: () => GoRouter.of(context).push('/support'),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _buildSectionCard('Аккаунт', [
                        _buildActionRow(
                          icon: Icons.logout_rounded,
                          title: 'Выйти',
                          subtitle: 'Сменить аккаунт',
                          onTap: () async {
                            await _authService.signOut();
                            if (GetIt.I.isRegistered<TreeProvider>()) {
                              await GetIt.I<TreeProvider>().clearSelection();
                            }
                            if (mounted) {
                              context.go('/login');
                            }
                          },
                        ),
                      ]),
                      const SizedBox(height: 16),
                      GlassPanel(
                        color: Theme.of(context)
                            .colorScheme
                            .errorContainer
                            .withValues(alpha: 0.6),
                        borderColor: Theme.of(context)
                            .colorScheme
                            .error
                            .withValues(alpha: 0.35),
                        child: _buildActionRow(
                          icon: Icons.delete_forever,
                          title: 'Удалить аккаунт',
                          subtitle: 'Это действие нельзя отменить',
                          onTap: _showDeleteAccountConfirmation,
                          destructive: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildSettingsHeader() {
    final theme = Theme.of(context);
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Родня',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _appVersionLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(String title, List<Widget> children) {
    final spacedChildren = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      spacedChildren.add(children[i]);
      if (i != children.length - 1) {
        spacedChildren.add(const SizedBox(height: 10));
      }
    }

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          ...spacedChildren,
        ],
      ),
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool enabled = true,
    bool destructive = false,
  }) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        enabled: enabled,
        onTap: onTap,
        leading: Icon(
          icon,
          color:
              destructive ? theme.colorScheme.error : theme.colorScheme.primary,
        ),
        title: Text(
          title,
          style: destructive ? TextStyle(color: theme.colorScheme.error) : null,
        ),
        subtitle: Text(subtitle),
        trailing: destructive ? null : const Icon(Icons.chevron_right_rounded),
      ),
    );
  }

  Widget _buildSwitchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
      ),
      child: SwitchListTile(
        secondary: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildPremiumRow() {
    return _buildActionRow(
      icon: _isPremium ? Icons.star : Icons.star_border,
      title: _isPremium ? 'Премиум активен' : 'Получить премиум',
      subtitle: _isPremium ? 'Спасибо за поддержку' : 'Разблокировать функции',
      onTap: _isPremium ? null : _purchasePremium,
      enabled: !_isPremium,
    );
  }

  Widget _buildOneTimePurchaseRow() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerLowest
            .withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        leading: const Icon(Icons.shopping_cart_outlined),
        title: const Text('Тестовая покупка'),
        subtitle: Text(ONE_TIME_PRODUCT_ID),
        trailing: _oneTimePurchaseLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FilledButton.tonal(
                onPressed: _purchaseOneTimeProduct,
                child: const Text('Купить'),
              ),
      ),
    );
  }

  Widget _buildReviewRow() {
    return _buildActionRow(
      icon:
          _hasRatedApp ? Icons.thumb_up_alt_outlined : Icons.star_rate_outlined,
      title: _hasRatedApp ? 'Спасибо за отзыв' : 'Оценить приложение',
      subtitle: _hasRatedApp ? 'Отзыв уже оставлен' : 'Открыть RuStore',
      enabled: !_hasRatedApp,
      onTap: _hasRatedApp
          ? null
          : () async {
              final currentContext = context;
              final reviewStatus = await _rustoreService.requestReviewStatus();

              if (!currentContext.mounted) {
                return;
              }

              if (reviewStatus == RustoreReviewRequestStatus.shown ||
                  reviewStatus == RustoreReviewRequestStatus.alreadyExists) {
                ScaffoldMessenger.of(currentContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      reviewStatus == RustoreReviewRequestStatus.alreadyExists
                          ? 'Отзыв уже существует. Спасибо!'
                          : 'Запрос на оценку отправлен.',
                    ),
                  ),
                );
                setState(() {
                  _hasRatedApp = true;
                });
                return;
              }

              ScaffoldMessenger.of(currentContext).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Не удалось открыть окно оценки RuStore.',
                  ),
                ),
              );
            },
    );
  }
}
