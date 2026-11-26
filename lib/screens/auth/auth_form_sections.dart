part of '../auth_screen.dart';

extension _AuthFormSections on _AuthScreenState {
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
        padding: EdgeInsets.all(compact ? 18 : 28),
        borderRadius: BorderRadius.circular(28),
        clipBehavior: kIsWeb ? Clip.none : Clip.antiAlias,
        color: cardColor,
        borderColor: isDark
            ? theme.colorScheme.outlineVariant.withValues(alpha: 0.9)
            : AppTheme.warmLine.withValues(alpha: 0.72),
        child: Form(
          key: _formKey,
          // Ship Q3 (2026-05-26): form-level autovalidate disabled —
          // per-field gating via TextFormField.autovalidateMode below.
          // UX audit 2026-05-25 Critical #2: form-level
          // onUserInteraction triggered ALL validators on EVERY
          // keystroke, so typing в «Имя» surfaced empty-email error
          // под Email field (visually adjacent → looked like wrong-
          // field mapping). Per-field mode validates only the field
          // user is interacting with; submit still runs Form.validate()
          // через все validators.
          autovalidateMode: AutovalidateMode.disabled,
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
              // Density chunk 18: the mode toggle right below already
              // says «Вход» / «Регистрация» — a second, much bigger
              // «Вход»/«Новый аккаунт» headline + caption underneath it
              // was a literal duplicate (~80dp of card height for
              // nothing new). Compact keeps a single caption line;
              // wide/desktop is untouched (toggle sits below there, so
              // the headline is the only mode indicator visible yet).
              if (compact) ...[
                _buildModeToggle(theme),
                const SizedBox(height: 10),
                Text(
                  _isLogin ? 'Откройте семью.' : 'Начните за минуту.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: secondaryTextColor,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
              ] else ...[
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
                const SizedBox(height: 22),
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
                  // Ship Q3: per-field autovalidate. Validator никогда
                  // не surface'ит email-related errors здесь.
                  autovalidateMode: _hasSubmitted
                      ? AutovalidateMode.onUserInteraction
                      : AutovalidateMode.disabled,
                  validator: (value) {
                    if (!_isLogin &&
                        (value == null || value.trim().length < 2)) {
                      return 'Имя должно содержать не менее 2 символов';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
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
                // Ship Q3: per-field autovalidate (см. Form-level комментарий).
                autovalidateMode: _hasSubmitted
                    ? AutovalidateMode.onUserInteraction
                    : AutovalidateMode.disabled,
                validator: (value) {
                  if (value == null ||
                      !value.contains('@') ||
                      !value.contains('.')) {
                    return 'Введите корректный email адрес';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
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
                            fontSize: 13,
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
                // Ship Q3: per-field autovalidate (см. Form-level комментарий).
                autovalidateMode: _hasSubmitted
                    ? AutovalidateMode.onUserInteraction
                    : AutovalidateMode.disabled,
                validator: (value) {
                  if (value == null || value.length < 6) {
                    return 'Пароль должен содержать не менее 6 символов';
                  }
                  return null;
                },
              ),
              if (!_isLogin) ...[
                const SizedBox(height: 10),
                // Обязательное согласие (тексты — docs/legal/SOGLASIE_PDN.md):
                // вся строка — тап-цель чекбокса, ссылки открывают документы.
                InkWell(
                  key: const Key('auth-consent-toggle'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () =>
                      _updateAuthState(() => _acceptedTerms = !_acceptedTerms),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: Checkbox(
                            value: _acceptedTerms,
                            onChanged: (checked) => _updateAuthState(
                              () => _acceptedTerms = checked ?? false,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text.rich(
                              TextSpan(
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 13,
                                  color: secondaryTextColor,
                                  height: 1.25,
                                ),
                                children: [
                                  const TextSpan(text: 'Я принимаю '),
                                  TextSpan(
                                    text: 'Пользовательское соглашение',
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    recognizer: _termsLinkRecognizer,
                                  ),
                                  const TextSpan(text: ' и даю '),
                                  TextSpan(
                                    text:
                                        'согласие на обработку моих персональных данных',
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    recognizer: _privacyLinkRecognizer,
                                  ),
                                  const TextSpan(
                                    text:
                                        ' в соответствии с Политикой конфиденциальности.',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('auth-submit'),
                onPressed: _isLoading ||
                        _isAnySocialLoading ||
                        (!_isLogin && !_acceptedTerms)
                    ? null
                    : _submit,
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
              // The inline «Забыли?» link above the password field
              // already covers password reset; the second one below
              // the submit button was a duplicate (user-reported:
              // «нахуя нам два забыли?»). Removed.
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Быстрый вход',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: secondaryTextColor,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 12),
              // Google web button is a fixed-width native pill (242x40).
              // Kept on its own centered row above the chip row — mixing
              // a 40dp-tall native pill into the compact chip row below
              // would force every chip to that height.
              // Ship Q3 (2026-05-26): UX audit 2026-05-25 Critical #3 —
              // «advertised-but-broken» Google login (snackbar «Google
              // появится после подключения ключей провайдера») gone.
              // Render Google button ONLY when capability check passes;
              // unconfigured environments просто не показывают кнопку.
              // Ship Q3a (2026-05-26): additionally gated by backend
              // authProviders.google flag — covers case когда client has
              // ID но backend has not enabled the provider.
              if (kIsWeb && _showGoogleButton) ...[
                Center(
                  child: buildGoogleSignInAction(
                    theme: theme,
                    isLoading: _isGoogleLoading,
                    enabled:
                        !_isLoading && !_isTelegramLoading && !_isVkLoading,
                    onPressed: _signInWithGoogle,
                    useNativeWebButton: true,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              // Density chunk 18: social chips + the QR-login entry used
              // to be a 60dp-circle-plus-label row (~86dp) FOLLOWED by a
              // separate centered QR text-button row (~50dp with its
              // gaps) — ~136dp of "быстрый вход" surface. Both are now
              // one Wrap of compact 46dp pill chips (icon + label side
              // by side); wraps to a second line only on very narrow
              // devices instead of always reserving two rows.
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  // Ship Q3 (2026-05-26): см. kIsWeb branch выше — кнопка
                  // показывается только когда provider configured.
                  // Ship Q3a (2026-05-26): + backend capability gate.
                  if (!kIsWeb && _showGoogleButton)
                    _SocialAuthChip(
                      label: 'Google',
                      icon: Icons.g_mobiledata_rounded,
                      isLoading: _isGoogleLoading,
                      onTap: () {
                        if (_isLoading ||
                            _isGoogleLoading ||
                            _isTelegramLoading ||
                            _isVkLoading ||
                            _isMaxLoading) {
                          return;
                        }
                        _signInWithGoogle();
                      },
                    ),
                  // Ship Q3a: Telegram/VK gated by backend availability.
                  // Null availability (legacy server либо load in-flight)
                  // → render (legacy behavior preserved).
                  if (_showTelegramButton)
                    _SocialAuthChip(
                      label: 'Telegram',
                      icon: Icons.send_rounded,
                      isLoading: _isTelegramLoading,
                      onTap: _isLoading || _isAnySocialLoading
                          ? null
                          : _startTelegramSignIn,
                    ),
                  if (_showVkButton)
                    _SocialAuthChip(
                      label: 'VK ID',
                      icon: Icons.alternate_email_rounded,
                      isLoading: _isVkLoading,
                      onTap: _isLoading || _isAnySocialLoading
                          ? null
                          : _startVkSignIn,
                    ),
                  // The mode toggle above already switches to register, and
                  // "Забыли?" sits inline with the password field, so the
                  // old duplicate "Создать аккаунт / У меня уже есть вход"
                  // and standalone "Пароль" links are gone — QR login is
                  // just another chip in this row, login-mode only.
                  if (_isLogin)
                    _SocialAuthChip(
                      label: 'QR-код',
                      icon: Icons.qr_code_2_rounded,
                      isLoading: false,
                      semanticsLabel: 'Войти по QR-коду',
                      onTap: _isLoading ? null : () => context.push('/auth/qr'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              // При регистрации согласие — явный чекбокс выше; пассивная
              // строка остаётся только для входа.
              if (_isLogin)
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Продолжая, вы соглашаетесь с ',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 14,
                        color: secondaryTextColor,
                      ),
                    ),
                    TextButton(
                      onPressed: () => GoRouter.of(context).push('/privacy'),
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(fontSize: 14),
                      ),
                      child: const Text('Политикой'),
                    ),
                    Text(
                      ' и ',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 14,
                        color: secondaryTextColor,
                      ),
                    ),
                    TextButton(
                      onPressed: () => GoRouter.of(context).push('/terms'),
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(fontSize: 14),
                      ),
                      child: const Text('Условиями'),
                    ),
                    Text(
                      '.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 14,
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

  Widget _buildModeToggle(ThemeData theme) {
    // User-reported: «Вход / Регистрация tabs выезжают за rounded
    // edges». The outer pill had no clipBehavior, so the inner
    // active-tab AnimatedContainer painted over the parent's
    // rounded corners on the left and right edges. Clip the parent
    // so the active pill is bounded by the same stadium shape.
    return Container(
      padding: const EdgeInsets.all(4),
      clipBehavior: Clip.antiAlias,
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
