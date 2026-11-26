part of '../relatives_screen.dart';

extension _RelativesData on _RelativesScreenState {
  bool get _isViewerOnly => _callerSemyaRole == SemyaRole.viewer;

  void _handleTreeChange() {
    if (!mounted) return;
    final newTreeId = _treeProviderInstance?.selectedTreeId;
    if (_currentTreeId != newTreeId) {
      _currentTreeId = newTreeId;
      _cancelSubscriptions();
      if (_currentTreeId != null) {
        _loadDataForSelectedTree(_currentTreeId!);
      } else {
        _updateRelativesState(() {
          _isLoading = false;
          _allRelatives = [];
          _relations = [];
          _currentUserPersonId = null;
          _callerSemyaRole = null;
          _chatPreviews = [];
          _pendingRequestsCount = 0;
          _errorMessage = '';
          _viewerDescriptorsByPersonId =
              const <String, TreeGraphViewerDescriptor>{};
        });
      }
    }
  }

  Future<void> _loadDataForSelectedTree(String treeId) async {
    if (!mounted || _currentUserId == null) return;
    debugPrint('RelativesScreen: Загрузка данных для дерева $treeId');
    _updateRelativesState(() {
      _isLoading = true;
      _errorMessage = '';
      _allRelatives = [];
      _relations = [];
      _currentUserPersonId = null;
      _callerSemyaRole = null;
      _chatPreviews = [];
      _pendingRequestsCount = 0;
      _isRelationsReady = false;
      _isChatsReady = false;
      _isPendingRequestsLoading = true;
      _conflictCounts = const <String, int>{};
      _treeConflictsCache = const <IdentityFieldConflict>[];
      _viewerDescriptorsByPersonId =
          const <String, TreeGraphViewerDescriptor>{};
    });

    unawaited(_refreshSemyaRole(treeId));
    unawaited(_checkPendingRequests(treeId));
    unawaited(_refreshConflictCounts(treeId));
    unawaited(_refreshViewerDescriptors(treeId));
    try {
      await _setupDataListeners(treeId, _currentUserId!);
    } catch (e) {
      debugPrint('Ошибка при инициализации данных для дерева $treeId: $e');
      _appStatusService.reportError(
        e,
        fallbackMessage: 'Не удалось загрузить список родных.',
      );
      if (mounted) {
        _updateRelativesState(() {
          _isLoading = false;
          if (_allRelatives.isEmpty) {
            _errorMessage = _appStatusService.isOffline
                ? 'Нет соединения. Родные появятся, когда интернет вернётся.'
                : 'Ошибка загрузки данных дерева.';
          }
        });
      }
    }
  }

  Future<void> _refreshSemyaRole(String treeId) async {
    final service = _familyService;
    if (service is! SemyaCapableFamilyTreeService) return;
    final capable = service as SemyaCapableFamilyTreeService;
    try {
      final mySemyi = await capable.listMySemya();
      Semya? bound;
      for (final entry in mySemyi) {
        if (entry.treeId == treeId) {
          bound = entry;
          break;
        }
      }
      if (bound == null) return;
      final semya = await capable.findSemyaById(bound.id);
      if (!mounted || _currentTreeId != treeId) return;
      final role = semya?.callerRole;
      if (role != _callerSemyaRole) {
        _updateRelativesState(() {
          _callerSemyaRole = role;
        });
      }
    } catch (_) {}
  }

  /// Phase 3.4 chunk 5: best-effort fetch identity conflicts на
  /// текущем tree'е. Сlient fail-safe: при ошибке cache stays
  /// empty, badge'ов нет. Backend без capability — silently
  /// skip'аем (старый сервер).
  Future<void> _refreshConflictCounts(String treeId) async {
    final service = _familyService;
    if (service is! IdentityConflictsCapableFamilyTreeService) return;
    final capable = service as IdentityConflictsCapableFamilyTreeService;
    List<IdentityFieldConflict> conflicts;
    try {
      conflicts = await capable.getIdentityConflictsForTree(treeId: treeId);
    } catch (_) {
      return;
    }
    if (!mounted || _currentTreeId != treeId) return;
    final unresolved =
        conflicts.where((c) => !c.isResolved).toList(growable: false);
    final counts = <String, int>{};
    for (final conflict in unresolved) {
      counts[conflict.targetPersonId] =
          (counts[conflict.targetPersonId] ?? 0) + 1;
    }
    _updateRelativesState(() {
      _conflictCounts = counts;
      _treeConflictsCache = unresolved;
    });
  }

  Future<void> _refreshViewerDescriptors(String treeId) async {
    final service = _familyService;
    if (service is! TreeGraphCapableFamilyTreeService) return;
    final capable = service as TreeGraphCapableFamilyTreeService;
    try {
      final snapshot = await capable.getTreeGraphSnapshot(treeId);
      if (!mounted || _currentTreeId != treeId) return;
      _updateRelativesState(() {
        _viewerDescriptorsByPersonId = snapshot.viewerDescriptorByPersonId;
      });
    } catch (_) {
      // Best-effort enrichment for multi-hop kinship labels.
    }
  }

  Future<void> _checkPendingRequests(String treeId) async {
    try {
      final requests = await _familyService.getRelationRequests(treeId: treeId);
      if (mounted) {
        _updateRelativesState(() {
          _pendingRequestsCount = requests.length;
        });
      }
    } catch (e) {
      debugPrint('Ошибка проверки запросов: $e');
      _appStatusService.reportError(
        e,
        fallbackMessage: 'Не удалось обновить запросы по дереву.',
      );
    } finally {
      if (mounted) {
        _updateRelativesState(() {
          _isPendingRequestsLoading = false;
        });
      }
    }
  }

  Future<void> _setupDataListeners(String treeId, String currentUserId) async {
    _cancelSubscriptions();

    final completerRelatives = Completer<void>();

    _relativesSubscription = _familyService.getRelativesStream(treeId).listen(
      (relatives) {
        String? currentUserPersonId;
        for (final person in relatives) {
          if (person.userId == _currentUserId) {
            currentUserPersonId = person.id;
            break;
          }
        }

        if (mounted) {
          _updateRelativesState(() {
            _allRelatives = relatives;
            _currentUserPersonId = currentUserPersonId;
            _errorMessage = '';
            _isLoading = false;
          });
          if (!completerRelatives.isCompleted) completerRelatives.complete();
        }
      },
      onError: (error, stackTrace) {
        if (mounted) {
          _handleStreamError(
            error,
            stackTrace,
            'RelativesStreamError',
            completerRelatives,
          );
        }
      },
      cancelOnError: false,
    );

    _relationsSubscription = _familyService.getRelationsStream(treeId).listen(
      (relations) {
        if (mounted) {
          _updateRelativesState(() {
            _relations = relations;
            _isRelationsReady = true;
          });
        }
      },
      onError: (error, stackTrace) {
        if (mounted) {
          debugPrint('Ошибка в Stream связей: $error');
          _handleStreamError(
            error,
            stackTrace,
            'RelationsStreamError',
            null,
          );
        }
      },
      cancelOnError: false,
    );

    _chatsSubscription = _chatService.getUserChatsStream(currentUserId).listen(
      (chatPreviews) {
        if (mounted) {
          _updateRelativesState(() {
            _chatPreviews = chatPreviews;
            _isChatsReady = true;
          });
        }
      },
      onError: (error, stackTrace) {
        if (mounted) {
          debugPrint('Ошибка в Stream чатов: $error');
          _handleStreamError(
            error,
            stackTrace,
            'ChatsStreamError',
            null,
          );
        }
      },
      cancelOnError: false,
    );

    try {
      await completerRelatives.future.timeout(const Duration(seconds: 10));
    } catch (e, stackTrace) {
      debugPrint('Ошибка или таймаут при ожидании данных: $e');
      debugPrint('Error: $e\n$stackTrace');
      if (mounted && _isLoading) {
        _updateRelativesState(() {
          _isLoading = false;
          _errorMessage = _appStatusService.isOffline
              ? 'Нет соединения. Проверьте интернет и попробуйте ещё раз.'
              : 'Не удалось загрузить список родных. Попробуйте ещё раз.';
        });
      }
    }
  }

  void _cancelSubscriptions() {
    _relativesSubscription?.cancel();
    _relationsSubscription?.cancel();
    _chatsSubscription?.cancel();
    _relativesSubscription = null;
    _relationsSubscription = null;
    _chatsSubscription = null;
    debugPrint('RelativesScreen: Подписки на данные отменены');
  }

  bool _isDeceasedWithoutAccount(FamilyPerson relative) {
    final userId = relative.userId;
    final hasAccount = userId != null && userId.isNotEmpty;
    if (hasAccount) return false;
    return !relative.isAlive || relative.deathDate != null;
  }

  String _getRelationDescription(FamilyPerson relative) {
    final currentUserPersonId = _currentUserPersonId;
    if (_currentUserId == null || currentUserPersonId == null) {
      return 'Родственник';
    }

    if (relative.id == currentUserPersonId) {
      return 'Вы';
    }

    final directRelation = _relations.firstWhere(
      (r) =>
          (r.person1Id == currentUserPersonId && r.person2Id == relative.id) ||
          (r.person1Id == relative.id && r.person2Id == currentUserPersonId),
      orElse: () => FamilyRelation(
        id: '',
        person1Id: '',
        person2Id: '',
        relation1to2: RelationType.other,
        relation2to1: RelationType.other,
        treeId: _currentTreeId ?? '',
        isConfirmed: false,
        createdAt: DateTime(0),
      ),
    );

    if (directRelation.id.isNotEmpty) {
      final bool userIsPerson1 =
          directRelation.person1Id == currentUserPersonId;
      final RelationType relevantRelationType = userIsPerson1
          ? directRelation.relation2to1
          : directRelation.relation1to2;
      final relationLabel = FamilyRelation.getRelationName(
        relevantRelationType,
        relative.gender,
      );
      if (relationLabel.isNotEmpty &&
          relationLabel !=
              FamilyRelation.getGenericRelationTypeStringRu(
                RelationType.other,
              )) {
        return relationLabel;
      }
    }

    final descriptorLabel = _normalizeSnapshotRelationLabel(
      _viewerDescriptorsByPersonId[relative.id]?.primaryRelationLabel,
    );
    if (descriptorLabel != null) {
      return descriptorLabel;
    }

    final multiHopLabel = _resolveMultiHopRelationLabel(
      fromPersonId: currentUserPersonId,
      targetPerson: relative,
    );
    if (multiHopLabel != null) {
      return multiHopLabel;
    }

    final storedRelation = _normalizeSnapshotRelationLabel(relative.relation);
    if (storedRelation != null) {
      return storedRelation;
    }

    final treeProvider = _treeProviderInstance;
    if (treeProvider?.selectedTreeKind == TreeKind.friends) {
      return 'Связь';
    }
    return 'Родственник';
  }

  String? _normalizeSnapshotRelationLabel(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    if (lower == 'это вы' ||
        lower == 'родственник' ||
        lower == 'не указано' ||
        lower.contains('родитель ребёнка') ||
        lower.contains('родитель ребенка') ||
        lower.contains('ребёнок родителя') ||
        lower.contains('ребенок родителя')) {
      return null;
    }
    const friendly = <String, String>{
      'тетя': 'Тётя',
      'теща': 'Тёща',
    };
    final mapped = friendly[lower];
    if (mapped != null) return mapped;
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }

  String? _resolveMultiHopRelationLabel({
    required String fromPersonId,
    required FamilyPerson targetPerson,
  }) {
    final targetId = targetPerson.id;
    if (fromPersonId.isEmpty || targetId.isEmpty || fromPersonId == targetId) {
      return null;
    }
    final queue = Queue<_RelationPathStep>();
    final visited = <String>{fromPersonId};
    queue.add(_RelationPathStep(personId: fromPersonId, code: ''));

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (current.code.length >= 3) continue;

      for (final rel in _relations) {
        late final String nextId;
        late final RelationType edgeType;
        if (rel.person1Id == current.personId) {
          nextId = rel.person2Id;
          edgeType = rel.relation2to1;
        } else if (rel.person2Id == current.personId) {
          nextId = rel.person1Id;
          edgeType = rel.relation1to2;
        } else {
          continue;
        }
        final hopChar = _hopCharForRelation(edgeType);
        if (hopChar == null) continue;
        final nextCode = '${current.code}$hopChar';
        if (nextId == targetId) {
          final label =
              _labelForRelationPathCode(nextCode, targetPerson.gender);
          if (label != null) return label;
        }
        if (visited.add(nextId)) {
          queue.add(_RelationPathStep(personId: nextId, code: nextCode));
        }
      }
    }
    return null;
  }

  String? _hopCharForRelation(RelationType type) {
    switch (type) {
      case RelationType.parent:
        return 'P';
      case RelationType.child:
        return 'C';
      case RelationType.sibling:
        return 'B';
      case RelationType.spouse:
      case RelationType.partner:
        return 'S';
      default:
        return null;
    }
  }

  String? _labelForRelationPathCode(String code, Gender gender) {
    switch (code) {
      case 'PP':
        if (gender == Gender.female) return 'Бабушка';
        if (gender == Gender.male) return 'Дедушка';
        return 'Бабушка/Дедушка';
      case 'PPP':
        if (gender == Gender.female) return 'Прабабушка';
        if (gender == Gender.male) return 'Прадедушка';
        return 'Прабабушка/Прадедушка';
      case 'CC':
        if (gender == Gender.female) return 'Внучка';
        if (gender == Gender.male) return 'Внук';
        return 'Внук/Внучка';
      case 'CCC':
        if (gender == Gender.female) return 'Правнучка';
        if (gender == Gender.male) return 'Правнук';
        return 'Правнук/Правнучка';
      case 'PB':
        return gender == Gender.female ? 'Тётя' : 'Дядя';
      case 'BC':
        if (gender == Gender.female) return 'Племянница';
        if (gender == Gender.male) return 'Племянник';
        return 'Племянник/Племянница';
      case 'PBC':
        if (gender == Gender.female) return 'Двоюродная сестра';
        if (gender == Gender.male) return 'Двоюродный брат';
        return 'Двоюродный брат/сестра';
      case 'SP':
        if (gender == Gender.female) return 'Свекровь/Тёща';
        if (gender == Gender.male) return 'Свёкор/Тесть';
        return 'Родитель супруга';
      case 'CS':
        if (gender == Gender.female) return 'Невестка';
        if (gender == Gender.male) return 'Зять';
        return 'Супруг ребёнка';
      case 'BS':
      case 'SB':
        return 'Родственник по браку';
      default:
        return null;
    }
  }

  bool _canStartChat(FamilyPerson relative) {
    final userId = relative.userId;
    return userId != null &&
        userId.isNotEmpty &&
        userId != _authService.currentUserId;
  }

  bool _canInviteRelative(FamilyPerson relative) {
    final userId = relative.userId;
    return relative.isAlive &&
        relative.deathDate == null &&
        (userId == null || userId.isEmpty) &&
        relative.id != _currentUserPersonId &&
        _currentTreeId != null;
  }

  String _formatTimestamp(DateTime rawDateTime) {
    // Таймзоны: серверные метки — UTC-режим; display обязан локализовать
    // (см. date_parser контракт; смоук 2026-07-04 показывал 13:25 вместо
    // 16:25 в превью чата).
    final DateTime dateTime = toLocalForDisplay(rawDateTime);
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime yesterday = today.subtract(const Duration(days: 1));

    final DateTime messageDate = DateTime(
      dateTime.year,
      dateTime.month,
      dateTime.day,
    );

    if (messageDate == today) {
      return DateFormat.Hm('ru').format(dateTime);
    } else if (messageDate == yesterday) {
      return 'Вчера';
    } else if (now.difference(dateTime).inDays < 7) {
      return DateFormat.E('ru').format(dateTime);
    } else {
      return DateFormat('dd.MM.yyyy', 'ru').format(dateTime);
    }
  }

  void _handleStreamError(
    dynamic error,
    StackTrace stackTrace,
    String reason,
    Completer<void>? completer,
  ) {
    debugPrint('Ошибка при загрузке данных: $error\n$stackTrace');
    _appStatusService.reportError(
      error,
      fallbackMessage: 'Не удалось обновить данные на экране родных.',
    );
    if (mounted) {
      _updateRelativesState(() {
        if (reason == 'RelationsStreamError') {
          _isRelationsReady = true;
        }
        if (reason == 'ChatsStreamError') {
          _isChatsReady = true;
        }
        if (_allRelatives.isNotEmpty) {
          return;
        }
        _errorMessage = describeUserFacingError(
          authService: _authService,
          error: error,
          fallbackMessage: 'Ошибка при загрузке данных ($reason).',
        );
      });
    }
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  }
}
