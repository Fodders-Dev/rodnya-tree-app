part of '../relative_details_screen.dart';

extension _RelativeDetailsHero on _RelativeDetailsScreenState {
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
      // P0b: без жаргона «досье» — тёплый и короткий лоадер.
      return _buildRelativeStateCard(
        icon: Icons.family_restroom_outlined,
        title: 'Открываем карточку…',
        message: 'Один момент.',
        showProgress: true,
      );
    }
    final errorKind = _errorKind;
    if (errorKind != null) {
      // P0b: честные заглушки — различаем «нет связи» / «не нашли» /
      // «нет доступа», тексты тёплые и без техслов.
      switch (errorKind) {
        case _CardErrorKind.network:
          return _buildRelativeStateCard(
            icon: Icons.cloud_off_outlined,
            title: 'Не получилось загрузить',
            message: 'Проверьте интернет и попробуйте ещё раз.',
            actions: [
              FilledButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
              ),
              OutlinedButton.icon(
                onPressed: _navigateBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Назад'),
              ),
            ],
          );
        case _CardErrorKind.notFound:
          return _buildRelativeStateCard(
            icon: Icons.person_search_outlined,
            title: 'Карточка не нашлась',
            message: 'Мы поискали во всех ваших деревьях. '
                'Возможно, эту карточку удалили.',
            actions: [
              OutlinedButton.icon(
                onPressed: _navigateBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Назад'),
              ),
            ],
          );
        case _CardErrorKind.accessDenied:
          return _buildRelativeStateCard(
            icon: Icons.lock_outline,
            title: 'Карточка закрыта',
            message: 'Её владелец ограничил доступ. '
                'Загляните позже или напишите ему.',
            actions: [
              OutlinedButton.icon(
                onPressed: _navigateBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Назад'),
              ),
            ],
          );
      }
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
            onPressed: _navigateBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Назад'),
          ),
        ],
      );
    }

    final dossier = _resolveDossier();
    final bool canStartChat = _canStartChatWithPerson();
    final bool canInvite = _canInvitePerson();
    final contactStatus = _getContactStatus();
    final directRelationLabel = _getDirectRelationLabel();
    final galleryEntries = _person!.photoGallery;

    final person = _person!;
    final isDeceased = !person.isAlive || person.deathDate != null;
    final fullName =
        dossier.displayName.isNotEmpty ? dossier.displayName : person.name;
    final loc = _composeRelativeLocation(dossier);
    final years = _composeYears(person);

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
        const SizedBox(height: 5),
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
              _buildReadFirstHeader(
                person: person,
                dossier: dossier,
                fullName: fullName,
                isDeceased: isDeceased,
                directRelationLabel: directRelationLabel,
                location: loc,
                deceasedYears: years,
                bio: dossier.bio.trim().isNotEmpty
                    ? dossier.bio.trim()
                    : (person.bio?.trim().isNotEmpty == true
                        ? person.bio!.trim()
                        : null),
                canStartChat: canStartChat,
                canInvite: canInvite,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: headerStatus,
              ),
              // «Основная информация» — key structured facts, right under
              // the header (§3.2.1, revised from C1: these are the card's
              // skeleton, kept on view). Self-hides if nothing is filled.
              _buildBasicInfoSection(),
              // MVP-1 «Спросить историю»: initiator-only status line for
              // their own open questions about this person — sits right
              // above the section it refers to. Key ties its lifetime to
              // _storyRequestStatusTick so a freshly sent request shows
              // up immediately (see _askFamilyStory).
              if (_person != null && _currentTreeId != null)
                StoryRequestStatusLine(
                  key: ValueKey(
                      'story-status-${person.id}-$_storyRequestStatusTick'),
                  personId: person.id,
                ),
              // «Семейные истории» — read-first article (§3.1 order: шапка →
              // Основная информация → биография → … → Семья). Empty-CTA
              // suppressed: the header's primary CTA already offers it.
              if (_person != null)
                ProfileBiographySection(
                  key: ValueKey('bio-${person.id}-$_biographyRefreshVersion'),
                  personId: person.id,
                  fullName: fullName,
                  relation: directRelationLabel,
                  gender: person.gender.name,
                  canEdit: _canEditBiography(),
                  showEmptyCta: false,
                  authorNames: _authorNamesMap(),
                ),
              // Phase 3.4 chunk 5: conflict header-banner.
              // Showcase'ит «у этого человека N расхождений с
              // другими ветками» с CTA «Посмотреть и решить» →
              // открывает reusable IdentityConflictsSheet.
              if (_personConflicts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  child: IdentityConflictsHeaderBanner(
                    count: _personConflicts.length,
                    onTap: _showPersonConflictsSheet,
                  ),
                ),
              if (_duplicateSuggestions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
                  child: _buildDuplicateSuggestionBanner(),
                ),
              // §3.1 read-first: «Семья» sits right under the biography
              // (only alerts between). «Связь», заметка, галерея,
              // история-audit … follow below — nothing removed/hidden.
              if (_buildDirectFamilyRows().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  child: _buildFamilySection(),
                ),
              // P1a: мягкое приглашение дозаполнить анкету (только на
              // редактируемой карточке; исчезает при полной анкете).
              // Паддинг внутри builder'а — скрытая плашка стоит 0dp.
              _buildCompletenessNudge(dossier, galleryEntries),
              if (_kinshipSectionHasContent()) _buildKinshipSection(),
              // «О человеке» (structured facts) moved to the «Основная
              // информация» ⋯-screen (§3.2.1) — keeps the main card
              // read-first.
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
                  (person.id != _currentUserPersonId || _canEditOrDelete()))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  child: _buildRelationToolsSection(),
                ),
              // «Кто видит карточку» (§3.2.2 card visibility + 100-year
              // rule) moved to its own ⋯-screen (ProfileVisibilityScreen)
              // — no longer inline on the main card.
              // Phase 3.4 chunk 4 (PHASE-3.4-UI-PROPOSAL §2.4):
              // sensitive contacts section с явным «Видно тебе»
              // badge. Owner-only-всегда (даже edit grant не
              // открывает). Показываем только когда viewer === self
              // (т.е. это карточка собственного аккаунта juzer'а),
              // потому что phone/email лежат в его UserProfile.
              // Anonymous person'ы (userId == null) не имеют
              // contacts payload'а в текущей схеме — sensitive
              // attribute поверх PersonAttribute(field:'contacts')
              // возможен, но deferred (TODO когда появится UI для
              // anonymous person contact entry).
              if (_isViewerOwnPerson(person))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  child: SensitiveContactsSection(
                    isOwner: true,
                    phoneNumber: _userProfile?.phoneNumber,
                    email: _userProfile?.email,
                    addressLine: _composeAddressLine(_userProfile),
                    onEdit: () => context.push('/profile/edit'),
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

  // ── Viewer §3.1: read-first header ─────────────────────────────────────────

  // Replaces the cover-style ProfileHeroCard on this screen with the
  // read-first header: centred 120px avatar, name (memorial framing when
  // deceased), «relation · age|years», preserved bio/location, a primary
  // «Добавить историю/воспоминание» CTA (editor-gated → article editor),
  // plus Написать/Пригласить as secondary CTAs. Management actions live in
  // the AppBar ⋯ menu; structured-field edit stays as the AppBar ✏️.
  Widget _buildReadFirstHeader({
    required FamilyPerson person,
    required PersonDossier dossier,
    required String fullName,
    required bool isDeceased,
    required String? directRelationLabel,
    required String? location,
    required String? deceasedYears,
    required String? bio,
    required bool canStartChat,
    required bool canInvite,
  }) {
    final theme = Theme.of(context);
    final photoUrl = normalizePhotoUrl(dossier.photoUrl);
    final initials = _avatarInitials(fullName);
    final subtitle = _composeRelationLine(
      directRelationLabel,
      person,
      isDeceased,
      deceasedYears,
    );
    final canEditStory = _canEditBiography();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildHeaderAvatar(photoUrl, initials),
          const SizedBox(height: 10),
          Text(
            isDeceased ? '† Память: $fullName' : fullName,
            key: const Key('profile-name'),
            textAlign: TextAlign.center,
            style: AppTheme.serif(
              color: theme.colorScheme.onSurface,
              fontSize: 23,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              height: 1.2,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 5),
            Text(
              subtitle,
              key: const Key('profile-relation-line'),
              textAlign: TextAlign.center,
              style: AppTheme.sans(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ],
          if (location != null && location.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              location,
              textAlign: TextAlign.center,
              style: AppTheme.sans(
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ],
          if (bio != null && bio.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              bio.trim(),
              textAlign: TextAlign.center,
              style: AppTheme.serif(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 14.5,
                fontWeight: FontWeight.w400,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Действия — один ряд компактных плиток (как в профиле Telegram),
          // а не столбик кнопок во всю ширину: три-четыре кнопки съедали
          // 150–200dp первого экрана. Ключи и подписи сохранены.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _HeroActionTile(
                    key: const Key('profile-ask-story'),
                    icon: Icons.question_answer_outlined,
                    label: 'Спросить историю',
                    primary: true,
                    onTap: () => _askFamilyStory(
                      name: fullName,
                      relation: directRelationLabel,
                      gender: person.gender.name,
                    ),
                  ),
                ),
                if (canEditStory) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _HeroActionTile(
                      key: const Key('profile-add-story'),
                      icon: Icons.edit_outlined,
                      label: isDeceased
                          ? 'Добавить воспоминание'
                          : 'Добавить историю',
                      onTap: () => _openBiographyEditor(
                        name: fullName,
                        relation: directRelationLabel,
                        gender: person.gender.name,
                      ),
                    ),
                  ),
                ],
                if (canStartChat) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _HeroActionTile(
                      key: const Key('profile-write'),
                      icon: Icons.message_outlined,
                      label: 'Написать',
                      onTap: _openChatWithPerson,
                    ),
                  ),
                ],
                if (canInvite) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _HeroActionTile(
                      key: const Key('profile-invite'),
                      icon: Icons.person_add_alt_1_outlined,
                      label:
                          _isGeneratingLink ? 'Готовим…' : 'Пригласить в Родню',
                      onTap: _isGeneratingLink
                          ? null
                          : _generateAndShareInviteLink,
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

  Widget _buildHeaderAvatar(String? photoUrl, String initials) {
    final theme = Theme.of(context);
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        border: Border.all(color: theme.colorScheme.surface, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            spreadRadius: -6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: (photoUrl != null && photoUrl.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: photoUrl,
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                // M2: декод под 120dp-аватар.
                memCacheWidth: decodeCacheWidth(context, 120),
                placeholder: (_, __) => _avatarFallback(initials),
                errorWidget: (_, __, ___) => _avatarFallback(initials),
              )
            : _avatarFallback(initials),
      ),
    );
  }

  Widget _avatarFallback(String initials) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  String _avatarInitials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  String? _composeRelationLine(
    String? relation,
    FamilyPerson person,
    bool isDeceased,
    String? deceasedYears,
  ) {
    final parts = <String>[];
    final rel = relation?.trim();
    if (rel != null && rel.isNotEmpty) parts.add(rel);
    if (isDeceased) {
      if (deceasedYears != null && deceasedYears.trim().isNotEmpty) {
        parts.add(deceasedYears.trim());
      }
    } else {
      final age = _composeAge(person);
      if (age != null) parts.add(age);
    }
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  String? _composeAge(FamilyPerson person) {
    final birth = person.birthDate;
    if (birth == null) return null;
    final now = DateTime.now();
    // F5: «знаю только год» — день/месяц фейковые (01.01), точный возраст
    // не посчитать. Считаем по годам и честно показываем «~78 лет».
    if (person.birthDateIsYearOnly) {
      final age = now.year - birth.year;
      if (age < 0 || age > 130) return null;
      return '~$age ${_pluralYears(age)}';
    }
    var age = now.year - birth.year;
    if (now.month < birth.month ||
        (now.month == birth.month && now.day < birth.day)) {
      age--;
    }
    if (age < 0 || age > 130) return null;
    return '$age ${_pluralYears(age)}';
  }

  String _pluralYears(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'год';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'года';
    return 'лет';
  }

  // AppBar ⋯ overflow — the §3.2 card menu. Each item maps to an existing
  // action or a dedicated screen, and is shown only when it has a
  // destination. Deferred: 📜 История изменений (needs a backend edit-
  // history endpoint — flagged as a separate заход) and 👥 Соавторы
  // (sub-chunk 2d). 🔗 Поделиться (browse-token, §3.2.7) isn't wired in
  // this context yet (only invite-to-family exists — that's the header CTA).
  Future<void> _openActionsMenu() async {
    final person = _person;
    if (person == null) return;
    final tiles = <Widget>[];
    // «Основная информация» is now a prominent on-card section (revised
    // from C1) — no longer a ⋯ entry.
    if (_canSuggestProfileEdits()) {
      tiles.add(_actionTile(
        keyValue: 'action-suggest-edits',
        icon: Icons.edit_note_outlined,
        label: 'Предложить правку',
        onTap: _suggestProfileChanges,
      ));
    }
    // §3.2.2 card visibility (radio + 100-year rule) — its own screen,
    // replacing the old inline VisibilityToggleSection.
    if (person.identityId != null && person.identityId!.isNotEmpty) {
      tiles.add(_actionTile(
        keyValue: 'action-visibility',
        icon: Icons.visibility_outlined,
        label: 'Кто видит карточку',
        onTap: _openVisibilityScreen,
      ));
    }
    // Per-field visibility (name / photo / dates …) — kept as a separate
    // entry so nothing is lost.
    if (_identityService != null && _canEditOrDelete()) {
      tiles.add(_actionTile(
        keyValue: 'action-privacy-fields',
        icon: Icons.lock_outline_rounded,
        label: _isUpdatingPrivacy ? 'Сохраняем…' : 'Видимость по полям',
        onTap: _showPrivacySettings,
      ));
    }
    // §3.2.4 article change log (read-access → any viewer). The ARTICLE
    // history (/article/history), not the broader inline tree-history.
    tiles.add(_actionTile(
      keyValue: 'action-history',
      icon: Icons.history_rounded,
      label: 'История изменений',
      onTap: _openArticleHistory,
    ));
    tiles.add(_actionTile(
      keyValue: 'action-voice',
      icon: Icons.graphic_eq_rounded,
      label: 'Голосовые записи',
      onTap: _openVoiceRecordings,
    ));
    tiles.add(_actionTile(
      keyValue: 'action-photos',
      icon: Icons.photo_library_outlined,
      label: 'Все фото',
      onTap: _openAllPhotos,
    ));
    if (_currentTreeId != null) {
      tiles.add(_actionTile(
        keyValue: 'action-open-tree',
        icon: Icons.account_tree_outlined,
        label: 'Открыть в дереве',
        onTap: _openInTree,
      ));
    }
    if (_identityService != null &&
        _currentTreeId != null &&
        person.userId != _authService.currentUserId) {
      tiles.add(_actionTile(
        keyValue: 'action-claim',
        icon: Icons.verified_user_outlined,
        label: _isUpdatingIdentity ? 'Подтверждение…' : 'Это моя карточка',
        onTap: _requestIdentityClaim,
      ));
    }
    if (_canUnlinkUser()) {
      tiles.add(_actionTile(
        keyValue: 'action-unlink',
        icon: Icons.person_remove_outlined,
        label: 'Отвязать пользователя',
        onTap: _unlinkUser,
      ));
    }
    if (_canDirectEditProfile()) {
      tiles.add(_actionTile(
        keyValue: 'action-delete',
        icon: Icons.delete_outline,
        label: 'Удалить из дерева',
        destructive: true,
        onTap: _deleteRelative,
      ));
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: tiles,
          ),
        ),
      ),
    );
  }

  void _openInTree() {
    final treeId = _currentTreeId;
    if (treeId == null) return;
    context.go('/tree/view/$treeId');
  }

  void _openVisibilityScreen() {
    final person = _person;
    if (person == null ||
        person.identityId == null ||
        person.identityId!.isEmpty) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileVisibilityScreen(
          graphPersonId: person.identityId!,
          viewerUserId: _authService.currentUserId ?? '',
          familyTreeService: _familyService,
        ),
      ),
    );
  }

  Widget _actionTile({
    required String keyValue,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final color = destructive ? Colors.redAccent : null;
    return ListTile(
      key: Key(keyValue),
      leading: Icon(icon, color: color),
      title: Text(label, style: color == null ? null : TextStyle(color: color)),
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
    );
  }
}
