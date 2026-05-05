import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';

/// Full-screen onboarding tour shown once after first registration.
///
/// Five slides, swipeable PageView, page indicators, "Пропустить" link in
/// the corner, and a single "Далее" / "Начать" CTA at the bottom. We persist
/// "seen" via [OnboardingService] both on Skip and on Finish so the tour
/// never re-shows itself.
///
/// Visual language follows [RodnyaDesignTokens] — warm cream gradient, sage
/// soft icon halo, ink/inkSecondary text — to read as part of the same app
/// and not a generic Material wizard.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.onFinish});

  /// Optional override for callers that want custom navigation after the
  /// tour ends (defaults to `context.go('/')`). Tests use this to avoid
  /// pulling the entire root navigator into the widget tree.
  final VoidCallback? onFinish;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _index = 0;

  static const List<_OnboardingSlide> _slides = [
    _OnboardingSlide(
      icon: Icons.eco_outlined,
      title: 'Добро пожаловать в Родню',
      body:
          'Это пространство для тёплых семейных связей — без алгоритмов '
          'и спама. Только ваши близкие.',
    ),
    _OnboardingSlide(
      icon: Icons.account_tree_outlined,
      title: 'Семейное древо',
      body:
          'Соберите дерево по веткам, добавьте родных и истории каждого '
          'человека. Дерево хранится приватно, видно только семье.',
    ),
    _OnboardingSlide(
      icon: Icons.auto_stories_outlined,
      title: 'Истории и моменты',
      body:
          'Делитесь короткими историями и постами — фото, видео, текст. '
          'Они доступны выбранному кругу: семье, близким или всем родным.',
    ),
    _OnboardingSlide(
      icon: Icons.forum_outlined,
      title: 'Чаты и события',
      body:
          'Личные и семейные чаты, кружочки голосом и видео, общий '
          'календарь дней рождения — всё под рукой.',
    ),
    _OnboardingSlide(
      icon: Icons.celebration_outlined,
      title: 'Готовы начать?',
      body:
          'Начнём с вашего профиля и первой ветки. Можно вернуться к '
          'инструкции из настроек в любой момент.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish({bool skipped = false}) async {
    await OnboardingService.instance.markSeen();
    if (!mounted) return;
    final onFinish = widget.onFinish;
    if (onFinish != null) {
      onFinish();
      return;
    }
    if (skipped) {
      context.go('/');
    } else {
      // Funnel new users into the profile editor first — that's the most
      // useful next step (avatar + name unlock relations and feeds). Falls
      // through to home if the route isn't available for any reason.
      context.go('/profile/edit');
    }
  }

  void _next() {
    if (_index >= _slides.length - 1) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        RodnyaDesignTokens.light;
    final isLast = _index == _slides.length - 1;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              tokens.bgTintWarm,
              tokens.bgBase,
              tokens.bgTintSage,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Column(
                  children: [
                    // Top bar — skip on the right while we have more slides.
                    SizedBox(
                      height: 40,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!isLast)
                            TextButton(
                              onPressed: () => _finish(skipped: true),
                              style: TextButton.styleFrom(
                                foregroundColor: tokens.inkSecondary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              child: const Text('Пропустить'),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _slides.length,
                        onPageChanged: (i) => setState(() => _index = i),
                        itemBuilder: (context, i) =>
                            _SlideView(slide: _slides[i], tokens: tokens),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _DotsIndicator(
                      count: _slides.length,
                      index: _index,
                      tokens: tokens,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _next,
                        style: FilledButton.styleFrom(
                          backgroundColor: tokens.accent,
                          foregroundColor: tokens.accentInk,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              tokens.radiusMd,
                            ),
                          ),
                          textStyle: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: Text(isLast ? 'Начать' : 'Далее'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide, required this.tokens});
  final _OnboardingSlide slide;
  final RodnyaDesignTokens tokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Soft halo behind the icon — sage tint matches the app's
          // accent-soft chips elsewhere (post composer audience pill, etc.).
          Container(
            width: 144,
            height: 144,
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              slide.icon,
              size: 64,
              color: tokens.accentStrong,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: tokens.ink,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              slide.body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: tokens.inkSecondary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DotsIndicator extends StatelessWidget {
  const _DotsIndicator({
    required this.count,
    required this.index,
    required this.tokens,
  });

  final int count;
  final int index;
  final RodnyaDesignTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active
                ? tokens.accent
                : tokens.ink.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
