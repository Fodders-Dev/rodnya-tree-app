import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/person_dossier.dart';
import '../theme/app_theme.dart';
import 'glass_panel.dart';

class PersonDossierView extends StatelessWidget {
  const PersonDossierView({
    super.key,
    required this.dossier,
    this.headerChips = const <Widget>[],
    this.actionButtons = const <Widget>[],
    this.banner,
    this.statsRow,
  });

  final PersonDossier dossier;
  final List<Widget> headerChips;
  final List<Widget> actionButtons;
  final Widget? banner;
  // Optional stats row (posts / relatives / trees) — shown in personal profile.
  final Widget? statsRow;

  @override
  Widget build(BuildContext context) {
    final sections = _buildSections(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroCard(
          dossier: dossier,
          headerChips: headerChips,
          actionButtons: actionButtons,
          statsRow: statsRow,
        ),
        if (banner != null) ...[
          const SizedBox(height: 12),
          banner!,
        ],
        if (sections.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...sections,
        ],
      ],
    );
  }

  List<Widget> _buildSections(BuildContext context) {
    final sections = <_SectionData>[];

    final personalItems = <_FieldData>[
      if (dossier.birthDate != null)
        _FieldData(
          Icons.cake_outlined,
          'Дата рождения',
          _formatDate(dossier.birthDate!),
        ),
      if ((dossier.birthPlace ?? '').isNotEmpty)
        _FieldData(
          Icons.location_city_outlined,
          'Место рождения',
          dossier.birthPlace!,
        ),
      if (dossier.maidenName.isNotEmpty)
        _FieldData(
          Icons.drive_file_rename_outline,
          'Девичья фамилия',
          dossier.maidenName,
        ),
      if (dossier.familyStatus.isNotEmpty)
        _FieldData(
          Icons.favorite_border,
          'Семейное положение',
          dossier.familyStatus,
        ),
      if (dossier.person.isAlive == false && dossier.person.deathDate != null)
        _FieldData(
          Icons.history_toggle_off_outlined,
          'Дата смерти',
          _formatDate(dossier.person.deathDate!),
        ),
      if ((dossier.person.deathPlace ?? '').isNotEmpty)
        _FieldData(
          Icons.place_outlined,
          'Место смерти',
          dossier.person.deathPlace!,
        ),
    ];
    if (personalItems.isNotEmpty) {
      sections.add(_SectionData('Основное', personalItems));
    }

    final aboutItems = <_FieldData>[
      if (dossier.bio.isNotEmpty)
        _FieldData(Icons.person_outline, 'О себе', dossier.bio),
      if (dossier.familySummary.isNotEmpty)
        _FieldData(
          dossier.isMemorial
              ? Icons.history_edu_outlined
              : Icons.groups_outlined,
          dossier.isMemorial ? 'Память семьи' : 'Семейная справка',
          dossier.familySummary,
        ),
      if (dossier.aboutFamily.isNotEmpty)
        _FieldData(Icons.chat_bubble_outline, 'Для семьи', dossier.aboutFamily),
    ];
    if (aboutItems.isNotEmpty) {
      sections.add(_SectionData('О человеке', aboutItems));
    }

    final backgroundItems = <_FieldData>[
      if (dossier.education.isNotEmpty)
        _FieldData(Icons.school_outlined, 'Учёба', dossier.education),
      if (dossier.work.isNotEmpty)
        _FieldData(Icons.work_outline, 'Работа и дело', dossier.work),
      if (dossier.hometown.isNotEmpty)
        _FieldData(
          Icons.home_outlined,
          'Родной город',
          dossier.hometown,
        ),
      if (dossier.languages.isNotEmpty)
        _FieldData(Icons.language, 'Языки', dossier.languages),
    ];
    if (backgroundItems.isNotEmpty) {
      sections.add(_SectionData('Путь и дело', backgroundItems));
    }

    final worldviewItems = <_FieldData>[
      if (dossier.values.isNotEmpty)
        _FieldData(Icons.stars_outlined, 'Ценности', dossier.values),
      if (dossier.religion.isNotEmpty)
        _FieldData(
          Icons.spa_outlined,
          'Религия и мировоззрение',
          dossier.religion,
        ),
      if (dossier.interests.isNotEmpty)
        _FieldData(
          Icons.interests_outlined,
          'Интересы и увлечения',
          dossier.interests,
        ),
    ];
    if (worldviewItems.isNotEmpty) {
      sections.add(_SectionData('Взгляды', worldviewItems));
    }

    return sections
        .asMap()
        .entries
        .map(
          (entry) => Padding(
            padding: EdgeInsets.only(
              bottom: entry.key < sections.length - 1 ? 10 : 0,
            ),
            child: _DossierSection(data: entry.value),
          ),
        )
        .toList();
  }

  String _formatDate(DateTime value) =>
      DateFormat('d MMMM y', 'ru').format(value);
}

// ── Hero card ─────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.dossier,
    required this.headerChips,
    required this.actionButtons,
    this.statsRow,
  });

  final PersonDossier dossier;
  final List<Widget> headerChips;
  final List<Widget> actionButtons;
  final Widget? statsRow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final location = [
      if ((dossier.city ?? '').isNotEmpty) dossier.city!,
      if ((dossier.country ?? '').isNotEmpty) dossier.country!,
    ].join(', ');

    // Ring colour: teal for living, purple-ish for memorial.
    final ringColor = dossier.isMemorial
        ? (isDark ? const Color(0xFF9B8DFF) : const Color(0xFF7C6FE0))
        : scheme.primary;

    final allChips = <Widget>[
      if (dossier.isMemorial)
        _StatusChip(
          icon: Icons.history_toggle_off_outlined,
          label: 'Память',
          color: ringColor,
          filled: true,
        ),
      ...headerChips,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Always use the cover-banner compact layout per Claude reference.
        // The legacy wide-card variant below is kept only as a fallback if
        // ever explicitly forced (currently never reached).
        const compact = true;

        if (compact) {
          final tokens = theme.extension<RodnyaDesignTokens>() ??
              (isDark ? RodnyaDesignTokens.dark : RodnyaDesignTokens.light);
          final controls = <Widget>[...allChips, ...actionButtons];
          return Container(
            decoration: BoxDecoration(
              color: tokens.surfaceStrong,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: tokens.surfaceLine),
              boxShadow: tokens.panelShadow(theme.brightness),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cover gradient banner
                Container(
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        tokens.accent,
                        tokens.warm,
                      ],
                    ),
                  ),
                ),
                // Avatar overlapping + content
                Transform.translate(
                  offset: const Offset(0, -34),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: tokens.surfaceStrong,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: 0.18,
                                    ),
                                    blurRadius: 22,
                                    spreadRadius: -10,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: _GradientAvatarRing(
                                photoUrl: dossier.photoUrl,
                                displayName: dossier.displayName,
                                radius: 36,
                                ringColor: ringColor,
                              ),
                            ),
                            const Spacer(),
                            // Edit chip placeholder rendered by actionButtons below
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (location.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.location_on_rounded,
                                  size: 13,
                                  color: tokens.inkMuted,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    location,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTheme.sans(
                                      color: tokens.inkMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Text(
                          dossier.displayName,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.serif(
                            color: tokens.ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.22,
                            height: 1.2,
                          ),
                        ),
                        if (statsRow != null) ...[
                          const SizedBox(height: 16),
                          statsRow!,
                        ],
                        if (controls.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: controls,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // ignore: dead_code
        return GlassPanel(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          borderRadius: BorderRadius.circular(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _GradientAvatarRing(
                photoUrl: dossier.photoUrl,
                displayName: dossier.displayName,
                radius: 42,
                ringColor: ringColor,
              ),
              const SizedBox(height: 14),
              Text(
                dossier.displayName,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              if (location.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      location,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
              if (statsRow != null) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),
                statsRow!,
              ],
              if (allChips.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: allChips,
                ),
              ],
              if (actionButtons.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: actionButtons,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ── Avatar with gradient ring ─────────────────────────────────────────────────

class _GradientAvatarRing extends StatelessWidget {
  const _GradientAvatarRing({
    required this.photoUrl,
    required this.displayName,
    required this.radius,
    required this.ringColor,
  });

  final String? photoUrl;
  final String displayName;
  final double radius;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = displayName.isNotEmpty
        ? displayName.characters.first.toUpperCase()
        : '?';

    return Container(
      width: radius * 2 + 6,
      height: radius * 2 + 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ringColor,
            Color.lerp(ringColor, Colors.white, 0.35) ?? ringColor,
            ringColor.withValues(alpha: 0.7),
          ],
        ),
      ),
      padding: const EdgeInsets.all(3),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.surface,
        ),
        padding: const EdgeInsets.all(2),
        child: ClipOval(
          child: photoUrl != null && photoUrl!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: photoUrl!,
                  width: radius * 2,
                  height: radius * 2,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => _AvatarPlaceholder(
                    radius: radius,
                    initials: initials,
                    color: ringColor,
                    theme: theme,
                  ),
                  errorWidget: (_, __, ___) => _AvatarPlaceholder(
                    radius: radius,
                    initials: initials,
                    color: ringColor,
                    theme: theme,
                  ),
                )
              : _AvatarPlaceholder(
                  radius: radius,
                  initials: initials,
                  color: ringColor,
                  theme: theme,
                ),
        ),
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({
    required this.radius,
    required this.initials,
    required this.color,
    required this.theme,
  });

  final double radius;
  final String initials;
  final Color color;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      color: color.withValues(alpha: 0.14),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: radius * 0.72,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
    );
  }
}

// ── Status chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info section ──────────────────────────────────────────────────────────────

class _SectionData {
  const _SectionData(this.title, this.fields);

  final String title;
  final List<_FieldData> fields;
}

class _FieldData {
  const _FieldData(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;
}

class _DossierSection extends StatelessWidget {
  const _DossierSection({required this.data});

  final _SectionData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Eyebrow: uppercase tracked label, no icon
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text(
            data.title.toUpperCase(),
            style: AppTheme.sans(
              color: tokens.inkMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        // Field card with rounded surfaceStrong + dividers
        Container(
          decoration: BoxDecoration(
            color: tokens.surfaceStrong,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: tokens.surfaceLine),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < data.fields.length; i++) ...[
                _FieldRow(field: data.fields[i]),
                if (i != data.fields.length - 1)
                  Container(
                    height: 0.7,
                    margin: const EdgeInsets.only(left: 56),
                    color: tokens.surfaceLine,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field});

  final _FieldData field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(field.icon, size: 17, color: tokens.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  field.label,
                  style: AppTheme.sans(
                    color: tokens.inkMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  field.value,
                  style: AppTheme.sans(
                    color: tokens.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
