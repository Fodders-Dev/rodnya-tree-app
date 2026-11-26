part of '../relative_details_screen.dart';

extension _RelativeDetailsDossier on _RelativeDetailsScreenState {
  // The person's dossier (linked profile → tree person fallback). Shared by
  // the main card and the «Основная информация» screen.
  PersonDossier _resolveDossier() {
    return _dossier ??
        (_userProfile != null
            ? PersonDossier.fromProfile(_userProfile!, treePerson: _person)
            : PersonDossier.fromPerson(
                _person!,
                canEditFamilyFields: _canEditOrDelete(),
              ));
  }

  String? _basicGenderLabel(Gender gender) {
    switch (gender) {
      case Gender.male:
        return 'Мужской';
      case Gender.female:
        return 'Женский';
      case Gender.other:
        return 'Другой';
      case Gender.unknown:
        return null;
    }
  }

  // §3.2.1 read-first facts section, on the card under the header. Shows
  // only filled fields, grouped (паспорт/места → отношение/пол → био-
  // факты). NO name (the header already shows it) and the birth DATE (not
  // the header's age). Edit ✏️ (gated) → existing structured editor.
  // Self-hides when nothing is filled.
  Widget _buildBasicInfoSection() {
    final person = _person;
    if (person == null) return const SizedBox.shrink();
    final d = _resolveDossier();

    final passport = <_BasicInfoRow>[];
    void addPassport(String label, String? value, {bool memorial = false}) {
      final v = value?.trim() ?? '';
      if (v.isNotEmpty) {
        passport.add(_BasicInfoRow(label, v, memorial: memorial));
      }
    }

    addPassport('Девичья фамилия', d.maidenName);
    if (person.birthDate != null) {
      // F5: «знаю только год» → «1888 год» вместо фейкового «1 января 1888».
      addPassport(
        person.birthDateIsYearOnly ? 'Год рождения' : 'Дата рождения',
        person.birthDateIsYearOnly
            ? '${person.birthDate!.year}'
            : _formatRussianDate(person.birthDate!),
      );
    }
    addPassport('Место рождения', d.birthPlace);
    addPassport('Родом из', d.hometown);
    if (person.deathDate != null) {
      addPassport(
        person.deathDateIsYearOnly ? 'Год смерти' : 'Дата смерти',
        person.deathDateIsYearOnly
            ? '${person.deathDate!.year}'
            : _formatRussianDate(person.deathDate!),
        memorial: true,
      );
    }
    addPassport('Место смерти', person.deathPlace);

    final who = <_BasicInfoRow>[];
    final relation = _getDirectRelationLabel();
    if (relation != null && relation.trim().isNotEmpty) {
      who.add(_BasicInfoRow('Отношение', relation.trim()));
    }
    final gender = _basicGenderLabel(person.gender);
    if (gender != null) who.add(_BasicInfoRow('Пол', gender));

    final about = <_BasicInfoRow>[];
    void addAbout(String label, String value) {
      if (value.trim().isNotEmpty) {
        about.add(_BasicInfoRow(label, value.trim()));
      }
    }

    addAbout('Образование', d.education);
    addAbout('Работа', d.work);
    addAbout('Языки', d.languages);
    addAbout('Интересы', d.interests);

    final groups = [passport, who, about].where((g) => g.isNotEmpty).toList();
    if (groups.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Основная информация',
                key: const Key('basic-info-title'),
                style: AppTheme.serif(
                  color: theme.colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              if (_canDirectEditProfile())
                IconButton(
                  key: const Key('basic-info-edit'),
                  tooltip: 'Редактировать',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: _editRelative,
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var gi = 0; gi < groups.length; gi++) ...[
            if (gi > 0) const SizedBox(height: 10),
            for (final row in groups[gi]) _basicInfoRow(theme, row),
          ],
        ],
      ),
    );
  }

  Widget _basicInfoRow(ThemeData theme, _BasicInfoRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              row.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'Lora',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (row.memorial) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '† Память',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Profile Redesign helpers (relative card flavour) ───────────────────────

  /// P1a: мягкий индикатор полноты анкеты + одна подсказка. Это
  /// приглашение, не задача: без красноты и процентов-укоров. Считаем 4
  /// базовых пункта (фото · дата рождения · место · биография); подсказка
  /// предлагает первый незаполненный по приоритету и по тапу открывает
  /// нужную форму. Полностью заполненная анкета — плашки нет.
  Widget _buildCompletenessNudge(
    PersonDossier dossier,
    List<Map<String, dynamic>> galleryEntries,
  ) {
    final person = _person;
    if (person == null || !_canDirectEditProfile()) {
      return const SizedBox.shrink();
    }

    final hasPhoto = (person.photoUrl?.trim().isNotEmpty ?? false) ||
        galleryEntries.isNotEmpty;
    final hasBirthDate = person.birthDate != null;
    final hasPlace = _composeRelativeLocation(dossier) != null;
    final hasBio = person.bio?.trim().isNotEmpty ?? false;

    final filled = [hasPhoto, hasBirthDate, hasPlace, hasBio]
        .where((value) => value)
        .length;
    const total = 4;
    if (filled >= total) {
      return const SizedBox.shrink();
    }

    // Приоритет подсказки: фото → даты → места → биография.
    final String hint;
    final VoidCallback onTap;
    if (!hasPhoto) {
      hint = 'Добавьте фото';
      onTap = _pickAndUploadGalleryImage;
    } else if (!hasBirthDate) {
      hint = 'Добавьте дату рождения';
      onTap = _editRelative;
    } else if (!hasPlace) {
      hint = 'Укажите место';
      onTap = _editRelative;
    } else {
      hint = 'Расскажите о человеке';
      onTap = _editRelative;
    }

    final tokens = AppTheme.tokensOf(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Material(
        color: tokens.accentSoft.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: const Key('relative-completeness-nudge'),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 18,
                  color: tokens.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Заполнено $filled из $total · $hint',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.sans(
                      color: tokens.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: tokens.inkMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _composeRelativeLocation(PersonDossier d) {
    final city = d.city?.trim() ?? '';
    final country = d.country?.trim() ?? '';
    final birthPlace = d.birthPlace?.trim() ?? '';
    if (city.isNotEmpty && country.isNotEmpty) return '$city · $country';
    if (city.isNotEmpty) return city;
    if (country.isNotEmpty) return country;
    if (birthPlace.isNotEmpty) return birthPlace;
    return null;
  }

  String? _composeYears(FamilyPerson person) {
    final birth = person.birthDate?.year;
    final death = person.deathDate?.year;
    if (birth == null && death == null) return null;
    if (birth != null && death != null) return '$birth — $death';
    if (birth != null) return '$birth г.';
    return '— $death';
  }

  bool _kinshipSectionHasContent() {
    final descriptor = _viewerDescriptor;
    if (descriptor == null) return false;
    if (_person?.id == _currentUserPersonId) return false;
    final label = (descriptor.primaryRelationLabel ?? '').trim();
    final summary = (descriptor.pathSummary ?? '').trim();
    return label.isNotEmpty || summary.isNotEmpty;
  }

  Widget _buildKinshipSection() {
    final descriptor = _viewerDescriptor!;
    final label = (descriptor.primaryRelationLabel ?? '').trim();
    final summary = (descriptor.pathSummary ?? '').trim();
    final modifier =
        descriptor.isBlood ? 'кровное родство' : 'родственная связь';
    final altCount = descriptor.alternatePathCount;
    final altSuffix = altCount > 0
        ? altCount == 1
            ? ' · ещё 1 путь'
            : ' · ещё $altCount пути'
        : '';

    final rows = <Widget>[];
    if (label.isNotEmpty) {
      rows.add(InfoRow(
        icon: Icons.diversity_3_outlined,
        label: 'Родство',
        value: '$label · $modifier$altSuffix',
        isFirst: rows.isEmpty,
      ));
    }
    if (summary.isNotEmpty) {
      rows.add(InfoRow(
        icon: Icons.route_outlined,
        label: 'Путь',
        value: summary,
        isFirst: rows.isEmpty,
        onTap: _showRelationPathSheet,
      ));
    }
    if (rows.isNotEmpty) {
      final last = rows.removeLast() as InfoRow;
      rows.add(InfoRow(
        icon: last.icon,
        label: last.label,
        value: last.value,
        isFirst: last.isFirst,
        isLast: true,
        onTap: last.onTap,
      ));
    }
    return ProfileSection(title: 'Связь', children: rows);
  }

  Widget _buildRelativeFamilyNoteSection(PersonDossier d) {
    final summary = d.familySummary.trim();
    final about = d.aboutFamily.trim();
    final rows = <Widget>[];
    if (summary.isNotEmpty) {
      rows.add(InfoRow(
        icon: Icons.notes_outlined,
        label: 'Для семьи',
        value: summary,
        warm: true,
        isFirst: rows.isEmpty,
      ));
    }
    if (about.isNotEmpty) {
      rows.add(InfoRow(
        icon: Icons.family_restroom_outlined,
        label: 'О семье',
        value: about,
        warm: true,
        isFirst: rows.isEmpty,
      ));
    }
    if (rows.isNotEmpty) {
      final last = rows.removeLast() as InfoRow;
      rows.add(InfoRow(
        icon: last.icon,
        label: last.label,
        value: last.value,
        warm: last.warm,
        isFirst: last.isFirst,
        isLast: true,
      ));
    }
    return ProfileSection(title: 'Заметка для семьи', children: rows);
  }

  String _formatRussianDate(DateTime d) {
    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    // Redesign-aligned section frame for the relative card's tail
    // sections (Фотографии / История изменений / Связанный профиль /
    // Связи и родство / Семья). Uppercase Manrope title + warm
    // tinted card matches the hero / facts pattern; the children get
    // their own internal padding via the inner Padding wrapper.
    return ProfileSection(
      title: title,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildLinkedProfileSection() {
    final linkedUserId = _person?.userId;
    if (linkedUserId == null || linkedUserId.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildInfoSection('Связанный профиль', [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.link_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _userProfile?.displayName ?? _person!.displayName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Карточка связана с аккаунтом в Родне. Фото, имя и базовые данные синхронизируются из профиля.',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.person_outline, size: 16),
                  label: Text(
                    _person?.id == _currentUserPersonId
                        ? 'Это ваш профиль'
                        : 'Профиль подтвержден',
                  ),
                ),
                if (_userProfile?.city != null || _userProfile?.country != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.location_on_outlined, size: 16),
                    label: Text(
                      _buildPlaceLabel(
                            _userProfile?.city,
                            _userProfile?.country,
                          ) ??
                          'Локация не указана',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ]);
  }

  String? _buildPlaceLabel(String? city, String? country) {
    final hasCity = city != null && city.isNotEmpty;
    final hasCountry = country != null && country.isNotEmpty;
    if (!hasCity && !hasCountry) {
      return null;
    }

    if (hasCity && hasCountry) {
      return '$city, $country';
    }

    return city ?? country;
  }

  String? _normalizeOptionalText(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  Widget _buildDuplicateSuggestionBanner() {
    final theme = Theme.of(context);
    final suggestion = _duplicateSuggestions.first;
    final otherPerson = suggestion.otherPersonFor(_person!.id);
    final extraCount = _duplicateSuggestions.length - 1;

    return GlassPanel(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_search_outlined,
              color: theme.colorScheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Возможное совпадение',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  extraCount > 0
                      ? 'Похоже, эта карточка может совпадать с ${otherPerson.displayName} и ещё $extraCount.'
                      : 'Похоже, эта карточка может совпадать с ${otherPerson.displayName}.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: suggestion.reasons
                      .take(3)
                      .map(
                        (reason) => Chip(
                          label: Text(reason),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _showDuplicateSuggestionSheet(suggestion),
                    icon: const Icon(Icons.compare_arrows_outlined),
                    label: const Text('Сравнить'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDuplicateSuggestionSheet(PersonDuplicateSuggestion suggestion) {
    if (_person == null || !suggestion.involves(_person!.id)) {
      return;
    }
    final currentPerson = suggestion.personA.id == _person!.id
        ? suggestion.personA
        : suggestion.personB;
    final otherPerson = suggestion.otherPersonFor(_person!.id);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Сравнение карточек',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Перед объединением семьи стоит проверить, не описывают ли эти карточки одного человека.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                _buildDuplicatePersonSummary('Эта карточка', currentPerson),
                const SizedBox(height: 12),
                _buildDuplicatePersonSummary('Похожая карточка', otherPerson),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: suggestion.reasons
                      .map(
                        (reason) => Chip(
                          avatar: const Icon(Icons.check, size: 16),
                          label: Text(reason),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDuplicatePersonSummary(String title, FamilyPerson person) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            person.displayName,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(_formatDuplicatePersonFacts(person)),
        ],
      ),
    );
  }

  String _formatDuplicatePersonFacts(FamilyPerson person) {
    final facts = <String>[
      _formatDuplicateGender(person.gender),
      person.birthDate != null
          // F5: для yearOnly — «р. 1888» вместо фейкового 01.01.1888.
          ? (person.birthDateIsYearOnly
              ? 'р. ${person.birthDate!.year}'
              : DateFormat('dd.MM.yyyy').format(person.birthDate!))
          : 'Дата рождения не указана',
    ];
    final birthPlace = person.birthPlace?.trim();
    if (birthPlace != null && birthPlace.isNotEmpty) {
      facts.add(birthPlace);
    }
    return facts.join(' • ');
  }

  String _formatDuplicateGender(Gender gender) {
    switch (gender) {
      case Gender.male:
        return 'Мужчина';
      case Gender.female:
        return 'Женщина';
      case Gender.other:
        return 'Другой пол';
      case Gender.unknown:
        return 'Пол не указан';
    }
  }
}
