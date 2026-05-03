import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

import '../backend/backend_provider_config.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../providers/tree_provider.dart';
import '../services/app_status_service.dart';
import '../services/custom_api_auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/user_facing_error.dart';
import '../widgets/glass_panel.dart';
import '../widgets/google_sign_in_action.dart';
import '../widgets/offline_indicator.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    this.redirectAfterLogin,
  });

  final String? redirectAfterLogin;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _nameFocusNode = FocusNode();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isTelegramLoading = false;
  bool _isVkLoading = false;
  bool _isMaxLoading = false;
  bool _hasSubmitted = false;
  late final bool _supportsGoogleAuth;
  StreamSubscription<void>? _googleWebAuthenticationSubscription;
  String? _pendingTelegramLinkCode;
  String? _pendingTelegramMessage;
  String? _pendingVkLinkCode;
  String? _pendingVkMessage;
  String? _pendingMaxLinkCode;
  String? _pendingMaxMessage;

  final List<_AuthFeature> _mvpHighlights = const [
    _AuthFeature(
      icon: Icons.account_tree_outlined,
      title: 'Дерево',
      description: 'Родные и связи в одном месте.',
    ),
    _AuthFeature(
      icon: Icons.people_alt_outlined,
      title: 'Родные',
      description: 'Карточки людей и профиль без лишних шагов.',
    ),
    _AuthFeature(
      icon: Icons.chat_bubble_outline,
      title: 'Чат',
      description: 'Личные диалоги с родными.',
    ),
    _AuthFeature(
      icon: Icons.circle_outlined,
      title: 'Stories',
      description: 'Короткие семейные обновления.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_handleAuthInputChanged);
    _passwordController.addListener(_handleAuthInputChanged);
    _nameController.addListener(_handleAuthInputChanged);
    final authService = _authService;
    _supportsGoogleAuth = authService is CustomApiAuthService
        ? authService.isGoogleSignInConfigured
        : BackendProviderConfig.current.authProvider !=
            BackendProviderKind.customApi;
    if (kIsWeb && authService is CustomApiAuthService && _supportsGoogleAuth) {
      _googleWebAuthenticationSubscription =
          authService.googleWebAuthenticationEvents.listen((_) {
        if (!mounted || _isGoogleLoading) {
          return;
        }
        unawaited(_signInWithGoogle());
      });
      unawaited(authService.initializeGoogleWebAuthentication());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_handleSocialRedirectResults());
    });
  }

  @override
  void dispose() {
    _emailController.removeListener(_handleAuthInputChanged);
    _passwordController.removeListener(_handleAuthInputChanged);
    _nameController.removeListener(_handleAuthInputChanged);
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _googleWebAuthenticationSubscription?.cancel();
    _emailFocusNode.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  bool get _isAnySocialLoading =>
      _isGoogleLoading || _isTelegramLoading || _isVkLoading || _isMaxLoading;

  Future<void> _submit() async {
    _clearSessionIssue();
    setState(() {
      _hasSubmitted = true;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isLogin) {
        await _authService.loginWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );
      } else {
        await _authService.registerWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          name: _nameController.text.trim(),
        );
      }

      if (_authService.currentUserId != null) {
        final linkedTelegram = await _tryLinkPendingTelegramIdentity();
        final linkedVk = await _tryLinkPendingVkIdentity();
        final linkedMax = await _tryLinkPendingMaxIdentity();
        if (GetIt.I.isRegistered<TreeProvider>()) {
          await GetIt.I<TreeProvider>().loadInitialTree();
        }

        if (!mounted) {
          return;
        }

        context.go(_resolvePostAuthTarget());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (linkedTelegram || linkedVk || linkedMax)
                  ? '${[
                      if (linkedTelegram) 'Telegram',
                      if (linkedVk) 'VK ID',
                      if (linkedMax) 'MAX',
                    ].join(', ')} привязан. Вход выполнен успешно.'
                  : _isLogin
                      ? 'Вход выполнен успешно.'
                      : 'Регистрация успешна. Добро пожаловать в Родню.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

      throw Exception('Ошибка авторизации: пользователь не найден');
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _authError(
              e,
              fallbackMessage: 'Не удалось войти. Попробуйте ещё раз.',
            ),
          ),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    _clearSessionIssue();
    setState(() {
      _isGoogleLoading = true;
    });

    try {
      await _authService.signInWithGoogle();

      if (mounted && _authService.currentUserId != null) {
        context.go(_resolvePostAuthTarget());
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _authError(
              e,
              fallbackMessage: 'Не удалось войти через Google.',
            ),
          ),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }

  Future<void> _startTelegramSignIn() async {
    if (!kIsWeb) {
      _showSocialAuthWebOnlyMessage('Telegram');
      return;
    }

    final authService = _authService;
    if (authService is! CustomApiAuthService) {
      _showPlannedSocialAuthMessage('Telegram');
      return;
    }

    _clearSessionIssue();
    setState(() {
      _isTelegramLoading = true;
    });

    try {
      final telegramStartUrl =
          await authService.resolveTelegramLoginStartUrl();
      final started = await launchUrl(
        Uri.parse(telegramStartUrl),
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );
      if (!started && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось открыть вход через Telegram.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTelegramLoading = false;
        });
      }
    }
  }

  Future<void> _startVkSignIn() async {
    if (!kIsWeb) {
      _showSocialAuthWebOnlyMessage('VK ID');
      return;
    }

    final authService = _authService;
    if (authService is! CustomApiAuthService) {
      _showPlannedSocialAuthMessage('VK ID');
      return;
    }

    _clearSessionIssue();
    setState(() {
      _isVkLoading = true;
    });

    try {
      final vkStartUrl = await authService.resolveVkLoginStartUrl();
      final started = await launchUrl(
        Uri.parse(vkStartUrl),
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );
      if (!started && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось открыть вход через VK ID.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isVkLoading = false;
        });
      }
    }
  }

  Future<void> _handleSocialRedirectResults() async {
    await _handleTelegramRedirectResult();
    await _handleVkRedirectResult();
    await _handleMaxRedirectResult();
  }

  Future<void> _handleTelegramRedirectResult() async {
    final intent = _socialQueryParameter('telegramIntent');
    final isLinkIntent = intent == 'link';
    final error = _socialQueryParameter('telegramAuthError');
    if (error != null && error.isNotEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    final code = _socialQueryParameter('telegramAuthCode');
    if (code == null || code.isEmpty) {
      return;
    }

    final authService = _authService;
    if (authService is! CustomApiAuthService) {
      return;
    }

    setState(() {
      _isTelegramLoading = true;
    });

    try {
      final completion = await authService.exchangeTelegramAuthCode(code);
      if (!mounted) {
        return;
      }

      if (completion.isAuthenticated) {
        if (GetIt.I.isRegistered<TreeProvider>()) {
          await GetIt.I<TreeProvider>().loadInitialTree();
        }
        if (!mounted) {
          return;
        }
        context.go(_resolvePostAuthTarget());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Вход через Telegram выполнен успешно.'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

      if (completion.isAlreadyLinked) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              completion.message ??
                  'Этот Telegram уже привязан к аккаунту Родни.',
            ),
          ),
        );
        if (isLinkIntent) {
          context.go('/profile/edit');
        }
        return;
      }

      if (isLinkIntent && authService.currentUserId != null) {
        final linkCode = completion.linkCode;
        if (linkCode == null || linkCode.isEmpty) {
          throw const CustomApiException(
            'Telegram link code не был получен для привязки',
          );
        }
        await authService.linkPendingTelegramIdentity(linkCode);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Telegram привязан к текущему аккаунту.'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/profile/edit');
        return;
      }

      final displayName = [
        completion.firstName?.trim() ?? '',
        completion.lastName?.trim() ?? '',
      ].where((part) => part.isNotEmpty).join(' ');
      if (displayName.isNotEmpty && _nameController.text.trim().isEmpty) {
        _nameController.text = displayName;
      }

      setState(() {
        _isLogin = true;
        _pendingTelegramLinkCode = completion.linkCode;
        _pendingTelegramMessage = completion.message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            completion.message ??
                'Telegram подтверждён. Теперь войдите в существующий аккаунт Родни, чтобы привязать его.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _authError(
              e,
              fallbackMessage: 'Не удалось завершить вход через Telegram.',
            ),
          ),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTelegramLoading = false;
        });
      }
    }
  }

  Future<void> _handleVkRedirectResult() async {
    final intent = _socialQueryParameter('vkIntent');
    final isLinkIntent = intent == 'link';
    final error = _socialQueryParameter('vkAuthError');
    if (error != null && error.isNotEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    final code = _socialQueryParameter('vkAuthCode');
    if (code == null || code.isEmpty) {
      return;
    }

    final authService = _authService;
    if (authService is! CustomApiAuthService) {
      return;
    }

    setState(() {
      _isVkLoading = true;
    });

    try {
      final completion = await authService.exchangeVkAuthCode(code);
      if (!mounted) {
        return;
      }

      if (completion.isAuthenticated) {
        if (GetIt.I.isRegistered<TreeProvider>()) {
          await GetIt.I<TreeProvider>().loadInitialTree();
        }
        if (!mounted) {
          return;
        }
        context.go(_resolvePostAuthTarget());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Вход через VK ID выполнен успешно.'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

      if (completion.isAlreadyLinked) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              completion.message ?? 'Этот VK ID уже привязан к аккаунту Родни.',
            ),
          ),
        );
        if (isLinkIntent) {
          context.go('/profile/edit');
        }
        return;
      }

      if (isLinkIntent && authService.currentUserId != null) {
        final linkCode = completion.linkCode;
        if (linkCode == null || linkCode.isEmpty) {
          throw const CustomApiException(
            'VK ID link code не был получен для привязки',
          );
        }
        await authService.linkPendingVkIdentity(linkCode);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('VK ID привязан к текущему аккаунту.'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/profile/edit');
        return;
      }

      final displayName = [
        completion.firstName?.trim() ?? '',
        completion.lastName?.trim() ?? '',
      ].where((part) => part.isNotEmpty).join(' ');
      if (displayName.isNotEmpty && _nameController.text.trim().isEmpty) {
        _nameController.text = displayName;
      }

      setState(() {
        _isLogin = true;
        _pendingVkLinkCode = completion.linkCode;
        _pendingVkMessage = completion.message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            completion.message ??
                'VK ID подтверждён. Теперь войдите в существующий аккаунт Родни, чтобы привязать его.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _authError(
              e,
              fallbackMessage: 'Не удалось завершить вход через VK ID.',
            ),
          ),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isVkLoading = false;
        });
      }
    }
  }

  // ignore: unused_element
  Future<void> _startMaxSignIn() async {
    if (!kIsWeb) {
      _showSocialAuthWebOnlyMessage('MAX');
      return;
    }

    final authService = _authService;
    if (authService is! CustomApiAuthService) {
      _showPlannedSocialAuthMessage('MAX');
      return;
    }

    _clearSessionIssue();
    setState(() {
      _isMaxLoading = true;
    });

    try {
      final maxStartUrl = await authService.resolveMaxLoginStartUrl();
      final started = await launchUrl(
        Uri.parse(maxStartUrl),
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );
      if (!started && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось открыть вход через MAX.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isMaxLoading = false;
        });
      }
    }
  }

  Future<void> _handleMaxRedirectResult() async {
    final intent = _socialQueryParameter('maxIntent');
    final isLinkIntent = intent == 'link';
    final error = _socialQueryParameter('maxAuthError');
    if (error != null && error.isNotEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    final code = _socialQueryParameter('maxAuthCode');
    if (code == null || code.isEmpty) {
      return;
    }

    final authService = _authService;
    if (authService is! CustomApiAuthService) {
      return;
    }

    setState(() {
      _isMaxLoading = true;
    });

    try {
      final completion = await authService.exchangeMaxAuthCode(code);
      if (!mounted) {
        return;
      }

      if (completion.isAuthenticated) {
        if (GetIt.I.isRegistered<TreeProvider>()) {
          await GetIt.I<TreeProvider>().loadInitialTree();
        }
        if (!mounted) {
          return;
        }
        context.go(_resolvePostAuthTarget());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Вход через MAX выполнен успешно.'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

      if (completion.isAlreadyLinked) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              completion.message ?? 'Этот MAX уже привязан к аккаунту Родни.',
            ),
          ),
        );
        if (isLinkIntent) {
          context.go('/profile/edit');
        }
        return;
      }

      if (isLinkIntent && authService.currentUserId != null) {
        final linkCode = completion.linkCode;
        if (linkCode == null || linkCode.isEmpty) {
          throw const CustomApiException(
            'MAX link code не был получен для привязки',
          );
        }
        await authService.linkPendingMaxIdentity(linkCode);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('MAX привязан к текущему аккаунту.'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/profile/edit');
        return;
      }

      final displayName = [
        completion.firstName?.trim() ?? '',
        completion.lastName?.trim() ?? '',
      ].where((part) => part.isNotEmpty).join(' ');
      if (displayName.isNotEmpty && _nameController.text.trim().isEmpty) {
        _nameController.text = displayName;
      }

      setState(() {
        _isLogin = true;
        _pendingMaxLinkCode = completion.linkCode;
        _pendingMaxMessage = completion.message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            completion.message ??
                'MAX подтверждён. Теперь войдите в существующий аккаунт Родни, чтобы привязать его.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _authError(
              e,
              fallbackMessage: 'Не удалось завершить вход через MAX.',
            ),
          ),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isMaxLoading = false;
        });
      }
    }
  }

  String? _socialQueryParameter(String name) {
    final directValue = Uri.base.queryParameters[name];
    if (directValue != null && directValue.isNotEmpty) {
      return directValue;
    }

    final fragment = Uri.base.fragment;
    if (fragment.isEmpty || !fragment.contains('?')) {
      return null;
    }

    final queryPart = fragment.split('?').skip(1).join('?');
    return Uri.splitQueryString(queryPart)[name];
  }

  Future<bool> _tryLinkPendingTelegramIdentity() async {
    final code = _pendingTelegramLinkCode;
    final authService = _authService;
    if (code == null || code.isEmpty || authService is! CustomApiAuthService) {
      return false;
    }

    await authService.linkPendingTelegramIdentity(code);
    if (!mounted) {
      return true;
    }

    setState(() {
      _pendingTelegramLinkCode = null;
      _pendingTelegramMessage = null;
    });
    return true;
  }

  Future<bool> _tryLinkPendingVkIdentity() async {
    final code = _pendingVkLinkCode;
    final authService = _authService;
    if (code == null || code.isEmpty || authService is! CustomApiAuthService) {
      return false;
    }

    await authService.linkPendingVkIdentity(code);
    if (!mounted) {
      return true;
    }

    setState(() {
      _pendingVkLinkCode = null;
      _pendingVkMessage = null;
    });
    return true;
  }

  Future<bool> _tryLinkPendingMaxIdentity() async {
    final code = _pendingMaxLinkCode;
    final authService = _authService;
    if (code == null || code.isEmpty || authService is! CustomApiAuthService) {
      return false;
    }

    await authService.linkPendingMaxIdentity(code);
    if (!mounted) {
      return true;
    }

    setState(() {
      _pendingMaxLinkCode = null;
      _pendingMaxMessage = null;
    });
    return true;
  }

  void _showPlannedSocialAuthMessage(String providerLabel) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$providerLabel появится после подключения ключей провайдера.',
        ),
      ),
    );
  }

  void _showSocialAuthWebOnlyMessage(String providerLabel) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$providerLabel пока доступен на web. Android deep link подключим отдельно.',
        ),
      ),
    );
  }

  String _authError(Object error, {required String fallbackMessage}) {
    return describeUserFacingError(
      authService: _authService,
      error: error,
      fallbackMessage: fallbackMessage,
    );
  }

  void _setMode(bool isLogin) {
    _clearSessionIssue();
    setState(() {
      _isLogin = isLogin;
      _hasSubmitted = false;
    });
  }

  void _handleAuthInputChanged() {
    if (_emailController.text.isEmpty &&
        _passwordController.text.isEmpty &&
        _nameController.text.isEmpty) {
      return;
    }
    _clearSessionIssue();
  }

  void _clearSessionIssue() {
    if (!GetIt.I.isRegistered<AppStatusService>()) {
      return;
    }
    GetIt.I<AppStatusService>().clearSessionIssue();
  }

  void _focusPrimaryField() {
    final focusNode = _isLogin ? _emailFocusNode : _nameFocusNode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      focusNode.requestFocus();
    });
  }

  String _resolvePostAuthTarget() {
    final from = widget.redirectAfterLogin;
    if (from == null || from.isEmpty || from == '/login') {
      return '/';
    }
    return from;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.14),
              const Color(0xFFF7F2E8),
              theme.colorScheme.secondary.withValues(alpha: 0.08),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const OfflineIndicator(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 960;
                    return Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isWide ? 1260 : 520,
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isWide ? 24 : 16,
                            vertical: isWide ? 28 : 16,
                          ),
                          child: isWide
                              ? _buildWideLayout(theme)
                              : _buildCompactLayout(theme),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWideLayout(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 10,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(right: 24),
              child: _buildHeroPanel(theme, compact: false),
            ),
          ),
        ),
        Expanded(
          flex: 9,
          child: SingleChildScrollView(
            child: _buildAuthCard(theme, compact: false),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactLayout(ThemeData theme) {
    // Reference layout: hero owns ~52% of viewport, the auth sheet pulls
    // up over it by 28px with a 32-radius top corner. Feature cards moved
    // into a single subtitle line — the hero is meant to deliver brand
    // gravity, not feature inventory. The sheet is where the user
    // actually does work.
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeroPanel(theme, compact: true),
          Transform.translate(
            offset: const Offset(0, -28),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.transparent,
              ),
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
              child: _buildAuthCard(theme, compact: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroPanel(ThemeData theme, {required bool compact}) {
    final colorScheme = theme.colorScheme;
    // Reference hero: sage gradient + decorative tree silhouette, the big
    // Lora tagline anchored to the bottom-left. Compact layout drops the
    // feature inventory — the sheet below has all the action surface.
    return Container(
      width: double.infinity,
      // Compact hero takes a generous ~360 minimum so the wordmark + tagline
      // breathe properly. Desktop wide retains the prior padded card.
      constraints: compact
          ? const BoxConstraints(minHeight: 380)
          : const BoxConstraints(),
      padding: EdgeInsets.fromLTRB(
        compact ? 22 : 28,
        compact ? 50 : 28,
        compact ? 22 : 28,
        compact ? 60 : 28,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment(-0.6, -1.0),
          end: Alignment(0.4, 1.0),
          colors: [
            Color(0xFF4F8A6E), // light sage top
            Color(0xFF2F6F58), // mid teal
            Color(0xFF1F4F40), // deep forest at bottom
          ],
        ),
        // Compact: only top corners are radiused; the sheet below sits
        // flush with no border-radius on the bottom of the hero. Wide:
        // a full 32-radius card with shadow.
        borderRadius: compact
            ? BorderRadius.zero
            : BorderRadius.circular(32),
        boxShadow: compact
            ? null
            : [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.18),
                  blurRadius: 30,
                  offset: const Offset(0, 18),
                ),
              ],
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Decorative tree silhouette per reference. Painted at low
          // opacity behind the text so the gradient still owns the eye.
          if (compact)
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.18,
                  child: CustomPaint(painter: const _AuthHeroTreePainter()),
                ),
              ),
            ),
          // Soft warm + sage glows in the corners, also from reference.
          if (compact) ...[
            Positioned(
              top: -60,
              right: -50,
              child: IgnorePointer(
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFEBC678).withValues(alpha: 0.40),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.7],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -80,
              left: -60,
              child: IgnorePointer(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF9DD8B5).withValues(alpha: 0.36),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.7],
                    ),
                  ),
                ),
              ),
            ),
          ],
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.eco_outlined,
                      size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'РОДНЯ',
                    style: AppTheme.sans(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.0,
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 70 : 24),
              Text(
                'Семья —',
                style: AppTheme.serif(
                  color: Colors.white,
                  fontSize: compact ? 38 : 38,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                  height: 1.05,
                ),
              ),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'это ',
                      style: AppTheme.serif(
                        color: Colors.white,
                        fontSize: compact ? 38 : 38,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                        height: 1.05,
                      ),
                    ),
                    TextSpan(
                      text: 'живое',
                      style: AppTheme.serif(
                        color: const Color(0xFFE9C273),
                        fontSize: compact ? 38 : 38,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                        height: 1.05,
                      ).copyWith(fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
              Text(
                'дерево.',
                style: AppTheme.serif(
                  color: Colors.white,
                  fontSize: compact ? 38 : 38,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Истории, голоса, лица и даты\nв одном пространстве для своих.',
                style: AppTheme.sans(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _mvpHighlights
                      .map(
                        (feature) => _FeatureCard(
                          feature: feature,
                          compact: true,
                        ),
                      )
                      .toList(),
                ),
              ],
              if (!compact) ...[
                const SizedBox(height: 22),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _isLoading || _isAnySocialLoading
                          ? null
                          : () {
                              _setMode(true);
                              _focusPrimaryField();
                            },
                      icon: const Icon(Icons.login),
                      label: const Text('Войти'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: colorScheme.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isLoading || _isAnySocialLoading
                          ? null
                          : () {
                              _setMode(false);
                              _focusPrimaryField();
                            },
                      icon: const Icon(Icons.family_restroom_outlined),
                      label: const Text('Создать аккаунт'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAuthCard(ThemeData theme, {required bool compact}) {
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark
        ? theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.96)
        : Colors.white.withValues(alpha: 0.86);
    final secondaryTextColor =
        isDark ? theme.colorScheme.onSurfaceVariant : Colors.grey[700];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: GlassPanel(
        padding: EdgeInsets.all(compact ? 20 : 28),
        borderRadius: BorderRadius.circular(28),
        clipBehavior: kIsWeb ? Clip.none : Clip.antiAlias,
        color: cardColor,
        borderColor: isDark
            ? theme.colorScheme.outlineVariant.withValues(alpha: 0.9)
            : AppTheme.warmLine.withValues(alpha: 0.72),
        child: Form(
          key: _formKey,
          autovalidateMode: _hasSubmitted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_pendingTelegramLinkCode != null ||
                  _pendingVkLinkCode != null ||
                  _pendingMaxLinkCode != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.link_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _pendingTelegramLinkCode != null
                              ? (_pendingTelegramMessage ??
                                  'Telegram подтверждён. Войдите в аккаунт, чтобы привязать его.')
                              : _pendingVkLinkCode != null
                                  ? (_pendingVkMessage ??
                                      'VK ID подтверждён. Войдите в аккаунт, чтобы привязать его.')
                                  : (_pendingMaxMessage ??
                                      'MAX подтверждён. Войдите в аккаунт, чтобы привязать его.'),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (compact) ...[
                _buildModeToggle(theme),
                const SizedBox(height: 18),
              ],
              Text(
                _isLogin ? 'Вход' : 'Новый аккаунт',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _isLogin ? 'Откройте семью.' : 'Начните за минуту.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: secondaryTextColor,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: compact ? 18 : 22),
              if (!compact) ...[
                _buildModeToggle(theme),
                const SizedBox(height: 22),
              ],
              if (!_isLogin) ...[
                TextFormField(
                  controller: _nameController,
                  focusNode: _nameFocusNode,
                  decoration: _fieldDecoration(
                    theme,
                    label: 'Имя',
                    icon: Icons.person_outline,
                  ),
                  keyboardType: TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (!_isLogin &&
                        (value == null || value.trim().length < 2)) {
                      return 'Имя должно содержать не менее 2 символов';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _emailController,
                focusNode: _emailFocusNode,
                decoration: _fieldDecoration(
                  theme,
                  label: 'Email',
                  icon: Icons.alternate_email,
                ),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null ||
                      !value.contains('@') ||
                      !value.contains('.')) {
                    return 'Введите корректный email адрес';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              if (_isLogin)
                // Inline "забыли?" link sits flush-right above the password
                // field — the same pattern the reference uses, so the
                // standalone "Пароль" link below the providers can go.
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, right: 4),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: _isLoading || _isAnySocialLoading
                          ? null
                          : () => context.push('/password_reset'),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Text(
                          'Забыли?',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              TextFormField(
                controller: _passwordController,
                decoration: _fieldDecoration(
                  theme,
                  label: 'Пароль',
                  icon: Icons.lock_outline,
                ),
                obscureText: true,
                textInputAction:
                    _isLogin ? TextInputAction.done : TextInputAction.next,
                onFieldSubmitted: (_) {
                  if (_isLogin) {
                    _submit();
                  }
                },
                validator: (value) {
                  if (value == null || value.length < 6) {
                    return 'Пароль должен содержать не менее 6 символов';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _isLoading || _isAnySocialLoading ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(_isLogin ? 'Войти' : 'Создать аккаунт'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Быстрый вход',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: secondaryTextColor,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),
              // Google web button is a fixed-width native pill (242x40).
              // Centering it (was: right-aligned) lines it up with the
              // equal-width Telegram + VK ID row below — the asymmetric
              // layout the previous version had came from one
              // right-aligned Google pill on top of three center-wrapped
              // OutlinedButtons of varying widths.
              if (kIsWeb) ...[
                Center(
                  child: buildGoogleSignInAction(
                    theme: theme,
                    isLoading: _isGoogleLoading,
                    enabled: !_isLoading &&
                        !_isTelegramLoading &&
                        !_isVkLoading &&
                        _supportsGoogleAuth,
                    onPressed: _supportsGoogleAuth
                        ? _signInWithGoogle
                        : () => _showPlannedSocialAuthMessage('Google'),
                    useNativeWebButton: true,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              // Two equal-width buttons in a Row gives a clean grid the
              // way the reference does. MAX is intentionally hidden until
              // the MAX OAuth handshake actually lands — the variable
              // _startMaxSignIn / _isMaxLoading are kept for when that
              // ships.
              Row(
                children: [
                  if (!kIsWeb)
                    Expanded(
                      child: buildGoogleSignInAction(
                        theme: theme,
                        isLoading: _isGoogleLoading,
                        enabled: !_isLoading &&
                            !_isTelegramLoading &&
                            !_isVkLoading &&
                            _supportsGoogleAuth,
                        onPressed: _supportsGoogleAuth
                            ? _signInWithGoogle
                            : () => _showPlannedSocialAuthMessage('Google'),
                      ),
                    ),
                  if (!kIsWeb) const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading || _isAnySocialLoading
                          ? null
                          : _startTelegramSignIn,
                      icon: _isTelegramLoading
                          ? SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.primary,
                              ),
                            )
                          : const Icon(Icons.send_outlined),
                      label: const Text('Telegram'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading || _isAnySocialLoading
                          ? null
                          : _startVkSignIn,
                      icon: _isVkLoading
                          ? SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.primary,
                              ),
                            )
                          : const Icon(Icons.alternate_email_outlined),
                      label: const Text('VK ID'),
                    ),
                  ),
                ],
              ),
              // The mode toggle above the form already switches to register,
              // and "Забыли?" sits inline with the password field — so the
              // duplicate "Создать аккаунт / У меня уже есть вход" and
              // standalone "Пароль" links the previous layout had are gone.
              // Keeping only the QR-login link, compact and icon-led.
              if (_isLogin) ...[
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    onPressed:
                        _isLoading ? null : () => context.push('/auth/qr'),
                    icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                    label: const Text('Войти по QR'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Продолжая, вы соглашаетесь с ',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondaryTextColor,
                    ),
                  ),
                  TextButton(
                    onPressed: () => GoRouter.of(context).push('/privacy'),
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Политикой'),
                  ),
                  Text(
                    ' и ',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondaryTextColor,
                    ),
                  ),
                  TextButton(
                    onPressed: () => GoRouter.of(context).push('/terms'),
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Условиями'),
                  ),
                  Text(
                    '.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(
    ThemeData theme, {
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor:
          theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.32),
        ),
      ),
    );
  }

  Widget _buildModeToggle(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color:
                    _isLogin ? theme.colorScheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: TextButton(
                onPressed: _isLoading ||
                        _isGoogleLoading ||
                        _isTelegramLoading ||
                        _isVkLoading ||
                        _isMaxLoading
                    ? null
                    : () {
                        _setMode(true);
                        _focusPrimaryField();
                      },
                child: Text(
                  'Вход',
                  style: TextStyle(
                    color: _isLogin ? Colors.white : theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color:
                    !_isLogin ? theme.colorScheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: TextButton(
                onPressed: _isLoading ||
                        _isGoogleLoading ||
                        _isTelegramLoading ||
                        _isVkLoading ||
                        _isMaxLoading
                    ? null
                    : () {
                        _setMode(false);
                        _focusPrimaryField();
                      },
                child: Text(
                  'Регистрация',
                  style: TextStyle(
                    color: !_isLogin ? Colors.white : theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.feature,
    required this.compact,
  });

  final _AuthFeature feature;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
        vertical: compact ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: compact ? 0.1 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(feature.icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            feature.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthFeature {
  const _AuthFeature({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

/// Decorative tree silhouette painted into the auth hero, behind the
/// tagline. Lifted from the reference jsx SVG path: a single trunk that
/// branches in symmetric pairs upward, with small dots marking the
/// branch terminals — reads as a stylized family graph.
class _AuthHeroTreePainter extends CustomPainter {
  const _AuthHeroTreePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Reference uses a 360x380 viewbox aligned to the bottom-center.
    // Project that into our actual canvas.
    final cx = w * 0.5;
    final baseY = h;
    final trunkTop = h * 0.37;

    final stroke = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..color = Colors.white;

    // Main trunk.
    canvas.drawLine(Offset(cx, baseY), Offset(cx, trunkTop), stroke);

    // Three pairs of branches, each going further up + outward.
    // pair 1 — wide spread, lowest branch fork
    final l1 = Offset(cx - w * 0.25, h * 0.42);
    final r1 = Offset(cx + w * 0.25, h * 0.42);
    canvas.drawPath(
      Path()
        ..moveTo(cx, h * 0.58)
        ..cubicTo(cx - w * 0.08, h * 0.53, l1.dx + w * 0.04, l1.dy + 12, l1.dx,
            l1.dy),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(cx, h * 0.58)
        ..cubicTo(cx + w * 0.08, h * 0.53, r1.dx - w * 0.04, r1.dy + 12, r1.dx,
            r1.dy),
      stroke,
    );

    // pair 2
    final l2 = Offset(cx - w * 0.17, h * 0.29);
    final r2 = Offset(cx + w * 0.17, h * 0.29);
    canvas.drawPath(
      Path()
        ..moveTo(cx, h * 0.45)
        ..cubicTo(cx - w * 0.06, h * 0.40, l2.dx + w * 0.03, l2.dy + 10, l2.dx,
            l2.dy),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(cx, h * 0.45)
        ..cubicTo(cx + w * 0.06, h * 0.40, r2.dx - w * 0.03, r2.dy + 10, r2.dx,
            r2.dy),
      stroke,
    );

    // pair 3 — top
    final l3 = Offset(cx - w * 0.085, h * 0.24);
    final r3 = Offset(cx + w * 0.085, h * 0.24);
    canvas.drawPath(
      Path()
        ..moveTo(cx, trunkTop)
        ..cubicTo(cx - w * 0.04, h * 0.33, l3.dx + w * 0.015, l3.dy + 8, l3.dx,
            l3.dy),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(cx, trunkTop)
        ..cubicTo(cx + w * 0.04, h * 0.33, r3.dx - w * 0.015, r3.dy + 8, r3.dx,
            r3.dy),
      stroke,
    );

    // Branch terminal dots.
    for (final node in [l1, r1, l2, r2, l3, r3, Offset(cx, trunkTop)]) {
      canvas.drawCircle(node, 5, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _AuthHeroTreePainter oldDelegate) => false;
}
