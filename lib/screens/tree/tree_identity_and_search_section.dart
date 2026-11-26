part of '../tree_view_screen.dart';

extension _TreeIdentityAndSearchSection on _TreeViewScreenState {
  Future<void> _refreshIdentitySuggestionCounts(
    String treeId,
    List<FamilyPerson> relatives,
  ) async {
    final service = _familyService;
    if (service is! IdentitySuggestionsCapableFamilyTreeService) return;
    final capable = service as IdentitySuggestionsCapableFamilyTreeService;
    final newCounts = <String, int>{};
    // Sequential fetch is acceptable here — only a handful of
    // persons typically and the response is tiny. Parallelizing
    // could trigger rate-limits on the auth route.
    for (final person in relatives) {
      try {
        final suggestions = await capable.getIdentitySuggestionsForPerson(
          treeId: treeId,
          personId: person.id,
        );
        if (suggestions.isNotEmpty) {
          newCounts[person.id] = suggestions.length;
        }
      } catch (_) {
        // Suggestion fetch is best-effort — failure on one
        // person shouldn't kill the whole batch.
      }
      if (!mounted || _currentTreeId != treeId) return;
    }
    if (mounted && _currentTreeId == treeId) {
      _updateSectionState(() {
        _identitySuggestionCounts = newCounts;
      });
    }
  }

  Future<void> _handleShowIdentitySuggestionsForPerson(String personId) async {
    final treeId = _currentTreeId;
    if (treeId == null) return;
    final service = _familyService;
    if (service is! IdentitySuggestionsCapableFamilyTreeService) return;
    final capable = service as IdentitySuggestionsCapableFamilyTreeService;
    List<IdentitySuggestion> suggestions;
    try {
      suggestions = await capable.getIdentitySuggestionsForPerson(
        treeId: treeId,
        personId: personId,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(humanizeError(error,
                fallback: 'Не удалось загрузить подсказки.'))),
      );
      return;
    }
    if (!mounted || suggestions.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _IdentitySuggestionsSheet(
        suggestions: suggestions,
        onConfirm: (suggestion) async {
          Navigator.of(sheetContext).pop();
          await _confirmIdentitySuggestion(suggestion);
        },
        onDismiss: (suggestion) async {
          await _dismissIdentitySuggestion(suggestion);
          // Re-render the sheet without that suggestion. Easiest
          // way: pop and reopen; or hand the sheet a stateful
          // wrapper. For simplicity, just pop — the dot count
          // refresh below will re-show one if others remain.
          if (sheetContext.mounted) {
            Navigator.of(sheetContext).pop();
          }
          // Reload list with remaining suggestions.
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await _handleShowIdentitySuggestionsForPerson(personId);
        },
      ),
    );
  }

  Future<void> _confirmIdentitySuggestion(IdentitySuggestion suggestion) async {
    final service = _familyService;
    if (service is! IdentitySuggestionsCapableFamilyTreeService) return;
    final capable = service as IdentitySuggestionsCapableFamilyTreeService;
    try {
      await capable.linkIdentity(
        sourceTreeId: suggestion.sourceTreeId,
        sourcePersonId: suggestion.sourcePersonId,
        targetTreeId: suggestion.targetTreeId,
        targetPersonId: suggestion.targetPersonId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Карточки связаны. Теперь правки в одной автоматически отразятся в другой.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      // Refresh tree (propagation may have already touched fields)
      // and recompute the 💡 counts (this pair drops out).
      final treeId = _currentTreeId;
      if (treeId != null) {
        await _loadData(treeId);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(humanizeError(error,
                fallback: 'Не удалось связать карточки.'))),
      );
    }
  }

  // ── Phase 1.3 edit-time conflict surfacing handlers ─────────────
  // Tree-level fetch, group-by personId, render ⚠️ badge on each
  // affected card. Tap → resolve sheet, applies user choice,
  // refreshes counts.

  Future<void> _refreshIdentityConflictCounts(String treeId) async {
    final service = _familyService;
    if (service is! IdentityConflictsCapableFamilyTreeService) return;
    final capable = service as IdentityConflictsCapableFamilyTreeService;
    List<IdentityFieldConflict> conflicts;
    try {
      conflicts = await capable.getIdentityConflictsForTree(treeId: treeId);
    } catch (_) {
      // Best-effort — a failed fetch shouldn't kill the tree
      // render. The badge just stays absent until next refresh.
      return;
    }
    if (!mounted || _currentTreeId != treeId) return;
    final counts = <String, int>{};
    for (final conflict in conflicts) {
      counts[conflict.targetPersonId] =
          (counts[conflict.targetPersonId] ?? 0) + 1;
    }
    _updateSectionState(() {
      _identityConflictCounts = counts;
      _identityConflictsCache = conflicts;
    });
  }

  Future<void> _handleShowIdentityConflictsForPerson(String personId) async {
    final treeId = _currentTreeId;
    if (treeId == null) return;
    final service = _familyService;
    if (service is! IdentityConflictsCapableFamilyTreeService) return;
    final personConflicts = _identityConflictsCache
        .where((c) => c.targetPersonId == personId && !c.isResolved)
        .toList(growable: false);
    if (personConflicts.isEmpty) {
      // Cache stale (already resolved on another device, deleted,
      // etc.) — refresh and bail. The badge will disappear once
      // counts state catches up.
      await _refreshIdentityConflictCounts(treeId);
      return;
    }

    await showIdentityConflictsSheet(
      context: context,
      conflicts: personConflicts,
      onChoice: (sheetContext, conflict, choice) async {
        final capable = service as IdentityConflictsCapableFamilyTreeService;
        try {
          await capable.resolveIdentityConflict(
            treeId: treeId,
            conflictId: conflict.id,
            choice: choice,
          );
        } catch (error) {
          if (sheetContext.mounted) {
            ScaffoldMessenger.of(sheetContext).showSnackBar(
              SnackBar(
                  content: Text(humanizeError(error,
                      fallback: 'Не удалось применить выбор.'))),
            );
          }
          return;
        }
        if (sheetContext.mounted) {
          Navigator.of(sheetContext).pop();
        }
        // overwrite changes the underlying person — pull a fresh
        // tree snapshot so the canvas shows the new canonical
        // value. keep is data-neutral but the refresh below
        // clears the badge either way.
        if (choice == 'overwrite') {
          await _loadData(treeId);
        } else {
          await _refreshIdentityConflictCounts(treeId);
        }
      },
    );
  }

  Future<void> _dismissIdentitySuggestion(IdentitySuggestion suggestion) async {
    final service = _familyService;
    if (service is! IdentitySuggestionsCapableFamilyTreeService) return;
    final capable = service as IdentitySuggestionsCapableFamilyTreeService;
    try {
      await capable.dismissIdentitySuggestion(
        sourceTreeId: suggestion.sourceTreeId,
        sourcePersonId: suggestion.sourcePersonId,
        targetPersonId: suggestion.targetPersonId,
      );
      // Optimistically drop the count by one — a fresh fetch
      // confirms after.
      if (mounted) {
        _updateSectionState(() {
          final next = Map<String, int>.from(_identitySuggestionCounts);
          final current = next[suggestion.sourcePersonId] ?? 0;
          if (current <= 1) {
            next.remove(suggestion.sourcePersonId);
          } else {
            next[suggestion.sourcePersonId] = current - 1;
          }
          _identitySuggestionCounts = next;
        });
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(humanizeError(error,
                fallback: 'Не удалось скрыть подсказку.'))),
      );
    }
  }

  // Blank-card creator handler. Called when the user tapped the
  // canvas-level "+ Карточка" FAB, filled name + gender in the
  // compact dialog, and pressed Save. We create the person without
  // any relation; the user connects them to the rest of the tree
  // via the edge-first connector. Pairs with the connector to
  // fully replace the form-based add-relative flow.
  bool _shouldShowFiltersButton() {
    final controller = _extendedNetworkController;
    if (controller == null || !controller.isCapable) return false;
    // Кнопку «Фильтры» показываем только если юзер в extended mode'е
    // (mine mode controls не нужны).
    return controller.mode == ExtendedNetworkMode.extended;
  }

  // ── Phase 4 chunk 4a: foreign node tap handler ──────────────────

  bool _shouldShowSearchButton() {
    final controller = _extendedNetworkController;
    if (controller == null || !controller.isCapable) return false;
    // Search only meaningful в extended mode когда slice non-empty.
    return controller.mode == ExtendedNetworkMode.extended &&
        controller.slice != null &&
        controller.slice!.graphPersons.isNotEmpty;
  }

  Future<void> _openSearchSheet() async {
    final controller = _extendedNetworkController;
    if (controller == null) return;
    final slice = controller.slice;
    if (slice == null) return;
    await showExtendedNetworkSearchSheet(
      context,
      slice: slice,
      onPersonSelected: _handleSearchResult,
    );
  }

  void _handleSearchResult(String graphPersonId) {
    // graphPersonId = identityId per slice. Route depending on
    // foreign-ness:
    //   • foreign → fabricate FamilyPerson + open foreign sheet.
    //   • own → lookup actual FamilyPerson в _treePeople +
    //     select + recenter canvas via existing flow.
    final controller = _extendedNetworkController;
    final slice = controller?.slice;
    if (slice == null) return;
    if (slice.isForeignNode(graphPersonId)) {
      final preview = slice.graphPersons.firstWhere(
        (p) => p.id == graphPersonId,
        orElse: () => const ExtendedNetworkPerson(
          id: '',
          name: '?',
          gender: null,
          birthDate: null,
          deathDate: null,
          photoUrl: null,
          isAlive: true,
          hopDistance: 0,
        ),
      );
      // Fabricate FamilyPerson из preview — foreign sheet uses
      // только identityId/name/photoUrl/dates/isAlive (see chunk 4a).
      final fabricated = FamilyPerson(
        id: preview.id,
        treeId: '', // foreign — no specific tree from current viewer scope
        userId: null,
        identityId: preview.id,
        name: preview.name ?? '',
        gender: _genderFromString(preview.gender),
        isAlive: preview.isAlive,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      unawaited(_handleForeignNodeTap(fabricated));
      return;
    }
    // Own: find tree person by identityId (graphPersonId).
    FamilyPerson? ownPerson;
    for (final p in _treePeople) {
      if (p.identityId == graphPersonId) {
        ownPerson = p;
        break;
      }
    }
    if (ownPerson == null) return; // Defensive — slice mismatch.
    final resolved = ownPerson;
    _updateSectionState(() {
      _recenterOnPersonIdAfterReload = resolved.id;
    });
    _selectTreePerson(resolved);
  }

  Gender _genderFromString(String? raw) {
    switch (raw) {
      case 'male':
        return Gender.male;
      case 'female':
        return Gender.female;
      default:
        return Gender.unknown;
    }
  }

  Future<void> _openFilterSheet() async {
    final controller = _extendedNetworkController;
    if (controller == null) return;
    // На narrow — bottom sheet; на wide layout sidebar и так persistent,
    // но кнопка всё равно открывает sheet (часть пользователей предпочитает
    // bottom sheet'ы). Не реквесь UX consistency сверх меры.
    await showExtendedNetworkFilterSheet(
      context,
      controller: controller,
      // v1 — branch options пустые (placeholder для Phase 4.1+
      // cross-branch). Текущая модель — branch === tree, и tree уже
      // выбран; chip «Все» один без content'а.
      branchOptions: const <BranchFilterOption>[],
    );
  }
}
