import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/person_dossier.dart';

class PersonDossierView extends StatelessWidget {
  const PersonDossierView({
    super.key,
    required this.dossier,
    this.headerChips = const <Widget>[],
    this.actionButtons = const <Widget>[],
    this.banner,
  });

  final PersonDossier dossier;
  final List<Widget> headerChips;
  final List<Widget> actionButtons;
  final Widget? banner;

  @override
  Widget build(BuildContext context) {
    final sections = _buildSections(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderCard(
          dossier: dossier,
          headerChips: headerChips,
          actionButtons: actionButtons,
        ),
        if (banner != null) ...[
          const SizedBox(height: 12),
          banner!,
        ],
        if (sections.isNotEmpty) ...[
          const SizedBox(height: 16),
          ...sections,
        ],
      ],
    );
  }

  List<Widget> _buildSections(BuildContext context) {
    final sections = <Widget>[];

    final personalItems = <_DossierItem>[
      if (dossier.birthDate != null)
        _DossierItem('Дата рождения', _formatDate(dossier.birthDate!)),
      if ((dossier.birthPlace ?? '').isNotEmpty)
        _DossierItem('Место рождения', dossier.birthPlace!),
      if (dossier.maidenName.isNotEmpty)
        _DossierItem('Девичья фамилия', dossier.maidenName),
      if (dossier.familyStatus.isNotEmpty)
        _DossierItem('Семейное положение', dossier.familyStatus),
      if (dossier.person.isAlive == false && dossier.person.deathDate != null)
        _DossierItem('Дата смерти', _formatDate(dossier.person.deathDate!)),
      if ((dossier.person.deathPlace ?? '').isNotEmpty)
        _DossierItem('Место смерти', dossier.person.deathPlace!),
    ];
    if (personalItems.isNotEmpty) {
      sections.add(_DossierSection(title: 'Основное', items: personalItems));
    }

    final aboutItems = <_DossierItem>[
      if (dossier.bio.isNotEmpty) _DossierItem('О себе', dossier.bio),
      if (dossier.familySummary.isNotEmpty)
        _DossierItem(
          dossier.isMemorial ? 'Память семьи' : 'Семейная справка',
          dossier.familySummary,
        ),
      if (dossier.aboutFamily.isNotEmpty)
        _DossierItem('Для семьи', dossier.aboutFamily),
    ];
    if (aboutItems.isNotEmpty) {
      sections.add(_DossierSection(title: 'О человеке', items: aboutItems));
    }

    final backgroundItems = <_DossierItem>[
      if (dossier.education.isNotEmpty)
        _DossierItem('Учёба', dossier.education),
      if (dossier.work.isNotEmpty) _DossierItem('Работа и дело', dossier.work),
      if (dossier.hometown.isNotEmpty)
        _DossierItem('Родной город', dossier.hometown),
      if (dossier.languages.isNotEmpty)
        _DossierItem('Языки', dossier.languages),
    ];
    if (backgroundItems.isNotEmpty) {
      sections
          .add(_DossierSection(title: 'Путь и дело', items: backgroundItems));
    }

    final worldviewItems = <_DossierItem>[
      if (dossier.values.isNotEmpty) _DossierItem('Ценности', dossier.values),
      if (dossier.religion.isNotEmpty)
        _DossierItem('Религия и мировоззрение', dossier.religion),
      if (dossier.interests.isNotEmpty)
        _DossierItem('Интересы и увлечения', dossier.interests),
    ];
    if (worldviewItems.isNotEmpty) {
      sections.add(_DossierSection(title: 'Взгляды', items: worldviewItems));
    }

    for (var index = 0; index < sections.length; index += 1) {
      if (index < sections.length - 1) {
        sections[index] = Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: sections[index],
        );
      }
    }

    return sections;
  }

  String _formatDate(DateTime value) =>
      DateFormat('d MMMM y', 'ru').format(value);
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.dossier,
    required this.headerChips,
    required this.actionButtons,
  });

  final PersonDossier dossier;
  final List<Widget> headerChips;
  final List<Widget> actionButtons;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = [
      if ((dossier.city ?? '').isNotEmpty) dossier.city!,
      if ((dossier.country ?? '').isNotEmpty) dossier.country!,
    ].join(', ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundImage: dossier.photoUrl != null
                    ? NetworkImage(dossier.photoUrl!)
                    : null,
                child: dossier.photoUrl == null
                    ? Text(
                        dossier.displayName.isNotEmpty
                            ? dossier.displayName.characters.first
                            : '?',
                        style: const TextStyle(fontSize: 24),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dossier.displayName,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        location,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DossierChip(
                icon: dossier.isMemorial
                    ? Icons.history_toggle_off_outlined
                    : Icons.favorite_border,
                label: dossier.isMemorial ? 'Память' : 'Живой профиль',
                highlighted: dossier.isMemorial,
              ),
              ...headerChips,
            ],
          ),
          if (actionButtons.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: actionButtons,
            ),
          ],
        ],
      ),
    );
  }
}

class _DossierSection extends StatelessWidget {
  const _DossierSection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<_DossierItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _DossierLine(item: item),
            ),
          ),
        ],
      ),
    );
  }
}

class _DossierLine extends StatelessWidget {
  const _DossierLine({required this.item});

  final _DossierItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          item.value,
          style: theme.textTheme.bodyLarge,
        ),
      ],
    );
  }
}

class _DossierChip extends StatelessWidget {
  const _DossierChip({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor:
          highlighted ? theme.colorScheme.secondaryContainer : null,
    );
  }
}

class _DossierItem {
  const _DossierItem(this.label, this.value);

  final String label;
  final String value;
}
