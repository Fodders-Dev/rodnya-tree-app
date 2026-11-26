part of '../custom_api_family_tree_service.dart';

abstract class _CustomApiFamilyTreeBase
    implements
        FamilyTreeServiceInterface,
        TreeGraphCapableFamilyTreeService,
        IdentityDuplicateCapableFamilyTreeService,
        CrossTreePersonSearchCapableFamilyTreeService,
        IdentitySuggestionsCapableFamilyTreeService,
        IdentityConflictsCapableFamilyTreeService,
        BloodRelationCapableFamilyTreeService,
        BranchDigestCapableFamilyTreeService,
        BulkImportCapableFamilyTreeService,
        GraphPersonAccessCapableFamilyTreeService,
        ExtendedNetworkCapableFamilyTreeService,
        OnboardingCapableFamilyTreeService,
        KinshipCheckCapableFamilyTreeService,
        StoryRequestCapableFamilyTreeService,
        PersonTreeResolutionCapableFamilyTreeService,
        RelativesCacheCapableFamilyTreeService,
        SemyaCapableFamilyTreeService,
        SemyaManageCapableFamilyTreeService {
  _CustomApiFamilyTreeBase({
    required CustomApiAuthService authService,
    required BackendRuntimeConfig runtimeConfig,
    http.Client? httpClient,
    LocalStorageService? localStorageService,
    ProfileServiceInterface? profileService,
    TreeGraphCache? treeGraphCache,
    DateTime Function()? clock,
  })  : _authService = authService,
        _runtimeConfig = runtimeConfig,
        _httpClient = httpClient ?? http.Client(),
        _localStorageService = localStorageService,
        _profileService = profileService,
        _treeGraphCache = treeGraphCache,
        _clock = clock ?? DateTime.now;

  final CustomApiAuthService _authService;
  final BackendRuntimeConfig _runtimeConfig;
  final http.Client _httpClient;
  final LocalStorageService? _localStorageService;
  final ProfileServiceInterface? _profileService;
  final TreeGraphCache? _treeGraphCache;
  final DateTime Function() _clock;
  final Map<String, String> _personTreeIds = <String, String>{};
  final Map<String, TreeGraphSnapshot> _graphSnapshotCache =
      <String, TreeGraphSnapshot>{};

  // perf(client): getRelatives(treeId) short-TTL cache + single-flight.
  // Cold start on the home screen calls this for the same treeId from
  // two independent deferred tasks a beat apart — the «Сегодня для
  // семьи» prompt and, ~1s later via StartupScheduler's queue,
  // EventService.getUpcomingEvents() — neither aware of the other. A
  // plain in-flight dedup wouldn't help (they don't overlap in time),
  // so this is a real TTL cache: short enough that a genuinely new
  // visit re-fetches almost immediately, long enough to absorb that
  // gap and any screen-to-screen navigation right after. Every person/
  // relation mutation below invalidates it immediately via
  // _invalidateTreeCaches, and RelativesCacheCapableFamilyTreeService
  // lets the tree_mutated realtime/push handler do the same for
  // changes made by another device.
  final Map<String, List<FamilyPerson>> _relativesCache =
      <String, List<FamilyPerson>>{};
  final Map<String, DateTime> _relativesCacheStamps = <String, DateTime>{};
  final Map<String, Future<List<FamilyPerson>>> _relativesInFlight =
      <String, Future<List<FamilyPerson>>>{};
  final Map<String, int> _treeCacheGeneration = <String, int>{};
  static const Duration _relativesCacheTtl = Duration(seconds: 30);
  late final StreamController<List<TreeInvitation>>
      _pendingInvitationsController =
      StreamController<List<TreeInvitation>>.broadcast(
    onListen: _handlePendingInvitationsListen,
    onCancel: _handlePendingInvitationsCancel,
  );
  Timer? _pendingInvitationsPollingTimer;
  bool _pendingInvitationsPollingStarted = false;
  int _pendingInvitationsListenerCount = 0;

  // Forwarders for cross-mixin calls.
  Map<String, dynamic> _normalizePersonPayload(Map<String, dynamic> personData);
  void _handlePendingInvitationsListen();
  Future<void> _handlePendingInvitationsCancel();

  /// Single choke point for treeId-scoped cache invalidation. Clears
  /// both the graph-snapshot cache (pre-existing) and the
  /// getRelatives() short-TTL cache above, and bumps generation so any
  /// in-flight fetch cannot write stale data back into cache.
  void _invalidateTreeCaches(String treeId) {
    _treeCacheGeneration[treeId] = (_treeCacheGeneration[treeId] ?? 0) + 1;
    _graphSnapshotCache.remove(treeId);
    _relativesCache.remove(treeId);
    _relativesCacheStamps.remove(treeId);
    _relativesInFlight.remove(treeId);
  }

  void _invalidateAllTreeCaches() {
    final treeIds = <String>{
      ..._graphSnapshotCache.keys,
      ..._relativesCache.keys,
      ..._relativesInFlight.keys,
      ..._treeCacheGeneration.keys,
    };
    for (final id in treeIds) {
      _treeCacheGeneration[id] = (_treeCacheGeneration[id] ?? 0) + 1;
    }
    _graphSnapshotCache.clear();
    _relativesCache.clear();
    _relativesCacheStamps.clear();
    _relativesInFlight.clear();
  }

  // graph-snapshot + getRelatives caches for each touched tree so the
  // next read fetches fresh data. Backwards-compatible: silently
  // no-ops on older response shapes that don't carry the field.
  void _invalidateCachesForPropagatedTrees(Map<String, dynamic> response) {
    // New shape (media routes): top-level `propagatedTo: [...]`.
    final propagated = response['propagatedTo'];
    if (propagated is List) {
      for (final entry in propagated) {
        if (entry is Map) {
          final treeId = entry['treeId']?.toString();
          if (treeId != null && treeId.isNotEmpty) {
            _invalidateTreeCaches(treeId);
          }
        }
      }
    }
    // Pre-existing shape (PATCH /persons/:id): nested under
    // `identityPropagation.affected`. Same semantics, same
    // invalidation; we accept both for forward/back-compat.
    final propagation = response['identityPropagation'];
    if (propagation is Map<String, dynamic>) {
      final affected = propagation['affected'];
      if (affected is List) {
        for (final entry in affected) {
          if (entry is Map) {
            final treeId = entry['treeId']?.toString();
            if (treeId != null && treeId.isNotEmpty) {
              _invalidateTreeCaches(treeId);
            }
          }
        }
      }
    }
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    StartupTrace.logRequest(method, path);
    final uri = _buildUri(path);
    final normalizedBody = body == null ? null : _normalizePersonPayload(body);
    late http.Response response;

    switch (method) {
      case 'GET':
        response = await _httpClient.get(uri, headers: _headers());
        break;
      case 'POST':
        response = await _httpClient.post(
          uri,
          headers: _headers(),
          body: jsonEncode(normalizedBody ?? const <String, dynamic>{}),
        );
        break;
      case 'PATCH':
        response = await _httpClient.patch(
          uri,
          headers: _headers(),
          body: jsonEncode(normalizedBody ?? const <String, dynamic>{}),
        );
        break;
      case 'DELETE':
        response = await _httpClient.delete(
          uri,
          headers: _headers(),
          body: normalizedBody == null ? null : jsonEncode(normalizedBody),
        );
        break;
      default:
        throw CustomApiException('Неподдерживаемый HTTP-метод: $method');
    }

    if (response.body.isEmpty) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const <String, dynamic>{};
      }
      throw CustomApiException(
        'Пустой ответ от backend',
        statusCode: response.statusCode,
      );
    }

    final payload = tryDecodeJsonMap(response.body);
    if (payload == null) {
      throw CustomApiException(
        'Сервер вернул некорректный ответ (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return payload;
    }

    throw CustomApiException(
      payload['message']?.toString() ??
          payload['error']?.toString() ??
          'Ошибка backend (${response.statusCode})',
      statusCode: response.statusCode,
    );
  }

  Future<void> _requestDelete({required String path}) async {
    final response = await _httpClient.delete(
      _buildUri(path),
      headers: _headers(),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    if (response.body.isNotEmpty) {
      final decoded = tryDecodeJsonMap(response.body);
      if (decoded != null) {
        throw CustomApiException(
          decoded['message']?.toString() ??
              'Ошибка backend (${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
    }

    throw CustomApiException(
      'Ошибка backend (${response.statusCode})',
      statusCode: response.statusCode,
    );
  }

  Uri _buildUri(String path) {
    final normalizedBase = _runtimeConfig.apiBaseUrl.replaceAll(
      RegExp(r'/$'),
      '',
    );
    return Uri.parse('$normalizedBase$path');
  }

  String _buildPathWithQuery(
    String path,
    Map<String, String> queryParameters,
  ) {
    final uri = Uri.parse(path);
    return uri.replace(queryParameters: queryParameters).toString();
  }

  Map<String, String> _headers() {
    final token = _authService.accessToken;
    if (token == null || token.isEmpty) {
      throw const CustomApiException('Нет активной customApi session');
    }

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<void> _cacheTree(FamilyTree tree) async {
    final localStorageService = _localStorageService;
    if (localStorageService != null) {
      await localStorageService.saveTree(tree);
    }
  }

  Future<void> _cacheTrees(List<FamilyTree> trees) async {
    final localStorageService = _localStorageService;
    if (localStorageService != null) {
      await localStorageService.saveTrees(trees);
    }
  }

  // Hotfix-2: кэш — best-effort. Сетевые данные уже на руках; отказ
  // локальной записи (как HiveError инцидента) не имеет права валить
  // загрузку экрана. Все 9 call-site'ов — хвостовые `await _cachePerson*`
  // перед return, ни один не зависит от успеха кэша.
  Future<void> _cachePerson(FamilyPerson person) async {
    final localStorageService = _localStorageService;
    if (localStorageService == null) {
      return;
    }
    try {
      await localStorageService.savePerson(person);
    } catch (error) {
      debugPrint(
        'Кэш-запись person ${person.id} не удалась (продолжаем без кэша): $error',
      );
    }
  }

  Future<void> _cachePersons(List<FamilyPerson> persons) async {
    final localStorageService = _localStorageService;
    if (localStorageService == null) {
      return;
    }
    try {
      await localStorageService.savePersons(persons);
    } catch (error) {
      debugPrint(
        'Кэш-запись ${persons.length} persons не удалась (продолжаем без кэша): $error',
      );
    }
  }

  Future<void> _cacheRelation(FamilyRelation relation) async {
    final localStorageService = _localStorageService;
    if (localStorageService != null) {
      await localStorageService.saveRelation(relation);
    }
  }

  Future<void> _cacheRelations(List<FamilyRelation> relations) async {
    final localStorageService = _localStorageService;
    if (localStorageService != null) {
      await localStorageService.saveRelations(relations);
    }
  }

  // P0 (мамин баг): резолв person→tree опубликован через
  // PersonTreeResolutionCapableFamilyTreeService, чтобы карточка
  // родственника могла открыться из любого контекста (уведомление,
  // событие, чат), а не только из выбранного дерева.
  @override
  String? cachedTreeIdForPerson(String personId) => _personTreeIds[personId];

  @override
  Future<String?> resolveTreeIdForPerson(String personId) async {
    if (_personTreeIds.containsKey(personId)) {
      return _personTreeIds[personId];
    }

    final localStorageService = _localStorageService;
    final cachedPerson = localStorageService == null
        ? null
        : await localStorageService.getPerson(personId);
    if (cachedPerson != null) {
      _personTreeIds[personId] = cachedPerson.treeId;
      return cachedPerson.treeId;
    }

    final trees = await getUserTrees();
    for (final tree in trees) {
      final persons = await getRelatives(tree.id);
      final matches = persons.where((person) => person.id == personId);
      if (matches.isNotEmpty) {
        _personTreeIds[personId] = tree.id;
        return tree.id;
      }
    }

    return null;
  }

  Future<String?> _resolvePersonIdForTree(
      String treeId, String rawPersonId) async {
    if (rawPersonId.isEmpty) {
      return null;
    }

    final localStorageService = _localStorageService;
    final cachedPerson = localStorageService == null
        ? null
        : await localStorageService.getPerson(rawPersonId);
    if (cachedPerson != null && cachedPerson.treeId == treeId) {
      _personTreeIds[cachedPerson.id] = treeId;
      return cachedPerson.id;
    }

    final persons = await getRelatives(treeId);
    for (final person in persons) {
      if (person.id == rawPersonId) {
        return person.id;
      }
      if (person.userId == rawPersonId) {
        return person.id;
      }
    }

    return null;
  }

  Future<UserProfile?> _loadCurrentUserProfile() async {
    final profileService = _profileService;
    if (profileService == null) {
      return null;
    }

    try {
      return await profileService.getCurrentUserProfile();
    } catch (_) {
      return null;
    }
  }
}

abstract class _CustomApiFamilyTreeHost extends _CustomApiFamilyTreeBase
    with _CustomApiFamilyTreeParsers {
  _CustomApiFamilyTreeHost({
    required super.authService,
    required super.runtimeConfig,
    super.httpClient,
    super.localStorageService,
    super.profileService,
    super.treeGraphCache,
    super.clock,
  });
}
