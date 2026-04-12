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

    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Удаление аккаунта'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Вы уверены, что хотите удалить свой аккаунт? Это действие нельзя отменить, и все ваши данные будут потеряны навсегда.',
                    style: TextStyle(height: 1.5),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Введите пароль для подтверждения:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: passwordController,
                    obscureText: !isPasswordVisible,
                    decoration: InputDecoration(
                      hintText: 'Ваш пароль',
                      border: OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isPasswordVisible
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            isPasswordVisible = !isPasswordVisible;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  child: Text('Отмена'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: Text('Удалить', style: TextStyle(color: Colors.red)),
                  onPressed: () {
                    Navigator.of(context).pop();
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
      appBar: AppBar(title: Text('Настройки')),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Раздел Аккаунт
                  Padding(
                    padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
                    child: Text(
                      'Аккаунт и безопасность',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // Кнопка выхода из аккаунта
                  ListTile(
                    leading: Icon(Icons.exit_to_app),
                    title: Text('Выйти из аккаунта'),
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

                  const Divider(height: 32),

                  // Кнопка удаления аккаунта
                  ListTile(
                    leading: Icon(Icons.delete_forever, color: Colors.red),
                    title: Text(
                      'Удалить аккаунт',
                      style: TextStyle(color: Colors.red),
                    ),
                    subtitle: const Text('Это действие нельзя отменить'),
                    onTap: _showDeleteAccountConfirmation,
                  ),

                  const SizedBox(height: 60),

                  // Информация о приложении
                  Center(
                    child: Column(
                      children: [
                        Text(
                          'Родня',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          _appVersionLabel,
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),

                  // Добавьте это в метод build в списке настроек:
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                    child: Text(
                      'Внешний вид',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // Переключатель темы
                  SwitchListTile(
                    title: Text('Тёмная тема'),
                    subtitle: Text('Изменить цветовую схему приложения'),
                    value: themeProvider.isDarkMode,
                    onChanged: (value) {
                      themeProvider.toggleTheme();
                    },
                    secondary: Icon(
                      themeProvider.isDarkMode
                          ? Icons.dark_mode
                          : Icons.light_mode,
                    ),
                  ),

                  // Добавьте это в метод build в списке настроек:
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                    child: Text(
                      'Уведомления и конфиденциальность',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // Настройки уведомлений
                  SwitchListTile(
                    title: Text('Уведомления'),
                    subtitle: Text('Получать уведомления о новых событиях'),
                    value: _notificationsEnabled,
                    onChanged: _toggleNotifications,
                    secondary: Icon(Icons.notifications),
                  ),

                  // Настройки приватности
                  SwitchListTile(
                    title: Text('Приватный профиль'),
                    subtitle: Text(
                      'Только приглашенные пользователи могут видеть ваш профиль',
                    ),
                    value: _profilePrivate,
                    onChanged: (value) {
                      setState(() {
                        _profilePrivate = value;
                        // Сохраняем настройки и обновляем в Firestore
                      });
                    },
                    secondary: Icon(Icons.lock),
                  ),

                  // Добавляем пункт Политика конфиденциальности
                  ListTile(
                    leading: Icon(Icons.privacy_tip_outlined),
                    title: Text('Политика конфиденциальности'),
                    onTap: () {
                      // Используем GoRouter для перехода
                      GoRouter.of(context).push('/privacy');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Условия использования'),
                    onTap: () => GoRouter.of(context).push('/terms'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.support_agent_outlined),
                    title: const Text('Поддержка'),
                    subtitle:
                        const Text('Публичная страница и email поддержки'),
                    onTap: () => GoRouter.of(context).push('/support'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.block_outlined),
                    title: const Text('Заблокированные пользователи'),
                    subtitle: const Text('Управление личными блокировками'),
                    onTap: () => GoRouter.of(context).push('/profile/blocks'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded),
                    title: const Text('Как удалить аккаунт'),
                    subtitle: const Text('Публичная release-ready инструкция'),
                    onTap: () => GoRouter.of(context).push('/account-deletion'),
                  ),

                  // Информация о приложении
                  ListTile(
                    leading: Icon(Icons.info),
                    title: Text('О приложении'),
                    onTap: () {
                      context.push('/profile/about');
                    },
                  ),

                  if (_showPremiumSection) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 32.0, bottom: 8.0),
                      child: Text(
                        'Премиум-статус',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _billingLoading
                        ? Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16.0),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : Column(
                            children: [
                              ListTile(
                                leading: Icon(
                                  _isPremium ? Icons.star : Icons.star_border,
                                  color: _isPremium ? Colors.amber : null,
                                ),
                                title: Text(
                                  _isPremium
                                      ? 'Премиум активен'
                                      : 'Получить Премиум',
                                ),
                                subtitle: Text(
                                  _isPremium
                                      ? 'Спасибо за поддержку!'
                                      : 'Разблокировать дополнительные функции.',
                                ),
                                trailing: _isPremium
                                    ? null // Не показываем кнопку, если уже премиум
                                    : ElevatedButton(
                                        onPressed: _purchasePremium,
                                        child: Text('Купить'),
                                      ),
                              ),
                              // Кнопка для удаления тестовой покупки (только если премиум активен)
                              if (_isPremium && _lastPurchaseId != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0,
                                    vertical: 8.0,
                                  ),
                                  child: TextButton(
                                    onPressed: _deleteTestPurchase,
                                    child: Text(
                                      'Сбросить тестовую покупку',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                    Divider(),
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                      child: Text(
                        'Разовая покупка (Тест)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                    ListTile(
                      leading: Icon(Icons.shopping_cart, color: Colors.orange),
                      title: Text('Купить тестовый товар'),
                      subtitle: Text('Проверка покупки разового товара'),
                      trailing: ElevatedButton(
                        onPressed: _oneTimePurchaseLoading
                            ? null
                            : _purchaseOneTimeProduct,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[700],
                        ),
                        child: _oneTimePurchaseLoading
                            ? SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text('Купить ($ONE_TIME_PRODUCT_ID)'),
                      ),
                    ),
                    Divider(),
                  ],

                  Padding(
                    padding: const EdgeInsets.only(
                      top: 16.0,
                      bottom: 8.0,
                    ),
                    child: Text(
                      'Обратная связь',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // Кнопка Оценить приложение (с обновленной логикой)
                  if (_showReviewSection)
                    _checkingRatingStatus
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16.0),
                            child: Center(
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : ListTile(
                            leading: Icon(
                              _hasRatedApp
                                  ? Icons.thumb_up_alt
                                  : Icons.star_rate_outlined,
                            ),
                            title: Text(
                              _hasRatedApp
                                  ? 'Спасибо за отзыв!'
                                  : 'Оценить приложение',
                            ),
                            subtitle: _hasRatedApp
                                ? Text('Мы ценим ваше мнение')
                                : Text('Оставить отзыв в RuStore'),
                            onTap: _hasRatedApp
                                ? null
                                : () async {
                                    final currentContext = context;
                                    debugPrint(
                                      'Attempting to request RuStore review...',
                                    );
                                    final reviewStatus = await _rustoreService
                                        .requestReviewStatus();

                                    if (!currentContext.mounted) {
                                      return;
                                    }

                                    if (reviewStatus ==
                                            RustoreReviewRequestStatus.shown ||
                                        reviewStatus ==
                                            RustoreReviewRequestStatus
                                                .alreadyExists) {
                                      debugPrint(
                                        'Review request initiated successfully.',
                                      );
                                      ScaffoldMessenger.of(
                                        currentContext,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            reviewStatus ==
                                                    RustoreReviewRequestStatus
                                                        .alreadyExists
                                                ? 'Отзыв в RuStore уже существует. Спасибо!'
                                                : 'Запрос на оценку отправлен. Спасибо!',
                                          ),
                                          duration: Duration(seconds: 3),
                                        ),
                                      );
                                      setState(() {
                                        _hasRatedApp = true;
                                      });
                                      return;
                                    }

                                    ScaffoldMessenger.of(
                                      currentContext,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Не удалось открыть окно оценки RuStore на этом устройстве.',
                                        ),
                                        duration: Duration(seconds: 5),
                                      ),
                                    );
                                  },
                            enabled: !_hasRatedApp,
                          ),
                  ListTile(
                    leading: const Icon(Icons.support_agent_outlined),
                    title: const Text('Связаться с поддержкой'),
                    subtitle: const Text('ahjkuio@gmail.com'),
                    onTap: () => GoRouter.of(context).push('/support'),
                  ),

                  Divider(),
                ],
              ),
            ),
    );
  }
}
