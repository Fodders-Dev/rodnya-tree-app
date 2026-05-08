part of 'relative_details_screen.dart';

extension _RelativeDetailsScreenSections on _RelativeDetailsScreenState {
  Widget _buildRelativeStateCard({
    required IconData icon,
    required String title,
    required String message,
    bool showProgress = false,
    List<Widget> actions = const <Widget>[],
  }) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: GlassPanel(
            padding: const EdgeInsets.all(22),
            borderRadius: BorderRadius.circular(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 28,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.38,
                  ),
                ),
                if (showProgress) ...[
                  const SizedBox(height: 18),
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildRelativeStateCard(
        icon: Icons.family_restroom_outlined,
        title: 'Открываем карточку',
        message: 'Подтягиваем досье, связи и семейный контекст.',
        showProgress: true,
      );
    }
    if (_errorMessage.isNotEmpty) {
      return _buildRelativeStateCard(
        icon: Icons.person_search_outlined,
        title: 'Карточка сейчас недоступна',
        message: _errorMessage,
        actions: [
          FilledButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: const Text('Повторить'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Назад'),
          ),
        ],
      );
    }
    if (_person == null) {
      return _buildRelativeStateCard(
        icon: Icons.person_off_outlined,
        title: 'Карточка не найдена',
        message:
            'Похоже, эта запись уже была удалена или ещё не успела синхронизироваться.',
        actions: [
          FilledButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: const Text('Обновить'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Назад'),
          ),
        ],
      );
    }

    final dossier = _dossier ??
        (_userProfile != null
            ? PersonDossier.fromProfile(
                _userProfile!,
                treePerson: _person,
              )
            : PersonDossier.fromPerson(
                _person!,
                canEditFamilyFields: _canEditOrDelete(),
              ));
    final bool canStartChat = _canStartChatWithPerson();
    final bool canInvite = _canInvitePerson();
    final contactStatus = _getContactStatus();
    final directRelationLabel = _getDirectRelationLabel();
    final galleryEntries = _person!.photoGallery;

    final person = _person!;
    final isDeceased = !person.isAlive || person.deathDate != null;
    final fullName = dossier.displayName.isNotEmpty
        ? dossier.displayName
        : person.name;
    final nameParts = _splitNameParts(person, dossier);
    final firstNameTrimmed = nameParts.firstName;
    final lastNameTrimmed = nameParts.lastName;
    final patronymicTrimmed = nameParts.patronymic;

    final loc = _composeRelativeLocation(dossier);
    final years = _composeYears(person);

    final actions = <Widget>[
      if (canStartChat)
        PillButton(
          label: 'Написать',
          icon: Icons.message_outlined,
          onPressed: _openChatWithPerson,
        ),
      if (canInvite)
        PillButton(
          label: _isGeneratingLink ? 'Готовим…' : 'Пригласить в Родню',
          icon: Icons.person_add_alt_1_outlined,
          variant: PillButtonVariant.outlined,
          onPressed: _isGeneratingLink ? null : _generateAndShareInviteLink,
        ),
      if (_canSuggestProfileEdits())
        PillButton(
          label: 'Предложить правку',
          icon: Icons.edit_note_outlined,
          variant: PillButtonVariant.outlined,
          onPressed: _suggestProfileChanges,
        ),
      if (_identityService != null &&
          _currentTreeId != null &&
          person.userId != _authService.currentUserId)
        PillButton(
          label:
              _isUpdatingIdentity ? 'Подтверждение…' : 'Это моя карточка',
          icon: Icons.verified_user_outlined,
          variant: PillButtonVariant.outlined,
          onPressed: _isUpdatingIdentity ? null : _requestIdentityClaim,
        ),
      if (_identityService != null && _canEditOrDelete())
        PillButton(
          label: _isUpdatingPrivacy ? 'Сохраняем…' : 'Приватность',
          icon: Icons.lock_outline_rounded,
          variant: PillButtonVariant.outlined,
          onPressed: _isUpdatingPrivacy ? null : _showPrivacySettings,
        ),
    ];

    final headerStatus = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: contactStatus.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: contactStatus.color.withValues(alpha: 0.22),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(contactStatus.icon, size: 13, color: contactStatus.color),
              const SizedBox(width: 5),
              Text(
                contactStatus.label,
                style: AppTheme.sans(
                  color: contactStatus.color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          contactStatus.description,
          style: AppTheme.sans(
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant
                .withValues(alpha: 0.85),
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
            height: 1.35,
          ),
        ),
      ],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileHeroCard(
                fullName: fullName,
                firstName:
                    firstNameTrimmed.isEmpty ? null : firstNameTrimmed,
                lastName:
                    lastNameTrimmed.isEmpty ? null : lastNameTrimmed,
                patronymic:
                    patronymicTrimmed.isEmpty ? null : patronymicTrimmed,
                photoUrl: dossier.photoUrl,
                location: loc,
                bio: dossier.bio.trim().isNotEmpty
                    ? dossier.bio.trim()
                    : (person.bio?.trim().isNotEmpty == true
                        ? person.bio!.trim()
                        : null),
                relBadge: directRelationLabel == null
                    ? null
                    : 'Для вас: $directRelationLabel',
                useWarmAvatar: true,
                deceased: isDeceased,
                deceasedYears: years,
                actions: actions,
                onEditPressed:
                    _canDirectEditProfile() ? _editRelative : null,
                editLabel: 'Редактировать',
              ),
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: headerStatus,
              ),
              if (_duplicateSuggestions.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(12, 18, 12, 0),
                  child: _buildDuplicateSuggestionBanner(),
                ),
              if (_kinshipSectionHasContent())
                _buildKinshipSection(),
              if (_relativeFactsHaveContent(dossier, person))
                _buildRelativeFactsSection(dossier, person),
              if (dossier.familySummary.trim().isNotEmpty ||
                  dossier.aboutFamily.trim().isNotEmpty)
                _buildRelativeFamilyNoteSection(dossier),
              if (galleryEntries.isNotEmpty || _canEditOrDelete())
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  child: _buildGallerySection(galleryEntries),
                ),
              if (_person != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  child: _buildHistorySection(),
                ),
              if (person.userId != null && person.userId!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  child: _buildLinkedProfileSection(),
                ),
              if (_graphTreeService != null &&
                  (person.id != _currentUserPersonId ||
                      _canEditOrDelete()))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  child: _buildRelationToolsSection(),
                ),
              if (_buildDirectFamilyRows().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  child: _buildInfoSection(
                    'Семья',
                    _buildDirectFamilyRows(),
                  ),
                ),
              // Profile Redesign: prominent «Удалить из дерева»
              // button at the tail of the card. Only shown when the
              // viewer can edit (mirrors the appbar trash icon's
              // existing gate). The bottom button matches the design
              // spec better than a tiny icon — destructive actions
              // shouldn't hide.
              if (_canDirectEditProfile())
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                  child: _DeleteRelativeButton(onTap: _deleteRelative),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Profile Redesign helpers (relative card flavour) ───────────────────────

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
    final modifier = descriptor.isBlood
        ? 'кровное родство'
        : 'родственная связь';
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

  bool _relativeFactsHaveContent(PersonDossier d, FamilyPerson p) {
    return p.birthDate != null ||
        (d.birthPlace ?? '').trim().isNotEmpty ||
        d.hometown.trim().isNotEmpty ||
        d.education.trim().isNotEmpty ||
        d.work.trim().isNotEmpty ||
        d.languages.trim().isNotEmpty ||
        d.interests.trim().isNotEmpty ||
        d.maidenName.trim().isNotEmpty;
  }

  Widget _buildRelativeFactsSection(PersonDossier d, FamilyPerson p) {
    final rows = <Widget>[];
    if (p.birthDate != null) {
      rows.add(InfoRow(
        icon: Icons.cake_outlined,
        label: 'Дата рождения',
        value: _formatRussianDate(p.birthDate!),
        warm: true,
        isFirst: rows.isEmpty,
      ));
    }
    if ((d.birthPlace ?? '').trim().isNotEmpty) {
      rows.add(InfoRow(
        icon: Icons.place_outlined,
        label: 'Место рождения',
        value: d.birthPlace!.trim(),
        warm: true,
        isFirst: rows.isEmpty,
      ));
    }
    if (d.hometown.trim().isNotEmpty) {
      rows.add(InfoRow(
        icon: Icons.account_tree_outlined,
        label: 'Родом из',
        value: d.hometown.trim(),
        warm: true,
        isFirst: rows.isEmpty,
      ));
    }
    if (d.education.trim().isNotEmpty) {
      rows.add(InfoRow(
        icon: Icons.school_outlined,
        label: 'Образование',
        value: d.education.trim(),
        warm: true,
        isFirst: rows.isEmpty,
      ));
    }
    if (d.work.trim().isNotEmpty) {
      rows.add(InfoRow(
        icon: Icons.work_outline_rounded,
        label: 'Работа',
        value: d.work.trim(),
        warm: true,
        isFirst: rows.isEmpty,
      ));
    }
    if (d.languages.trim().isNotEmpty) {
      rows.add(InfoRow(
        icon: Icons.language_outlined,
        label: 'Языки',
        value: d.languages.trim(),
        warm: true,
        isFirst: rows.isEmpty,
      ));
    }
    if (d.interests.trim().isNotEmpty) {
      rows.add(InfoRow(
        icon: Icons.auto_awesome_outlined,
        label: 'Интересы',
        value: d.interests.trim(),
        warm: true,
        isFirst: rows.isEmpty,
      ));
    }
    if (d.maidenName.trim().isNotEmpty) {
      rows.add(InfoRow(
        icon: Icons.label_outline,
        label: 'Девичья фамилия',
        value: d.maidenName.trim(),
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
    return ProfileSection(title: 'О человеке', children: rows);
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

  _RelativeNameParts _splitNameParts(
    FamilyPerson person,
    PersonDossier dossier,
  ) {
    final linked = dossier.linkedProfile;
    if (linked != null) {
      return _RelativeNameParts(
        firstName: linked.firstName.trim(),
        lastName: linked.lastName.trim(),
        patronymic: linked.middleName.trim(),
      );
    }
    final raw = person.name.trim();
    if (raw.isEmpty) {
      return const _RelativeNameParts(
        firstName: '',
        lastName: '',
        patronymic: '',
      );
    }
    // FamilyPerson stores name as «Фамилия Имя Отчество». Splitting
    // by whitespace gives us back those three parts (or fewer when the
    // record is partial). The hero-card composes them again as
    // «Имя Отчество\nФамилия» so both halves get the redesign's split
    // typography.
    final parts =
        raw.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.length == 1) {
      return _RelativeNameParts(
        firstName: parts.first,
        lastName: '',
        patronymic: '',
      );
    }
    if (parts.length == 2) {
      return _RelativeNameParts(
        firstName: parts[1],
        lastName: parts.first,
        patronymic: '',
      );
    }
    return _RelativeNameParts(
      firstName: parts[1],
      lastName: parts.first,
      patronymic: parts.sublist(2).join(' '),
    );
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
          ? DateFormat('dd.MM.yyyy').format(person.birthDate!)
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

  Widget _buildGallerySection(List<Map<String, dynamic>> galleryEntries) {
    final canManageGallery = _canEditOrDelete();
    final countLabel = galleryEntries.isEmpty
        ? 'Фотографий пока нет'
        : galleryEntries.length == 1
            ? '1 фото'
            : '${galleryEntries.length} фото';

    return _buildInfoSection('Фотографии', [
      Row(
        children: [
          Expanded(
            child: Text(
              countLabel,
              style: TextStyle(color: Colors.grey[700]),
            ),
          ),
          if (_isUpdatingGallery)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (canManageGallery)
            OutlinedButton.icon(
              onPressed: _pickAndUploadGalleryImage,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Добавить фото'),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (galleryEntries.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Text(
            canManageGallery
                ? 'Добавьте первое фото, чтобы у родственника появилась медиакарточка.'
                : 'У этого родственника пока нет загруженных фотографий.',
            style: TextStyle(color: Colors.grey[700], height: 1.35),
          ),
        )
      else
        SizedBox(
          height: 146,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: galleryEntries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final media = galleryEntries[index];
              final mediaUrl = media['url']?.toString() ?? '';
              final normalizedMediaUrl = normalizePhotoUrl(mediaUrl);
              final isPrimary = media['isPrimary'] == true;

              return InkWell(
                onTap: normalizedMediaUrl == null
                    ? null
                    : () => _openGalleryViewer(
                          galleryEntries,
                          initialIndex: index,
                        ),
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  width: 116,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isPrimary
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .outlineVariant,
                                  width: isPrimary ? 2 : 1,
                                ),
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerLowest,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: normalizedMediaUrl == null
                                  ? Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: Colors.grey[600],
                                      ),
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: normalizedMediaUrl,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      errorWidget: (context, url, error) =>
                                          Center(
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ),
                            ),
                            Positioned(
                              left: 8,
                              top: 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.58),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    isPrimary ? 'Основное' : 'Фото',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (canManageGallery)
                              Positioned(
                                right: 4,
                                top: 4,
                                child: PopupMenuButton<_RelativeGalleryAction>(
                                  tooltip: 'Действия с фото',
                                  onSelected: (action) {
                                    switch (action) {
                                      case _RelativeGalleryAction.makePrimary:
                                        _setPrimaryGalleryMedia(media);
                                        break;
                                      case _RelativeGalleryAction.delete:
                                        _deleteGalleryMedia(media);
                                        break;
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    if (!isPrimary)
                                      const PopupMenuItem<
                                          _RelativeGalleryAction>(
                                        value:
                                            _RelativeGalleryAction.makePrimary,
                                        child: Text('Сделать основным'),
                                      ),
                                    const PopupMenuItem<_RelativeGalleryAction>(
                                      value: _RelativeGalleryAction.delete,
                                      child: Text('Удалить фото'),
                                    ),
                                  ],
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.55),
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(6),
                                    child: const Icon(
                                      Icons.more_vert,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isPrimary ? 'Используется в дереве' : 'Дополнительное',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[800],
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
    ]);
  }

  Widget _buildHistorySection() {
    final latestRecord =
        _historyRecords.isNotEmpty ? _historyRecords.first : null;
    final summaryLabel = _historyRecords.isEmpty
        ? 'Журнал пока пуст'
        : _historyRecords.length == 1
            ? '1 запись'
            : '${_historyRecords.length} записей';

    return _buildInfoSection('История изменений', [
      if (_isLoadingHistory)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator()),
        )
      else
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
                crossAxisAlignment: CrossAxisAlignment.start,
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
                      latestRecord == null
                          ? Icons.history_outlined
                          : _historyIcon(latestRecord),
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
                          latestRecord == null
                              ? 'Журнал ещё пуст.'
                              : _historyTitle(latestRecord),
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          latestRecord == null
                              ? 'Как только семья добавит правку, фото или новую связь, здесь появится история изменений.'
                              : _historySubtitle(latestRecord),
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 12,
                            height: 1.3,
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
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.summarize_outlined, size: 16),
                    label: Text(summaryLabel),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _openHistorySheet,
                    icon: const Icon(Icons.history_outlined, size: 18),
                    label: const Text('Открыть историю'),
                  ),
                ],
              ),
            ],
          ),
        ),
    ]);
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

  Widget _buildRelationToolsSection() {
    final personWarnings = _graphWarningsForCurrentPerson();
    return _buildInfoSection('Связи и родство', [
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
            Text(
              'Проверка работает поверх нового графа дерева: можно посмотреть цепочку родства и быстро исправить прямые связи.',
              style: TextStyle(
                color: Colors.grey[800],
                height: 1.35,
              ),
            ),
            if (personWarnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...personWarnings.map(
                (warning) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildGraphWarningCard(warning),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_person != null && _currentTreeId != null)
                  FilledButton.icon(
                    onPressed: _showQuickAddRelativeSheet,
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                    label: const Text('Добавить родственника'),
                  ),
                if (_person!.id != _currentUserPersonId)
                  FilledButton.tonalIcon(
                    onPressed: _showRelationPathSheet,
                    icon: const Icon(Icons.route_outlined, size: 18),
                    label: const Text('Путь родства'),
                  ),
                if (_hasAdditionalParentSets())
                  OutlinedButton.icon(
                    onPressed: _showOtherParentsSheet,
                    icon: const Icon(Icons.account_tree_outlined, size: 18),
                    label: const Text('Другие родители'),
                  ),
                if (_canEditOrDelete())
                  OutlinedButton.icon(
                    onPressed: _showRelationManagementSheet,
                    icon: const Icon(Icons.hub_outlined, size: 18),
                    label: const Text('Исправить связи'),
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

  _RelativeContactStatus _getContactStatus() {
    if (_person?.id == _currentUserPersonId) {
      return const _RelativeContactStatus(
        label: 'Это вы',
        description:
            'Эта карточка уже связана с вашим профилем и показывает семье актуальные данные о вас.',
        icon: Icons.person,
        color: Colors.blue,
      );
    }

    if (_canStartChatWithPerson()) {
      return _RelativeContactStatus(
        label: 'Есть аккаунт в Родне',
        description:
            'Сейчас проще всего быстро выйти на контакт: написать человеку или помочь с обновлением профиля.',
        icon: Icons.verified_user_outlined,
        color: Colors.green.shade700,
      );
    }

    if (_canInvitePerson()) {
      return _RelativeContactStatus(
        label: 'Пока без аккаунта',
        description:
            'Сначала отправьте приглашение, чтобы человек подключился к дереву, чату и своему профилю.',
        icon: Icons.person_add_alt_1_outlined,
        color: Colors.orange.shade700,
      );
    }

    return _RelativeContactStatus(
      label: 'Карточка в дереве',
      description:
          'Пока это только карточка в дереве. Здесь лучше всего собирать семейные сведения, фотографии и память о человеке.',
      icon: Icons.visibility_outlined,
      color: Colors.grey.shade700,
    );
  }

  String? _getDirectRelationLabel() {
    final exactViewerLabel = _viewerRelationLabel?.trim();
    if (exactViewerLabel != null && exactViewerLabel.isNotEmpty) {
      return exactViewerLabel;
    }
    if (_person == null ||
        _relationToCurrentUser == null ||
        _relationToCurrentUser == RelationType.other) {
      return null;
    }

    final relationRelativeToUser = FamilyRelation.getMirrorRelation(
      _relationToCurrentUser!,
    );
    return FamilyRelation.getRelationName(
      relationRelativeToUser,
      _person!.gender,
    );
  }

  List<_EditableRelationLink> _buildEditableRelationLinks() {
    if (_person == null) {
      return const <_EditableRelationLink>[];
    }

    final peopleById = {for (final person in _treePeople) person.id: person};
    final links = <_EditableRelationLink>[];
    for (final relation in _relations) {
      late final String relatedPersonId;
      late final RelationType relationFromRelatedPerson;
      if (relation.person1Id == _person!.id) {
        relatedPersonId = relation.person2Id;
        relationFromRelatedPerson = relation.relation2to1;
      } else if (relation.person2Id == _person!.id) {
        relatedPersonId = relation.person1Id;
        relationFromRelatedPerson = relation.relation1to2;
      } else {
        continue;
      }

      final relatedPerson = peopleById[relatedPersonId];
      if (relatedPerson == null) {
        continue;
      }
      links.add(
        _EditableRelationLink(
          relation: relation,
          relatedPerson: relatedPerson,
          relationFromRelatedPerson: relationFromRelatedPerson,
        ),
      );
    }
    return links;
  }

  List<TreeGraphFamilyUnit> _parentFamilyUnitsForCurrentPerson() {
    if (_person == null || _graphSnapshot == null) {
      return const <TreeGraphFamilyUnit>[];
    }
    return _graphSnapshot!.parentFamilyUnitsForChild(_person!.id);
  }

  bool _hasAdditionalParentSets() {
    final units = _parentFamilyUnitsForCurrentPerson();
    if (units.length > 1) {
      return true;
    }
    return units.any((unit) => unit.isPrimaryParentSet == false);
  }

  List<TreeGraphWarning> _graphWarningsForCurrentPerson() {
    if (_person == null || _graphSnapshot == null) {
      return const <TreeGraphWarning>[];
    }
    return _sortedGraphWarnings(_graphSnapshot!.warningsForPerson(_person!.id));
  }

  List<TreeGraphWarning> _graphWarningsForRelationManagement(
    List<_EditableRelationLink> links,
  ) {
    final snapshot = _graphSnapshot;
    if (snapshot == null) {
      return _graphWarningsForCurrentPerson();
    }

    final warningsById = <String, TreeGraphWarning>{
      for (final warning in _graphWarningsForCurrentPerson())
        warning.id: warning,
    };
    for (final link in links) {
      for (final warning in snapshot.warningsForRelation(link.relation.id)) {
        warningsById[warning.id] = warning;
      }
    }
    return _sortedGraphWarnings(warningsById.values);
  }

  List<TreeGraphWarning> _sortedGraphWarnings(
    Iterable<TreeGraphWarning> warnings,
  ) {
    final items = warnings.toList();
    items.sort((left, right) {
      final severityComparison = _graphWarningPriority(right.severity)
          .compareTo(_graphWarningPriority(left.severity));
      if (severityComparison != 0) {
        return severityComparison;
      }
      return left.message.compareTo(right.message);
    });
    return items;
  }

  int _graphWarningPriority(String? severity) {
    switch ((severity ?? '').trim().toLowerCase()) {
      case 'error':
        return 3;
      case 'warning':
        return 2;
      case 'info':
        return 1;
      default:
        return 0;
    }
  }

  String _graphWarningTitle(TreeGraphWarning warning) {
    switch (warning.code) {
      case 'multiple_primary_parent_sets':
        return 'Несколько основных родителей';
      case 'auto_repaired_parent_link':
        return 'Связь достроена автоматически';
      case 'conflicting_direct_links':
        return 'Конфликт прямых связей';
      default:
        return 'Проверка дерева';
    }
  }

  Color _graphWarningAccent(TreeGraphWarning warning) {
    final colorScheme = Theme.of(context).colorScheme;
    switch ((warning.severity).trim().toLowerCase()) {
      case 'error':
        return colorScheme.error;
      case 'info':
        return colorScheme.primary;
      default:
        return colorScheme.tertiary;
    }
  }

  IconData _graphWarningIcon(TreeGraphWarning warning) {
    switch ((warning.severity).trim().toLowerCase()) {
      case 'error':
        return Icons.error_outline_rounded;
      case 'info':
        return Icons.info_outline_rounded;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  Widget _buildGraphWarningCard(
    TreeGraphWarning warning, {
    bool compact = false,
  }) {
    final accent = _graphWarningAccent(warning);
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accent.withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _graphWarningIcon(warning),
            size: compact ? 18 : 20,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _graphWarningTitle(warning),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  warning.message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.35,
                        color: colorScheme.onSurface,
                      ),
                ),
                if (warning.hint != null &&
                    warning.hint!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    warning.hint!.trim(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.35,
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _normalizeOptionalText(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  FamilyRelation? _findDirectRelation(String fromPersonId, String toPersonId) {
    final snapshotRelation =
        _graphSnapshot?.findDirectRelation(fromPersonId, toPersonId);
    if (snapshotRelation != null) {
      return snapshotRelation;
    }
    for (final relation in _relations) {
      if ((relation.person1Id == fromPersonId &&
              relation.person2Id == toPersonId) ||
          (relation.person1Id == toPersonId &&
              relation.person2Id == fromPersonId)) {
        return relation;
      }
    }
    return null;
  }

  String? _describeRelationContext(FamilyRelation relation) {
    final parts = <String>[];
    final normalizedParentSetType =
        _normalizeOptionalText(relation.parentSetType);
    if (normalizedParentSetType != null) {
      var label = FamilyRelation.getParentSetTypeLabel(normalizedParentSetType);
      if (relation.isPrimaryParentSet == false) {
        label = '$label, дополнительный набор родителей';
      }
      parts.add(label);
    }

    final unionParts = <String>[];
    final normalizedUnionType = _normalizeOptionalText(relation.unionType);
    if (normalizedUnionType != null) {
      unionParts.add(FamilyRelation.getUnionTypeLabel(normalizedUnionType));
    }
    final normalizedUnionStatus = _normalizeOptionalText(relation.unionStatus);
    if (normalizedUnionStatus != null) {
      unionParts.add(FamilyRelation.getUnionStatusLabel(normalizedUnionStatus));
    }
    if (unionParts.isNotEmpty) {
      parts.add(unionParts.join(' • '));
    }

    return parts.isEmpty ? null : parts.join(' • ');
  }

  String _buildPathStepLabel({
    required String fromPersonId,
    required String toPersonId,
    required Map<String, FamilyPerson> peopleById,
  }) {
    final relation = _findDirectRelation(fromPersonId, toPersonId);
    if (relation == null) {
      return 'Связь';
    }
    final customLabel = relation.customLabelFromPerson(fromPersonId);
    if (customLabel != null) {
      return customLabel;
    }
    final relationType = relation.relationFromPerson(fromPersonId);
    if (relationType == null) {
      return 'Связь';
    }
    return FamilyRelation.getRelationName(
      relationType,
      peopleById[toPersonId]?.gender,
    );
  }

  Widget _buildPathInfoChip({
    required IconData icon,
    required String label,
  }) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(label),
    );
  }

  // _buildStatusChip used to render a contact-status chip in the
  // PersonDossierView header area. The new redesign hero card surfaces
  // the same information through `relBadge` + the status text rendered
  // directly under the hero — the chip helper is no longer needed.

  List<Widget> _buildDirectFamilyRows() {
    if (_person == null) {
      return const [];
    }

    final peopleById = {for (final person in _treePeople) person.id: person};
    final rows = <Widget>[];

    for (final relation in _relations) {
      late final String relatedPersonId;
      late final RelationType relationFromRelatedPerson;

      if (relation.person1Id == _person!.id) {
        relatedPersonId = relation.person2Id;
        relationFromRelatedPerson = relation.relation2to1;
      } else if (relation.person2Id == _person!.id) {
        relatedPersonId = relation.person1Id;
        relationFromRelatedPerson = relation.relation1to2;
      } else {
        continue;
      }

      final relatedPerson = peopleById[relatedPersonId];
      if (relatedPerson == null) {
        continue;
      }

      rows.add(
        InkWell(
          onTap: () => context.push('/relative/details/${relatedPerson.id}'),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    relatedPerson.displayName,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  relation.customLabelToPerson(_person!.id) ??
                      FamilyRelation.getRelationName(
                        relationFromRelatedPerson,
                        relatedPerson.gender,
                      ),
                  style: TextStyle(color: Colors.grey[700]),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      );
    }

    return rows;
  }
}

class _RelativeNameParts {
  const _RelativeNameParts({
    required this.firstName,
    required this.lastName,
    required this.patronymic,
  });

  final String firstName;
  final String lastName;
  final String patronymic;
}

/// Bottom-of-card destructive button for «Удалить из дерева». Matches
/// the design's red-tinted ghost treatment (Bordered, transparent
/// fill, soft red ink) — destructive intent without screaming red.
class _DeleteRelativeButton extends StatelessWidget {
  const _DeleteRelativeButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const dangerInk = Color(0xFFC0392B);
    final dangerLine = dangerInk.withValues(alpha: 0.32);
    final dangerSoft = dangerInk.withValues(alpha: 0.06);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? dangerSoft
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: dangerLine, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: dangerInk),
              const SizedBox(width: 8),
              Text(
                'Удалить из дерева',
                style: AppTheme.sans(
                  color: dangerInk,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

