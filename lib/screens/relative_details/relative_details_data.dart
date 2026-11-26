part of '../relative_details_screen.dart';

extension _RelativeDetailsData on _RelativeDetailsScreenState {
  // Small wrapper so _sections.dart (an `extension on _RelativeDetails-
  // ScreenState`, not a State subclass itself) can trigger a rebuild
  // without calling the @protected State.setState directly — that trips
  // `invalid_use_of_protected_member` from an extension method.
  void _refreshStoryRequestStatus() {
    _updateRelativeDetailsState(() => _storyRequestStatusTick++);
  }

  void _bumpBiographyRefreshVersion() {
    _updateRelativeDetailsState(() => _biographyRefreshVersion++);
  }

  void _navigateBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/tree');
    }
  }

  /// P0: определяем дерево человека. Порядок: явный treeId из роута →
  /// кэш person→tree сервиса → выбранное дерево → полный обход деревьев
  /// пользователя. КАЖДЫЙ шаг (включая явный — чанк C: протухшая ссылка
  /// с мёртвым treeId не терминальна) проверяется GET'ом; «не в этом
  /// дереве» (404/410) и «нет доступа» (403/401) ведут к следующему шагу,
  /// 403 при этом запоминается для честной заглушки. Сетевые ошибки
  /// пробрасываются (их различает _loadData). Найденный по пути человек
  /// переиспользуется без повторного GET.
  Future<_PersonTreeResolution> _resolvePersonContext() async {
    final personId = widget.personId;
    final service = _familyService;
    // Деревья провайдера читаем синхронно, до await'ов (контекст через
    // async-gap не трогаем).
    var providerTrees = const <FamilyTree>[];
    try {
      providerTrees =
          Provider.of<TreeProvider>(context, listen: false).availableTrees;
    } catch (_) {
      providerTrees = const <FamilyTree>[];
    }

    var sawAccessDenied = false;

    bool isAccessDenied(Object error) =>
        error is CustomApiException &&
        (error.statusCode == 403 || error.statusCode == 401);

    bool isMissingOnTree(Object error) =>
        error is CustomApiException &&
        (error.statusCode == 404 || error.statusCode == 410);

    // true → шаг «промахнулся», идём дальше; иначе пробрасываем (сеть).
    bool fallthroughOrRethrow(Object error) {
      if (isAccessDenied(error)) {
        sawAccessDenied = true;
        return true;
      }
      if (isMissingOnTree(error)) {
        return true;
      }
      return false;
    }

    final tried = <String>{};

    Future<_PersonTreeResolution?> tryTree(String treeId) async {
      if (treeId.isEmpty || !tried.add(treeId)) return null;
      try {
        final person = await service.getPersonById(treeId, personId);
        return _PersonTreeResolution(treeId: treeId, person: person);
      } catch (error) {
        if (!fallthroughOrRethrow(error)) rethrow;
        return null;
      }
    }

    // 1. Явный контекст из точки входа — проверяем, НЕ доверяем слепо:
    // старая ссылка может нести удалённое дерево.
    final explicit = widget.treeId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      final hit = await tryTree(explicit);
      if (hit != null) return hit;
    }

    final resolution = service is PersonTreeResolutionCapableFamilyTreeService
        ? service as PersonTreeResolutionCapableFamilyTreeService
        : null;

    // 2. Кэш сервиса (может протухнуть — GET-проверка самоисцеляет).
    final cached = resolution?.cachedTreeIdForPerson(personId);
    if (cached != null && cached.isNotEmpty) {
      final hit = await tryTree(cached);
      if (hit != null) return hit;
    }

    // 3. Выбранное дерево.
    final selected = _selectedTreeIdAtOpen;
    if (selected != null && selected.isNotEmpty) {
      final hit = await tryTree(selected);
      if (hit != null) return hit;
    }

    // 4. Полный обход. Предпочитаем сервисный резолв (кэш + локальное
    // хранилище + деревья); без capability — обходим деревья провайдера
    // вручную.
    if (resolution != null) {
      final resolved = await resolution.resolveTreeIdForPerson(personId);
      if (resolved != null && resolved.isNotEmpty) {
        return _PersonTreeResolution(
          treeId: resolved,
          sawAccessDenied: sawAccessDenied,
        );
      }
      return _PersonTreeResolution(sawAccessDenied: sawAccessDenied);
    }

    var trees = providerTrees;
    if (trees.isEmpty) {
      try {
        trees = await service.getUserTrees();
      } catch (_) {
        trees = const <FamilyTree>[];
      }
    }
    for (final tree in trees) {
      final hit = await tryTree(tree.id);
      if (hit != null) return hit;
    }
    return _PersonTreeResolution(sawAccessDenied: sawAccessDenied);
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    _updateRelativeDetailsState(() {
      _isLoading = true;
      _errorKind = null;
      _person = null;
      _treePeople = [];
      _semyaMembers = [];
      _relations = [];
      _historyRecords = [];
      _userProfile = null;
      _dossier = null;
      _duplicateSuggestions = const <PersonDuplicateSuggestion>[];
      _relationToCurrentUser = null;
      _graphSnapshot = null;
      _viewerDescriptor = null;
      _viewerRelationLabel = null;
      _currentUserPersonId = null;
      _isLoadingHistory = true;
      _personConflicts = const <IdentityFieldConflict>[];
    });

    // ── Критическая часть: дерево + сам человек. Только её отказ даёт
    // полноэкранную заглушку; всё остальное деградирует секциями. ──
    final _PersonTreeResolution resolved;
    try {
      // P0 (мамин баг): сперва определяем дерево ЧЕЛОВЕКА, а не берём
      // слепо выбранное — карточка из другого дерева раньше падала в 404
      // и показывала заглушку.
      resolved = await _resolvePersonContext();
    } catch (e) {
      debugPrint('Не удалось определить дерево для ${widget.personId}: $e');
      _failLoad(_classifyCriticalError(e));
      return;
    }
    _currentTreeId = resolved.treeId;
    if (_currentTreeId == null) {
      // Чанк C: если по пути цепочки встречался 403/401 — карточка
      // существует, но закрыта; «не нашлась» было бы неправдой.
      _failLoad(
        resolved.sawAccessDenied
            ? _CardErrorKind.accessDenied
            : _CardErrorKind.notFound,
      );
      return;
    }

    try {
      _person = resolved.person ??
          await _familyService.getPersonById(_currentTreeId!, widget.personId);
    } catch (e) {
      debugPrint('Ошибка загрузки данных родственника ${widget.personId}: $e');
      _failLoad(_classifyCriticalError(e));
      return;
    }

    // ── Второстепенное: каждый блок в своём try — отказ гасит секцию
    // (подписи связей, биографию, историю…), но карточка живёт. ──

    // 0. Профиль ТЕКУЩЕГО пользователя (нужен для getReciprocalType).
    final currentUserId = _authService.currentUserId;
    if (currentUserId != null) {
      try {
        await _profileService.getUserProfile(currentUserId);
      } catch (profileError) {
        debugPrint(
          'Не удалось загрузить профиль текущего пользователя: $profileError',
        );
        // Не считаем критичной ошибкой для отображения деталей родственника
      }
    }

    // 1. Люди и связи дерева — без них карточка остаётся без подписей
    // родства, но открывается.
    try {
      final relatives = await _familyService.getRelatives(_currentTreeId!);
      _relations = await _familyService.getRelations(_currentTreeId!);
      _treePeople = relatives;
      final currentUserPerson =
          relatives.where((p) => p.userId == currentUserId);
      _currentUserPersonId =
          currentUserPerson.isNotEmpty ? currentUserPerson.first.id : null;
    } catch (relativesError) {
      debugPrint(
        'Не удалось загрузить родственников/связи дерева $_currentTreeId: $relativesError',
      );
      _treePeople = [];
      _relations = [];
      _currentUserPersonId = null;
    }

    // 1b. MVP-1.1 «Спросить историю»: члены семьи этого дерева, включая
    // тех, у кого нет своей персоны в дереве (see _semyaMembers doc).
    // Best-effort — сбой резолва семьи не должен ронять карточку, шаг
    // «Кого спросить» просто останется как раньше (только персоны дерева).
    if (_familyService is SemyaCapableFamilyTreeService) {
      try {
        final semyaService = _familyService as SemyaCapableFamilyTreeService;
        final semyi = await semyaService.listMySemya();
        Semya? semya;
        for (final s in semyi) {
          if (s.treeId == _currentTreeId) {
            semya = s;
            break;
          }
        }
        _semyaMembers = semya == null
            ? []
            : await semyaService.listMembershipsForSemya(semya.id);
      } catch (semyaError) {
        debugPrint(
          'Не удалось загрузить членов семьи дерева $_currentTreeId: $semyaError',
        );
        _semyaMembers = [];
      }
    }

    _dossierLoadFailed = false;
    try {
      _dossier = await _familyService.getPersonDossier(
        _currentTreeId!,
        widget.personId,
      );
      _dossierLoadFailed = false;
      _person = _dossier!.person;
      _userProfile = _dossier!.linkedProfile;
    } on NoSuchMethodError {
      _dossier = null;
      _dossierLoadFailed = false;
    } on UnimplementedError {
      _dossier = null;
      _dossierLoadFailed = false;
    } on UnsupportedError {
      _dossier = null;
      _dossierLoadFailed = false;
    } catch (_) {
      _dossier = null;
      _dossierLoadFailed = true;
    }

    // 2. Если есть userId, пытаемся загрузить UserProfile
    if (_userProfile == null &&
        _person!.userId != null &&
        _person!.userId!.isNotEmpty) {
      try {
        _userProfile = await _profileService.getUserProfile(_person!.userId!);
      } catch (profileError) {
        // Не критично: карточка живёт без привязанного профиля.
        debugPrint(
          'Не удалось загрузить профиль ${_person!.userId}: $profileError',
        );
        _userProfile = null;
      }
    }

    // 3. Определяем родственную связь с текущим пользователем
    if (_currentUserPersonId != null && _person != null) {
      try {
        _relationToCurrentUser = await _familyService.getRelationBetween(
          _currentTreeId!,
          _currentUserPersonId!,
          _person!.id,
        );
        debugPrint(
          'Связь ${widget.personId} с текущим пользователем ($_currentUserPersonId): $_relationToCurrentUser',
        );
      } catch (relationError) {
        debugPrint(
          'Не удалось определить связь с ${widget.personId}: $relationError',
        );
        _relationToCurrentUser = null;
      }
    }
    if (_graphTreeService != null && _person != null) {
      try {
        final snapshot =
            await _graphTreeService!.getTreeGraphSnapshot(_currentTreeId!);
        _graphSnapshot = snapshot;
        _viewerDescriptor = snapshot.findViewerDescriptor(_person!.id);
        _viewerRelationLabel = _viewerDescriptor?.primaryRelationLabel?.trim();
      } catch (snapshotError) {
        debugPrint(
          'Не удалось загрузить graph snapshot для $_currentTreeId: $snapshotError',
        );
        _graphSnapshot = null;
        _viewerDescriptor = null;
        _viewerRelationLabel = null;
      }
    }

    if (_identityDuplicateService != null && _person != null) {
      try {
        final suggestions = await _identityDuplicateService!
            .getDuplicateSuggestions(_currentTreeId!);
        _duplicateSuggestions = suggestions
            .where((suggestion) => suggestion.involves(_person!.id))
            .toList(growable: false);
      } catch (duplicateError) {
        debugPrint(
          'Не удалось загрузить возможные совпадения для ${widget.personId}: $duplicateError',
        );
        _duplicateSuggestions = const <PersonDuplicateSuggestion>[];
      }
    }

    // Phase 3.4 chunk 5: load identity conflicts for this person.
    // Best-effort — failure ничего не блокирует (badge/banner
    // просто не появятся). Filter by targetPersonId — это
    // конкретный person на текущей tree'е.
    if (_person != null &&
        _familyService is IdentityConflictsCapableFamilyTreeService) {
      try {
        final capable =
            _familyService as IdentityConflictsCapableFamilyTreeService;
        final allConflicts = await capable.getIdentityConflictsForTree(
          treeId: _currentTreeId!,
        );
        _personConflicts = allConflicts
            .where((c) => c.targetPersonId == _person!.id && !c.isResolved)
            .toList(growable: false);
      } catch (conflictsError) {
        debugPrint(
          'Не удалось загрузить расхождения для ${widget.personId}: $conflictsError',
        );
        _personConflicts = const <IdentityFieldConflict>[];
      }
    }

    try {
      if (_person != null) {
        _historyRecords = await _familyService.getTreeHistory(
          treeId: _currentTreeId!,
          personId: _person!.id,
        );
      }
    } catch (historyError) {
      debugPrint(
        'Не удалось загрузить историю изменений для ${widget.personId}: $historyError',
      );
      _historyRecords = [];
    }

    if (mounted) {
      _updateRelativeDetailsState(() {
        _isLoading = false;
        _isLoadingHistory = false;
      });
      _maybeHandleInitialAction();
    }
  }

  void _failLoad(_CardErrorKind kind) {
    if (!mounted) return;
    _updateRelativeDetailsState(() {
      _isLoading = false;
      _isLoadingHistory = false;
      _errorKind = kind;
    });
  }

  void _maybeHandleInitialAction() {
    if (!mounted || _initialActionHandled) {
      return;
    }
    final action = widget.initialAction?.trim().toLowerCase();
    if (action == null || action.isEmpty) {
      return;
    }

    VoidCallback? handler;
    switch (action) {
      case 'path':
        handler = _showRelationPathSheet;
        break;
      case 'parents':
        if (_hasAdditionalParentSets()) {
          handler = _showOtherParentsSheet;
        }
        break;
      case 'relations':
        if (_canEditOrDelete()) {
          handler = _showRelationManagementSheet;
        }
        break;
      case 'story':
      case 'askstory':
      case 'ask_story':
        final person = _person;
        if (person != null) {
          handler = () => _askFamilyStory(
                name: person.displayName,
                relation: _getDirectRelationLabel(),
                gender: person.gender.name,
              );
        }
        break;
    }

    if (handler == null) {
      return;
    }

    _initialActionHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      handler!();
    });
  }

  bool _canEditOrDelete() {
    if (_person == null) {
      return false;
    }
    if (_dossier != null) {
      return _dossier!.canEditFamilyFields;
    }
    // Fail closed on real dossier fetch/403/network errors; only fall back to
    // editable when the service doesn't implement getPersonDossier (legacy/test fakes).
    return !_dossierLoadFailed;
  }

  /// Phase 3.4 chunk 4 (PHASE-3.4-UI-PROPOSAL §2.4): true когда
  /// карта связана с user-аккаунтом, и viewer — этот же аккаунт.
  /// Используется для gating'а sensitive contacts section: phone/
  /// email лежат в собственном UserProfile, и показывать их можно
  /// только себе (даже creator'у чужой карточки нельзя — это его
  /// данные не его).
  bool _isViewerOwnPerson(FamilyPerson person) {
    final ownerId = person.userId;
    final viewerId = _authService.currentUserId;
    if (ownerId == null || ownerId.isEmpty) return false;
    if (viewerId == null || viewerId.isEmpty) return false;
    return ownerId == viewerId;
  }

  /// Phase 3.4 chunk 4: build «city, country» либо single component
  /// либо null. UserProfile не имеет точного «адреса» поля —
  /// city+country это самое близкое к локации. Если оба пусты —
  /// addressLine null, sensitive section покажет empty-state с
  /// invite to «Добавить» (ведёт в profile editor).
  String? _composeAddressLine(UserProfile? profile) {
    if (profile == null) return null;
    final parts = <String>[];
    final city = profile.city?.trim();
    final country = profile.country?.trim();
    if (city != null && city.isNotEmpty) parts.add(city);
    if (country != null && country.isNotEmpty) parts.add(country);
    if (parts.isEmpty) return null;
    return parts.join(', ');
  }

  bool _canDirectEditProfile() {
    return _person != null &&
        (_person!.userId == null ||
            _person!.userId!.isEmpty ||
            !_person!.isAlive) &&
        _canEditOrDelete();
  }

  bool _canEditBiography() {
    return _person != null &&
        (_isViewerOwnPerson(_person!) || _canDirectEditProfile());
  }

  bool _canSuggestProfileEdits() {
    return _person != null && (_dossier?.canSuggestOwnerFields ?? false);
  }

  bool _canStartChatWithPerson() {
    final userId = _person?.userId;
    return userId != null &&
        userId.isNotEmpty &&
        _person?.isAlive == true &&
        userId != _authService.currentUserId;
  }

  bool _canInvitePerson() {
    final userId = _person?.userId;
    return _person != null &&
        _person!.isAlive &&
        (userId == null || userId.isEmpty) &&
        _person!.id != _currentUserPersonId;
  }

  /// Кнопка «Отвязать пользователя» доступна когда:
  /// 1) к слоту привязан какой-то аккаунт (есть userId)
  /// 2) этот аккаунт — НЕ текущий юзер (себя нельзя)
  ///
  /// Дополнительный гейт по правам — на бэкенде: эндпоинт
  /// `DELETE /v1/trees/.../user-link` сам отдаёт 403 если caller
  /// не tree.creatorId. Раньше я гейтил здесь по `_canEditOrDelete()`
  /// который зависит от поля `canEditFamilyFields` в dossier — а
  /// dossier для чужой карточки в чужом дереве может вернуться
  /// с false. Из-за этого кнопка не показывалась владельцу дерева.
  /// Теперь показываем оптимистично, бэкенд отшибёт несанкционированных
  /// с понятным toast'ом.
  bool _canUnlinkUser() {
    final userId = _person?.userId;
    if (userId == null || userId.isEmpty) {
      return false;
    }
    if (userId == _authService.currentUserId) {
      return false;
    }
    return true;
  }

  String _describeRelativeActionError(
    Object error, {
    required String fallbackMessage,
  }) {
    return describeUserFacingError(
      authService: _authService,
      error: error,
      fallbackMessage: fallbackMessage,
    );
  }

  void _showRelativeSnackBar(
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
      ),
    );
  }

  // Друзья-полиш FR1: копия приглашения зависит от вида дерева карточки.
  // Берём тот же источник, что и резолвер контекста (_resolvePersonContext) —
  // availableTrees, — но матчим по фактическому дереву карточки
  // (_currentTreeId), а не по «выбранному», т.к. карточка может быть из
  // другого дерева. Дефолт — семья (false), если дерево вдруг не в списке.
  bool _isCurrentTreeFriends() {
    try {
      final trees =
          Provider.of<TreeProvider>(context, listen: false).availableTrees;
      for (final tree in trees) {
        if (tree.id == _currentTreeId) return tree.isFriendsTree;
      }
    } catch (_) {
      // Нет TreeProvider в scope — трактуем как семейное дерево.
    }
    return false;
  }

  Future<void> _refreshHistory() async {
    if (_currentTreeId == null || _person == null) {
      return;
    }

    if (mounted) {
      _updateRelativeDetailsState(() {
        _isLoadingHistory = true;
      });
    }

    try {
      final records = await _familyService.getTreeHistory(
        treeId: _currentTreeId!,
        personId: _person!.id,
      );

      if (!mounted) {
        return;
      }

      _updateRelativeDetailsState(() {
        _historyRecords = records;
        _isLoadingHistory = false;
      });
    } catch (e) {
      debugPrint('Ошибка обновления истории изменений: $e');
      if (mounted) {
        _updateRelativeDetailsState(() {
          _isLoadingHistory = false;
        });
      }
    }
  }

  String _historyTitle(TreeChangeRecord record) {
    switch (record.type) {
      case 'person_media.created':
        return 'Добавлено фото';
      case 'person_media.updated':
        return 'Обновлено фото';
      case 'person_media.deleted':
        return 'Удалено фото';
      case 'person.created':
        return 'Создан профиль';
      case 'person.updated':
        return 'Обновлён профиль';
      case 'person.deleted':
        return 'Профиль удалён';
      case 'relation.created':
        return 'Добавлена связь';
      case 'relation.deleted':
        return 'Удалена связь';
      default:
        return 'Изменение в дереве';
    }
  }

  String _historySubtitle(TreeChangeRecord record) {
    final rawActorName = record.actorName?.trim();
    final who = (record.actorId != null &&
            _authService.currentUserId != null &&
            _authService.currentUserId!.isNotEmpty &&
            record.actorId == _authService.currentUserId)
        ? 'Вы'
        : (rawActorName != null && rawActorName.isNotEmpty)
            ? rawActorName
            : (record.actorId == null || record.actorId!.isEmpty)
                ? 'Действие в дереве'
                : 'Участник дерева';
    final when = DateFormat('d MMM, HH:mm', 'ru')
        .format(toLocalForDisplay(record.createdAt));
    return '$who · $when';
  }

  // userId → display name, from the people on this tree — for «кто записал»
  // (Голосовые) and «Соавторы» (2d).
  Map<String, String> _authorNamesMap() {
    final map = <String, String>{};
    for (final person in _treePeople) {
      final uid = person.userId;
      if (uid != null && uid.isNotEmpty && person.name.trim().isNotEmpty) {
        map[uid] = person.name.trim();
      }
    }
    for (final member in _semyaMembers) {
      final uid = member.userId;
      final displayName = member.displayName?.trim();
      if (uid.isNotEmpty &&
          displayName != null &&
          displayName.isNotEmpty &&
          !map.containsKey(uid)) {
        map[uid] = displayName;
      }
    }
    return map;
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
}
