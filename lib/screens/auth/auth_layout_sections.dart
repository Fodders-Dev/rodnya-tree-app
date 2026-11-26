part of '../auth_screen.dart';

extension _AuthLayoutSections on _AuthScreenState {
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
    // User-reported: «Зеленый блок выглядит острым ... надо бы
    // дизайн переделать фонов этих». Hero used to span edge-to-edge
    // with sharp side corners, dark forest gradient bottoming out in
    // a hard horizontal line. Now it's a floating card — 12 dp side
    // margins, all-rounded 28 dp corners, softer sage gradient that
    // doesn't crush into deep forest at the bottom — sitting on the
    // scaffold's cream background. The auth card below is also a
    // floating card with the same 12 dp side margin so the pair
    // visually breathe.
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: _buildHeroPanel(theme, compact: true),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: _buildAuthCard(theme, compact: true),
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
      key: const Key('auth-hero-panel'),
      width: double.infinity,
      // Density chunk 18: compact hero used to force a 320dp floor —
      // a third of a 412×915 phone screen before any actionable
      // content. Headline shrunk to 2 lines (see below), so the hero
      // now sizes to its (much smaller) content; 150dp keeps it from
      // ever looking collapsed on very short strings.
      constraints: compact
          ? const BoxConstraints(minHeight: 150)
          : const BoxConstraints(),
      padding: EdgeInsets.fromLTRB(
        compact ? 22 : 28,
        compact ? 18 : 28,
        compact ? 22 : 28,
        compact ? 18 : 28,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment(-0.6, -1.0),
          end: Alignment(0.4, 1.0),
          colors: [
            Color(0xFF5A9778), // softer sage top
            Color(0xFF3F8265), // mid forest
            Color(0xFF2F6753), // deep but not crushed
          ],
        ),
        // Both compact AND wide get all-rounded corners now — the
        // hero is a floating card on cream, not a fused header.
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: compact ? 0.14 : 0.18),
            blurRadius: compact ? 24 : 30,
            offset: Offset(0, compact ? 12 : 18),
            spreadRadius: -4,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
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
                  const Icon(Icons.eco_outlined, size: 18, color: Colors.white),
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
              SizedBox(height: compact ? 10 : 24),
              // Density chunk 18: compact hero used to stack "Семья —" /
              // "это живое" / "дерево." as three separate block-level
              // lines at 38sp (~130dp just for the headline) — a third
              // of the phone screen before any actionable content. The
              // first two pieces now share a row so the whole headline
              // reads in 2 lines at a smaller size; wide/desktop keeps
              // the original 3-line 38sp treatment untouched.
              if (compact) ...[
                // FittedBox/scaleDown — "Семья — это живое" at 25sp
                // fits ≥390dp phones as-is; on narrower devices (320dp
                // class) it scales down instead of overflowing the
                // RenderFlex (mainAxisSize.min doesn't wrap on its own).
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        'Семья —',
                        style: AppTheme.serif(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'это ',
                              style: AppTheme.serif(
                                color: Colors.white,
                                fontSize: 25,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                                height: 1.05,
                              ),
                            ),
                            TextSpan(
                              text: 'живое',
                              style: AppTheme.serif(
                                color: const Color(0xFFE9C273),
                                fontSize: 25,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                                height: 1.05,
                              ).copyWith(fontStyle: FontStyle.italic),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'дерево.',
                  style: AppTheme.serif(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Истории, лица и даты — всё в одном месте.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.sans(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ] else ...[
                Text(
                  'Семья —',
                  style: AppTheme.serif(
                    color: Colors.white,
                    fontSize: 38,
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
                          fontSize: 38,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.4,
                          height: 1.05,
                        ),
                      ),
                      TextSpan(
                        text: 'живое',
                        style: AppTheme.serif(
                          color: const Color(0xFFE9C273),
                          fontSize: 38,
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
                    fontSize: 38,
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
              ],
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
}
