import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart'; // Импортируем Provider
import 'package:get_it/get_it.dart';

import '../backend/backend_runtime_config.dart';
import '../models/family_person.dart';
import '../models/family_relation.dart';
import '../models/family_tree.dart';
import '../widgets/interactive_family_tree.dart';
import '../widgets/tree_history_sheet.dart';
import '../widgets/glass_panel.dart';
import '../providers/tree_provider.dart'; // Импортируем TreeProvider
import 'package:go_router/go_router.dart'; // Для навигации
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/chat_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/tree_graph_capable_family_tree_service.dart';

import '../services/app_status_service.dart';
import '../services/public_tree_link_service.dart';
import '../services/local_storage_service.dart';
import '../models/tree_graph_snapshot.dart';
import '../utils/user_facing_error.dart';
import '../utils/e2e_state_bridge.dart';

part 'tree_view_screen_sections.dart';

enum _TreeToolbarAction {
  refresh,
  openHistory,
  openRelatives,
  openChats,
  createPost,
  toggleEditMode,
  openBranchChat,
  openBranchDetails,
  copyPublicLink,
  resetBranchFocus,
  resetLayout,
}

class SectionTitle extends StatelessWidget {
  final String title;

  const SectionTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class TreeViewScreen extends StatefulWidget {
  final String? routeTreeId;
  final String? routeTreeName;

  const TreeViewScreen({
    super.key,
    this.routeTreeId,
    this.routeTreeName,
  });

  @override
  State<TreeViewScreen> createState() => _TreeViewScreenState();
}

class _TreeViewScreenState extends State<TreeViewScreen> {
  final FamilyTreeServiceInterface _familyService =
      GetIt.I<FamilyTreeServiceInterface>();
  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();
  final ChatServiceInterface _chatService = GetIt.I<ChatServiceInterface>();
  final AppStatusService _appStatusService = GetIt.I<AppStatusService>();
  final LocalStorageService _localStorageService =
      GetIt.I<LocalStorageService>();

  // Map<String, dynamic> _graphData = {'nodes': [], 'edges': []}; // Больше не нужно
  bool _isLoading = true;
  String _errorMessage = '';
  bool _isEditMode = false; // <<< Добавляем состояние режима редактирования
  TreeProvider? _treeProviderInstance; // Храним экземпляр
  String? _currentTreeId;
  String? _branchRootPersonId;
  String? _selectedEditPersonId;
  FamilyTree? _currentTreeMeta;
  Map<String, Offset> _manualNodePositions = <String, Offset>{};
  TreeGraphSnapshot? _graphSnapshot;
  // <<< НОВОЕ СОСТОЯНИЕ: Флаг, добавлен ли текущий пользователь в дерево >>>
  bool _currentUserIsInTree = true; // Изначально true, пока не проверили

  bool get _isFriendsTree => _currentTreeMeta?.isFriendsTree == true;

  TreeGraphCapableFamilyTreeService? get _graphTreeService {
    final service = _familyService;
    if (service is TreeGraphCapableFamilyTreeService) {
      return service as TreeGraphCapableFamilyTreeService;
    }
    return null;
  }

  String _describeTreeActionError(
    Object error, {
    required String fallbackMessage,
  }) {
    return describeUserFacingError(
      authService: _authService,
      error: error,
      fallbackMessage: fallbackMessage,
    );
  }

  List<FamilyPerson> get _treePeople => _relativesData
      .map((entry) => entry['person'])
      .whereType<FamilyPerson>()
      .toList();

  FamilyPerson? get _selectedEditPerson {
    final selectedId = _selectedEditPersonId;
    if (selectedId == null) {
      return null;
    }
    for (final person in _treePeople) {
      if (person.id == selectedId) {
        return person;
      }
    }
    return null;
  }

  void _updateSectionState(VoidCallback update) {
    setState(update);
  }

  void _publishTreeE2EState(String? selectedTreeId) {
    if (!E2EStateBridge.isEnabled) {
      return;
    }

    final people = _treePeople;
    final selectedPerson = _selectedEditPerson;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      E2EStateBridge.publish(
        screen: 'tree',
        state: <String, dynamic>{
          'selectedTreeId': selectedTreeId,
          'currentTreeId': _currentTreeId,
          'treeName': _currentTreeMeta?.name ?? widget.routeTreeName,
          'isLoading': _isLoading,
          'isEditMode': _isEditMode,
          'branchRootPersonId': _branchRootPersonId,
          'selectedEditPersonId': _selectedEditPersonId,
          'selectedEditPerson': selectedPerson == null
              ? null
              : <String, dynamic>{
                  'id': selectedPerson.id,
                  'name': selectedPerson.name,
                  'photoCount': selectedPerson.photoGallery.length,
                  'hasPrimaryPhoto': selectedPerson.primaryPhotoUrl != null,
                },
          'people': people
              .map(
                (person) => <String, dynamic>{
                  'id': person.id,
                  'name': person.name,
                  'photoCount': person.photoGallery.length,
                  'hasPrimaryPhoto': person.primaryPhotoUrl != null,
                },
              )
              .toList(),
        },
      );
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _treeProviderInstance = Provider.of<TreeProvider>(context, listen: false);
      _treeProviderInstance!.addListener(_handleTreeChange); // Подписываемся
      _syncTreeFromRouteOrProvider();
    });
  }

  @override
  void dispose() {
    _treeProviderInstance?.removeListener(_handleTreeChange); // Отписываемся
    super.dispose();
  }

  Future<void> _syncTreeFromRouteOrProvider() async {
    final routeTreeId = widget.routeTreeId;
    final routeTreeName = widget.routeTreeName;
    final provider = _treeProviderInstance;
    if (provider == null) {
      return;
    }

    if (routeTreeId != null && routeTreeId.isNotEmpty) {
      final currentId = provider.selectedTreeId;
      final currentName = provider.selectedTreeName;
      final needsSync = currentId != routeTreeId ||
          ((routeTreeName?.isNotEmpty ?? false) &&
              currentName != routeTreeName);

      if (needsSync) {
        await provider.selectTree(routeTreeId, routeTreeName);
        return;
      }

      _currentTreeId = routeTreeId;
      await _loadData(routeTreeId);
      return;
    }

    _currentTreeId = provider.selectedTreeId;
    if (_currentTreeId != null) {
      await _loadData(_currentTreeId!);
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Метод-обработчик изменений
  void _handleTreeChange() {
    if (!mounted) return;
    final newTreeId = _treeProviderInstance?.selectedTreeId;
    if (_currentTreeId != newTreeId) {
      debugPrint(
        'TreeView: Обнаружено изменение дерева с $_currentTreeId на $newTreeId',
      );
      _currentTreeId = newTreeId;
      if (_currentTreeId != null) {
        _loadData(_currentTreeId!);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = '';
          _manualNodePositions = <String, Offset>{};
        });
      }
    }
  }

  // Метод загрузки данных, теперь принимает treeId
  Future<void> _loadData(String treeId) async {
    if (!mounted) return;
    debugPrint('TreeView: Загрузка данных для дерева $treeId');
    final hasCachedTreeData = _currentTreeMeta?.id == treeId &&
        (_relativesData.isNotEmpty || _relationsData.isNotEmpty);
    final graphTreeService = _graphTreeService;
    setState(() {
      _isLoading = !hasCachedTreeData;
      _errorMessage = '';
      _currentUserIsInTree = true;
      if (!hasCachedTreeData) {
        _relativesData = [];
        _relationsData = [];
        _manualNodePositions = <String, Offset>{};
        _graphSnapshot = null;
      }
    });

    try {
      if (_authService.currentUserId == null) {
        context.go('/login');
        return;
      }
      if (graphTreeService == null) {
        throw StateError(
          'Текущее подключение не поддерживает graph snapshot дерева.',
        );
      }

      late final List<FamilyPerson> relatives;
      late final List<FamilyRelation> relations;
      late final FamilyTree? treeMeta;
      final loadResults = await Future.wait<Object?>([
        graphTreeService.getTreeGraphSnapshot(treeId),
        _loadCurrentTreeMeta(treeId),
      ]);
      final graphSnapshot = loadResults[0] as TreeGraphSnapshot;
      relatives = graphSnapshot.people;
      relations = graphSnapshot.relations;
      treeMeta = loadResults[1] as FamilyTree?;
      debugPrint(
        'Загружено родственников: ${relatives.length}, связей: ${relations.length}',
      );

      if (!mounted) return;

      if (relatives.isEmpty) {
        debugPrint('Дерево $treeId пустое.');
        setState(() {
          _isLoading = false;
          _errorMessage = '';
          _relativesData = [];
          _relationsData = [];
          _currentTreeMeta = treeMeta;
          _manualNodePositions = <String, Offset>{};
          _graphSnapshot = graphSnapshot;
          _currentUserIsInTree = graphSnapshot.viewerPersonId != null;
        });
        return;
      }

      final List<Map<String, dynamic>> peopleData = [];
      final viewerDescriptors = graphSnapshot.viewerDescriptorByPersonId;
      for (var person in relatives) {
        peopleData.add({
          'person': person,
          'userProfile': null,
          'viewerDescriptor': viewerDescriptors[person.id],
        });
      }

      final savedPositions = await _localStorageService.getTreeNodePositions(
        treeId,
      );
      final visiblePersonIds = relatives.map((person) => person.id).toSet();
      final filteredPositions = <String, Offset>{};
      for (final entry in savedPositions.entries) {
        if (visiblePersonIds.contains(entry.key)) {
          filteredPositions[entry.key] = entry.value;
        }
      }

      // Сохраняем данные в состоянии для передачи в виджет
      if (mounted) {
        final branchRootStillExists = _branchRootPersonId == null ||
            relatives.any((person) => person.id == _branchRootPersonId);
        final selectedEditPersonStillExists = _selectedEditPersonId == null ||
            relatives.any((person) => person.id == _selectedEditPersonId);
        setState(() {
          // Сохраняем исходные данные, а не построенный граф
          _relativesData = peopleData;
          _relationsData = relations;
          _currentTreeMeta = treeMeta;
          _manualNodePositions = filteredPositions;
          _graphSnapshot = graphSnapshot;
          _isLoading = false;
          _currentUserIsInTree = graphSnapshot.viewerPersonId != null;
          if (!branchRootStillExists) {
            _branchRootPersonId = null;
          }
          if (!selectedEditPersonStillExists) {
            _selectedEditPersonId = null;
          }
        });
      }
    } catch (e, s) {
      debugPrint('Ошибка загрузки данных дерева $treeId: $e\\n$s');
      _appStatusService.reportError(
        e,
        fallbackMessage: 'Не удалось загрузить дерево.',
      );
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (!hasCachedTreeData) {
            _errorMessage = e is StateError
                ? 'Этот backend не поддерживает новый graph snapshot дерева.'
                : _appStatusService.isOffline
                    ? 'Нет соединения. Откройте дерево снова, когда интернет вернётся.'
                    : 'Не удалось загрузить данные дерева.';
          }
        });
      }
    }
  }

  // Добавляем переменные состояния для хранения данных
  List<Map<String, dynamic>> _relativesData = [];
  List<FamilyRelation> _relationsData = [];

  @override
  Widget build(BuildContext context) {
    final treeProvider = Provider.of<TreeProvider>(context);
    final selectedTreeId = treeProvider.selectedTreeId ?? widget.routeTreeId;
    _publishTreeE2EState(selectedTreeId);
    final selectedTreeName = treeProvider.selectedTreeName ??
        widget.routeTreeName ??
        'Семейное дерево';

    if (selectedTreeId == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Семейное дерево'),
          leading: context.canPop()
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                )
              : null,
          actions: [
            IconButton(
              icon: const Icon(Icons.account_tree_outlined),
              tooltip: 'Выбрать дерево',
              onPressed: () => context.go('/tree?selector=1'),
            ),
          ],
        ),
        body: _buildTreeState(
          icon: Icons.account_tree_outlined,
          title: 'Выберите дерево',
          message: 'Здесь появится схема семьи.',
          actions: [
            FilledButton.icon(
              onPressed: () => context.go('/tree?selector=1'),
              icon: const Icon(Icons.list_alt),
              label: const Text('Открыть'),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(selectedTreeName),
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.account_tree_outlined),
            tooltip: 'Выбрать другое дерево',
            onPressed: () => context.go('/tree?selector=1'),
          ),
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined),
            tooltip: _isFriendsTree ? 'Добавить в круг' : 'Добавить человека',
            onPressed: () => _navigateToAddRelative(selectedTreeId),
          ),
          PopupMenuButton<_TreeToolbarAction>(
            tooltip: 'Действия дерева',
            onSelected: (action) =>
                _handleTreeToolbarAction(selectedTreeId, action),
            itemBuilder: (context) => _buildTreeToolbarMenuItems(),
          ),
        ],
      ),
      body: SafeArea(
        child: _buildTreeBody(selectedTreeId: selectedTreeId),
      ),
    );
  }

  Future<void> _handleTreeToolbarAction(
    String selectedTreeId,
    _TreeToolbarAction action,
  ) async {
    final branchRootPerson = _findBranchRootPerson();

    switch (action) {
      case _TreeToolbarAction.refresh:
        await _loadData(selectedTreeId);
        return;
      case _TreeToolbarAction.openHistory:
        await _showTreeHistorySheet();
        return;
      case _TreeToolbarAction.openRelatives:
        context.go('/relatives');
        return;
      case _TreeToolbarAction.openChats:
        context.go('/chats');
        return;
      case _TreeToolbarAction.createPost:
        context.push('/post/create');
        return;
      case _TreeToolbarAction.toggleEditMode:
        if (!mounted) {
          return;
        }
        setState(() {
          _isEditMode = !_isEditMode;
          if (!_isEditMode) {
            _selectedEditPersonId = null;
          }
        });
        return;
      case _TreeToolbarAction.openBranchChat:
        await _openBranchChat(selectedTreeId, branchRootPerson);
        return;
      case _TreeToolbarAction.openBranchDetails:
        if (branchRootPerson != null) {
          _openPersonDetails(branchRootPerson);
        }
        return;
      case _TreeToolbarAction.copyPublicLink:
        await _copyPublicTreeLink();
        return;
      case _TreeToolbarAction.resetBranchFocus:
        _resetBranchFocus();
        return;
      case _TreeToolbarAction.resetLayout:
        await _resetManualTreeLayout(selectedTreeId);
        return;
    }
  }

  void _openPersonDetails(FamilyPerson person, {String? action}) {
    final normalizedAction = action?.trim();
    if (normalizedAction == null || normalizedAction.isEmpty) {
      context.push('/relative/details/${person.id}');
      return;
    }
    final encodedAction = Uri.encodeQueryComponent(normalizedAction);
    context.push('/relative/details/${person.id}?action=$encodedAction');
  }

  // === НОВЫЙ МЕТОД-КОЛЛБЭК для InteractiveFamilyTree ===
  Future<void> _handleNodePositionsChanged(
    Map<String, Offset> updatedPositions,
  ) async {
    final treeId = _currentTreeId;
    if (treeId == null) {
      return;
    }

    setState(() {
      _manualNodePositions = updatedPositions;
    });
    await _localStorageService.saveTreeNodePositions(treeId, updatedPositions);
  }

  Future<void> _resetManualTreeLayout(String treeId) async {
    await _localStorageService.clearTreeNodePositions(treeId);
    if (!mounted) {
      return;
    }
    setState(() {
      _manualNodePositions = <String, Offset>{};
    });
    await _loadData(treeId);
  }

  void _handleAddRelativeFromTree(FamilyPerson person, RelationType type) {
    if (_currentTreeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Не удалось определить активное дерево. Откройте его заново и повторите действие.',
          ),
        ),
      );
      return;
    }
    debugPrint(
      'Добавление родственника типа $type к ${person.name} (${person.id}) в дереве $_currentTreeId',
    );

    // Переходим на экран добавления, передавая контекст
    // AddRelativeScreen должен будет обработать эти параметры в 'extra'
    context.push(
      '/relatives/add/$_currentTreeId',
      extra: {
        'contextPersonId': person.id, // К кому добавляем
        'relationType':
            type, // Какого типа родственника добавляем (относительно contextPersonId)
        'quickAddMode': true,
      },
    ).then((result) {
      if (!mounted) {
        return;
      }
      if (result == true) {
        debugPrint('Возврат с экрана добавления (из дерева), перезагрузка...');
        _loadData(_currentTreeId!);
        return;
      }
      if (result is Map<String, dynamic> && result['updated'] == true) {
        final focusPersonId = result['focusPersonId']?.toString();
        _loadData(_currentTreeId!).then((_) {
          if (!mounted || focusPersonId == null) {
            return;
          }
          final focusedPerson = _relativesData
              .map((entry) => entry['person'])
              .whereType<FamilyPerson>()
              .firstWhere(
                (candidate) => candidate.id == focusPersonId,
                orElse: () => FamilyPerson.empty,
              );
          if (focusedPerson != FamilyPerson.empty) {
            setState(() {
              _selectedEditPersonId = focusedPerson.id;
            });
          }
        });
      }
    });
  }

  // <<< НОВЫЙ МЕТОД-КОЛЛБЭК: Обработка добавления себя из дерева >>>
  Future<void> _handleAddSelfFromTree(
    FamilyPerson targetPerson,
    RelationType relationType,
  ) async {
    if (_currentTreeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Не удалось определить активное дерево. Откройте его заново и повторите действие.',
          ),
        ),
      );
      return;
    }

    final currentUserId = _authService.currentUserId;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Сессия завершилась. Войдите снова.')),
      );
      context.go('/login'); // Перенаправляем на логин
      return;
    }

    // Показываем индикатор загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("Добавляем вас в дерево..."),
              ],
            ),
          ),
        );
      },
    );

    try {
      debugPrint(
        'Добавление ТЕКУЩЕГО ПОЛЬЗОВАТЕЛЯ ($currentUserId) типа $relationType к ${targetPerson.name} (${targetPerson.id}) в дереве $_currentTreeId',
      );

      // Вызываем новый метод сервиса
      await _familyService.addCurrentUserToTree(
        treeId: _currentTreeId!,
        targetPersonId: targetPerson.id,
        relationType: relationType,
      );
      if (!mounted) return;

      // Закрываем диалог загрузки
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Вы успешно добавлены в дерево!'),
          duration: Duration(seconds: 2),
        ),
      );

      // Обновляем данные дерева, чтобы отобразить изменения и скрыть кнопку
      debugPrint('Перезагрузка дерева после добавления себя...');
      setState(() {
        _currentUserIsInTree = true;
      });
      await _loadData(_currentTreeId!);
    } catch (e, s) {
      // Закрываем диалог загрузки в случае ошибки
      if (mounted) Navigator.pop(context);

      debugPrint('Ошибка при добавлении себя в дерево: $e\\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _describeTreeActionError(
                e,
                fallbackMessage:
                    'Не удалось добавить вас в дерево. Попробуйте ещё раз.',
              ),
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
      debugPrint('Error in handleAddSelfFromTree: $e\n$s');
    }
  }

  // =============================================================

  Future<void> _showTreeHistorySheet({FamilyPerson? person}) async {
    final treeId = _currentTreeId;
    if (treeId == null) {
      return;
    }

    final historyFuture = _familyService.getTreeHistory(
      treeId: treeId,
      personId: person?.id,
    );
    final sheetTitle = person == null ? 'История дерева' : 'История изменений';
    final sheetSubtitle = person?.name ??
        _currentTreeMeta?.name ??
        widget.routeTreeName ??
        'Текущее дерево';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return TreeHistorySheet(
          historyFuture: historyFuture,
          title: sheetTitle,
          subtitle: sheetSubtitle,
          currentUserId: _authService.currentUserId,
          emptyMessage: person == null
              ? 'В журнале дерева пока нет записей.'
              : 'Для этой карточки пока нет записей в журнале.',
          errorBuilder: (error) => _describeTreeActionError(
            error,
            fallbackMessage: 'Не удалось загрузить историю.',
          ),
          onOpenPerson: (personId) {
            Navigator.of(sheetContext).pop();
            if (!mounted) {
              return;
            }
            context.push('/relative/details/$personId');
          },
        );
      },
    );
  }

  Future<void> _showPersonHistorySheet(FamilyPerson person) {
    return _showTreeHistorySheet(person: person);
  }

  Future<void> _navigateToAddRelative(String treeId) async {
    final result = await context.push('/relatives/add/$treeId');
    if ((result == true ||
            (result is Map<String, dynamic> && result['updated'] == true)) &&
        mounted) {
      await _loadData(treeId);
    }
  }

  Set<String> _buildBranchVisiblePersonIds(String branchRootPersonId) {
    final graphSnapshot = _graphSnapshot;
    final personIds = _relativesData
        .map((entry) => entry['person'])
        .whereType<FamilyPerson>()
        .map((person) => person.id)
        .toSet();
    if (graphSnapshot != null) {
      final branchBlock =
          graphSnapshot.findBranchBlockForPerson(branchRootPersonId);
      if (branchBlock != null) {
        return branchBlock.memberPersonIds.toSet();
      }
    }
    return personIds;
  }

  List<String> _buildBranchChatParticipantIds(String branchRootPersonId) {
    final participantIds = <String>{};
    final currentUserId = _authService.currentUserId;
    if (currentUserId != null && currentUserId.isNotEmpty) {
      participantIds.add(currentUserId);
    }

    final visibleIds = _buildBranchVisiblePersonIds(branchRootPersonId);
    for (final entry in _relativesData) {
      final person = entry['person'];
      if (person is! FamilyPerson || !visibleIds.contains(person.id)) {
        continue;
      }
      final linkedUserId = person.userId?.trim();
      if (linkedUserId != null && linkedUserId.isNotEmpty) {
        participantIds.add(linkedUserId);
      }
    }

    final sortedIds = participantIds.toList();
    sortedIds.sort();
    return sortedIds;
  }

  Future<FamilyTree?> _loadCurrentTreeMeta(String treeId) async {
    try {
      final trees = await _familyService.getUserTrees();
      for (final tree in trees) {
        if (tree.id == treeId) {
          return tree;
        }
      }
    } catch (_) {}
    return _currentTreeMeta?.id == treeId ? _currentTreeMeta : null;
  }

  void _focusBranch(FamilyPerson person) {
    if (!mounted) {
      return;
    }
    setState(() {
      _branchRootPersonId = person.id;
    });
  }

  void _resetBranchFocus() {
    if (!mounted) {
      return;
    }
    setState(() {
      _branchRootPersonId = null;
    });
  }

  FamilyPerson? _findBranchRootPerson() {
    final branchRootPersonId = _branchRootPersonId;
    if (branchRootPersonId == null) {
      return null;
    }

    for (final entry in _relativesData) {
      final person = entry['person'];
      if (person is FamilyPerson && person.id == branchRootPersonId) {
        return person;
      }
    }
    return null;
  }

  Future<void> _openBranchChat(
    String treeId,
    FamilyPerson? branchRootPerson,
  ) async {
    if (branchRootPerson == null) {
      return;
    }

    final participantIds = _buildBranchChatParticipantIds(branchRootPerson.id);
    if (participantIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('В этой ветке пока некому писать в общий чат.'),
        ),
      );
      return;
    }

    final graphBranchBlock =
        _graphSnapshot?.findBranchBlockForPerson(branchRootPerson.id);
    final title = graphBranchBlock?.label ?? 'Ветка ${branchRootPerson.name}';
    try {
      final chatId = await _chatService.createBranchChat(
        treeId: treeId,
        branchRootPersonIds: <String>[branchRootPerson.id],
        title: title,
      );
      if (!mounted) {
        return;
      }
      if (chatId == null || chatId.isEmpty) {
        throw StateError('Не удалось создать чат ветки');
      }

      context.push(
        '/chats/view/$chatId?type=branch&title=${Uri.encodeComponent(title)}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _describeTreeActionError(
              error,
              fallbackMessage: 'Не удалось открыть чат ветки.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _copyPublicTreeLink() async {
    final treeMeta = _currentTreeMeta;
    if (treeMeta == null || !treeMeta.isPublic) {
      return;
    }

    final publicUri = PublicTreeLinkService.buildPublicTreeUri(
      treeMeta.publicRouteId,
      publicAppUrl: BackendRuntimeConfig.current.publicAppUrl,
    );

    await Clipboard.setData(ClipboardData(text: publicUri.toString()));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Публичная ссылка скопирована.')),
    );
  }
}
