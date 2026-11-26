part of '../interactive_family_tree.dart';

extension _InteractiveTreeInteractions on _InteractiveFamilyTreeState {
  bool get _isSelectionLassoEnabled =>
      widget.selectionMode && widget.onPersonSelectionToggle != null;

  Offset _viewportToCanvas(Offset viewportPoint) {
    return _transformationController.toScene(viewportPoint);
  }

  /// K (culling): the currently-visible region in scene/canvas coords. The
  /// transform is translate + uniform scale only (no rotation), so two
  /// opposite viewport corners mapped to scene space bound the visible rect.
  /// Null before the first LayoutBuilder frame → callers build all nodes.
  Rect? _visibleSceneRect() {
    final vp = _viewportSize;
    if (vp == null || vp.width <= 0 || vp.height <= 0) {
      return null;
    }
    final topLeft = _transformationController.toScene(Offset.zero);
    final bottomRight =
        _transformationController.toScene(Offset(vp.width, vp.height));
    return Rect.fromPoints(topLeft, bottomRight);
  }

  void _handleLassoStart(DragStartDetails details) {
    if (!_isSelectionLassoEnabled) return;
    final canvasPoint = _viewportToCanvas(details.localPosition);
    _updateTreeState(() {
      _lassoStartCanvas = canvasPoint;
      _lassoCurrentCanvas = canvasPoint;
      _lassoPreviewIds = const <String>{};
    });
  }

  void _handleLassoUpdate(DragUpdateDetails details) {
    if (_lassoStartCanvas == null) return;
    final canvasPoint = _viewportToCanvas(details.localPosition);
    final preview = _personsInsideLassoRect(_lassoStartCanvas!, canvasPoint);
    _updateTreeState(() {
      _lassoCurrentCanvas = canvasPoint;
      _lassoPreviewIds = preview;
    });
  }

  void _handleLassoEnd(DragEndDetails details) {
    if (_lassoStartCanvas == null) return;
    final committed = List<String>.from(_lassoPreviewIds);
    _updateTreeState(() {
      _lassoStartCanvas = null;
      _lassoCurrentCanvas = null;
      _lassoPreviewIds = const <String>{};
    });
    if (committed.isEmpty) return;
    final toggle = widget.onPersonSelectionToggle;
    if (toggle == null) return;
    final peopleById = <String, FamilyPerson>{
      for (final entry in widget.peopleData)
        if (entry['person'] is FamilyPerson)
          (entry['person'] as FamilyPerson).id: entry['person'] as FamilyPerson,
    };
    // Strictly additive: only toggle ids the host doesn't already
    // have. Without this guard a partially-overlapping lasso would
    // *un-pick* the cards the user previously tapped, which is the
    // opposite of what the gesture should do.
    for (final id in committed) {
      if (widget.selectedPersonIds.contains(id)) continue;
      final person = peopleById[id];
      if (person == null) continue;
      toggle(person);
    }
  }

  void _handleLassoCancel() {
    if (_lassoStartCanvas == null) return;
    _updateTreeState(() {
      _lassoStartCanvas = null;
      _lassoCurrentCanvas = null;
      _lassoPreviewIds = const <String>{};
    });
  }

  Set<String> _personsInsideLassoRect(Offset start, Offset end) {
    final rect = Rect.fromPoints(start, end);
    final result = <String>{};
    for (final entry in nodePositions.entries) {
      final cardRect = Rect.fromCenter(
        center: entry.value,
        width: InteractiveFamilyTree.nodeWidth,
        height: InteractiveFamilyTree.nodeHeight,
      );
      if (rect.overlaps(cardRect)) {
        result.add(entry.key);
      }
    }
    return result;
  }

  // Normalizes a backend role label for the role pill on tree
  // cards. We strip the pronoun («Ваш/Ваша») — every card lives in
  // a tree centered on the current user, so prepending "Ваш(а)" to
  // every label was visually noisy and pushed long roles
  // («Ваша двоюродная сестра») past the pill's max-width into
  // ellipsis. Also folds Soviet-style «Мать»/«Отец» to the warmer
  // «Мама»/«Папа», fixes the missing ё in «тетя»/«теща», and
  // capitalizes the first letter so "свояк" reads as "Свояк".
  String _normalizeRelationLabel(String roleLabel) {
    final lower = roleLabel.toLowerCase().trim();
    if (lower.isEmpty) return roleLabel;
    const friendly = <String, String>{
      'мать': 'Мама',
      'отец': 'Папа',
      'тетя': 'Тётя',
      'теща': 'Тёща',
    };
    final mapped = friendly[lower];
    if (mapped != null) return mapped;
    return lower[0].toUpperCase() + lower.substring(1);
  }

  bool get _isConnecting => _connectingFromPersonId != null;

  void _startConnecting(String sourcePersonId) {
    if (widget.onConnectExistingPersons == null) return;
    if (widget.isEditMode) return;
    if (_connectingFromPersonId == sourcePersonId) return;
    HapticFeedback.selectionClick();
    _updateTreeState(() {
      _connectingFromPersonId = sourcePersonId;
      _connectingPointerCanvasPosition = nodePositions[sourcePersonId];
      _connectingHoverTargetId = null;
      _showingRelationPicker = false;
    });
    // Grab focus so ESC works on desktop. Do it after the frame so
    // the FocusNode is mounted into the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isConnecting) {
        _connectModeFocusNode.requestFocus();
      }
    });
  }

  void _cancelConnecting() {
    if (!_isConnecting && !_showingRelationPicker) return;
    _updateTreeState(() {
      _connectingFromPersonId = null;
      _connectingPointerCanvasPosition = null;
      _connectingHoverTargetId = null;
      _showingRelationPicker = false;
    });
  }

  void _setHoverTargetForConnect(String targetPersonId) {
    if (!_isConnecting) return;
    if (targetPersonId == _connectingFromPersonId) return;
    if (_connectingHoverTargetId == targetPersonId) return;
    _updateTreeState(() {
      _connectingHoverTargetId = targetPersonId;
    });
  }

  void _clearHoverTargetIfMatches(String targetPersonId) {
    if (_connectingHoverTargetId != targetPersonId) return;
    _updateTreeState(() {
      _connectingHoverTargetId = null;
    });
  }

  Future<void> _completeConnection(String sourceId, String targetId) async {
    if (!_isConnecting) return;
    if (sourceId == targetId) {
      _cancelConnecting();
      return;
    }
    HapticFeedback.mediumImpact();
    // Resolve persons for nicer copy in the picker.
    final sourcePerson = _findPersonInData(sourceId);
    final targetPerson = _findPersonInData(targetId);
    _updateTreeState(() {
      _showingRelationPicker = true;
      _connectingHoverTargetId = targetId;
    });
    final picked = await showDialog<RelationType>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (dialogContext) => _ConnectorRelationTypePicker(
        sourceName: sourcePerson?.displayName ?? 'этот человек',
        targetName: targetPerson?.displayName ?? 'этому человеку',
      ),
    );
    if (!mounted) return;
    if (picked == null) {
      // User dismissed the picker (tapped outside / pressed back).
      _cancelConnecting();
      return;
    }
    // Fire-and-forget: the consumer reloads the tree, didUpdateWidget
    // will pick up the new relation and re-render. We clear our local
    // state immediately so the preview line/pill go away.
    widget.onConnectExistingPersons?.call(sourceId, targetId, picked);
    _cancelConnecting();
  }

  FamilyPerson? _findPersonInData(String personId) {
    for (final entry in widget.peopleData) {
      final person = entry['person'];
      if (person is FamilyPerson && person.id == personId) {
        return person;
      }
    }
    return null;
  }

  Set<String>? _computeActivePath(String? selectedId) {
    if (selectedId == null || selectedId.isEmpty) return null;
    final result = <String>{selectedId};
    final parents = <String>{};
    bool isParentRel(RelationType t) => t == RelationType.parent;
    bool isChildRel(RelationType t) =>
        t == RelationType.child ||
        t == RelationType.grandchild ||
        t == RelationType.greatGrandchild;
    bool isSpousal(RelationType t) =>
        t == RelationType.spouse || t == RelationType.partner;

    for (final relation in widget.relations) {
      final r12 = relation.relation1to2;
      final r21 = relation.relation2to1;
      if (relation.person1Id == selectedId) {
        if (isParentRel(r12)) {
          // person2 is selected's child (selected is parent of person2)
          // — wait: r12 says how person1 relates to person2. If r12==parent,
          // person1 is parent of person2.
          result.add(relation.person2Id);
        }
        if (isChildRel(r12)) {
          // person1 is child of person2 → person2 is parent
          parents.add(relation.person2Id);
          result.add(relation.person2Id);
        }
        if (isSpousal(r12)) {
          result.add(relation.person2Id);
        }
      }
      if (relation.person2Id == selectedId) {
        if (isParentRel(r12)) {
          // person1 is parent of person2 (selected) → add person1 as parent
          parents.add(relation.person1Id);
          result.add(relation.person1Id);
        }
        if (isChildRel(r12)) {
          // person1 is child of person2 (selected) → add person1 as child
          result.add(relation.person1Id);
        }
        if (isSpousal(r21)) {
          result.add(relation.person1Id);
        }
      }
    }
    // Siblings: anyone whose parent set intersects mine.
    if (parents.isNotEmpty) {
      for (final relation in widget.relations) {
        if (relation.relation1to2 == RelationType.parent &&
            parents.contains(relation.person1Id) &&
            relation.person2Id != selectedId) {
          result.add(relation.person2Id);
        }
        if (relation.relation1to2 == RelationType.child &&
            parents.contains(relation.person2Id) &&
            relation.person1Id != selectedId) {
          result.add(relation.person1Id);
        }
      }
    }
    return result;
  }

  void _selectEditPerson(FamilyPerson person) {
    if (!mounted) {
      return;
    }
    _updateTreeState(() {
      _selectedEditPersonId = person.id;
    });
    widget.onEditPersonSelected?.call(person);
  }
}
