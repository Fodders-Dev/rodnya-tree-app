import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/person_dossier.dart';
import 'glass_panel.dart';

// Icon mapping for each dossier section.
const _kSectionIcons = <String, IconData>{
  'Основное': Icons.cake_outlined,
  'О человеке': Icons.auto_stories_outlined,
  'Путь и дело': Icons.school_outlined,
  'Взгляды': Icons.spa_outlined,
};

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
      _StatusChip(
        icon: dossier.isMemorial
            ? Icons.history_toggle_off_outlined
            : Icons.favorite_border_rounded,
        label: dossier.isMemorial ? 'Память' : 'Живой профиль',
        color: ringColor,
        filled: true,
      ),
      ...headerChips,
    ];

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      borderRadius: BorderRadius.circular(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Avatar with gradient ring ──────────────────────────────────────
          _GradientAvatarRing(
            photoUrl: dossier.photoUrl,
            displayName: dossier.displayName,
            radius: 46,
            ringColor: ringColor,
          ),
          const SizedBox(height: 16),

          // ── Name ──────────────────────────────────────────────────────────
          Text(
            dossier.displayName,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),

          // ── Location ──────────────────────────────────────────────────────
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

          // ── Stats row (optional — personal profile only) ───────────────
          if (statsRow != null) ...[
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 16),
            statsRow!,
          ],

          // ── Status chips ───────────────────────────────────────────────
          if (allChips.isNotEmpty) ...[
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: allChips,
            ),
          ],

          // ── Action buttons ─────────────────────────────────────────────
          if (actionButtons.isNotEmpty) ...[
            const SizedBox(height: 16),
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
    final scheme = theme.colorScheme;
    final sectionIcon = _kSectionIcons[data.title] ?? Icons.info_outline;

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header: icon + title
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(sectionIcon, size: 17, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Text(
                data.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Fields
          ...data.fields.asMap().entries.map((entry) {
            final isLast = entry.key == data.fields.length - 1;
            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: _FieldRow(field: entry.value),
            );
          }),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field});

  final _FieldData field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(field.icon, size: 16, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                field.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                field.value,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
