part of '../auth_screen.dart';

extension _AuthEmailActions on _AuthScreenState {
  Future<void> _submit() async {
    if (_isLoading || _isAnySocialLoading) {
      return;
    }
    _clearSessionIssue();
    _updateAuthState(() {
      _hasSubmitted = true;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }

    _updateAuthState(() {
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
          // Чекбокс обязателен (кнопка без него неактивна) — фиксируем
          // версию принятых документов; момент ставит бэк.
          consentDocVersion: kLegalDocsVersion,
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

        // Brand-new email registrations get the onboarding tour first —
        // gives them a quick orientation before being dropped into an
        // empty home feed. Existing users (login) skip straight to the
        // resolved target. We still gate by hasSeen() so a returning user
        // who happens to register on a second device doesn't re-watch.
        final shouldShowOnboarding = !_isLogin &&
            !linkedTelegram &&
            !linkedVk &&
            !linkedMax &&
            !(await OnboardingService.instance.hasSeen());

        if (!mounted) {
          return;
        }

        final pendingInviteToken =
            SemyaInvitationDeepLinkService().pendingToken;
        if (pendingInviteToken != null && pendingInviteToken.isNotEmpty) {
          context.go('/invite/$pendingInviteToken');
        } else if (_authService.currentRequiresOnboarding) {
          context.go('/setup');
        } else if (shouldShowOnboarding) {
          context.go('/onboarding');
        } else {
          context.go(_resolvePostAuthRedirect());
        }
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
        _updateAuthState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Ship Bug B (2026-05-26): central handler для 409
  /// EMAIL_PROVIDER_MISMATCH. Shows disambig modal — user picks
  /// existing provider, мы dispatch к correct flow.
  Future<void> _handleEmailProviderMismatch(
    EmailProviderMismatch payload,
  ) async {
    final picked = await showEmailProviderMismatchDialog(context, payload);
    if (!mounted || picked == null) return;
    switch (picked) {
      case 'password':
        // Switch to login mode + pre-fill email so user знает что
        // ввести именно его password.
        _setMode(true);
        _emailController.text = payload.email;
        _focusPrimaryField();
        break;
      case 'google':
        if (_showGoogleButton) await _signInWithGoogle();
        break;
      case 'vk':
        if (_showVkButton) await _startVkSignIn();
        break;
      case 'telegram':
        if (_showTelegramButton) await _startTelegramSignIn();
        break;
      // 'max' currently не has UI entry-point (chip absent); skip.
    }
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
    _updateAuthState(() {
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

  /// Phase 6 chunk 4a (DECISIONS 2026-05-14 «post-signup redirect
  /// Option A»): `requiresOnboarding` от backend → redirect к
  /// `/setup` wizard. Иначе следуем pre-Phase-6 logic (redirectAfter
  /// либо `/`). Carousel branch `/onboarding` обрабатывается
  /// отдельно в email-submit path (только для пользователей
  /// без requiresOnboarding flag).
  String _resolvePostAuthRedirect() {
    final pendingInviteToken = SemyaInvitationDeepLinkService().pendingToken;
    if (pendingInviteToken != null && pendingInviteToken.isNotEmpty) {
      return '/invite/$pendingInviteToken';
    }
    if (_authService.currentRequiresOnboarding) {
      return '/setup';
    }
    return _resolvePostAuthTarget();
  }
}
