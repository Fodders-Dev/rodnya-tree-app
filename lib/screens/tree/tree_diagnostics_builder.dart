part of '../tree_view_screen.dart';

extension _TreeDiagnosticsBuilder on _TreeViewScreenState {
  Future<void> _sendTreeDiagnostics() async {
    final payload = _buildTreeDiagnosticPayload();
    final encodedPayload = const JsonEncoder.withIndent('  ').convert(payload);
    await Clipboard.setData(ClipboardData(text: encodedPayload));

    String? eventId;
    if (GetIt.I.isRegistered<CustomApiDiagnosticsService>()) {
      eventId = await GetIt.I<CustomApiDiagnosticsService>().capture(
        type: 'tree_layout_snapshot',
        message: 'Диагностика раскладки дерева',
        context: payload,
      );
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          eventId == null
              ? 'Диагностика дерева скопирована. Отправка на сервер недоступна.'
              : 'Диагностика дерева отправлена и скопирована.',
        ),
      ),
    );
  }

  Map<String, dynamic> _buildTreeDiagnosticPayload() {
    final mediaQuery = MediaQuery.maybeOf(context);
    final snapshot = _graphSnapshot;
    return <String, dynamic>{
      'kind': 'tree_layout_snapshot',
      'createdAt': DateTime.now().toIso8601String(),
      'tree': <String, dynamic>{
        'treeId': _currentTreeId,
        'treeName': _currentTreeMeta?.name,
        'isFriendsTree': _isFriendsTree,
        'branchRootPersonId': _branchRootPersonId,
      },
      'viewer': <String, dynamic>{
        'userId': _authService.currentUserId,
        'viewerPersonId': snapshot?.viewerPersonId,
        'currentUserIsInTree': _currentUserIsInTree,
        'role': _callerSemyaRole?.name,
        'viewerOnly': _isViewerOnly,
      },
      'uiState': <String, dynamic>{
        'selectedPersonSheetId': _selectedPersonSheetId,
        'selectedEditPersonId': _selectedEditPersonId,
        'selectedPersonIds': _selectedPersonIds.toList()..sort(),
        'isEditMode': _isEditMode,
        'isSelectionMode': _isSelectionMode,
        'manualPositionCount': _manualNodePositions.length,
      },
      'viewport': mediaQuery == null
          ? null
          : <String, dynamic>{
              'width': mediaQuery.size.width,
              'height': mediaQuery.size.height,
              'devicePixelRatio': mediaQuery.devicePixelRatio,
              'padding': <String, dynamic>{
                'left': mediaQuery.padding.left,
                'top': mediaQuery.padding.top,
                'right': mediaQuery.padding.right,
                'bottom': mediaQuery.padding.bottom,
              },
            },
      'people': _treePeople.map(_personDiagnosticPayload).toList(),
      'relations': _relationsData.map(_relationDiagnosticPayload).toList(),
      'manualNodePositions': _manualNodePositions.map(
        (id, position) => MapEntry(
          id,
          <String, dynamic>{
            'dx': position.dx,
            'dy': position.dy,
          },
        ),
      ),
      'graphSnapshot': snapshot == null
          ? null
          : <String, dynamic>{
              'treeId': snapshot.treeId,
              'viewerPersonId': snapshot.viewerPersonId,
              'familyUnits': snapshot.familyUnits
                  .map(_familyUnitDiagnosticPayload)
                  .toList(),
              'branchBlocks': snapshot.branchBlocks
                  .map(_branchBlockDiagnosticPayload)
                  .toList(),
              'generationRows': snapshot.generationRows
                  .map(_generationRowDiagnosticPayload)
                  .toList(),
              'viewerDescriptors': snapshot.viewerDescriptors
                  .map(_viewerDescriptorDiagnosticPayload)
                  .toList(),
              'warnings':
                  snapshot.warnings.map(_warningDiagnosticPayload).toList(),
            },
    };
  }

  Map<String, dynamic> _personDiagnosticPayload(FamilyPerson person) {
    return <String, dynamic>{
      'id': person.id,
      'treeId': person.treeId,
      'identityId': person.identityId,
      'name': person.name,
      'maidenName': person.maidenName,
      'gender': person.gender.name,
      'birthDate': person.birthDate?.toIso8601String(),
      'birthDatePrecision': person.birthDatePrecision,
      'deathDate': person.deathDate?.toIso8601String(),
      'deathDatePrecision': person.deathDatePrecision,
      'isAlive': person.isAlive,
      'relation': person.relation,
      'hasLinkedUser': (person.userId ?? '').trim().isNotEmpty,
      'parentIds': person.parentIds ?? const <String>[],
      'childrenIds': person.childrenIds ?? const <String>[],
      'spouseId': person.spouseId,
      'siblingIds': person.siblingIds ?? const <String>[],
    };
  }

  Map<String, dynamic> _relationDiagnosticPayload(FamilyRelation relation) {
    return <String, dynamic>{
      'id': relation.id,
      'treeId': relation.treeId,
      'person1Id': relation.person1Id,
      'person2Id': relation.person2Id,
      'relation1to2': relation.relation1to2.name,
      'relation2to1': relation.relation2to1.name,
      'isConfirmed': relation.isConfirmed,
      'parentSetId': relation.parentSetId,
      'parentSetType': relation.parentSetType,
      'isPrimaryParentSet': relation.isPrimaryParentSet,
      'unionId': relation.unionId,
      'unionType': relation.unionType,
      'unionStatus': relation.unionStatus,
      'marriageDate': relation.marriageDate?.toIso8601String(),
      'divorceDate': relation.divorceDate?.toIso8601String(),
    };
  }

  Map<String, dynamic> _familyUnitDiagnosticPayload(
    TreeGraphFamilyUnit unit,
  ) {
    return <String, dynamic>{
      'id': unit.id,
      'rootParentSetId': unit.rootParentSetId,
      'adultIds': unit.adultIds,
      'childIds': unit.childIds,
      'relationIds': unit.relationIds,
      'unionId': unit.unionId,
      'unionType': unit.unionType,
      'unionStatus': unit.unionStatus,
      'parentSetType': unit.parentSetType,
      'isPrimaryParentSet': unit.isPrimaryParentSet,
      'label': unit.label,
    };
  }

  Map<String, dynamic> _branchBlockDiagnosticPayload(
    TreeGraphBranchBlock block,
  ) {
    return <String, dynamic>{
      'id': block.id,
      'rootUnitId': block.rootUnitId,
      'label': block.label,
      'memberPersonIds': block.memberPersonIds,
    };
  }

  Map<String, dynamic> _generationRowDiagnosticPayload(
    TreeGraphGenerationRow row,
  ) {
    return <String, dynamic>{
      'row': row.row,
      'label': row.label,
      'personIds': row.personIds,
      'familyUnitIds': row.familyUnitIds,
    };
  }

  Map<String, dynamic> _viewerDescriptorDiagnosticPayload(
    TreeGraphViewerDescriptor descriptor,
  ) {
    return <String, dynamic>{
      'personId': descriptor.personId,
      'primaryRelationLabel': descriptor.primaryRelationLabel,
      'isBlood': descriptor.isBlood,
      'alternatePathCount': descriptor.alternatePathCount,
      'pathSummary': descriptor.pathSummary,
      'primaryPathPersonIds': descriptor.primaryPathPersonIds,
    };
  }

  Map<String, dynamic> _warningDiagnosticPayload(TreeGraphWarning warning) {
    return <String, dynamic>{
      'id': warning.id,
      'code': warning.code,
      'severity': warning.severity,
      'message': warning.message,
      'hint': warning.hint,
      'personIds': warning.personIds,
      'familyUnitIds': warning.familyUnitIds,
      'relationIds': warning.relationIds,
    };
  }

  // ── Phase 4 chunk 2: filter button helpers ───────────────────────
}
