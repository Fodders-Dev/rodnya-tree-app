import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

import '../backend/backend_provider_config.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/models/auth_providers_availability.dart';
import '../backend/models/email_provider_mismatch.dart';
import '../backend/models/google_account_preview.dart';
import '../providers/tree_provider.dart';
import '../services/app_status_service.dart';
import '../services/custom_api_auth_service.dart';
import '../services/semya_invitation_deep_link_service.dart';
import 'package:app_links/app_links.dart';

import '../theme/app_theme.dart';
import '../utils/user_facing_error.dart';
import '../widgets/dismiss_keyboard.dart';
import '../widgets/email_provider_mismatch_dialog.dart';
import '../widgets/glass_panel.dart';
import '../widgets/google_account_confirm_dialog.dart';
import '../widgets/google_sign_in_action.dart';
import '../widgets/offline_indicator.dart';
import 'privacy_policy_screen.dart' show kLegalDocsVersion;

part 'auth/auth_email_actions.dart';
part 'auth/auth_social_actions.dart';
part 'auth/auth_form_sections.dart';
part 'auth/auth_layout_sections.dart';
part 'auth/auth_widgets.dart';

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

  // Согласие при регистрации: обязательный чекбокс — без него кнопка
  // «Создать аккаунт» неактивна; версия документов уходит на бэк.
  bool _acceptedTerms = false;

  late final TapGestureRecognizer _termsLinkRecognizer = TapGestureRecognizer()
    ..onTap = () => GoRouter.of(context).push('/terms');

  late final TapGestureRecognizer _privacyLinkRecognizer =
      TapGestureRecognizer()
        ..onTap = () => GoRouter.of(context).push('/privacy');

  bool _isGoogleLoading = false;

  bool _isTelegramLoading = false;

  bool _isVkLoading = false;

  bool _isMaxLoading = false;

  bool _hasSubmitted = false;

  late final bool _supportsGoogleAuth;

  // Ship Q3a (2026-05-26): backend-driven capability flags for VK/
  // Telegram/MAX (and confirms Google). Null когда capability data
  // не loaded yet (in-flight либо legacy server без /health authProviders
  // field) → render «as-is» fallback (Telegram/VK/MAX show, Google
  // already gated by _supportsGoogleAuth). Non-null → gate per flag.
  AuthProvidersAvailability? _providersAvailability;

  StreamSubscription<void>? _googleWebAuthenticationSubscription;

  StreamSubscription<Uri>? _appLinkSubscription;

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
    _bindAppLinksListener();
    // Ship Q3a (2026-05-26): fetch backend provider availability.
    // Fire-and-forget — UI initially renders fallback (как раньше);
    // when data arrives, setState triggers re-render с gated buttons.
    unawaited(_loadProvidersAvailability());
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
    _appLinkSubscription?.cancel();
    _emailFocusNode.dispose();
    _nameFocusNode.dispose();
    _termsLinkRecognizer.dispose();
    _privacyLinkRecognizer.dispose();
    super.dispose();
  }

  /// When a deep-link OAuth callback fires (Android: app_links picks up
  /// rodnya://oauth/callback?...), we set [_pendingDeepLinkUri] so the
  /// _socialQueryParameter helper reads from there instead of Uri.base
  /// (which is the web-page URL and meaningless on mobile).
  Uri? _pendingDeepLinkUri;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: DismissKeyboardOnTap(
        child: Container(
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
            // UX audit 2026-05-25 Screen 1.1 (ed62ba6): Samsung S20 FE с
            // active Android call/status pill clip'ил hero — user видел
            // только «...дерево.» tail of headline. Default SafeArea
            // полагается на MediaQuery.padding, который на Android при
            // call-pill активном иногда reports lower than actual safe
            // area. `minimum: EdgeInsets.only(top: 12)` устанавливает
            // floor — даже если system padding несоответствует, hero
            // получает breathing room above. Bottom intentionally
            // omitted — keyboard / nav bar handled другими mechanisms.
            minimum: const EdgeInsets.only(top: 12),
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
                              // Compact bumped 16 → 20 — extra breathing
                              // perч после SafeArea minimum (per Audit
                              // 1.1). Wide unchanged — большой viewport
                              // не has the same clip risk.
                              vertical: isWide ? 28 : 20,
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
      // UX audit 2026-05-25 Screen 1.2 (ed62ba6): validation error
      // («Пароль должен содержать не менее 6 символов») truncated
      // на narrow screens к «Пароль должен содержать не мене...».
      // Flutter default `errorMaxLines: 1` причина. Allow до 2-х
      // строк wrap так every validator message helper читается
      // полностью (longest current is password message at ~42 chars
      // в Cyrillic, fits 2 lines comfortably на любом mobile width).
      errorMaxLines: 2,
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

  void _updateAuthState(VoidCallback fn) {
    setState(fn);
  }
}
