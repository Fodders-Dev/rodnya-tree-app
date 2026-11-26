part of '../create_post_screen.dart';

extension _CreatePostAudience on _CreatePostScreenState {
  String get _selectedAudienceLabel {
    final activePreset = _activePreset;
    if (activePreset != null) {
      return activePreset.label;
    }
    final selectedCircle = _selectedCircle;
    if (_scopeType == TreeContentScopeType.branches &&
        _selectedBranchPersonIds.isNotEmpty) {
      return _isFriendsTree
          ? '${_selectedBranchPersonIds.length} круг(а)'
          : '${_selectedBranchPersonIds.length} ветк(и)';
    }
    if (selectedCircle != null) {
      return selectedCircle.name;
    }
    return _isFriendsTree ? 'Весь круг' : 'Всё дерево';
  }

  String get _selectedAudienceDetail {
    final selectedCircle = _selectedCircle;
    final parts = <String>[];
    if (_scopeType == TreeContentScopeType.branches &&
        _selectedBranchPersonIds.isNotEmpty) {
      parts.add(
        _isFriendsTree
            ? 'выбранные люди и их круги'
            : 'выбранные люди и их ветки',
      );
    } else if (selectedCircle != null) {
      parts.add(_memberLabel(selectedCircle.memberCount));
      if ((selectedCircle.description ?? '').trim().isNotEmpty) {
        parts.add(selectedCircle.description!.trim());
      } else if (selectedCircle.isAllTree) {
        parts.add(_isFriendsTree ? 'весь круг' : 'вся семья');
      } else if (selectedCircle.isAuto) {
        parts.add('автоматический круг по ветке');
      }
    } else {
      parts.add(_isFriendsTree ? 'внутри текущего круга' : 'внутри дерева');
    }
    if (_isPublic) {
      parts.add('публично по ссылке');
    }
    return parts.join(' · ');
  }

  Future<void> _loadCurrentTreeMeta() async {
    final treeId = _currentTreeId;
    if (treeId == null) {
      return;
    }
    final treeMeta = await _localStorageService.getTree(treeId);
    if (!mounted) {
      return;
    }
    _updateCreatePostState(() {
      _currentTreeMeta = treeMeta;
    });
  }

  // Phase 3.4: load the user's OTHER branches (legacy: trees) so
  // the composer can offer "Опубликовать также в:" toggles for
  // multi-branch posts. Best-effort — when the call fails the
  // section just stays hidden and the user posts to the primary
  // branch only (legacy behavior).
  Future<void> _loadOtherUserTrees() async {
    final treeId = _currentTreeId;
    if (treeId == null) return;
    try {
      final trees = await _familyTreeService.getUserTrees();
      if (!mounted) return;
      _updateCreatePostState(() {
        _otherUserTrees =
            trees.where((tree) => tree.id != treeId).toList(growable: false);
      });
    } catch (_) {
      // Silent: multi-branch is opt-in. If we can't load the list,
      // hide the section rather than blocking the composer.
    }
  }

  Future<void> _loadBranchCandidates() async {
    if (_currentTreeId == null) {
      return;
    }

    _updateCreatePostState(() {
      _isLoadingPeople = true;
    });

    try {
      final people = await _familyTreeService.getRelatives(_currentTreeId!);
      final sortedPeople = List<FamilyPerson>.from(people)
        ..sort(
          (left, right) => left.displayName.toLowerCase().compareTo(
                right.displayName.toLowerCase(),
              ),
        );
      if (!mounted) {
        return;
      }
      _updateCreatePostState(() {
        _availablePeople = sortedPeople;
        _branchCandidatesUnavailable = false;
      });
    } catch (error) {
      _appStatusService.reportError(
        error,
        fallbackMessage: 'Не удалось загрузить список веток для публикации.',
      );
      if (!mounted) {
        return;
      }
      _updateCreatePostState(() {
        _branchCandidatesUnavailable = true;
      });
    } finally {
      if (mounted) {
        _updateCreatePostState(() {
          _isLoadingPeople = false;
        });
      }
    }
  }

  Future<void> _loadAudienceCircles() async {
    final treeId = _currentTreeId;
    final circleService = _circleService;
    if (treeId == null || circleService == null) {
      return;
    }

    _updateCreatePostState(() {
      _isLoadingCircles = true;
    });

    try {
      final circles = await circleService.getCircles(treeId);
      // Audience presets are best-effort — the older backend simply
      // doesn't have the endpoint and returns 404, which the service
      // turns into the empty response. Wrap in a separate try so a
      // presets failure doesn't blank out the regular circles list.
      AudiencePresetsResponse presets = AudiencePresetsResponse.empty;
      try {
        presets = await circleService.getAudiencePresets(treeId);
      } catch (_) {
        // ignore — picker just won't show smart tiles
      }
      if (!mounted) {
        return;
      }
      _updateCreatePostState(() {
        _audienceCircles = circles;
        _audiencePresets = presets;
        _selectedCircleId = _resolveSelectedCircleId(circles);
        _circlesUnavailable = false;
      });
    } catch (error) {
      _appStatusService.reportError(
        error,
        fallbackMessage: 'Не удалось загрузить круги для публикации.',
      );
      if (!mounted) {
        return;
      }
      _updateCreatePostState(() {
        _circlesUnavailable = true;
      });
    } finally {
      if (mounted) {
        _updateCreatePostState(() {
          _isLoadingCircles = false;
        });
      }
    }
  }

  String? _resolveSelectedCircleId(List<FamilyCircle> circles) {
    final selectedId = _selectedCircleId;
    if (selectedId != null &&
        circles.any((circle) => circle.id == selectedId)) {
      return selectedId;
    }
    for (final circle in circles) {
      if (circle.isAllTree) {
        return circle.id;
      }
    }
    return circles.isEmpty ? null : circles.first.id;
  }

  void _applyAudiencePreset(
    AudiencePreset preset,
    StateSetter? sheetSetState,
  ) {
    _updateAudienceState(() {
      if (_selectedPresetKey == preset.key) {
        // Tapping an already-selected preset clears it (back to "Всё
        // дерево" or whatever circle was selected before).
        _selectedPresetKey = null;
        _selectedBranchPersonIds.clear();
        _scopeType = TreeContentScopeType.wholeTree;
        return;
      }
      _selectedPresetKey = preset.key;
      _selectedCircleId = null;
      _scopeType = TreeContentScopeType.branches;
      _selectedBranchPersonIds
        ..clear()
        ..addAll(preset.personIds);
    }, sheetSetState);
  }

  Future<void> _showAudienceSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, sheetSetState) {
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.86,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
                  child: _buildAudiencePanelContent(
                    sheetSetState: sheetSetState,
                    inSheet: true,
                    onDone: () => Navigator.of(sheetContext).pop(),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _updateAudienceState(VoidCallback update, [StateSetter? sheetSetState]) {
    if (!mounted) {
      return;
    }
    _updateCreatePostState(update);
    sheetSetState?.call(() {});
  }

  Widget _buildAudiencePanel() {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: _buildAudiencePanelContent(inSheet: false),
    );
  }

  Widget _buildAudiencePanelContent({
    required bool inSheet,
    StateSetter? sheetSetState,
    VoidCallback? onDone,
  }) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Кто увидит пост?',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: tokens.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Выбор аудитории сохраняется вместе с постом. При необходимости круг можно поменять перед публикацией.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.inkSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        if (_audiencePresets.presets.isNotEmpty) ...[
          // Smart-tile row above the regular picker. Single tap takes
          // care of "Мoя семья" / "Близкие" — the 80% case the user
          // described as "тонна выбора" in the flat list.
          _buildPresetTilesRow(theme, tokens, sheetSetState),
          const SizedBox(height: 16),
        ],
        AudiencePicker(
          circles: _audienceCircles,
          selectedCircleId: _activePreset == null ? _selectedCircleId : null,
          onChanged: (circleId) {
            _updateAudienceState(() {
              // Picking a regular circle clears any active preset —
              // they're mutually exclusive selections.
              _selectedPresetKey = null;
              _selectedCircleId = circleId;
              _selectedBranchPersonIds.clear();
              if (_scopeType == TreeContentScopeType.branches &&
                  _selectedBranchPersonIds.isEmpty) {
                _scopeType = TreeContentScopeType.wholeTree;
              }
            }, sheetSetState);
          },
          isLoading: _isLoadingCircles,
          isUnavailable: _circlesUnavailable,
          isFriendsTree: _isFriendsTree,
          onRetry: _loadAudienceCircles,
        ),
        const SizedBox(height: 16),
        _buildBranchAudienceSection(sheetSetState: sheetSetState),
        const SizedBox(height: 16),
        _buildCrossBranchSection(theme, tokens, sheetSetState),
        _buildAudienceSummaryBadge(theme, tokens),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('По публичной ссылке'),
          subtitle: Text(
            _isPublic
                ? 'Пост можно будет открыть по ссылке.'
                : 'Пост останется внутри выбранной аудитории.',
          ),
          value: _isPublic,
          onChanged: (value) {
            _updateAudienceState(() {
              _isPublic = value;
            }, sheetSetState);
          },
        ),
        if (inSheet) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onDone,
              child: const Text('Готово'),
            ),
          ),
        ],
      ],
    );
  }

  // Phase 3.4 cross-branch composer section. Renders an empty
  // SizedBox when the user has 0 other trees; otherwise shows a
  // "Опубликовать также в:" row with one FilterChip per other
  // branch. Toggles add/remove the branch id from the set the
  // post will fan out to. The primary branch is always included
  // server-side, so the chips here are pure additions.
  Widget _buildCrossBranchSection(
    ThemeData theme,
    RodnyaDesignTokens tokens,
    StateSetter? sheetSetState,
  ) {
    if (_otherUserTrees.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Опубликовать также в:',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: tokens.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Один пост увидят сразу несколько ваших веток. Реакции и комментарии останутся общими.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.inkSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _otherUserTrees.map((tree) {
              final selected = _additionalBranchIds.contains(tree.id);
              return FilterChip(
                label: Text(tree.name),
                selected: selected,
                onSelected: (next) {
                  _updateAudienceState(() {
                    if (next) {
                      _additionalBranchIds.add(tree.id);
                    } else {
                      _additionalBranchIds.remove(tree.id);
                    }
                  }, sheetSetState);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// "Этот пост увидят: X человек • N ветке/веток" — live audience
  /// preview that reacts whenever the user toggles a cross-branch
  /// chip or switches the primary branch. Closes the loop on the
  /// audience model: until this badge existed, the author had to
  /// guess how many people the fan-out reached. The number is the
  /// union of branch.memberIds across selected branches (NOT the
  /// circle/branch-anchored audience narrowing — that's harder to
  /// compute correctly client-side and worth a follow-up if users
  /// ask). Author is included — the badge reads as "audience size",
  /// and pretending the author isn't in their own audience
  /// confuses the count when they open their own post seconds later.
  Widget _buildAudienceSummaryBadge(
    ThemeData theme,
    RodnyaDesignTokens tokens,
  ) {
    final summary = _audienceSummary;
    if (summary == null) return const SizedBox.shrink();
    final viewerLabel = _pluralizeViewers(summary.viewers);
    final branchLabel = _pluralizeBranches(summary.branches);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.accentSoft.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: tokens.accent.withValues(alpha: 0.32),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.visibility_outlined,
            size: 18,
            color: tokens.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.ink,
                  height: 1.3,
                ),
                children: [
                  const TextSpan(text: 'Этот пост увидят '),
                  TextSpan(
                    text: viewerLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: tokens.accent,
                    ),
                  ),
                  TextSpan(text: ' в $branchLabel.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _pluralizeViewers(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return '$count человек';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return '$count человека';
    }
    return '$count человек';
  }

  String _pluralizeBranches(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return '$count ветке';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return '$count ветках';
    }
    return '$count ветках';
  }

  Widget _buildBranchAudienceSection({StateSetter? sheetSetState}) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _isFriendsTree ? 'Отдельные круги' : 'Отдельные ветки',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: tokens.ink,
                ),
              ),
            ),
            if (_selectedBranchPersonIds.isNotEmpty)
              TextButton(
                onPressed: () {
                  _updateAudienceState(() {
                    _selectedBranchPersonIds.clear();
                    _scopeType = TreeContentScopeType.wholeTree;
                  }, sheetSetState);
                },
                child: const Text('Сбросить'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _isFriendsTree
              ? 'Можно сузить видимость до выбранных людей и их кругов.'
              : 'Можно сузить видимость до выбранных людей и их веток.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.inkSecondary,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 10),
        if (_isLoadingPeople)
          _buildScopeState(
            icon: Icons.sync,
            title: 'Подбираем ветки',
            message:
                'Проверяем, какие люди доступны для выборочной публикации.',
            showProgress: true,
          )
        else if (_branchCandidatesUnavailable)
          _buildScopeState(
            icon: _appStatusService.isOffline
                ? Icons.cloud_off_outlined
                : Icons.error_outline,
            title: _appStatusService.isOffline
                ? 'Нет соединения'
                : 'Ветки сейчас недоступны',
            message: _appStatusService.isOffline
                ? 'Список веток вернётся, когда интернет снова появится.'
                : 'Не удалось обновить список веток. Попробуйте ещё раз.',
            actions: [
              OutlinedButton.icon(
                onPressed: _loadBranchCandidates,
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
              ),
            ],
          )
        else if (_availablePeople.isEmpty)
          _buildScopeState(
            icon: Icons.alt_route,
            title: _isFriendsTree ? 'Кругов пока нет' : 'Веток пока нет',
            message: _isFriendsTree
                ? 'Сначала добавьте людей в круг.'
                : 'Сначала добавьте людей и связи в дерево.',
          )
        else
          // Compact summary instead of an N-chip Wrap. The flat
          // FilterChip list didn't scale past ~30 people and would
          // become a wall on a 200-person tree (user feedback).
          // Tapping the card opens a fullscreen multi-picker with
          // search + virtualized list — that scales linearly.
          _buildBranchPickerSummary(theme, tokens, sheetSetState),
      ],
    );
  }

  Widget _buildBranchPickerSummary(
    ThemeData theme,
    RodnyaDesignTokens tokens,
    StateSetter? sheetSetState,
  ) {
    final selectedCount = _selectedBranchPersonIds.length;
    final selectedPeople = _availablePeople
        .where((p) => _selectedBranchPersonIds.contains(p.id))
        .take(3)
        .toList();
    return InkWell(
      onTap: () => _openBranchMultiPicker(sheetSetState),
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: selectedCount > 0
              ? tokens.accentSoft
              : tokens.surfaceStrong.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          border: Border.all(
            color: selectedCount > 0 ? tokens.accent : tokens.surfaceLine,
            width: selectedCount > 0 ? 1.2 : 0.7,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: selectedCount > 0
                    ? tokens.accent.withValues(alpha: 0.18)
                    : tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
              child: Icon(
                Icons.alt_route_outlined,
                color: selectedCount > 0 ? tokens.accent : tokens.inkSecondary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedCount > 0
                        ? 'Выбрано ${_memberLabel(selectedCount)}'
                        : 'Выбрать людей',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: tokens.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    selectedCount == 0
                        ? 'Поиск по имени · доступно ${_memberLabel(_availablePeople.length)}'
                        : selectedPeople.map((p) => p.displayName).join(', ') +
                            (selectedCount > selectedPeople.length
                                ? ' и ещё ${selectedCount - selectedPeople.length}'
                                : ''),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.inkSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.chevron_right_rounded,
              color: tokens.inkSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openBranchMultiPicker(StateSetter? sheetSetState) async {
    final result = await PersonMultiPickerSheet.show(
      context,
      people: _availablePeople,
      initialSelection: Set<String>.from(_selectedBranchPersonIds),
      title: _isFriendsTree ? 'Отдельные круги' : 'Отдельные ветки',
    );
    if (result == null || !mounted) return;
    _updateAudienceState(() {
      // Picking a custom person set always clears the active preset
      // and circle so the three selection paths stay mutually
      // exclusive.
      _selectedPresetKey = null;
      _selectedCircleId = null;
      _selectedBranchPersonIds
        ..clear()
        ..addAll(result);
      if (_selectedBranchPersonIds.isEmpty) {
        _scopeType = TreeContentScopeType.wholeTree;
      } else {
        _scopeType = TreeContentScopeType.branches;
      }
    }, sheetSetState);
  }

  String _memberLabel(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    final suffix = mod10 == 1 && mod100 != 11
        ? 'человек'
        : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
            ? 'человека'
            : 'человек';
    return '$count $suffix';
  }

  /// Q6: a compact audience summary shown by default. Rather than laying
  /// out the whole circle/branch taxonomy as a chip strip up front (which
  /// read as noisy and pushed people to overthink reach), we show the
  /// current audience — defaulting to «Всё дерево» — with an «Изменить»
  /// action that opens the full picker sheet. The taxonomy still lives
  /// behind that one tap.
  Widget _buildAudienceSummaryRow() {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    final circle = _selectedCircle;
    final inBranches = _scopeType == TreeContentScopeType.branches;
    final icon = inBranches
        ? Icons.alt_route_outlined
        : (circle != null ? _circleIcon(circle) : Icons.groups_outlined);
    final accent = (!inBranches && circle != null)
        ? _circleAccent(circle, tokens)
        : tokens.accent;

    return Material(
      color: tokens.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: const Key('compose-audience-summary'),
        borderRadius: BorderRadius.circular(14),
        onTap: _showAudienceSheet,
        // Плотность (чанк 12): строка уже сидит на заливке Material
        // ВНУТРИ обведённой карточки композера — свой контур поверх
        // контура карточки был рамкой в рамке. Заливка отличает пилюлю
        // от фона карточки без второго контура.
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Кто увидит',
                      style: AppTheme.sans(
                        color: tokens.inkMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    Text(
                      _selectedAudienceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.sans(
                        color: tokens.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_isLoadingCircles)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                )
              else ...[
                Text(
                  'Изменить',
                  style: AppTheme.sans(
                    color: tokens.accent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.expand_more_rounded, size: 18, color: tokens.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScopeState({
    required IconData icon,
    required String title,
    required String message,
    bool showProgress = false,
    List<Widget> actions = const <Widget>[],
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (showProgress)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}
