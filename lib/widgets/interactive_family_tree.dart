import 'package:flutter/material.dart';
import 'dart:math'; // <--- Добавляем импорт для функции min
import 'package:graphview/GraphView.dart';
import '../models/family_person.dart';
import '../models/family_relation.dart';
import '../models/user_profile.dart';

// Структура для хранения информации о связях для отрисовки
class FamilyConnection {
  final String fromId;
  final String toId;
  final RelationType type; // Добавляем тип связи
  
  FamilyConnection({required this.fromId, required this.toId, required this.type});
}

class InteractiveFamilyTree extends StatefulWidget {
  final List<Map<String, dynamic>> peopleData; // Теперь содержит {'person': FamilyPerson, 'userProfile': UserProfile?}
  final List<FamilyRelation> relations;
  final Function(FamilyPerson) onPersonTap; // Коллбэк при нажатии на узел
  final bool isEditMode; // Флаг режима редактирования
  final void Function(FamilyPerson person, RelationType type) onAddRelativeTapWithType; // Коллбэк для добавления
  final bool currentUserIsInTree; // <<< НОВЫЙ ПАРАМЕТР: Флаг, добавлен ли текущий пользователь
  final void Function(FamilyPerson targetPerson, RelationType relationType) onAddSelfTapWithType; // <<< НОВЫЙ ПАРАМЕТР: Коллбэк для добавления себя

  // Константы для размеров узлов и отступов - понадобятся для расчета layout
  static const double nodeWidth = 120; // Примерная ширина карточки
  static const double nodeHeight = 100; // Примерная высота карточки
  static const double levelSeparation = 80; // Вертикальное расстояние между уровнями
  static const double siblingSeparation = 40; // Горизонтальное расстояние между братьями/сестрами
  static const double spouseSeparation = 20; // Горизонтальное расстояние между супругами
  
  const InteractiveFamilyTree({
    Key? key,
    required this.peopleData,
    required this.relations,
    required this.onPersonTap,
    this.isEditMode = false, // По умолчанию выключен
    required this.onAddRelativeTapWithType,
    required this.currentUserIsInTree, // Делаем обязательным
    required this.onAddSelfTapWithType, // Делаем обязательным
  }) : super(key: key);

  @override
  State<InteractiveFamilyTree> createState() => _InteractiveFamilyTreeState();
}

class _InteractiveFamilyTreeState extends State<InteractiveFamilyTree> {
  // Данные для CustomPainter
  Map<String, Offset> nodePositions = {}; // ID человека -> его позиция (центр)
  List<FamilyConnection> connections = []; // Список связей для отрисовки линий
  Size treeSize = Size.zero; // Общий размер дерева для CustomPaint и Stack

  @override
  void initState() {
    super.initState();
    _calculateLayout(); // Вызываем расчет layout
  }
  
  @override
  void didUpdateWidget(InteractiveFamilyTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.peopleData != widget.peopleData || 
        oldWidget.relations != widget.relations) {
      _calculateLayout(); // Пересчитываем layout при изменении данных
    }
  }
  
  // Метод для расчета позиций узлов и связей
  void _calculateLayout() {
    if (widget.peopleData.isEmpty) {
      setState(() {
        nodePositions = {};
        connections = [];
        treeSize = Size.zero;
      });
      return;
    }

    // --- Шаг 1: Подготовка данных и определение поколений --- 
    final Map<String, List<String>> parentToChildrenMap = {};
    final Map<String, List<String>> childToParentsMap = {};
    final Map<String, List<String>> spouseMap = {}; // Карта супругов (id -> список супругов)
    final Set<String> personIds = widget.peopleData.map((d) => (d['person'] as FamilyPerson).id).toSet();

    for (var relation in widget.relations) {
      final p1Id = relation.person1Id;
      final p2Id = relation.person2Id;

      // Убедимся, что оба ID существуют в peopleData
      if (!personIds.contains(p1Id) || !personIds.contains(p2Id)) continue;

      if (relation.relation1to2 == RelationType.parent) { // p1 родитель p2
        parentToChildrenMap.putIfAbsent(p1Id, () => []).add(p2Id);
        childToParentsMap.putIfAbsent(p2Id, () => []).add(p1Id);
      } else if (relation.relation1to2 == RelationType.child) { // p1 ребенок p2
        parentToChildrenMap.putIfAbsent(p2Id, () => []).add(p1Id);
        childToParentsMap.putIfAbsent(p1Id, () => []).add(p2Id);
      } else if (relation.relation1to2 == RelationType.spouse) { // Супруги
        spouseMap.putIfAbsent(p1Id, () => []).add(p2Id);
        spouseMap.putIfAbsent(p2Id, () => []).add(p1Id);
      }
    }

    // --- Улучшенная логика определения корней --- 
    final List<String> roots = [];
    final Set<String> nonRoots = {}; 

    for (final id in personIds) {
      if (nonRoots.contains(id)) continue;

      bool hasParents = childToParentsMap.containsKey(id) && childToParentsMap[id]!.isNotEmpty;
      bool hasSpouseWithParents = false;
      final spouses = spouseMap[id] ?? [];
      for (final spouseId in spouses) {
        if (childToParentsMap.containsKey(spouseId) && childToParentsMap[spouseId]!.isNotEmpty) {
          hasSpouseWithParents = true;
          nonRoots.add(spouseId);
          break; 
        }
      }

      if (!hasParents && !hasSpouseWithParents) {
        roots.add(id);
      } else {
        nonRoots.add(id);
      }
    }
    // --- Конец улучшенной логики --- 

    final Map<String, int> nodeLevels = {}; // Объявляем здесь
    final Set<String> visited = {};
    final Map<String, int> queue = {};
    final Set<String> processing = {}; 

    // Начальная инициализация для корней
    for (final rootId in roots) {
      if (!processing.contains(rootId)) {
         queue[rootId] = 0;
         processing.add(rootId);
      }
    }

    // Добавляем все остальные узлы с высоким уровнем
    for (final personId in personIds) {
        if (!processing.contains(personId)) { 
            queue[personId] = 10000;
            processing.add(personId);
        }
    }

    // BFS для определения уровней
    while (queue.isNotEmpty) {
      String currentId = '';
      int minLevelInQueue = 1000000; 
      queue.forEach((id, level) {
         if (level < minLevelInQueue) {
            minLevelInQueue = level;
            currentId = id;
         }
      });
      
      if (currentId.isEmpty && queue.isNotEmpty) {
          break; 
      }
      if (currentId.isEmpty) break; 

      final currentLevel = queue.remove(currentId)!;
      nodeLevels[currentId] = currentLevel; 
      visited.add(currentId);
      processing.remove(currentId); 

      // --- Обрабатываем ДЕТЕЙ ---
          final children = parentToChildrenMap[currentId] ?? [];
          for (final childId in children) {
        final newChildLevel = currentLevel + 1;
            if (!visited.contains(childId)) {
            if (processing.contains(childId)) {
                if (newChildLevel < queue[childId]!) {
                    queue[childId] = newChildLevel;
                }
            } else {
                queue[childId] = newChildLevel;
                processing.add(childId);
            }
        }
      }

      // --- Обрабатываем СУПРУГОВ ---
          final currentSpouses = spouseMap[currentId] ?? [];
          for (final spouseId in currentSpouses) {
         final newSpouseLevel = currentLevel; 
            if (!visited.contains(spouseId)) {
             if (processing.contains(spouseId)) {
                 if (newSpouseLevel < queue[spouseId]!) {
                     queue[spouseId] = newSpouseLevel;
                 } else if (newSpouseLevel > queue[spouseId]!) {
                 }
             } else {
                 queue[spouseId] = newSpouseLevel;
                 processing.add(spouseId);
             }
         } else {
         }
      }
    } 

    // --- Шаг 2: Расчет X и Y координат --- 
    final Map<int, List<String>> nodesByLevel = {};
    int maxLevel = 0;
    nodeLevels.forEach((nodeId, level) {
      if (level < 0) { 
          level = 0; 
          nodeLevels[nodeId] = 0;
      }
      nodesByLevel.putIfAbsent(level, () => []).add(nodeId);
      if (level > maxLevel) {
        maxLevel = level;
      }
    });

    Map<String, Offset> currentPositions = _performInitialXLayout(
        maxLevel,
        nodesByLevel,
        spouseMap,
        nodeLevels,
        childToParentsMap
    );

    // --- Итеративная корректировка для центрирования детей --- 
    int iterations = 20; // Увеличиваем количество итераций
    double adjustmentFactor = 0.5; // Ослабляем корректировку

    for (int i = 0; i < iterations; i++) {
        Map<String, Offset> nextPositions = Map.from(currentPositions);
        for (int level = maxLevel - 1; level >= 0; level--) {
            final levelNodes = nodesByLevel[level] ?? [];
            for (final nodeId in levelNodes) {
                 final parentPos = currentPositions[nodeId];
                 if (parentPos == null) continue;

                 final children = parentToChildrenMap[nodeId] ?? [];
                 final childrenOnNextLevel = children
                     .where((childId) => nodeLevels.containsKey(childId) && nodeLevels[childId] == level + 1)
                     .toList();
                 
                 if (childrenOnNextLevel.isEmpty) continue;

                 // --- Улучшенный расчет центра детей: среднее арифметическое --- 
                 double childrenSumX = 0;
                 int validChildrenCount = 0;
                 for (final childId in childrenOnNextLevel) {
                    final childPos = currentPositions[childId];
                    if (childPos != null) {
                       childrenSumX += childPos.dx;
                       validChildrenCount++;
                    } 
                 }

                 if (validChildrenCount > 0) {
                    final childrenCenterX = childrenSumX / validChildrenCount;
                    // --- Конец улучшенного расчета --- 
                    
                    final parentGroupIds = _getNodeGroup(nodeId, level, currentPositions, spouseMap);

                    double minParentX = double.infinity;
                    double maxParentX = double.negativeInfinity;
                    for (final pId in parentGroupIds) {
                        final pPos = currentPositions[pId];
                        if (pPos != null) {
                           minParentX = min(minParentX, pPos.dx);
                           maxParentX = max(maxParentX, pPos.dx);
                        }
                    }
                    
                    if (minParentX.isFinite && maxParentX.isFinite) {
                       final parentGroupCenterX = (minParentX + maxParentX) / 2;
                       final targetShift = childrenCenterX - parentGroupCenterX;
                       final shiftAmount = targetShift * adjustmentFactor;

                       for (final pId in parentGroupIds) {
                          final currentPPos = nextPositions[pId];
                          if (currentPPos != null) {
                             nextPositions[pId] = Offset(currentPPos.dx + shiftAmount, currentPPos.dy);
                          }
                       }
                    }
                 }
            }
        }
        currentPositions = _resolveCollisions(maxLevel, nodesByLevel, nextPositions, spouseMap);
    }

    // --- NEW: Add a second pass for centering children under parents ---
    for (int i = 0; i < iterations; i++) { // Используем то же кол-во итераций
        Map<String, Offset> nextPositions = Map.from(currentPositions);
        for (int level = 1; level <= maxLevel; level++) { // Идем снизу вверх
            final levelNodes = nodesByLevel[level] ?? [];
            for (final childId in levelNodes) {
                final childPos = currentPositions[childId];
                if (childPos == null) continue;

                final parents = childToParentsMap[childId] ?? [];
                final parentsOnPrevLevel = parents
                    .where((parentId) => nodeLevels.containsKey(parentId) && nodeLevels[parentId] == level - 1)
                    .toList();

                if (parentsOnPrevLevel.isEmpty) continue;

                double parentSumX = 0;
                int validParentCount = 0;
                for (final parentId in parentsOnPrevLevel) {
                   final parentPos = currentPositions[parentId];
                   if (parentPos != null) {
                      parentSumX += parentPos.dx;
                      validParentCount++;
                   }
                }

                if (validParentCount > 0) {
                   final parentCenterX = parentSumX / validParentCount;
                   
                   // Определяем группу ребенка (он сам + супруги на том же уровне)
                   final childGroupIds = _getNodeGroup(childId, level, currentPositions, spouseMap);

                   double minChildGroupX = double.infinity;
                   double maxChildGroupX = double.negativeInfinity;
                   for (final cId in childGroupIds) {
                       final cPos = currentPositions[cId];
                       if (cPos != null) {
                          minChildGroupX = min(minChildGroupX, cPos.dx);
                          maxChildGroupX = max(maxChildGroupX, cPos.dx);
                       }
                   }

                   if (minChildGroupX.isFinite && maxChildGroupX.isFinite) {
                      final childGroupCenterX = (minChildGroupX + maxChildGroupX) / 2;
                      final targetShift = parentCenterX - childGroupCenterX;
                      final shiftAmount = targetShift * adjustmentFactor; // Используем ослабленный adjustmentFactor

                      for (final cId in childGroupIds) {
                         final currentCPos = nextPositions[cId];
                         if (currentCPos != null) {
                            nextPositions[cId] = Offset(currentCPos.dx + shiftAmount, currentCPos.dy);
                         }
                      }
                   }
                }
            }
        }
        // Применяем разрешение коллизий после каждого шага центрирования детей
        currentPositions = _resolveCollisions(maxLevel, nodesByLevel, nextPositions, spouseMap);
    }
    // --- END NEW PASS ---

    Map<String, Offset> finalPositions = currentPositions;

    double maxTreeWidth = 0;
    if (finalPositions.isNotEmpty) {
       double minX = double.infinity;
       double maxX = double.negativeInfinity;
       finalPositions.values.forEach((pos) {
         minX = min(minX, pos.dx);
         maxX = max(maxX, pos.dx);
       });
       maxTreeWidth = (maxX + InteractiveFamilyTree.nodeWidth / 2) - (minX - InteractiveFamilyTree.nodeWidth / 2);
       
       double shiftX = 0;
       if (minX < InteractiveFamilyTree.nodeWidth / 2 + InteractiveFamilyTree.siblingSeparation) {
          shiftX = (InteractiveFamilyTree.nodeWidth / 2 + InteractiveFamilyTree.siblingSeparation) - minX; 
          Map<String, Offset> shiftedPositions = {};
          finalPositions.forEach((key, value) { 
             shiftedPositions[key] = Offset(value.dx + shiftX, value.dy); 
          });
          finalPositions = shiftedPositions; 
          maxTreeWidth += shiftX; 
       }
    }

    // --- Шаг 4: Формирование связей (connections) --- 
    final List<FamilyConnection> finalConnections = [];
    final Set<String> addedSpousePairs = {}; 

    for (var relation in widget.relations) {
      final p1Id = relation.person1Id;
      final p2Id = relation.person2Id;
      final type1to2 = relation.relation1to2;
      
      if (finalPositions.containsKey(p1Id) && finalPositions.containsKey(p2Id)){
           if (type1to2 == RelationType.parent || type1to2 == RelationType.child) {
              final parentIdForLog = (type1to2 == RelationType.parent) ? p1Id : p2Id;
              final childIdForLog = (type1to2 == RelationType.parent) ? p2Id : p1Id;
              final parentLevel = nodeLevels[parentIdForLog];
              final childLevel = nodeLevels[childIdForLog];
              final parentId = (type1to2 == RelationType.parent) ? p1Id : p2Id;
              final childId = (type1to2 == RelationType.parent) ? p2Id : p1Id;
             if (nodeLevels.containsKey(parentId) && nodeLevels.containsKey(childId) &&
                 nodeLevels[parentId]! + 1 == nodeLevels[childId]!){
                  finalConnections.add(FamilyConnection(fromId: parentId, toId: childId, type: RelationType.parent));
             }
           }
           else if (type1to2 == RelationType.spouse) {
              if (nodeLevels.containsKey(p1Id) && nodeLevels.containsKey(p2Id) &&
                  nodeLevels[p1Id] == nodeLevels[p2Id]) {
               final pairKey = [p1Id, p2Id]..sort();
               final pairString = pairKey.join('-');
               if (!addedSpousePairs.contains(pairString)) {
                  finalConnections.add(FamilyConnection(fromId: p1Id, toId: p2Id, type: RelationType.spouse));
                  addedSpousePairs.add(pairString);
               }
           }
        }
      }
    }

    // --- Шаг 5: Расчет общего размера (treeSize) --- 
    double finalMaxY = (maxLevel * (InteractiveFamilyTree.nodeHeight + InteractiveFamilyTree.levelSeparation)) + InteractiveFamilyTree.nodeHeight;
    final Size finalTreeSize = Size(max(maxTreeWidth, 300.0), max(finalMaxY, 300.0)); 

    setState(() {
      this.nodePositions = finalPositions;
      this.connections = finalConnections;
      this.treeSize = finalTreeSize;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final stackWidth = treeSize.width + 200; 
    final stackHeight = treeSize.height + 200;

    return Scaffold(
      body: InteractiveViewer(
        constrained: false,
        boundaryMargin: const EdgeInsets.all(100), 
        minScale: 0.1, 
        maxScale: 2.0, 
        child: SizedBox(
           width: stackWidth,
           height: stackHeight,
           child: Stack(
             children: [
               CustomPaint(
                 size: Size(stackWidth, stackHeight),
                 painter: FamilyTreePainter(nodePositions, connections),
               ),
               ..._buildPersonWidgets(), 
             ],
           ),
        ),
      ),
    );
  }

  List<Widget> _buildPersonWidgets() {
    return nodePositions.entries.map((entry) {
      final personId = entry.key;
      final position = entry.value; 
      var nodeData = widget.peopleData.firstWhere(
          (data) => (data['person'] as FamilyPerson).id == personId,
          orElse: () => <String, dynamic>{});

      if (nodeData.isEmpty) return const SizedBox.shrink(); 

      final topLeftX = position.dx - InteractiveFamilyTree.nodeWidth / 2;
      final topLeftY = position.dy - InteractiveFamilyTree.nodeHeight / 2;

      return Positioned(
        left: topLeftX,
        top: topLeftY,
        width: InteractiveFamilyTree.nodeWidth,
        child: _buildPersonNode(nodeData), 
      );
    }).toList();
  }
  
  Widget _buildPersonNode(Map<String, dynamic> nodeData) {
    final FamilyPerson person = nodeData['person'];
    final UserProfile? userProfile = nodeData['userProfile'];
    
    final String displayName = userProfile != null
        ? '${userProfile.firstName} ${userProfile.lastName}'.trim()
        : person.name;
    final String? displayPhotoUrl = userProfile?.photoURL ?? person.photoUrl;
    final Gender displayGender = person.gender;
    
    final cardContent = Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor, 
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
          border: Border.all(
            color: displayGender == Gender.male
                ? Colors.blue.shade300
                : Colors.pink.shade300,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              backgroundColor: displayGender == Gender.male
                  ? Colors.blue.shade100
                  : Colors.pink.shade100,
              backgroundImage: displayPhotoUrl != null && displayPhotoUrl.isNotEmpty
                  ? NetworkImage(displayPhotoUrl)
                  : null,
              radius: 18, 
              child: displayPhotoUrl == null || displayPhotoUrl.isEmpty
                  ? Icon(
                      displayGender == Gender.male
                          ? Icons.person
                          : Icons.person_outline,
                      size: 18, 
                      color: displayGender == Gender.male
                          ? Colors.blue.shade800
                          : Colors.pink.shade800,
                    )
                  : null,
            ),
            const SizedBox(height: 4),
            Text(
              displayName,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 10, 
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              _getLifeDates(person),
              style: TextStyle(
                fontSize: 8, 
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
              ),
          ],
        ),
      );

    return Stack(
      clipBehavior: Clip.none, 
      alignment: Alignment.center,
      children: [
        GestureDetector(
           onTap: () => widget.onPersonTap(person),
           child: cardContent, 
        ),
        if (widget.isEditMode) ...[
          _buildEditButtonsOverlay(context, person),
        ],
      ],
    );
  }

  Widget _buildEditButtonsOverlay(BuildContext context, FamilyPerson person) {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6), // Полупрозрачный фон
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // --- Кнопки добавления родственников ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                 // Добавить Отца/Мать (в зависимости от пола)
                 _buildAddButton(context, person, RelationType.parent, Icons.arrow_upward, "Родителя"),
                 // Добавить Супруга
                 _buildAddButton(context, person, RelationType.spouse, Icons.favorite_border, "Супруга"),
              ],
            ),
            Row(
               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
               children: [
                 // Добавить Ребенка
                 _buildAddButton(context, person, RelationType.child, Icons.arrow_downward, "Ребенка"),
                 // Добавить Брата/Сестру (если есть родители)
                 // Логика добавления сиблингов может быть сложнее, пока просто кнопка
                 _buildAddButton(context, person, RelationType.sibling, Icons.people_outline, "Сиблинга"),
               ],
            ),
            // --- Кнопка "Добавить себя" --- 
            if (!widget.currentUserIsInTree) // Показываем, только если пользователь НЕ в дереве
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: _buildAddSelfButton(context, person, Icons.person_add_alt_1, "Добавить себя ...")
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton(BuildContext context, FamilyPerson person, RelationType type, IconData icon, String tooltip) {
    return Tooltip(
      message: 'Добавить ${tooltip.toLowerCase()}',
      child: Material(
         color: Colors.transparent,
         child: InkWell(
           borderRadius: BorderRadius.circular(20),
           onTap: () => widget.onAddRelativeTapWithType(person, type),
           child: Padding(
             padding: const EdgeInsets.all(4.0),
             child: Icon(icon, size: 18, color: Colors.white),
           ),
         ),
      ),
    );
  }
  
  Widget _buildAddSelfButton(BuildContext context, FamilyPerson targetPerson, IconData icon, String tooltip) {
    return Tooltip(
      message: tooltip, 
      child: Material(
         color: Colors.transparent,
      child: InkWell(
           borderRadius: BorderRadius.circular(20),
           onTap: () {
             // Показываем диалог выбора типа связи для себя
             _showAddSelfRelationTypeDialog(context, targetPerson);
           },
        child: Padding(
             padding: const EdgeInsets.all(4.0),
             child: Icon(icon, size: 18, color: Colors.lightGreenAccent), // Другой цвет для выделения
           ),
        ),
      ),
    );
  }

  void _showAddSelfRelationTypeDialog(BuildContext context, FamilyPerson targetPerson) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Добавить себя как...'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: RelationType.values
                .where((type) => 
                    /* type != RelationType.unknown && */ type != RelationType.other &&
                    // <<< Дополнительный фильтр: Убираем слишком далекие/сложные связи для этого диалога >>>
                    ![RelationType.greatGrandparent, RelationType.greatGrandchild, 
                     RelationType.cousin, RelationType.parentInLaw, RelationType.childInLaw, 
                     RelationType.siblingInLaw, RelationType.stepparent, RelationType.stepchild,
                     RelationType.inlaw, RelationType.ex_spouse, RelationType.ex_partner,
                     RelationType.friend, RelationType.colleague].contains(type)
                  ) // Фильтруем ненужные и сложные
                .map((type) {
                   // Определяем текст кнопки на основе типа связи
                   String buttonText = 'Как ${FamilyRelation.getGenericRelationTypeStringRu(type).toLowerCase()}';
                   IconData iconData = Icons.person; // Иконка по умолчанию
                   switch(type) {
                     case RelationType.parent: iconData = Icons.arrow_upward; break;
                     case RelationType.child: iconData = Icons.arrow_downward; break;
                     case RelationType.spouse: iconData = Icons.favorite; break;
                     case RelationType.sibling: iconData = Icons.people; break;
                     default: break;
                   }

                   return ListTile(
                     leading: Icon(iconData),
                     title: Text(buttonText),
                     onTap: () {
                        Navigator.of(dialogContext).pop(); // Закрываем диалог
                        // <<< ИСПРАВЛЕНИЕ: Вызываем коллбэк с ЗЕРКАЛЬНЫМ типом связи >>>
                        // Передаем отношение ОТ targetPerson К новому пользователю
                        widget.onAddSelfTapWithType(targetPerson, FamilyRelation.getMirrorRelation(type));
                     },
                   );
                 }).toList(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Отмена'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }
  
  String _getLifeDates(FamilyPerson person) {
    String birthYear = person.birthDate != null
        ? person.birthDate!.year.toString()
        : '?';
    
    if (person.isAlive) {
      return '$birthYear - н.в.';
    } else {
      String deathYear = person.deathDate != null
          ? person.deathDate!.year.toString()
          : '?';
      return '$birthYear - $deathYear';
    }
  }

  Map<String, Offset> _performInitialXLayout(
      int maxLevel,
      Map<int, List<String>> nodesByLevel,
      Map<String, List<String>> spouseMap,
      Map<String, int> nodeLevels,
      Map<String, List<String>> childToParentsMap
  ) {
      final Map<String, Offset> initialPositions = {};
      double layoutMaxX = 0; 

      for (int level = 0; level <= maxLevel; level++) {
          final levelNodes = nodesByLevel[level] ?? [];
          if (levelNodes.isEmpty) continue;

          // --- NEW: Sort nodes based on average parent X position ---
          Map<String, double> avgParentX = {}; // Карта для хранения среднего X родителя
          if (level > 0) { // Сортировка имеет смысл только для уровней > 0
              for (final nodeId in levelNodes) {
                  final parents = childToParentsMap[nodeId] ?? [];
                  double parentSumX = 0;
                  int parentCount = 0;
                  for (final parentId in parents) {
                      // Проверяем, что родитель на предыдущем уровне и имеет позицию
                      if (nodeLevels.containsKey(parentId) &&
                          nodeLevels[parentId] == level - 1 &&
                          initialPositions.containsKey(parentId))
                      {
                           parentSumX += initialPositions[parentId]!.dx;
                           parentCount++;
                      }
                  }
                  // Используем среднее X родителей или 0.0, если родителей нет/не найдены
                  avgParentX[nodeId] = (parentCount > 0) ? parentSumX / parentCount : 0.0;
              }
              // Сортируем узлы уровня по вычисленному среднему X родителей
              levelNodes.sort((a, b) => avgParentX[a]!.compareTo(avgParentX[b]!));
          } else {
              // Для уровня 0 оставляем простую сортировку (например, по ID)
              levelNodes.sort(); 
          }
          // --- END NEW ---

          double currentX = 0; 
          final Set<String> placedNodesInLevel = {}; 
          
          // Используем отсортированный levelNodes
          for (final nodeId in levelNodes) {
              if (placedNodesInLevel.contains(nodeId)) continue; 

              final yPos = level * (InteractiveFamilyTree.nodeHeight + InteractiveFamilyTree.levelSeparation) +
                           InteractiveFamilyTree.nodeHeight / 2;

              final List<String> spousesOnLevel = (spouseMap[nodeId] ?? [])
                   // Снова используем where, т.к. nodeLevels теперь передается
                   .where((spouseId) => nodeLevels.containsKey(spouseId) && nodeLevels[spouseId] == level)
                   .toList();

               // --- Определяем членов группы (узел + супруги) --- 
               final List<String> groupMembers = [nodeId, ...spousesOnLevel]
                                      .toSet() // Удаляем дубликаты, если spouseMap двунаправленный
                  .toList();

                 // --- Place the sorted group members (Original logic before revision) ---
              double groupWidth = InteractiveFamilyTree.nodeWidth + 
                                     (groupMembers.length - 1) * (InteractiveFamilyTree.spouseSeparation + InteractiveFamilyTree.nodeWidth);

                 double memberStartX = currentX;               
                 for (final memberId in groupMembers) {
                     if (!placedNodesInLevel.contains(memberId)) {
                         initialPositions[memberId] = Offset(memberStartX + InteractiveFamilyTree.nodeWidth / 2, yPos);
                         placedNodesInLevel.add(memberId);
                     }
                     // We always advance memberStartX even if placed, assuming standard widths/separations for the group block
                     memberStartX += InteractiveFamilyTree.nodeWidth + InteractiveFamilyTree.spouseSeparation;
                 }
                 // Update currentX for the next group/node
                 // The next node starts after the full block width + sibling separation
                 currentX += groupWidth + InteractiveFamilyTree.siblingSeparation;
                 // --- End Original Placement Logic --- 
           }
          if (currentX > 0) {
              layoutMaxX = max(layoutMaxX, (currentX - InteractiveFamilyTree.siblingSeparation));
          }
      }
      return initialPositions;
  }

  Map<String, Offset> _resolveCollisions(
      int maxLevel,
      Map<int, List<String>> nodesByLevel,
      Map<String, Offset> currentPositions,
      Map<String, List<String>> spouseMap,
  ) {
      Map<String, Offset> resolvedPositions = Map.from(currentPositions);
      final double minSeparation = InteractiveFamilyTree.siblingSeparation;
      final double nodeWidth = InteractiveFamilyTree.nodeWidth;

      for (int level = 0; level <= maxLevel; level++) {
          final levelNodes = nodesByLevel[level] ?? [];
          if (levelNodes.length < 2) continue;

          bool shifted;
          int maxPasses = levelNodes.length * levelNodes.length; 
          int passes = 0;
          do {
              shifted = false;
              passes++;
          List<String> sortedLevelNodeIds = levelNodes
                  .where((id) => resolvedPositions.containsKey(id)) 
              .toList();
              sortedLevelNodeIds.sort((a, b) => 
                  (resolvedPositions[a]!.dx - nodeWidth / 2)
                  .compareTo(resolvedPositions[b]!.dx - nodeWidth / 2));

          for (int i = 0; i < sortedLevelNodeIds.length - 1; i++) {
              final node1Id = sortedLevelNodeIds[i];
                  final pos1 = resolvedPositions[node1Id];
                  if (pos1 == null) continue;
              
                  final group1Ids = _getNodeGroup(node1Id, level, resolvedPositions, spouseMap);
                  double group1RightEdge = double.negativeInfinity;
              for (final id in group1Ids) {
                 final pos = resolvedPositions[id];
                 if (pos != null) {
                          group1RightEdge = max(group1RightEdge, pos.dx + nodeWidth / 2);
                      }
                  }
                  if (group1RightEdge == double.negativeInfinity) continue; 

                  String? node2Id;
                  int j = i + 1;
                  while(j < sortedLevelNodeIds.length) {
                      final potentialNode2Id = sortedLevelNodeIds[j];
                      if (!group1Ids.contains(potentialNode2Id)) {
                          node2Id = potentialNode2Id;
                          break;
                      }
                      j++;
                  }
                  if (node2Id == null) continue; 

                  final pos2 = resolvedPositions[node2Id];
                  if (pos2 == null) continue;
                  
                  final group2Ids = _getNodeGroup(node2Id, level, resolvedPositions, spouseMap);
                  double group2LeftEdge = double.infinity;
              for (final id in group2Ids) {
                 final pos = resolvedPositions[id];
                 if (pos != null) {
                          group2LeftEdge = min(group2LeftEdge, pos.dx - nodeWidth / 2);
                 }
              }
                  if (group2LeftEdge == double.infinity) continue; 

              final currentSeparation = group2LeftEdge - group1RightEdge;
              if (currentSeparation < minSeparation) {
                  final shiftNeeded = minSeparation - currentSeparation;
                  for (final idToShift in group2Ids) {
                      final currentPos = resolvedPositions[idToShift];
                      if (currentPos != null) {
                         resolvedPositions[idToShift] = Offset(currentPos.dx + shiftNeeded, currentPos.dy);
                      }
                  }
                   shifted = true; 
                   break; 
              }
          }
            } while (shifted && passes < maxPasses); 
      }
      return resolvedPositions;
  }

  Set<String> _getNodeGroup(
    String nodeId,
    int level,
    Map<String, Offset> positions,
    Map<String, List<String>> spouseMap,
  ) {
     final group = {nodeId};
     final potentialSpouses = spouseMap[nodeId] ?? [];
     for (final spouseId in potentialSpouses) {
       if (positions.containsKey(spouseId) && 
           positions[spouseId]!.dy == positions[nodeId]!.dy &&
           !group.contains(spouseId)) 
       { 
         group.add(spouseId);
       } 
     } // <- Добавляем недостающую скобку для закрытия цикла for
      return group;
   } // <- Конец функции _getNodeGroup

} // <- Закрывающая скобка для класса _InteractiveFamilyTreeState

// Класс для отрисовки линий связей - ВНЕ класса _InteractiveFamilyTreeState
class FamilyTreePainter extends CustomPainter {
  final Map<String, Offset> nodePositions; // Центры узлов
  final List<FamilyConnection> connections;
  final Paint linePaint;

  FamilyTreePainter(this.nodePositions, this.connections) 
      : linePaint = Paint()
          ..color = Colors.grey.shade600
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    // Теперь используем тип связи
    for (final connection in connections) {
      final startNodePos = nodePositions[connection.fromId];
      final endNodePos = nodePositions[connection.toId];

      if (startNodePos != null && endNodePos != null) {
        if (connection.type == RelationType.spouse) {
          _drawSpouseLine(canvas, startNodePos, endNodePos);
        } else if (connection.type == RelationType.parent) {
          _drawParentChildLine(canvas, startNodePos, endNodePos);
        }
        // Можно добавить другие типы линий, если нужно
      }
    }
  }

  // Метод для рисования линии между супругами
  void _drawSpouseLine(Canvas canvas, Offset pos1, Offset pos2) {
    // Просто рисуем горизонтальную линию между боковыми центрами
    final y = pos1.dy; // Супруги на одном уровне
    final x1 = pos1.dx + (pos1.dx < pos2.dx ? InteractiveFamilyTree.nodeWidth / 2 : -InteractiveFamilyTree.nodeWidth / 2);
    final x2 = pos2.dx + (pos1.dx < pos2.dx ? -InteractiveFamilyTree.nodeWidth / 2 : InteractiveFamilyTree.nodeWidth / 2);
    canvas.drawLine(Offset(x1, y), Offset(x2, y), linePaint);
  }

  // Метод для рисования ломаной линии родитель-ребенок
  void _drawParentChildLine(Canvas canvas, Offset parentPos, Offset childPos) {
    // Точки для линии
    final Offset parentBottomCenter = Offset(parentPos.dx, parentPos.dy + InteractiveFamilyTree.nodeHeight / 2);
    final Offset childTopCenter = Offset(childPos.dx, childPos.dy - InteractiveFamilyTree.nodeHeight / 2);
    
    // Промежуточная точка для изгиба (на полпути по Y)
    final double midY = parentBottomCenter.dy + (childTopCenter.dy - parentBottomCenter.dy) / 2;
    
    final Path path = Path();
    path.moveTo(parentBottomCenter.dx, parentBottomCenter.dy);
    path.lineTo(parentBottomCenter.dx, midY); // Вниз от родителя
    path.lineTo(childTopCenter.dx, midY);     // Горизонтально к X ребенка
    path.lineTo(childTopCenter.dx, childTopCenter.dy); // Вверх к ребенку

    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant FamilyTreePainter oldDelegate) {
    // Перерисовываем, если изменились позиции узлов или сами связи
    return oldDelegate.nodePositions != nodePositions || 
           oldDelegate.connections != connections;
  }
} // <- Скобка закрывает класс FamilyTreePainter 