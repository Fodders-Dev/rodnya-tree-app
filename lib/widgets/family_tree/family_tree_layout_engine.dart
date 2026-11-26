part of '../interactive_family_tree.dart';

// Maps the viewer-relative relation label the backend computes
// (e.g., "Дядя", "Двоюродная сестра", "Бабушка") to a generation
// offset in the layout's row index space:
//   negative → older generation (above the viewer row)
//   zero     → same generation as the viewer
//   positive → younger generation (below the viewer row)
//
// Returns null when the label doesn't map cleanly to a single
// offset (e.g., "В законе" / "Друг" / unknown). The caller should
// then fall back to whatever the structural BFS came up with.
//
// The matcher is intentionally lowercase substring — backend
// labels can carry suffixes ("+2", "по жене", colloquial forms)
// which we strip before testing.
int? _generationOffsetFromRelationLabel(String? rawLabel) {
  if (rawLabel == null) return null;
  final label = rawLabel.toLowerCase().trim();
  if (label.isEmpty) return null;

  // Order matters: more specific patterns first so "прабабушка"
  // doesn't accidentally match the "бабушка" rule.
  if (label.contains('прапрадед') ||
      label.contains('прапрабабушк') ||
      label.contains('прапрадеду')) {
    return -4;
  }
  if (label.contains('прадед') ||
      label.contains('прабаб') ||
      label.contains('прадеду')) {
    return -3;
  }
  if (label.contains('двоюродн')) {
    // Двоюродный/-ая брат/сестра/племянник/дядя/тётя — the
    // generation offset depends on the second half.
    if (label.contains('брат') || label.contains('сестр')) return 0;
    if (label.contains('племянн')) return 1;
    if (label.contains('дядя') ||
        label.contains('тёт') ||
        label.contains('тет')) {
      return -1;
    }
    if (label.contains('бабуш') || label.contains('дед')) return -2;
    if (label.contains('внук') || label.contains('внучк')) return 2;
    return null;
  }
  if (label.contains('дед') ||
      label.contains('бабуш') ||
      label.contains('бабк')) {
    return -2;
  }
  if (label.contains('внук') || label.contains('внучк')) return 2;
  if (label.contains('племянн') || label.contains('племяшк')) return 1;
  if (label.contains('дядя') ||
      label.contains('тёт') ||
      label.contains('тет')) {
    return -1;
  }
  if (label.contains('мать') ||
      label.contains('мам') ||
      label.contains('отец') ||
      label.contains('папа') ||
      label.contains('родитель') ||
      label.contains('мачех') ||
      label.contains('отчим')) {
    return -1;
  }
  if (label.contains('сын') ||
      label.contains('дочь') ||
      label.contains('дочк') ||
      label.contains('пасынк') ||
      label.contains('падчериц')) {
    return 1;
  }
  if (label.contains('брат') || label.contains('сестр')) return 0;
  if (label.contains('супруг') ||
      label.contains('партнёр') ||
      label.contains('партнер') ||
      label.contains('жен') ||
      label.contains('муж')) {
    return 0;
  }
  return null;
}

bool _isInactiveUnionStatus(String? status) {
  final normalized = (status ?? '').trim().toLowerCase();
  return normalized == 'past' || normalized == 'ended_by_death';
}

class _TreeLayoutEngine {
  _TreeLayoutEngine({
    required this.peopleData,
    required this.relations,
    this.graphSnapshot,
    this.currentUserId,
  });

  final List<Map<String, dynamic>> peopleData;
  final List<FamilyRelation> relations;
  final TreeGraphSnapshot? graphSnapshot;
  final String? currentUserId;

  _TreeLayoutComputation compute() {
    final peopleById = <String, FamilyPerson>{
      for (final entry in peopleData)
        (entry['person'] as FamilyPerson).id: entry['person'] as FamilyPerson,
    };
    if (peopleById.isEmpty) {
      return const _TreeLayoutComputation(
        nodePositions: <String, Offset>{},
        connections: <FamilyConnection>[],
        treeSize: Size.zero,
      );
    }

    final parentToChildren = <String, Set<String>>{};
    final childToParents = <String, Set<String>>{};
    final spousesByPerson = <String, Set<String>>{};
    final siblingsByPerson = <String, Set<String>>{};
    final adjacency = <String, Set<String>>{
      for (final id in peopleById.keys) id: <String>{},
    };

    for (final relation in relations) {
      final parentId = _parentIdFromRelation(relation);
      final childId = _childIdFromRelation(relation);
      if (parentId != null && childId != null) {
        parentToChildren.putIfAbsent(parentId, () => <String>{}).add(childId);
        childToParents.putIfAbsent(childId, () => <String>{}).add(parentId);
        adjacency[parentId]!.add(childId);
        adjacency[childId]!.add(parentId);
      } else if (_isSpouseRelation(relation)) {
        spousesByPerson
            .putIfAbsent(relation.person1Id, () => <String>{})
            .add(relation.person2Id);
        spousesByPerson
            .putIfAbsent(relation.person2Id, () => <String>{})
            .add(relation.person1Id);
        adjacency[relation.person1Id]!.add(relation.person2Id);
        adjacency[relation.person2Id]!.add(relation.person1Id);
      } else if (_isSiblingRelation(relation)) {
        siblingsByPerson
            .putIfAbsent(relation.person1Id, () => <String>{})
            .add(relation.person2Id);
        siblingsByPerson
            .putIfAbsent(relation.person2Id, () => <String>{})
            .add(relation.person1Id);
        adjacency[relation.person1Id]!.add(relation.person2Id);
        adjacency[relation.person2Id]!.add(relation.person1Id);
      }
    }

    // Enrich parent/child + spouse adjacency from the backend's family
    // unit snapshot. Without this, distant relatives the user adds via
    // their relation type ("cousin", "aunt", "uncle", "niece" ...)
    // never get parent/child edges in this layout — only the literal
    // RelationType.parent/child/spouse/partner/sibling kinds are
    // extracted above. The backend's graph builder already resolves
    // those distant types into proper family units (adultIds + childIds
    // = parent edge, two adultIds = couple), so we just have to
    // re-project them back into adjacency. This is what was breaking
    // the user's tree the moment a cousin was added: she landed in the
    // graph but the layout had no idea who her parents were, so her
    // group's `_desiredCenterForGroup` returned null and she drifted
    // to the far right of the row.
    final snapshot = graphSnapshot;
    if (snapshot != null) {
      for (final unit in snapshot.familyUnits) {
        final adultIds =
            unit.adultIds.where(peopleById.containsKey).toList(growable: false);
        final childIds =
            unit.childIds.where(peopleById.containsKey).toList(growable: false);

        // Adults of the same family unit form an implicit couple even
        // when no explicit spouse/partner relation exists (e.g. an
        // unmarried mother + father the user added independently).
        for (var i = 0; i < adultIds.length; i++) {
          for (var j = i + 1; j < adultIds.length; j++) {
            final a = adultIds[i];
            final b = adultIds[j];
            spousesByPerson.putIfAbsent(a, () => <String>{}).add(b);
            spousesByPerson.putIfAbsent(b, () => <String>{}).add(a);
            adjacency[a]!.add(b);
            adjacency[b]!.add(a);
          }
        }

        // Each adult is a parent of every child in the unit.
        for (final adultId in adultIds) {
          for (final childId in childIds) {
            parentToChildren
                .putIfAbsent(adultId, () => <String>{})
                .add(childId);
            childToParents.putIfAbsent(childId, () => <String>{}).add(adultId);
            adjacency[adultId]!.add(childId);
            adjacency[childId]!.add(adultId);
          }
        }

        // Children of the same family unit are siblings of each other.
        for (var i = 0; i < childIds.length; i++) {
          for (var j = i + 1; j < childIds.length; j++) {
            final a = childIds[i];
            final b = childIds[j];
            siblingsByPerson.putIfAbsent(a, () => <String>{}).add(b);
            siblingsByPerson.putIfAbsent(b, () => <String>{}).add(a);
            adjacency[a]!.add(b);
            adjacency[b]!.add(a);
          }
        }
      }
    }

    final components = _buildComponents(adjacency, peopleById);

    // ── Find viewer + their global level BEFORE the components loop.
    // We process the viewer's component first, capture its levels,
    // and use the viewer's level as the global anchor for any
    // OTHER component that has a viewer-relative descriptor (e.g.,
    // an uncle-by-marriage who has no structural connection to the
    // viewer's blood ancestors). Without this, separate components
    // each min-shift to row 0 and float independently — placing an
    // uncle's branch at the canvas top instead of the parents' row.
    FamilyPerson? viewerPerson;
    if (currentUserId != null && currentUserId!.isNotEmpty) {
      for (final person in peopleById.values) {
        if (person.userId == currentUserId) {
          viewerPerson = person;
          break;
        }
      }
    }
    int? viewerGlobalLevel;
    final componentLevels = <Set<String>, Map<String, int>>{};

    // Pre-pass: assign levels for every component AND find the
    // viewer's level. We can't do this lazily inside the position
    // loop because uncle's component might be processed before
    // viewer's component, and uncle needs viewer's level to anchor.
    for (final component in components) {
      final levels = _assignLevels(
        component: component,
        peopleById: peopleById,
        childToParents: childToParents,
        parentToChildren: parentToChildren,
        spousesByPerson: spousesByPerson,
        siblingsByPerson: siblingsByPerson,
      );
      componentLevels[component] = levels;
      if (viewerPerson != null && component.contains(viewerPerson.id)) {
        viewerGlobalLevel = levels[viewerPerson.id];
      }
    }

    // Viewer-relation anchor pass: for each NON-viewer component,
    // override its levels using descriptors so people land on the
    // right global row even when they're structurally disconnected
    // from the viewer. Specifically for the uncle-by-marriage case,
    // his "Дядя" descriptor → -1 from viewer → moved to viewer-1.
    final descriptors = graphSnapshot?.viewerDescriptorByPersonId;
    if (viewerGlobalLevel != null &&
        descriptors != null &&
        descriptors.isNotEmpty) {
      for (final component in components) {
        if (viewerPerson != null && component.contains(viewerPerson.id)) {
          // The viewer's own component already has the right
          // structural levels — don't second-guess them.
          continue;
        }
        final levels = componentLevels[component];
        if (levels == null) continue;

        // Find anchor candidates in this component. Each anchor's
        // desired global level (viewerGlobalLevel + offset) maps
        // to a current level in the component; the difference is
        // the shift to apply to ALL members of this component to
        // align them to the viewer's coordinate space.
        final shifts = <int>[];
        for (final personId in component) {
          final descriptor = descriptors[personId];
          if (descriptor == null) continue;
          final offset = _generationOffsetFromRelationLabel(
            descriptor.primaryRelationLabel,
          );
          if (offset == null) continue;
          final currentLevel = levels[personId];
          if (currentLevel == null) continue;
          shifts.add((viewerGlobalLevel + offset) - currentLevel);
        }
        if (shifts.isEmpty) continue;

        // Use the median shift — robust against one weird
        // descriptor pulling everyone the wrong way.
        shifts.sort();
        final medianShift = shifts[shifts.length ~/ 2];
        if (medianShift == 0) continue;

        for (final entry in levels.entries.toList()) {
          levels[entry.key] = entry.value + medianShift;
        }
      }

      // Within-component anchor pass — for the viewer's OWN
      // component. Same idea as the cross-component median shift
      // above, but applied per-person: when an in-law (e.g.
      // "Дядя" by marriage) is connected to the viewer's main
      // family graph via a child edge but has no explicit spouse
      // edge to anchor him to his wife's row, his BFS-derived
      // level is wrong by exactly one. The descriptor knows
      // better, so we override.
      //
      // Critical safety: only override when the move respects
      // parent>child constraints in BOTH directions:
      //   * Person's level must end up > each in-component parent.
      //   * Person's level must end up < each in-component child.
      // If the move would violate either, the structural data is
      // tighter than the descriptor and we leave it alone.
      //
      // We loop until stable so that overriding a parent (e.g.
      // Vitya) ALSO pulls his children (e.g. Nastya) along —
      // the spouse-parity loop in _assignLevels will handle the
      // re-balance after each override.
      if (viewerPerson != null) {
        final viewerOwnComponent = components.firstWhere(
          (component) => component.contains(viewerPerson!.id),
          orElse: () => <String>{},
        );
        final levels = componentLevels[viewerOwnComponent];
        if (levels != null && viewerOwnComponent.isNotEmpty) {
          final maxIterations = viewerOwnComponent.length * 2 + 4;
          var changed = true;
          var iteration = 0;
          while (changed && iteration < maxIterations) {
            changed = false;
            iteration += 1;
            for (final personId in viewerOwnComponent) {
              if (personId == viewerPerson.id) continue;
              final descriptor = descriptors[personId];
              if (descriptor == null) continue;
              final offset = _generationOffsetFromRelationLabel(
                descriptor.primaryRelationLabel,
              );
              if (offset == null) continue;
              final desiredLevel = viewerGlobalLevel + offset;
              final currentLevel = levels[personId];
              if (currentLevel == null) continue;
              if (currentLevel == desiredLevel) continue;
              // Parent-child safety: don't pull a person below
              // their own children, don't push them above their
              // own parents, EVEN if the descriptor disagrees
              // with the BFS. Structural data wins on direction.
              final parents = childToParents[personId] ?? const <String>{};
              final children = parentToChildren[personId] ?? const <String>{};
              var safe = true;
              for (final parentId in parents) {
                if (!viewerOwnComponent.contains(parentId)) continue;
                final parentLevel = levels[parentId];
                if (parentLevel == null) continue;
                if (desiredLevel <= parentLevel) {
                  safe = false;
                  break;
                }
              }
              if (!safe) continue;
              for (final childId in children) {
                if (!viewerOwnComponent.contains(childId)) continue;
                final childLevel = levels[childId];
                if (childLevel == null) continue;
                if (desiredLevel >= childLevel) {
                  safe = false;
                  break;
                }
              }
              if (!safe) continue;
              // Spouse parity: if person has spouse(s) at OTHER
              // levels, snap them along.
              levels[personId] = desiredLevel;
              for (final spouseId
                  in spousesByPerson[personId] ?? const <String>{}) {
                if (viewerOwnComponent.contains(spouseId) &&
                    levels[spouseId] != desiredLevel) {
                  levels[spouseId] = desiredLevel;
                }
              }
              // Children of the moved person should be ONE row
              // below — set them now so the next iteration sees
              // the correct constraint when checking their own
              // descriptors.
              for (final childId in children) {
                if (viewerOwnComponent.contains(childId)) {
                  final newChildLevel = desiredLevel + 1;
                  if ((levels[childId] ?? 0) < newChildLevel) {
                    levels[childId] = newChildLevel;
                  }
                }
              }
              changed = true;
            }
          }
        }
      }
    }

    final nodePositions = <String, Offset>{};
    var offsetX = InteractiveFamilyTree.contentInsetHorizontal +
        InteractiveFamilyTree.nodeWidth / 2 +
        InteractiveFamilyTree.siblingSeparation;
    var maxBottomY = 0.0;

    for (final component in components) {
      final levels = componentLevels[component]!;
      final groupsByLevel = _buildGroupsByLevel(
        component: component,
        levels: levels,
        spousesByPerson: spousesByPerson,
        siblingsByPerson: siblingsByPerson,
        parentToChildren: parentToChildren,
        peopleById: peopleById,
      );

      final componentPositions = <String, Offset>{};
      final levelOrder = groupsByLevel.keys.toList()..sort();
      for (final level in levelOrder) {
        final groups = [...(groupsByLevel[level] ?? const <_SpouseGroup>[])]
          ..sort((left, right) {
            final leftDesired = _desiredCenterForGroup(
              group: left,
              positions: componentPositions,
              childToParents: childToParents,
              parentToChildren: parentToChildren,
              siblingsByPerson: siblingsByPerson,
              spousesByPerson: spousesByPerson,
            );
            final rightDesired = _desiredCenterForGroup(
              group: right,
              positions: componentPositions,
              childToParents: childToParents,
              parentToChildren: parentToChildren,
              siblingsByPerson: siblingsByPerson,
              spousesByPerson: spousesByPerson,
            );
            if (leftDesired != null && rightDesired != null) {
              final centerCompare = leftDesired.compareTo(rightDesired);
              if (centerCompare != 0) {
                return centerCompare;
              }
            } else if (leftDesired != null) {
              return -1;
            } else if (rightDesired != null) {
              return 1;
            }

            final leftWeight = _groupDescendantWeight(
              left.memberIds,
              parentToChildren,
            );
            final rightWeight = _groupDescendantWeight(
              right.memberIds,
              parentToChildren,
            );
            if (leftWeight != rightWeight) {
              return rightWeight.compareTo(leftWeight);
            }

            return _comparePersons(
              peopleById[left.memberIds.first]!,
              peopleById[right.memberIds.first]!,
            );
          });
        groupsByLevel[level] = groups;
        var currentLeft = offsetX;
        for (final group in groups) {
          final requestedCenter = _desiredCenterForGroup(
            group: group,
            positions: componentPositions,
            childToParents: childToParents,
            parentToChildren: parentToChildren,
            siblingsByPerson: siblingsByPerson,
            spousesByPerson: spousesByPerson,
          );
          final groupWidth = _groupWidth(group.memberIds.length);
          final requestedLeft = requestedCenter == null
              ? currentLeft
              : requestedCenter - groupWidth / 2;
          final left = max(currentLeft, requestedLeft);
          final y = InteractiveFamilyTree.contentInsetTop +
              InteractiveFamilyTree.nodeHeight / 2 +
              level *
                  (InteractiveFamilyTree.nodeHeight +
                      InteractiveFamilyTree.levelSeparation);
          for (var index = 0; index < group.memberIds.length; index++) {
            final personId = group.memberIds[index];
            final x = left +
                InteractiveFamilyTree.nodeWidth / 2 +
                index *
                    (InteractiveFamilyTree.nodeWidth +
                        InteractiveFamilyTree.spouseSeparation);
            componentPositions[personId] = Offset(x, y);
            maxBottomY = max(
              maxBottomY,
              y + InteractiveFamilyTree.nodeHeight / 2,
            );
          }
          currentLeft =
              left + groupWidth + InteractiveFamilyTree.siblingSeparation;
        }
      }

      _normalizeGroups(
        componentPositions,
        groupsByLevel,
        levels: levels,
        childToParents: childToParents,
        parentToChildren: parentToChildren,
        siblingsByPerson: siblingsByPerson,
        peopleById: peopleById,
        componentStartX: offsetX,
      );
      _centerParents(componentPositions, groupsByLevel, parentToChildren);
      _normalizeGroups(
        componentPositions,
        groupsByLevel,
        levels: levels,
        childToParents: childToParents,
        parentToChildren: parentToChildren,
        siblingsByPerson: siblingsByPerson,
        peopleById: peopleById,
        componentStartX: offsetX,
      );
      // Authoritative X pass: guarantee each pair's children are a contiguous,
      // non-overlapping block under their parents (no branch interleaving).
      // Runs last so it overrides any residual greedy/center drift; uses the
      // earlier passes only for stable left→right ordering.
      _enforceContiguousSubtreeBlocks(
        componentPositions,
        groupsByLevel,
        childToParents,
        parentToChildren,
        peopleById,
        componentStartX: offsetX,
      );
      _anchorComponentToStart(
        componentPositions,
        componentStartX: offsetX,
      );
      nodePositions.addAll(componentPositions);

      var rightEdge = offsetX;
      for (final position in componentPositions.values) {
        rightEdge = max(
          rightEdge,
          position.dx + InteractiveFamilyTree.nodeWidth / 2,
        );
      }
      offsetX = rightEdge + InteractiveFamilyTree.siblingSeparation * 3;
    }

    final connections = _buildConnections(relations, nodePositions);
    final maxRight = nodePositions.values.fold<double>(
      InteractiveFamilyTree.nodeWidth,
      (value, position) =>
          max(value, position.dx + InteractiveFamilyTree.nodeWidth / 2),
    );

    return _TreeLayoutComputation(
      nodePositions: nodePositions,
      connections: connections,
      treeSize: Size(
        max(
          maxRight + InteractiveFamilyTree.contentInsetHorizontal,
          300,
        ),
        max(
          maxBottomY + InteractiveFamilyTree.contentInsetBottom,
          300,
        ),
      ),
    );
  }

  List<Set<String>> _buildComponents(
    Map<String, Set<String>> adjacency,
    Map<String, FamilyPerson> peopleById,
  ) {
    final components = <Set<String>>[];
    final visited = <String>{};
    final ids = peopleById.keys.toList()
      ..sort((a, b) => _comparePersons(peopleById[a]!, peopleById[b]!));
    for (final id in ids) {
      if (!visited.add(id)) {
        continue;
      }
      final component = <String>{id};
      final queue = <String>[id];
      while (queue.isNotEmpty) {
        final currentId = queue.removeAt(0);
        for (final neighbour in adjacency[currentId] ?? const <String>{}) {
          if (visited.add(neighbour)) {
            component.add(neighbour);
            queue.add(neighbour);
          }
        }
      }
      components.add(component);
    }
    return components;
  }

  Map<String, int> _assignLevels({
    required Set<String> component,
    required Map<String, FamilyPerson> peopleById,
    required Map<String, Set<String>> childToParents,
    required Map<String, Set<String>> parentToChildren,
    required Map<String, Set<String>> spousesByPerson,
    required Map<String, Set<String>> siblingsByPerson,
  }) {
    final levels = <String, int>{};
    final roots = component
        .where(
          (id) => (childToParents[id] ?? const <String>{})
              .where(component.contains)
              .isEmpty,
        )
        .toList()
      ..sort((a, b) => _comparePersons(peopleById[a]!, peopleById[b]!));
    final queue = <String>[...(roots.isNotEmpty ? roots : component)];

    // Cycle / runaway-loop guard. The BFS re-enqueues whenever a
    // spouse / sibling / child level disagrees, so a malformed graph
    // (e.g. user accidentally added "X is parent of Y" AND "Y is
    // parent of X") can loop forever. Worst-case stable BFS visits
    // each node O(component.size) times — anything beyond that is a
    // cycle, so we just bail with the levels we have.
    final maxBfsSteps = component.length * 16 + 16;
    var bfsSteps = 0;
    while (queue.isNotEmpty) {
      bfsSteps += 1;
      if (bfsSteps > maxBfsSteps) {
        debugPrint(
          'InteractiveFamilyTree._assignLevels: BFS exceeded '
          'safety cap ($maxBfsSteps) — likely cyclic relations. '
          'Falling back to current level assignments.',
        );
        break;
      }

      final currentId = queue.removeAt(0);
      final currentLevel = levels[currentId] ?? 0;
      levels[currentId] = currentLevel;

      for (final spouseId in spousesByPerson[currentId] ?? const <String>{}) {
        if (!component.contains(spouseId)) {
          continue;
        }
        final existing = levels[spouseId];
        if (existing == null || existing != currentLevel) {
          levels[spouseId] = currentLevel;
          queue.add(spouseId);
        }
      }

      for (final childId in parentToChildren[currentId] ?? const <String>{}) {
        if (!component.contains(childId)) {
          continue;
        }
        final childLevel = currentLevel + 1;
        final existing = levels[childId];
        if (existing == null || childLevel > existing) {
          levels[childId] = childLevel;
          queue.add(childId);
        }
      }

      for (final siblingId in siblingsByPerson[currentId] ?? const <String>{}) {
        if (!component.contains(siblingId)) {
          continue;
        }
        final existing = levels[siblingId];
        if (existing == null || existing != currentLevel) {
          levels[siblingId] = currentLevel;
          queue.add(siblingId);
        }
      }
    }

    for (final id in component) {
      levels.putIfAbsent(id, () {
        final parentLevels = (childToParents[id] ?? const <String>{})
            .where(component.contains)
            .map((parentId) => levels[parentId])
            .whereType<int>()
            .toList();
        return parentLevels.isEmpty ? 0 : parentLevels.reduce(max) + 1;
      });
    }

    final snapshot = graphSnapshot;
    if (snapshot != null && snapshot.generationRows.isNotEmpty) {
      final snapshotLevels = <String, int>{};
      for (final row in snapshot.generationRows) {
        for (final personId in row.personIds) {
          if (component.contains(personId)) {
            snapshotLevels[personId] = row.row;
          }
        }
      }
      if (snapshotLevels.isNotEmpty) {
        final snapshotMinLevel = snapshotLevels.values.reduce(min);
        for (final entry in snapshotLevels.entries) {
          levels[entry.key] = entry.value - snapshotMinLevel;
        }

        final relevantUnits = snapshot.familyUnits.where((unit) {
          return unit.adultIds.any(component.contains) ||
              unit.childIds.any(component.contains);
        }).toList(growable: false);
        final maxIterations = component.length + relevantUnits.length + 4;
        var changed = true;
        var iteration = 0;
        while (changed && iteration < maxIterations) {
          changed = false;
          iteration += 1;

          for (final personId in component) {
            final spouseIds = (spousesByPerson[personId] ?? const <String>{})
                .where(component.contains)
                .toList(growable: false);
            if (spouseIds.isEmpty) {
              continue;
            }
            final targetLevel = [
              levels[personId] ?? 0,
              ...spouseIds.map((spouseId) => levels[spouseId] ?? 0),
            ].reduce(max);
            if ((levels[personId] ?? 0) != targetLevel) {
              levels[personId] = targetLevel;
              changed = true;
            }
            for (final spouseId in spouseIds) {
              if ((levels[spouseId] ?? 0) != targetLevel) {
                levels[spouseId] = targetLevel;
                changed = true;
              }
            }
          }

          for (final unit in relevantUnits) {
            final adultIds =
                unit.adultIds.where(component.contains).toList(growable: false);
            final childIds =
                unit.childIds.where(component.contains).toList(growable: false);
            if (adultIds.isEmpty && childIds.isEmpty) {
              continue;
            }

            int? desiredAdultLevel;
            if (childIds.isNotEmpty) {
              desiredAdultLevel = max(
                0,
                childIds.map((personId) => levels[personId] ?? 0).reduce(min) -
                    1,
              );
            } else if (adultIds.isNotEmpty) {
              desiredAdultLevel =
                  adultIds.map((personId) => levels[personId] ?? 0).reduce(max);
            }

            if (desiredAdultLevel != null) {
              for (final adultId in adultIds) {
                if ((levels[adultId] ?? 0) != desiredAdultLevel) {
                  levels[adultId] = desiredAdultLevel;
                  changed = true;
                }
              }
            }

            if (desiredAdultLevel != null && childIds.isNotEmpty) {
              final desiredChildLevel = desiredAdultLevel + 1;
              for (final childId in childIds) {
                if ((levels[childId] ?? 0) != desiredChildLevel) {
                  levels[childId] = desiredChildLevel;
                  changed = true;
                }
              }
            }
          }

          for (final personId in component) {
            final siblingIds = (siblingsByPerson[personId] ?? const <String>{})
                .where(component.contains)
                .toList(growable: false);
            if (siblingIds.isEmpty) {
              continue;
            }
            final targetLevel = [
              levels[personId] ?? 0,
              ...siblingIds.map((siblingId) => levels[siblingId] ?? 0),
            ].reduce(max);
            if ((levels[personId] ?? 0) != targetLevel) {
              levels[personId] = targetLevel;
              changed = true;
            }
            for (final siblingId in siblingIds) {
              if ((levels[siblingId] ?? 0) != targetLevel) {
                levels[siblingId] = targetLevel;
                changed = true;
              }
            }
          }
        }
      }
    }

    // Derive implicit couples from shared children: any two adults who
    // share at least one biological child should be treated as a couple
    // for layout purposes, even when no explicit spouse/partner relation
    // exists. Without this, a mother and a father that the user added
    // independently (only as "parent of me") end up on different rows.
    final impliedCouples = <String, Set<String>>{};
    for (final entry in parentToChildren.entries) {
      final parentA = entry.key;
      if (!component.contains(parentA)) continue;
      final children = entry.value.where(component.contains).toList();
      for (final childId in children) {
        for (final parentB in childToParents[childId] ?? const <String>{}) {
          if (parentB == parentA || !component.contains(parentB)) continue;
          impliedCouples.putIfAbsent(parentA, () => <String>{}).add(parentB);
        }
      }
    }

    // Final spouse-parity pass — runs even when there's no snapshot. The
    // earlier loops can leave a spouse pair on different rows when one
    // partner has parents in-tree and the other doesn't, or when adding a
    // sibling-in-law (e.g. an aunt) re-anchors one partner via a different
    // family unit.
    //
    // Iterate until stable: for each spouse pair, snap both to the row of
    // their lowest-level child minus one (the row that satisfies the
    // parent→child constraint), or to the max of their current levels if
    // they have no children. Sibling pairs follow the same max-rule.
    var changed = true;
    var safetyIterations = 0;
    final maxIterations = component.length * 2 + 8;
    while (changed && safetyIterations < maxIterations) {
      changed = false;
      safetyIterations += 1;

      // Spouses ↔ shared row. Anchored by their kids' row when possible.
      // Use both explicit spouse/partner relations AND implicit "shared-
      // child" pairings so a mother and father that the user added
      // independently still end up on the same row.
      for (final personId in component) {
        final spouseIds = <String>{
          ...(spousesByPerson[personId] ?? const <String>{}),
          ...(impliedCouples[personId] ?? const <String>{}),
        }.where(component.contains).toList(growable: false);
        if (spouseIds.isEmpty) continue;

        final pair = <String>{personId, ...spouseIds};
        final sharedChildren = <String>{};
        for (final memberId in pair) {
          for (final childId
              in parentToChildren[memberId] ?? const <String>{}) {
            if (!component.contains(childId)) {
              continue;
            }
            final parentsInPair = (childToParents[childId] ?? const <String>{})
                .where(pair.contains)
                .length;
            if (parentsInPair >= 2) {
              sharedChildren.add(childId);
            }
          }
        }

        int targetLevel;
        if (sharedChildren.isNotEmpty) {
          // Parents go to one above the lowest-level child — that puts
          // them at the same generation as their kids' other parent set.
          targetLevel = max(
            0,
            sharedChildren.map((childId) => levels[childId] ?? 0).reduce(min) -
                1,
          );
        } else {
          // No children — fall back to the highest current level among
          // the spouses (matches reference: spouses must share a row).
          targetLevel =
              pair.map((memberId) => levels[memberId] ?? 0).reduce(max);
        }

        for (final memberId in pair) {
          if ((levels[memberId] ?? 0) != targetLevel) {
            levels[memberId] = targetLevel;
            changed = true;
          }
        }
      }

      for (final parentId in component) {
        final parentLevel = levels[parentId] ?? 0;
        for (final childId in parentToChildren[parentId] ?? const <String>{}) {
          if (!component.contains(childId)) {
            continue;
          }
          final desiredChildLevel = parentLevel + 1;
          if ((levels[childId] ?? 0) < desiredChildLevel) {
            levels[childId] = desiredChildLevel;
            changed = true;
          }
        }
      }

      // Siblings ↔ shared row. Anchored by their parents' row when known,
      // but bounded BELOW by each sibling's own children — otherwise the
      // sibling rule can pull a parent up out of their kids' row (e.g.
      // father is sibling-of-aunt at parent+1=1, but his own son is at
      // level 3 forcing parent at 2 to stay aligned with the mother).
      for (final personId in component) {
        final siblingIds = (siblingsByPerson[personId] ?? const <String>{})
            .where(component.contains)
            .toList(growable: false);
        if (siblingIds.isEmpty) continue;

        final pair = <String>{personId, ...siblingIds};
        final sharedParents = <String>{};
        for (final memberId in pair) {
          for (final parentId in childToParents[memberId] ?? const <String>{}) {
            if (component.contains(parentId)) {
              sharedParents.add(parentId);
            }
          }
        }

        // Floor — directly below the highest-level parent.
        final parentFloor = sharedParents.isNotEmpty
            ? sharedParents
                    .map((parentId) => levels[parentId] ?? 0)
                    .reduce(max) +
                1
            : pair.map((memberId) => levels[memberId] ?? 0).reduce(max);

        // Per-sibling floor from their own children, then take the
        // strongest constraint across the group so spouses with kids
        // don't drag back to parent+1.
        int targetLevel = parentFloor;
        for (final memberId in pair) {
          final ownChildren = (parentToChildren[memberId] ?? const <String>{})
              .where(component.contains)
              .toList(growable: false);
          if (ownChildren.isNotEmpty) {
            final childFloor =
                ownChildren.map((childId) => levels[childId] ?? 0).reduce(min) -
                    1;
            if (childFloor > targetLevel) {
              targetLevel = childFloor;
            }
          }
        }

        for (final memberId in pair) {
          if ((levels[memberId] ?? 0) != targetLevel) {
            levels[memberId] = targetLevel;
            changed = true;
          }
        }
      }
    }

    // ── Viewer-relation anchor pass ───────────────────────────────────
    // The structural BFS gets confused when one half of a couple has
    // strong anchors in-tree (e.g., wife is daughter of grandparents,
    // child of viewer's grandparent → anchored at parents' row) and
    // the other half has only a weak anchor (e.g., husband-by-marriage
    // with only one parent-of-cousin edge — gets dropped a generation
    // because his only kid floats up). In that case the BFS puts the
    // weakly-anchored spouse one row higher than they should be, and
    // their kid follows.
    //
    // The backend already computes a label for everyone relative to
    // the viewer (Дядя / Тётя / Двоюродная сестра / etc), and that
    // label encodes a clear generation offset. When the structural
    // level disagrees by exactly 1 row with what the relation label
    // demands, the label wins — same with the spouse-pairing rules,
    // we treat it as the "ground truth" the BFS should match.
    //
    // We're conservative: only override by ±1 (not ±2+), so a
    // genuinely-broken graph doesn't get yanked across the canvas
    // by a stale label. And the override re-runs the spouse-/kid-
    // anchor passes implicitly via _propagateLevelChange below.
    final minLevel = levels.values.reduce(min);
    if (minLevel != 0) {
      for (final entry in levels.entries.toList()) {
        levels[entry.key] = entry.value - minLevel;
      }
    }
    return levels;
  }

  Map<int, List<_SpouseGroup>> _buildGroupsByLevel({
    required Set<String> component,
    required Map<String, int> levels,
    required Map<String, Set<String>> spousesByPerson,
    required Map<String, Set<String>> siblingsByPerson,
    required Map<String, Set<String>> parentToChildren,
    required Map<String, FamilyPerson> peopleById,
  }) {
    final groupsByLevel = <int, List<_SpouseGroup>>{};
    final grouped = <String>{};
    final ids = component.toList()
      ..sort((a, b) {
        final levelCompare = (levels[a] ?? 0).compareTo(levels[b] ?? 0);
        if (levelCompare != 0) {
          return levelCompare;
        }
        return _comparePersons(peopleById[a]!, peopleById[b]!);
      });

    for (final id in ids) {
      if (grouped.contains(id)) {
        continue;
      }
      final level = levels[id] ?? 0;
      final memberIds = <String>{id};
      final queue = <String>[id];
      while (queue.isNotEmpty) {
        final currentId = queue.removeAt(0);
        for (final spouseId in spousesByPerson[currentId] ?? const <String>{}) {
          if (!component.contains(spouseId) ||
              grouped.contains(spouseId) ||
              (levels[spouseId] ?? 0) != level) {
            continue;
          }
          if (memberIds.add(spouseId)) {
            queue.add(spouseId);
          }
        }
      }
      grouped.addAll(memberIds);
      final orderedIds = _orderedPartnerMemberIds(
        memberIds.toList(),
        peopleById,
      );
      groupsByLevel.putIfAbsent(level, () => <_SpouseGroup>[]).add(
            _SpouseGroup(memberIds: orderedIds),
          );
    }

    for (final groups in groupsByLevel.values) {
      groups.sort((a, b) {
        final aWeight = _groupDescendantWeight(a.memberIds, parentToChildren);
        final bWeight = _groupDescendantWeight(b.memberIds, parentToChildren);
        if (aWeight != bWeight) {
          return bWeight.compareTo(aWeight);
        }
        return _comparePersons(
          peopleById[a.memberIds.first]!,
          peopleById[b.memberIds.first]!,
        );
      });
    }
    return groupsByLevel;
  }

  double? _desiredCenterForGroup({
    required _SpouseGroup group,
    required Map<String, Offset> positions,
    required Map<String, Set<String>> childToParents,
    required Map<String, Set<String>> parentToChildren,
    required Map<String, Set<String>> siblingsByPerson,
    required Map<String, Set<String>> spousesByPerson,
  }) {
    final parentCenters = <double>[];
    for (final memberId in group.memberIds) {
      for (final parentId in childToParents[memberId] ?? const <String>{}) {
        final parentPosition = positions[parentId];
        if (parentPosition != null) {
          parentCenters.add(parentPosition.dx);
        }
      }
    }
    if (parentCenters.isNotEmpty) {
      return parentCenters.reduce((a, b) => a + b) / parentCenters.length;
    }

    final referenceCenters = <double>[];
    for (final memberId in group.memberIds) {
      for (final siblingId in siblingsByPerson[memberId] ?? const <String>{}) {
        final siblingPosition = positions[siblingId];
        if (siblingPosition != null) {
          referenceCenters.add(siblingPosition.dx);
        }
      }
      for (final childId in parentToChildren[memberId] ?? const <String>{}) {
        final childPosition = positions[childId];
        if (childPosition != null) {
          referenceCenters.add(childPosition.dx);
        }
      }
      // UX-T2: якорим группу к уже-размещённому супругу. Без этого нынешний
      // супруг (узел поколения-N), который при этом единственный родитель
      // ребёнка из N+1 без со-родителя, не имел ни одного reference-center
      // (родители/сиблинги/дети ещё/не размещены) и улетал в левый край.
      // Спутник из того же group ещё не размещён (positions[...] == null) —
      // тянет только реально расставленный супруг из соседней группы.
      for (final spouseId in spousesByPerson[memberId] ?? const <String>{}) {
        final spousePosition = positions[spouseId];
        if (spousePosition != null) {
          referenceCenters.add(spousePosition.dx);
        }
      }
    }

    // Snapshot-based anchor: when none of the explicit parent/child/sibling
    // edges resolve to a placed position (orphan in the graph — e.g. a
    // cousin added before her parents were even claimed), fall back to
    // any already-placed person in the SAME family unit. The backend
    // groups co-resident family members into a unit so we treat them
    // as anchors of last resort. This keeps a freshly-added cousin
    // from drifting to the far right of her row.
    if (referenceCenters.isEmpty && graphSnapshot != null) {
      for (final memberId in group.memberIds) {
        for (final unit in graphSnapshot!.familyUnits) {
          final inUnit = unit.adultIds.contains(memberId) ||
              unit.childIds.contains(memberId);
          if (!inUnit) continue;
          for (final relativeId in [...unit.adultIds, ...unit.childIds]) {
            if (relativeId == memberId) continue;
            final placed = positions[relativeId];
            if (placed != null) {
              referenceCenters.add(placed.dx);
            }
          }
        }
      }
    }

    if (referenceCenters.isEmpty) {
      return null;
    }
    return referenceCenters.reduce((a, b) => a + b) / referenceCenters.length;
  }

  void _centerParents(
    Map<String, Offset> positions,
    Map<int, List<_SpouseGroup>> groupsByLevel,
    Map<String, Set<String>> parentToChildren,
  ) {
    final levelOrder = groupsByLevel.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    for (final level in levelOrder) {
      for (final group in groupsByLevel[level] ?? const <_SpouseGroup>[]) {
        final childCenters = <double>[];
        for (final memberId in group.memberIds) {
          for (final childId
              in parentToChildren[memberId] ?? const <String>{}) {
            final childPosition = positions[childId];
            if (childPosition != null) {
              childCenters.add(childPosition.dx);
            }
          }
        }
        if (childCenters.isEmpty) {
          continue;
        }
        final currentCenter = group.memberIds
                .map((memberId) => positions[memberId]!.dx)
                .reduce((a, b) => a + b) /
            group.memberIds.length;
        final childCenter =
            childCenters.reduce((a, b) => a + b) / childCenters.length;
        final shift = childCenter - currentCenter;
        for (final memberId in group.memberIds) {
          final current = positions[memberId]!;
          positions[memberId] = Offset(current.dx + shift, current.dy);
        }
      }
    }
  }

  /// Tidy-tree post-pass that recomputes X so every parent group's children
  /// form a single CONTIGUOUS, non-overlapping block centered under the
  /// parents, with sibling families ≥ [siblingSeparation] apart.
  ///
  /// Fixes branch interleaving: the flat per-level placement reserved no
  /// horizontal room for whole subtrees, so a wide/deep subtree — or the
  /// spouse-anchor in [_desiredCenterForGroup] averaging across BOTH spouses'
  /// parent families — could scatter one pair's children into a neighbour's
  /// child-bus span (a child then looked like it belonged to two couples).
  ///
  /// Every spouse group is assigned to exactly ONE primary parent group
  /// (the family with the most parent links into it; ties broken left-most),
  /// so subtree widths can be reserved without a child belonging to two
  /// blocks. Children order by a structural key (descendant weight, B4); a
  /// bridge child biases to the block edge toward its other family. Width is
  /// reserved bottom-up, positions assigned top-down.
  ///
  /// A couple that bridges TWO parent families (the blended case — each spouse
  /// has their own ancestors) is nudged toward the midpoint of both so it
  /// straddles them instead of floating under one with a long cross-link. The
  /// nudge is UNCLAMPED; a left→right separation sweep per level (deepest
  /// first) then guarantees no two subtrees overlap — so no foreign child can
  /// land inside another pair's child-bus span (B2, safe by construction). The
  /// two iterate to convergence. False roots (B3) are reseeded near their
  /// parents. Levels (Y) are preserved; only X is rewritten.
  void _enforceContiguousSubtreeBlocks(
    Map<String, Offset> positions,
    Map<int, List<_SpouseGroup>> groupsByLevel,
    Map<String, Set<String>> childToParents,
    Map<String, Set<String>> parentToChildren,
    Map<String, FamilyPerson> peopleById, {
    required double componentStartX,
  }) {
    final allGroups = <_SpouseGroup>[];
    final levelOfGroup = <_SpouseGroup, int>{};
    final groupOfMember = <String, _SpouseGroup>{};
    groupsByLevel.forEach((level, groups) {
      for (final group in groups) {
        allGroups.add(group);
        levelOfGroup[group] = level;
        for (final memberId in group.memberIds) {
          groupOfMember[memberId] = group;
        }
      }
    });
    if (allGroups.isEmpty) {
      return;
    }

    double groupCenterX(_SpouseGroup group) =>
        group.memberIds
            .map((memberId) => positions[memberId]!.dx)
            .reduce((a, b) => a + b) /
        group.memberIds.length;

    // 1) Assign each group to a single primary parent group + collect kids.
    //    Also record ALL resolved parent families per group: a group with 2+
    //    is a BRIDGE (blended/cross case) and is ordered to the edge of its
    //    block toward its other family (step 2) so it can straddle. A group
    //    that references parents but resolves NONE is a FALSE root (B3) —
    //    reseeded near its parents in step 5 instead of dumped far-left.
    final childGroups = <_SpouseGroup, List<_SpouseGroup>>{};
    final primaryParent = <_SpouseGroup, _SpouseGroup?>{};
    final parentFamiliesOf = <_SpouseGroup, List<_SpouseGroup>>{};
    final falseRootParentIds = <_SpouseGroup, Set<String>>{};
    for (final group in allGroups) {
      final groupLevel = levelOfGroup[group]!;
      final linkCounts = <_SpouseGroup, int>{};
      final referencedParentIds = <String>{};
      for (final memberId in group.memberIds) {
        for (final parentId in childToParents[memberId] ?? const <String>{}) {
          if (group.memberIds.contains(parentId)) continue; // self/spouse edge
          referencedParentIds.add(parentId);
          final parentGroup = groupOfMember[parentId];
          if (parentGroup == null) continue;
          final parentLevel = levelOfGroup[parentGroup];
          // Parents must live on a shallower level — guards against cycles
          // and same-level spouse edges masquerading as parentage.
          if (parentLevel == null || parentLevel >= groupLevel) continue;
          linkCounts[parentGroup] = (linkCounts[parentGroup] ?? 0) + 1;
        }
      }
      _SpouseGroup? primary;
      if (linkCounts.isNotEmpty) {
        final entries = linkCounts.entries.toList()
          ..sort((a, b) {
            if (a.value != b.value) return b.value.compareTo(a.value);
            return groupCenterX(a.key).compareTo(groupCenterX(b.key));
          });
        primary = entries.first.key;
        parentFamiliesOf[group] = entries.map((e) => e.key).toList();
      }
      primaryParent[group] = primary;
      if (primary != null) {
        childGroups.putIfAbsent(primary, () => <_SpouseGroup>[]).add(group);
      } else if (referencedParentIds.isNotEmpty) {
        falseRootParentIds[group] = referencedParentIds;
      }
    }

    // 2) Order each parent's children by a STRUCTURAL key, not the greedy
    //    groupCenterX from the prior passes (B4 — that inherited the very
    //    interleave drift we're fixing and was non-deterministic). A bridge
    //    child is biased to the block EDGE toward its OTHER parent family so it
    //    can straddle (the side it must reach); the rest order by descendant
    //    weight (heaviest first) then a stable person compare, matching the
    //    convention already used in _buildGroupsByLevel.
    childGroups.forEach((family, kids) {
      final familyX = groupCenterX(family);
      double bridgeSide(_SpouseGroup child) {
        final families = parentFamiliesOf[child];
        if (families == null || families.length < 2) return 0;
        final others = families.where((g) => g != family).toList();
        if (others.isEmpty) return 0;
        final othersMean =
            others.map(groupCenterX).reduce((a, b) => a + b) / others.length;
        return (othersMean - familyX).sign;
      }

      kids.sort((a, b) {
        final sideCompare = bridgeSide(a).compareTo(bridgeSide(b));
        if (sideCompare != 0) return sideCompare;
        final aWeight = _groupDescendantWeight(a.memberIds, parentToChildren);
        final bWeight = _groupDescendantWeight(b.memberIds, parentToChildren);
        if (aWeight != bWeight) return bWeight.compareTo(aWeight);
        return _comparePersons(
          peopleById[a.memberIds.first]!,
          peopleById[b.memberIds.first]!,
        );
      });
    });

    // 3) Reserve subtree width bottom-up.
    final widthOf = <_SpouseGroup, double>{};
    final levelsDeepFirst = groupsByLevel.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    for (final level in levelsDeepFirst) {
      for (final group in groupsByLevel[level] ?? const <_SpouseGroup>[]) {
        final ownWidth = _groupWidth(group.memberIds.length);
        final kids = childGroups[group] ?? const <_SpouseGroup>[];
        if (kids.isEmpty) {
          widthOf[group] = ownWidth;
          continue;
        }
        var kidsWidth = 0.0;
        for (var i = 0; i < kids.length; i++) {
          kidsWidth +=
              widthOf[kids[i]] ?? _groupWidth(kids[i].memberIds.length);
          if (i < kids.length - 1) {
            kidsWidth += InteractiveFamilyTree.siblingSeparation;
          }
        }
        widthOf[group] = max(ownWidth, kidsWidth);
      }
    }

    // 4) Assign X top-down: center each group over its reserved block and lay
    //    its children block contiguously beneath it.
    final placed = <_SpouseGroup>{};
    void placeSubtree(_SpouseGroup group, double leftEdge) {
      if (!placed.add(group)) return; // forest is acyclic; guard anyway
      final width = widthOf[group]!;
      final center = leftEdge + width / 2;
      final ordered = [...group.memberIds]
        ..sort((a, b) => positions[a]!.dx.compareTo(positions[b]!.dx));
      final ownWidth = _groupWidth(ordered.length);
      for (var i = 0; i < ordered.length; i++) {
        final memberId = ordered[i];
        final x = center -
            ownWidth / 2 +
            InteractiveFamilyTree.nodeWidth / 2 +
            i *
                (InteractiveFamilyTree.nodeWidth +
                    InteractiveFamilyTree.spouseSeparation);
        positions[memberId] = Offset(x, positions[memberId]!.dy);
      }
      final kids = childGroups[group] ?? const <_SpouseGroup>[];
      if (kids.isEmpty) return;
      var kidsWidth = 0.0;
      for (var i = 0; i < kids.length; i++) {
        kidsWidth += widthOf[kids[i]]!;
        if (i < kids.length - 1) {
          kidsWidth += InteractiveFamilyTree.siblingSeparation;
        }
      }
      var childLeft = center - kidsWidth / 2;
      for (final child in kids) {
        placeSubtree(child, childLeft);
        childLeft += widthOf[child]! + InteractiveFamilyTree.siblingSeparation;
      }
    }

    final roots = allGroups.where((g) => primaryParent[g] == null).toList()
      ..sort((a, b) {
        final levelCompare = levelOfGroup[a]!.compareTo(levelOfGroup[b]!);
        if (levelCompare != 0) return levelCompare;
        return groupCenterX(a).compareTo(groupCenterX(b));
      });
    var cursor = componentStartX;
    for (final root in roots) {
      placeSubtree(root, cursor);
      cursor += widthOf[root]! + InteractiveFamilyTree.siblingSeparation;
    }
    // Defensive: place any group the root forest didn't reach (disconnected
    // primary-parent chain) so nothing keeps a stale X.
    for (final group in allGroups) {
      if (placed.contains(group)) continue;
      placeSubtree(group, cursor);
      cursor += widthOf[group]! + InteractiveFamilyTree.siblingSeparation;
    }

    // Subtree helpers shared by the recenter, reseed and sweep below.
    List<String> subtreeMembers(_SpouseGroup group) {
      final out = <String>[];
      final stack = <_SpouseGroup>[group];
      final seen = <_SpouseGroup>{};
      while (stack.isNotEmpty) {
        final current = stack.removeLast();
        if (!seen.add(current)) continue;
        out.addAll(current.memberIds);
        stack.addAll(childGroups[current] ?? const <_SpouseGroup>[]);
      }
      return out;
    }

    List<double> subtreeExtent(_SpouseGroup group) {
      var lo = double.infinity;
      var hi = double.negativeInfinity;
      for (final memberId in subtreeMembers(group)) {
        final x = positions[memberId]!.dx;
        lo = min(lo, x - InteractiveFamilyTree.nodeWidth / 2);
        hi = max(hi, x + InteractiveFamilyTree.nodeWidth / 2);
      }
      return <double>[lo, hi];
    }

    void shiftSubtree(_SpouseGroup group, double shift) {
      if (shift.abs() < 0.5) return;
      for (final memberId in subtreeMembers(group)) {
        final current = positions[memberId]!;
        positions[memberId] = Offset(current.dx + shift, current.dy);
      }
    }

    // 5) Orphan reseed (B3): a false root (parents referenced but none
    //    resolved to a placed group) was laid out at the component's far-left
    //    corner. Pull its subtree to the mean X of whatever parents ARE
    //    positioned. The sweep below resolves any overlap this introduces.
    falseRootParentIds.forEach((group, parentIds) {
      final parentXs =
          parentIds.map((id) => positions[id]?.dx).whereType<double>().toList();
      if (parentXs.isEmpty) return;
      final target = parentXs.reduce((a, b) => a + b) / parentXs.length;
      shiftSubtree(group, target - groupCenterX(group));
    });

    // 6) Bridge recenter + separation sweep (B2). A bridge couple sits at the
    //    edge of its primary block (step 2) toward its other parent family;
    //    nudge it + its subtree toward the midpoint of its parent families so
    //    it STRADDLES them. The nudge is UNCLAMPED — instead of the old fragile
    //    immediate-neighbour clamp, a final left→right separation sweep per
    //    level makes it safe BY CONSTRUCTION: no two subtrees overlap, so no
    //    foreign child can land inside another pair's child-bus span. The sweep
    //    settles families, so we iterate {sweep → recentre bridges} until the
    //    inter-family gap opens and the midpoint stops moving (converges fast),
    //    then sweep once more so the invariant holds after the last recentre.
    final bridges = parentFamiliesOf.entries
        .where((e) => e.value.length >= 2)
        .map((e) => e.key)
        .toList()
      ..sort((a, b) => levelOfGroup[a]!.compareTo(levelOfGroup[b]!));
    final sweepLevelsDeepFirst = groupsByLevel.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    void separationSweep() {
      for (final level in sweepLevelsDeepFirst) {
        final ordered = [...(groupsByLevel[level] ?? const <_SpouseGroup>[])]
          ..sort((a, b) => subtreeExtent(a)[0].compareTo(subtreeExtent(b)[0]));
        var runningRight = double.negativeInfinity;
        for (final group in ordered) {
          final extent = subtreeExtent(group);
          if (runningRight.isFinite &&
              extent[0] <
                  runningRight + InteractiveFamilyTree.siblingSeparation) {
            shiftSubtree(
              group,
              runningRight +
                  InteractiveFamilyTree.siblingSeparation -
                  extent[0],
            );
          }
          runningRight = subtreeExtent(group)[1];
        }
      }
    }

    for (var iteration = 0; iteration < 4; iteration++) {
      for (final bridge in bridges) {
        final centers = parentFamiliesOf[bridge]!.map(groupCenterX).toList();
        final mid = centers.reduce((a, b) => a + b) / centers.length;
        shiftSubtree(bridge, mid - groupCenterX(bridge));
      }
      separationSweep();
    }
  }

  void _normalizeGroups(
    Map<String, Offset> positions,
    Map<int, List<_SpouseGroup>> groupsByLevel, {
    required Map<String, int> levels,
    required Map<String, Set<String>> childToParents,
    required Map<String, Set<String>> parentToChildren,
    required Map<String, Set<String>> siblingsByPerson,
    required Map<String, FamilyPerson> peopleById,
    required double componentStartX,
  }) {
    for (final entry in groupsByLevel.entries) {
      final level = entry.key;
      final groups = entry.value
        ..sort((a, b) {
          final aCenter = a.memberIds
                  .map((memberId) => positions[memberId]!.dx)
                  .reduce((x, y) => x + y) /
              a.memberIds.length;
          final bCenter = b.memberIds
                  .map((memberId) => positions[memberId]!.dx)
                  .reduce((x, y) => x + y) /
              b.memberIds.length;
          return aCenter.compareTo(bCenter);
        });

      double currentLeft = componentStartX;
      for (final group in groups) {
        final orderedMemberIds = _orientedMemberIds(
          memberIds: group.memberIds,
          level: level,
          positions: positions,
          levels: levels,
          childToParents: childToParents,
          parentToChildren: parentToChildren,
          siblingsByPerson: siblingsByPerson,
          peopleById: peopleById,
        );
        final groupWidth = _groupWidth(orderedMemberIds.length);
        final currentCenter = orderedMemberIds
                .map((memberId) => positions[memberId]!.dx)
                .reduce((x, y) => x + y) /
            orderedMemberIds.length;
        final left = max(currentLeft, currentCenter - groupWidth / 2);
        for (var index = 0; index < orderedMemberIds.length; index++) {
          final memberId = orderedMemberIds[index];
          final current = positions[memberId]!;
          final x = left +
              InteractiveFamilyTree.nodeWidth / 2 +
              index *
                  (InteractiveFamilyTree.nodeWidth +
                      InteractiveFamilyTree.spouseSeparation);
          positions[memberId] = Offset(x, current.dy);
        }
        currentLeft =
            left + groupWidth + InteractiveFamilyTree.siblingSeparation;
      }
    }
  }

  void _anchorComponentToStart(
    Map<String, Offset> positions, {
    required double componentStartX,
  }) {
    if (positions.isEmpty) {
      return;
    }
    final currentLeft = positions.values
        .map((position) => position.dx - InteractiveFamilyTree.nodeWidth / 2)
        .reduce(min);
    final shift = componentStartX - currentLeft;
    if (shift.abs() < 0.1) {
      return;
    }
    for (final entry in positions.entries.toList(growable: false)) {
      positions[entry.key] = Offset(entry.value.dx + shift, entry.value.dy);
    }
  }

  List<String> _orientedMemberIds({
    required List<String> memberIds,
    required int level,
    required Map<String, Offset> positions,
    required Map<String, int> levels,
    required Map<String, Set<String>> childToParents,
    required Map<String, Set<String>> parentToChildren,
    required Map<String, Set<String>> siblingsByPerson,
    required Map<String, FamilyPerson> peopleById,
  }) {
    final baseOrderedMemberIds = _orderedPartnerMemberIds(
      memberIds,
      peopleById,
    );
    if (baseOrderedMemberIds.length <= 1) {
      return baseOrderedMemberIds;
    }

    int lineageScore(String memberId) {
      final previousLevelParents =
          (childToParents[memberId] ?? const <String>{})
              .where((parentId) => levels[parentId] == level - 1)
              .length;
      final nextLevelChildren = (parentToChildren[memberId] ?? const <String>{})
          .where((childId) => levels[childId] == level + 1)
          .length;
      final allChildren =
          (parentToChildren[memberId] ?? const <String>{}).length;
      return previousLevelParents * 100 + nextLevelChildren * 10 + allChildren;
    }

    final scores = <String, int>{
      for (final memberId in baseOrderedMemberIds)
        memberId: lineageScore(memberId),
    };
    final highestScore = scores.values.reduce(max);
    final primaryMembers = baseOrderedMemberIds
        .where((memberId) => scores[memberId] == highestScore)
        .toList();
    final familyReferenceCenters = <String, double?>{
      for (final memberId in baseOrderedMemberIds)
        memberId: _memberPreferredReferenceCenter(
          memberId: memberId,
          level: level,
          positions: positions,
          levels: levels,
          childToParents: childToParents,
          parentToChildren: parentToChildren,
          siblingsByPerson: siblingsByPerson,
        ),
    };
    final anchoredMembers = baseOrderedMemberIds
        .where((memberId) => familyReferenceCenters[memberId] != null)
        .toList();

    if (anchoredMembers.length > 1) {
      final baseIndexes = <String, int>{
        for (var index = 0; index < baseOrderedMemberIds.length; index++)
          baseOrderedMemberIds[index]: index,
      };
      final hasDistinctReferenceCenters = anchoredMembers
              .map((memberId) => familyReferenceCenters[memberId]!)
              .toSet()
              .length >
          1;
      if (hasDistinctReferenceCenters) {
        final orientedIds = [...baseOrderedMemberIds];
        orientedIds.sort((left, right) {
          final leftCenter = familyReferenceCenters[left];
          final rightCenter = familyReferenceCenters[right];
          if (leftCenter != null &&
              rightCenter != null &&
              (leftCenter - rightCenter).abs() > 0.1) {
            return leftCenter.compareTo(rightCenter);
          }
          return (baseIndexes[left] ?? 0).compareTo(baseIndexes[right] ?? 0);
        });
        return orientedIds;
      }
    }

    if (highestScore <= 0 || primaryMembers.length != 1) {
      return baseOrderedMemberIds;
    }

    final primaryMemberId = primaryMembers.single;
    final primaryReferenceCenter = familyReferenceCenters[primaryMemberId];
    if (primaryReferenceCenter == null) {
      return baseOrderedMemberIds;
    }
    final groupCenter = baseOrderedMemberIds
            .map((memberId) => positions[memberId]?.dx)
            .whereType<double>()
            .fold<double>(0, (sum, value) => sum + value) /
        baseOrderedMemberIds.length;
    if ((primaryReferenceCenter - groupCenter).abs() <= 0.1) {
      return baseOrderedMemberIds;
    }
    final otherMemberIds = baseOrderedMemberIds
        .where((memberId) => memberId != primaryMemberId)
        .toList();

    if (primaryReferenceCenter < groupCenter) {
      return <String>[primaryMemberId, ...otherMemberIds];
    }
    return <String>[...otherMemberIds, primaryMemberId];
  }

  double? _memberPreferredReferenceCenter({
    required String memberId,
    required int level,
    required Map<String, Offset> positions,
    required Map<String, int> levels,
    required Map<String, Set<String>> childToParents,
    required Map<String, Set<String>> parentToChildren,
    required Map<String, Set<String>> siblingsByPerson,
  }) {
    final siblingCenter = _memberSiblingReferenceCenter(
      memberId: memberId,
      level: level,
      positions: positions,
      levels: levels,
      siblingsByPerson: siblingsByPerson,
    );
    if (siblingCenter != null) {
      return siblingCenter;
    }
    final parentCenter = _memberParentReferenceCenter(
      memberId: memberId,
      level: level,
      positions: positions,
      levels: levels,
      childToParents: childToParents,
    );
    if (parentCenter != null) {
      return parentCenter;
    }
    return _memberChildReferenceCenter(
      memberId: memberId,
      level: level,
      positions: positions,
      levels: levels,
      parentToChildren: parentToChildren,
    );
  }

  double? _memberParentReferenceCenter({
    required String memberId,
    required int level,
    required Map<String, Offset> positions,
    required Map<String, int> levels,
    required Map<String, Set<String>> childToParents,
  }) {
    final referenceCenters = <double>[];
    for (final parentId in childToParents[memberId] ?? const <String>{}) {
      if (levels[parentId] != level - 1) {
        continue;
      }
      final parentPosition = positions[parentId];
      if (parentPosition != null) {
        referenceCenters.add(parentPosition.dx);
      }
    }
    if (referenceCenters.isEmpty) {
      return null;
    }
    return referenceCenters.reduce((a, b) => a + b) / referenceCenters.length;
  }

  double? _memberSiblingReferenceCenter({
    required String memberId,
    required int level,
    required Map<String, Offset> positions,
    required Map<String, int> levels,
    required Map<String, Set<String>> siblingsByPerson,
  }) {
    final referenceCenters = <double>[];
    for (final siblingId in siblingsByPerson[memberId] ?? const <String>{}) {
      if (levels[siblingId] != level) {
        continue;
      }
      final siblingPosition = positions[siblingId];
      if (siblingPosition != null) {
        referenceCenters.add(siblingPosition.dx);
      }
    }
    if (referenceCenters.isEmpty) {
      return null;
    }
    return referenceCenters.reduce((a, b) => a + b) / referenceCenters.length;
  }

  double? _memberChildReferenceCenter({
    required String memberId,
    required int level,
    required Map<String, Offset> positions,
    required Map<String, int> levels,
    required Map<String, Set<String>> parentToChildren,
  }) {
    final referenceCenters = <double>[];
    for (final childId in parentToChildren[memberId] ?? const <String>{}) {
      if (levels[childId] != level + 1) {
        continue;
      }
      final childPosition = positions[childId];
      if (childPosition != null) {
        referenceCenters.add(childPosition.dx);
      }
    }
    if (referenceCenters.isEmpty) {
      return null;
    }
    return referenceCenters.reduce((a, b) => a + b) / referenceCenters.length;
  }

  List<String> _orderedPartnerMemberIds(
    List<String> memberIds,
    Map<String, FamilyPerson> peopleById,
  ) {
    final orderedIds = [...memberIds];
    orderedIds.sort((left, right) {
      final leftRank = _partnerGenderSortWeight(peopleById[left]?.gender);
      final rightRank = _partnerGenderSortWeight(peopleById[right]?.gender);
      if (leftRank != rightRank) {
        return leftRank.compareTo(rightRank);
      }
      return _comparePersons(peopleById[left]!, peopleById[right]!);
    });
    return orderedIds;
  }

  int _partnerGenderSortWeight(Gender? gender) {
    switch (gender) {
      case Gender.male:
        return 0;
      case Gender.female:
        return 1;
      case Gender.other:
        return 2;
      case Gender.unknown:
      case null:
        return 3;
    }
  }

  List<FamilyConnection> _buildConnections(
    List<FamilyRelation> relations,
    Map<String, Offset> positions,
  ) {
    final connections = <FamilyConnection>[];
    final spousePairs = <String>{};
    final parentChildPairs = <String>{};

    String parentChildKey(String parentId, String childId) =>
        '$parentId::$childId';
    String spousePairKey(String a, String b) {
      final pair = [a, b]..sort();
      return pair.join('::');
    }

    for (final relation in relations) {
      final parentId = _parentIdFromRelation(relation);
      final childId = _childIdFromRelation(relation);
      if (parentId != null &&
          childId != null &&
          positions.containsKey(parentId) &&
          positions.containsKey(childId)) {
        if (parentChildPairs.add(parentChildKey(parentId, childId))) {
          connections.add(
            FamilyConnection(
              fromId: parentId,
              toId: childId,
              type: RelationType.parent,
            ),
          );
        }
        continue;
      }
      if (_isSpouseRelation(relation) &&
          positions.containsKey(relation.person1Id) &&
          positions.containsKey(relation.person2Id)) {
        final pairKey = spousePairKey(relation.person1Id, relation.person2Id);
        if (spousePairs.add(pairKey)) {
          final pair = [relation.person1Id, relation.person2Id]..sort();
          connections.add(
            FamilyConnection(
              fromId: pair.first,
              toId: pair.last,
              type: RelationType.spouse,
              isPastUnion: _isPastUnionRelation(relation),
            ),
          );
        }
      }
    }

    // Enrich connection lines from snapshot family units. Without this,
    // distant relatives the user adds via "cousin" / "aunt" / "niece"
    // relation types end up positioned correctly (because we already
    // enrich the layout adjacency from the same source) but with no
    // visible line connecting them to their parents — they appear as
    // floating cards. Drawing the parent → child line from the family
    // unit closes the loop.
    final snapshot = graphSnapshot;
    if (snapshot != null) {
      for (final unit in snapshot.familyUnits) {
        final adultIds =
            unit.adultIds.where(positions.containsKey).toList(growable: false);
        final childIds =
            unit.childIds.where(positions.containsKey).toList(growable: false);

        for (var i = 0; i < adultIds.length; i++) {
          for (var j = i + 1; j < adultIds.length; j++) {
            final a = adultIds[i];
            final b = adultIds[j];
            final key = spousePairKey(a, b);
            if (spousePairs.add(key)) {
              final pair = [a, b]..sort();
              connections.add(
                FamilyConnection(
                  fromId: pair.first,
                  toId: pair.last,
                  type: RelationType.spouse,
                  isPastUnion: _isInactiveUnionStatus(unit.unionStatus),
                ),
              );
            }
          }
        }

        for (final adultId in adultIds) {
          for (final childId in childIds) {
            if (parentChildPairs.add(parentChildKey(adultId, childId))) {
              connections.add(
                FamilyConnection(
                  fromId: adultId,
                  toId: childId,
                  type: RelationType.parent,
                ),
              );
            }
          }
        }
      }
    }

    return connections;
  }

  bool _isSpouseRelation(FamilyRelation relation) {
    return relation.relation1to2 == RelationType.spouse ||
        relation.relation2to1 == RelationType.spouse ||
        relation.relation1to2 == RelationType.partner ||
        relation.relation2to1 == RelationType.partner ||
        _isPastUnionRelation(relation);
  }

  /// F2: бывший союз — ex-тип связи либо проставленная дата развода.
  /// Та же логика, что у бэкового normalizeUnionStatus.
  bool _isPastUnionRelation(FamilyRelation relation) {
    return relation.relation1to2 == RelationType.ex_spouse ||
        relation.relation2to1 == RelationType.ex_spouse ||
        relation.relation1to2 == RelationType.ex_partner ||
        relation.relation2to1 == RelationType.ex_partner ||
        _isInactiveUnionStatus(relation.unionStatus) ||
        relation.divorceDate != null;
  }

  bool _isSiblingRelation(FamilyRelation relation) {
    return relation.relation1to2 == RelationType.sibling ||
        relation.relation2to1 == RelationType.sibling;
  }

  String? _parentIdFromRelation(FamilyRelation relation) {
    if (relation.relation1to2 == RelationType.parent ||
        relation.relation2to1 == RelationType.child) {
      return relation.person1Id;
    }
    if (relation.relation2to1 == RelationType.parent ||
        relation.relation1to2 == RelationType.child) {
      return relation.person2Id;
    }
    return null;
  }

  String? _childIdFromRelation(FamilyRelation relation) {
    if (relation.relation1to2 == RelationType.parent ||
        relation.relation2to1 == RelationType.child) {
      return relation.person2Id;
    }
    if (relation.relation2to1 == RelationType.parent ||
        relation.relation1to2 == RelationType.child) {
      return relation.person1Id;
    }
    return null;
  }

  int _comparePersons(FamilyPerson a, FamilyPerson b) {
    final nameCompare = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (nameCompare != 0) {
      return nameCompare;
    }
    return a.id.compareTo(b.id);
  }

  double _groupWidth(int membersCount) {
    return membersCount * InteractiveFamilyTree.nodeWidth +
        (membersCount - 1) * InteractiveFamilyTree.spouseSeparation;
  }

  int _groupDescendantWeight(
    List<String> memberIds,
    Map<String, Set<String>> parentToChildren,
  ) {
    final visited = <String>{};
    final queue = <String>[...memberIds];
    while (queue.isNotEmpty) {
      final currentId = queue.removeLast();
      for (final childId in parentToChildren[currentId] ?? const <String>{}) {
        if (visited.add(childId)) {
          queue.add(childId);
        }
      }
    }
    return visited.length;
  }
}
