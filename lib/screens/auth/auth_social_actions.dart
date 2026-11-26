part of '../auth_screen.dart';

extension _AuthSocialActions on _AuthScreenState {
  Future<void> _loadProvidersAvailability() async {
    final result = await _authService.fetchAuthProvidersAvailability();
    if (!mounted || result == null) return;
    _updateAuthState(() {
      _providersAvailability = result;
    });
  }

  /// Ship Q3a: helpers gate each social button. Когда availability
  /// not yet loaded (либо backend incapable) — return true для
  /// preserved legacy behavior, except Google which сохраняет existing
  /// client-side _supportsGoogleAuth check.
  ///
  /// MAX chip not currently rendered в provider chip row (audit обозначил
  /// что MAX hidden пока OAuth flow не shipped), поэтому MAX gate not
  /// needed here — _providersAvailability.max остаётся accessible
  /// caller'у когда / если MAX button gets reintroduced.
  bool get _showGoogleButton =>
      _supportsGoogleAuth && (_providersAvailability?.google ?? true);

  bool get _showTelegramButton => _providersAvailability?.telegram ?? true;

  bool get _showVkButton => _providersAvailability?.vk ?? true;

  /// Subscribe to deep-link OAuth callbacks (Android opens the system
  /// browser for the OAuth dance, the backend redirects to
  /// rodnya://oauth/callback?xxxAuthCode=... when finalRedirect is
  /// set, app_links picks the URI up via the manifest intent-filter
  /// and routes it here). Web runs the same handlers via Uri.base.
  Future<void> _bindAppLinksListener() async {
    if (kIsWeb) return;
    try {
      final appLinks = AppLinks();
      // Cold-start case: the app was launched by tapping the deep
      // link → fetch initial URI and dispatch.
      final initial = await appLinks.getInitialLink();
      if (!mounted) return;
      if (initial != null) {
        unawaited(_dispatchOauthDeepLink(initial));
      }
      _appLinkSubscription = appLinks.uriLinkStream.listen((uri) {
        if (!mounted) return;
        unawaited(_dispatchOauthDeepLink(uri));
      });
    } catch (error) {
      debugPrint('Failed to bind app_links listener: $error');
    }
  }

  Future<void> _dispatchOauthDeepLink(Uri uri) async {
    // Accept BOTH the legacy custom-scheme callback and the
    // verified https App Link path. The custom scheme stays for
    // backward compat with older installs / devices that haven't
    // picked up the verified intent filter; the https path is the
    // only one another app can't intercept (Digital Asset Links
    // gives us exclusive ownership of /oauth/* on rodnya-tree.ru).
    final isCustomScheme = uri.scheme == 'rodnya' && uri.host == 'oauth';
    final isVerifiedHttps = uri.scheme == 'https' &&
        uri.host == 'rodnya-tree.ru' &&
        uri.path.startsWith('/oauth/');
    if (!isCustomScheme && !isVerifiedHttps) return;
    if (!mounted) return;
    _updateAuthState(() => _pendingDeepLinkUri = uri);
    try {
      await _handleSocialRedirectResults();
    } finally {
      if (mounted) {
        _updateAuthState(() => _pendingDeepLinkUri = null);
      }
    }
  }

  bool get _isAnySocialLoading =>
      _isGoogleLoading || _isTelegramLoading || _isVkLoading || _isMaxLoading;

  Future<void> _signInWithGoogle() => _runGoogleSignIn();

  /// [consentDocVersion] is set on the retry after the consent modal — a
  /// brand-new Google account needs affirmative consent (152-ФЗ). On that
  /// retry the account is already chosen, so we skip the confirm dialog.
  Future<void> _runGoogleSignIn({String? consentDocVersion}) async {
    _clearSessionIssue();
    _updateAuthState(() {
      _isGoogleLoading = true;
    });

    final isConsentRetry = consentDocVersion != null;
    try {
      // Ship Q2 (2026-05-25): surface confirm dialog после Google
      // chooser returns account info, ПЕРЕД backend session exchange.
      // Captures «silent wrong-account» case (Артёма mama hit это on
      // his old phone — Google chooser showed только his account,
      // she tapped reflex, landed в его production).
      final result = await _authService.signInWithGoogle(
        confirm: isConsentRetry
            ? null
            : (preview) async {
                if (!mounted) return GoogleAccountConfirmDecision.cancel;
                return showGoogleAccountConfirmDialog(context, preview);
              },
        consentDocVersion: consentDocVersion,
      );
      if (!mounted) return;

      // New social account → backend asked for consent. Show the consent
      // step and retry the SAME Google flow with the accepted doc version.
      if (result is SocialConsentRequired) {
        final accepted = await _showSocialConsentSheet('Google');
        if (!mounted || !accepted) return;
        await _runGoogleSignIn(consentDocVersion: kLegalDocsVersion);
        return;
      }

      if (_authService.currentUserId != null) {
        if (GetIt.I.isRegistered<TreeProvider>()) {
          await GetIt.I<TreeProvider>().loadInitialTree();
        }
        if (!mounted) return;
        context.go(_resolvePostAuthRedirect());
      }
    } on EmailProviderMismatchException catch (mismatch) {
      // Ship Bug B (2026-05-26): cross-provider email collision blocked
      // by backend. Show disambig modal so user can log in via existing
      // identity вместо silent-merge.
      if (!mounted) return;
      await _handleEmailProviderMismatch(mismatch.payload);
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
        _updateAuthState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }

  /// Consent step for a brand-new social account (152-ФЗ). Mirrors the
  /// email-registration checkbox: same Соглашение + ПДН texts and the same
  /// link recognizers. Returns true if the user affirmatively accepts.
  Future<bool> _showSocialConsentSheet(String providerLabel) async {
    final theme = Theme.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Согласие на обработку данных'),
          content: Text.rich(
            TextSpan(
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
              children: [
                TextSpan(
                  text: 'Чтобы создать аккаунт через $providerLabel, примите ',
                ),
                TextSpan(
                  text: 'Пользовательское соглашение',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                  recognizer: _termsLinkRecognizer,
                ),
                const TextSpan(text: ' и дайте '),
                TextSpan(
                  text: 'согласие на обработку персональных данных',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                  recognizer: _privacyLinkRecognizer,
                ),
                const TextSpan(
                  text: ' в соответствии с Политикой конфиденциальности.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Принимаю'),
            ),
          ],
        );
      },
    );
    return accepted ?? false;
  }

  Future<void> _startTelegramSignIn() async {
    final authService = _authService;
    if (authService is! CustomApiAuthService) {
      _showPlannedSocialAuthMessage('Telegram');
      return;
    }

    _clearSessionIssue();
    _updateAuthState(() {
      _isTelegramLoading = true;
    });

    try {
      final telegramStartUrl = await authService.resolveTelegramLoginStartUrl();
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _authError(
              e,
              fallbackMessage: 'Не удалось начать вход через Telegram.',
            ),
          ),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) {
        _updateAuthState(() {
          _isTelegramLoading = false;
        });
      }
    }
  }

  Future<void> _startVkSignIn({String? consentDocVersion}) async {
    final authService = _authService;
    if (authService is! CustomApiAuthService) {
      _showPlannedSocialAuthMessage('VK ID');
      return;
    }

    _clearSessionIssue();
    _updateAuthState(() {
      _isVkLoading = true;
    });

    try {
      // consentDocVersion is set on the re-start after the consent modal so a
      // brand-new VK account can be created with recorded consent (152-ФЗ).
      final vkStartUrl = await authService.resolveVkLoginStartUrl(
        consentDocVersion: consentDocVersion,
      );
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _authError(
              e,
              fallbackMessage: 'Не удалось начать вход через VK ID.',
            ),
          ),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) {
        _updateAuthState(() {
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

    _updateAuthState(() {
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
        context.go(_resolvePostAuthRedirect());
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

      // Don't force _isLogin=true — that traps a brand-new user
      // (no Rodnya account yet) in the login form they can't satisfy.
      // If we got a name from Telegram, default to register mode so
      // the user just picks an email + password and the link runs
      // automatically inside _submit() via _tryLinkPendingTelegramIdentity.
      // The mode toggle stays visible so existing users can flip
      // back to login and the link still attaches afterwards.
      _updateAuthState(() {
        if (displayName.isNotEmpty) {
          _isLogin = false;
        }
        _pendingTelegramLinkCode = completion.linkCode;
        _pendingTelegramMessage = completion.message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Telegram подтверждён. Войдите в аккаунт или создайте новый — '
            'Telegram привяжется автоматически.',
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
        _updateAuthState(() {
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

    _updateAuthState(() {
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
        context.go(_resolvePostAuthRedirect());
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

      // New VK account → backend asked for consent. Show the consent step and
      // re-run the VK flow with the accepted doc version (the VK code is
      // one-time, so we restart the provider flow rather than reuse a token).
      if (completion.isRequiresConsent) {
        final accepted = await _showSocialConsentSheet('VK ID');
        if (!mounted || !accepted) return;
        await _startVkSignIn(consentDocVersion: kLegalDocsVersion);
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

      // See _exchangeTelegramAuthCode for the rationale — same
      // pattern: don't trap a new user in login mode if we got
      // a usable name from VK ID.
      _updateAuthState(() {
        if (displayName.isNotEmpty) {
          _isLogin = false;
        }
        _pendingVkLinkCode = completion.linkCode;
        _pendingVkMessage = completion.message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'VK ID подтверждён. Войдите в аккаунт или создайте новый — '
            'VK ID привяжется автоматически.',
          ),
        ),
      );
    } on EmailProviderMismatchException catch (mismatch) {
      // Ship Bug B (2026-05-26): cross-provider email collision arrived
      // through VK handoff payload (exchangeVkAuthCode throws когда
      // backend returns status='email_provider_mismatch'). Same modal
      // pattern как Google.
      if (!mounted) return;
      await _handleEmailProviderMismatch(mismatch.payload);
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
        _updateAuthState(() {
          _isVkLoading = false;
        });
      }
    }
  }

  // ignore: unused_element
  Future<void> _startMaxSignIn() async {
    final authService = _authService;
    if (authService is! CustomApiAuthService) {
      _showPlannedSocialAuthMessage('MAX');
      return;
    }

    _clearSessionIssue();
    _updateAuthState(() {
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
        _updateAuthState(() {
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

    _updateAuthState(() {
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
        context.go(_resolvePostAuthRedirect());
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

      // Same pattern as Telegram / VK ID — see _exchangeTelegramAuthCode
      // for rationale.
      _updateAuthState(() {
        if (displayName.isNotEmpty) {
          _isLogin = false;
        }
        _pendingMaxLinkCode = completion.linkCode;
        _pendingMaxMessage = completion.message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'MAX подтверждён. Войдите в аккаунт или создайте новый — '
            'MAX привяжется автоматически.',
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
        _updateAuthState(() {
          _isMaxLoading = false;
        });
      }
    }
  }

  String? _socialQueryParameter(String name) {
    final overrideUri = _pendingDeepLinkUri;
    if (overrideUri != null) {
      final fromOverride = overrideUri.queryParameters[name];
      if (fromOverride != null && fromOverride.isNotEmpty) {
        return fromOverride;
      }
      // Some deep links carry the params in the fragment (#...).
      final fragment = overrideUri.fragment;
      if (fragment.isNotEmpty && fragment.contains('?')) {
        final queryPart = fragment.split('?').skip(1).join('?');
        final fromFragment = Uri.splitQueryString(queryPart)[name];
        if (fromFragment != null && fromFragment.isNotEmpty) {
          return fromFragment;
        }
      }
    }
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

    _updateAuthState(() {
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

    _updateAuthState(() {
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

    _updateAuthState(() {
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
}
