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
import '../models/user_profile.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/chat_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';

import '../services/public_tree_link_service.dart';
import '../services/local_storage_service.dart';
import '../utils/user_facing_error.dart';
import '../utils/e2e_state_bridge.dart';

enum _TreeToolbarAction {
  refresh,
  openHistory,
  openRelatives,
  openChats,
  createPost,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).primaryColor,
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
  // <<< НОВОЕ СОСТОЯНИЕ: Флаг, добавлен ли текущий пользователь в дерево >>>
  bool _currentUserIsInTree = true; // Изначально true, пока не проверили

  bool get _isFriendsTree => _currentTreeMeta?.isFriendsTree == true;

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
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      // Сбрасываем флаг перед проверкой
      _currentUserIsInTree = true;
    });

    try {
      if (_authService.currentUserId == null) {
        context.go('/login');
        return;
      }

      // Загружаем родственников и связи
      List<FamilyPerson> relatives = await _familyService.getRelatives(treeId);
      List<FamilyRelation> relations = await _familyService.getRelations(
        treeId,
      );
      final treeMeta = await _loadCurrentTreeMeta(treeId);
      debugPrint(
        'Загружено родственников: ${relatives.length}, связей: ${relations.length}',
      );

      if (!mounted) return;

      if (relatives.isEmpty) {
        debugPrint('Дерево $treeId пустое.');
        setState(() {
          _isLoading = false;
          _errorMessage = 'В этом дереве еще нет людей.';
          _manualNodePositions = <String, Offset>{};
        });
        return;
      }

      // <<< НОВАЯ ПРОВЕРКА: Есть ли текущий пользователь в дереве >>>
      bool userInTree = await _familyService.isCurrentUserInTree(treeId);
      if (!mounted) return;
      setState(() {
        _currentUserIsInTree = userInTree;
        debugPrint(
          'Текущий пользователь ${_authService.currentUserId} ${_currentUserIsInTree ? "" : "НЕ "}найден в дереве $treeId',
        );
      });
      // <<< КОНЕЦ ПРОВЕРКИ >>>

      // Собираем данные для peopleData (добавляем userProfile, если он есть)
      // TODO: Оптимизировать загрузку профилей, если это будет тормозить
      List<Map<String, dynamic>> peopleData = [];
      for (var person in relatives) {
        // Попытка загрузить UserProfile, если есть userId
        UserProfile? userProfile;
        if (person.userId != null) {
          // Здесь нужен ProfileService, но чтобы не усложнять, пока пропустим
          // userProfile = await _profileService.getUserProfile(person.userId!);
        }
        peopleData.add({
          'person': person,
          'userProfile': userProfile, // Будет null, если профиль не загружен
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
          _isLoading = false;
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
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Не удалось загрузить данные дерева.';
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
          IconButton(
            icon: Icon(
              _isEditMode ? Icons.edit_off_outlined : Icons.edit_outlined,
            ),
            tooltip: _isEditMode
                ? 'Выйти из режима редактирования'
                : 'Редактировать дерево',
            onPressed: () {
              if (!mounted) return;
              setState(() {
                _isEditMode = !_isEditMode;
                if (!_isEditMode) {
                  _selectedEditPersonId = null;
                }
              });
            },
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
        child: _buildTreeBody(
          selectedTreeId: selectedTreeId,
          selectedTreeName: selectedTreeName,
        ),
      ),
    );
  }

  Widget _buildTreeBody({
    required String selectedTreeId,
    required String selectedTreeName,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;
        final isWideDesktop = constraints.maxWidth >= 1180;

        if (_isLoading) {
          return _buildTreeState(
            icon: Icons.sync,
            title: 'Загружаем дерево',
            message: 'Подтягиваем людей и связи.',
            showProgress: true,
          );
        }

        if (_errorMessage.isNotEmpty) {
          final isEmptyTree = _relativesData.isEmpty && _relationsData.isEmpty;
          return _buildTreeState(
            icon: isEmptyTree ? Icons.account_tree : Icons.error_outline,
            title: isEmptyTree ? 'Дерево пустое' : 'Не удалось загрузить',
            message: isEmptyTree ? 'Добавьте первого человека.' : _errorMessage,
            actions: [
              if (isEmptyTree)
                FilledButton.icon(
                  onPressed: () => _navigateToAddRelative(selectedTreeId),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Добавить'),
                ),
              OutlinedButton.icon(
                onPressed: () => _loadData(selectedTreeId),
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
              ),
            ],
          );
        }

        final treeCanvas = _buildTreeCanvas();
        final horizontalPadding =
            isWideDesktop ? 10.0 : (isCompact ? 10.0 : 16.0);
        final topPadding = isWideDesktop ? 10.0 : (isCompact ? 8.0 : 12.0);
        final bottomPadding = isWideDesktop ? 14.0 : (isCompact ? 12.0 : 16.0);

        Widget content = Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding,
            horizontalPadding,
            bottomPadding,
          ),
          child: Column(
            children: [
              _buildTreeEscapeStrip(
                selectedTreeName: selectedTreeName,
                isWideDesktop: isWideDesktop,
              ),
              const SizedBox(height: 12),
              Expanded(child: treeCanvas),
            ],
          ),
        );

        if (isWideDesktop) {
          content = Center(
            child: SizedBox(
              width: constraints.maxWidth > 1560 ? 1560 : constraints.maxWidth,
              height: constraints.maxHeight,
              child: content,
            ),
          );
        }

        return content;
      },
    );
  }

  Widget _buildTreeCanvas() {
    final theme = Theme.of(context);
    final canvasAccent =
        _isFriendsTree ? const Color(0xFF0F9D8A) : theme.colorScheme.primary;
    return GlassPanel(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(30),
      blur: 14,
      color: theme.colorScheme.surface.withValues(alpha: 0.72),
      borderColor: canvasAccent.withValues(alpha: 0.18),
      boxShadow: [
        BoxShadow(
          color: theme.colorScheme.shadow.withValues(alpha: 0.08),
          blurRadius: 28,
          offset: const Offset(0, 18),
        ),
      ],
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surface.withValues(alpha: 0.88),
              canvasAccent.withValues(alpha: _isFriendsTree ? 0.05 : 0.03),
            ],
          ),
          borderRadius: BorderRadius.circular(30),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, 0.04),
                      radius: 0.72,
                      colors: [
                        canvasAccent.withValues(
                          alpha: _isFriendsTree ? 0.14 : 0.10,
                        ),
                        theme.colorScheme.surface.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        theme.colorScheme.surface.withValues(alpha: 0.16),
                        theme.colorScheme.surface.withValues(alpha: 0),
                        canvasAccent.withValues(alpha: 0.04),
                      ],
                    ),
                  ),
                ),
              ),
              InteractiveFamilyTree(
                peopleData: _relativesData,
                relations: _relationsData,
                currentUserId: _authService.currentUserId,
                branchRootPersonId: _branchRootPersonId,
                onBranchFocusCleared: _resetBranchFocus,
                onPersonTap: (person) {
                  debugPrint('Нажатие на узел: ${person.name} (${person.id})');
                  context.push('/relative/details/${person.id}');
                },
                onBranchFocusRequested: _focusBranch,
                isEditMode: _isEditMode,
                selectedEditPersonId: _selectedEditPersonId,
                onEditPersonSelected: (person) {
                  setState(() {
                    _selectedEditPersonId = person.id;
                  });
                },
                onOpenPersonHistory: _showPersonHistorySheet,
                manualNodePositions: _manualNodePositions,
                onNodePositionsChanged: (positions) {
                  _handleNodePositionsChanged(positions);
                },
                showGenerationGuides: !_isFriendsTree,
                enableClusterHighlights: !_isFriendsTree,
                graphLabel: _isFriendsTree ? 'дружеского графа' : 'дерева',
                hasManualLayout: _manualNodePositions.isNotEmpty,
                onResetLayout:
                    _manualNodePositions.isNotEmpty && _currentTreeId != null
                        ? () => _resetManualTreeLayout(_currentTreeId!)
                        : null,
                onAddRelativeTapWithType: _handleAddRelativeFromTree,
                currentUserIsInTree: _currentUserIsInTree,
                onAddSelfTapWithType: _handleAddSelfFromTree,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTreeEscapeStrip({
    required String selectedTreeName,
    required bool isWideDesktop,
  }) {
    final theme = Theme.of(context);
    final treeKindLabel = _isFriendsTree ? 'Круг' : 'Семья';

    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      borderRadius: BorderRadius.circular(24),
      color: theme.colorScheme.surface.withValues(alpha: 0.76),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isFriendsTree
                      ? Icons.diversity_3_outlined
                      : Icons.account_tree_outlined,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  isWideDesktop ? selectedTreeName : treeKindLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _buildTreeEscapeAction(
            icon: Icons.home_outlined,
            label: 'Главная',
            onTap: () => context.go('/'),
            primary: true,
          ),
          _buildTreeEscapeAction(
            icon: _isFriendsTree ? Icons.hub_outlined : Icons.people_outline,
            label: _isFriendsTree ? 'Люди' : 'Родные',
            onTap: () => context.go('/relatives'),
          ),
          _buildTreeEscapeAction(
            icon: Icons.forum_outlined,
            label: 'Чаты',
            onTap: () => context.go('/chats'),
          ),
          _buildTreeEscapeAction(
            icon: Icons.swap_horiz_outlined,
            label: 'Деревья',
            onTap: () => context.go('/tree?selector=1'),
          ),
          _buildTreeEscapeAction(
            icon: Icons.history_outlined,
            label: 'История',
            onTap: () => unawaited(_showTreeHistorySheet()),
          ),
        ],
      ),
    );
  }

  Widget _buildTreeEscapeAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool primary = false,
  }) {
    final button = primary
        ? FilledButton.tonalIcon(
            onPressed: onTap,
            icon: Icon(icon, size: 18),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );

    return button;
  }

  Widget _buildTreeState({
    required IconData icon,
    required String title,
    required String message,
    List<Widget> actions = const [],
    bool showProgress = false,
  }) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GlassPanel(
            padding: const EdgeInsets.all(24),
            borderRadius: BorderRadius.circular(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showProgress)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: CircularProgressIndicator(),
                  )
                else
                  Icon(icon, size: 56, color: theme.colorScheme.primary),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<PopupMenuEntry<_TreeToolbarAction>> _buildTreeToolbarMenuItems() {
    final branchRootPerson = _findBranchRootPerson();
    final items = <PopupMenuEntry<_TreeToolbarAction>>[
      _buildTreeToolbarMenuItem(
        value: _TreeToolbarAction.refresh,
        icon: Icons.refresh,
        label: 'Обновить дерево',
      ),
      _buildTreeToolbarMenuItem(
        value: _TreeToolbarAction.openHistory,
        icon: Icons.history_outlined,
        label: 'История изменений',
      ),
      _buildTreeToolbarMenuItem(
        value: _TreeToolbarAction.openRelatives,
        icon: Icons.people_outline,
        label: _isFriendsTree ? 'Открыть связи' : 'Открыть родных',
      ),
      _buildTreeToolbarMenuItem(
        value: _TreeToolbarAction.openChats,
        icon: Icons.forum_outlined,
        label: 'Открыть чаты',
      ),
      _buildTreeToolbarMenuItem(
        value: _TreeToolbarAction.createPost,
        icon: Icons.post_add_outlined,
        label: _isFriendsTree ? 'Пост в круг' : 'Новый пост',
      ),
    ];

    if (branchRootPerson != null) {
      items.add(
        _buildTreeToolbarMenuItem(
          value: _TreeToolbarAction.openBranchChat,
          icon: Icons.alt_route_outlined,
          label: _isFriendsTree ? 'Написать кругу' : 'Написать ветке',
        ),
      );
      items.add(
        _buildTreeToolbarMenuItem(
          value: _TreeToolbarAction.openBranchDetails,
          icon: Icons.open_in_new,
          label: _isFriendsTree
              ? 'Открыть карточку круга'
              : 'Открыть карточку ветки',
        ),
      );
    }

    if (_branchRootPersonId != null) {
      items.add(
        _buildTreeToolbarMenuItem(
          value: _TreeToolbarAction.resetBranchFocus,
          icon: Icons.clear_all,
          label: _isFriendsTree ? 'Показать весь граф' : 'Показать всё дерево',
        ),
      );
    }

    if (_currentTreeMeta?.isPublic == true) {
      items.add(
        _buildTreeToolbarMenuItem(
          value: _TreeToolbarAction.copyPublicLink,
          icon: Icons.link_outlined,
          label: 'Скопировать публичную ссылку',
        ),
      );
    }

    if (_manualNodePositions.isNotEmpty) {
      items.add(
        _buildTreeToolbarMenuItem(
          value: _TreeToolbarAction.resetLayout,
          icon: Icons.restart_alt,
          label: 'Сбросить layout',
        ),
      );
    }

    return items;
  }

  PopupMenuItem<_TreeToolbarAction> _buildTreeToolbarMenuItem({
    required _TreeToolbarAction value,
    required IconData icon,
    required String label,
  }) {
    return PopupMenuItem<_TreeToolbarAction>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
        ],
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
      case _TreeToolbarAction.openBranchChat:
        await _openBranchChat(selectedTreeId, branchRootPerson);
        return;
      case _TreeToolbarAction.openBranchDetails:
        if (branchRootPerson != null) {
          context.push('/relative/details/${branchRootPerson.id}');
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
          content: Text('Ошибка: Не удается определить текущее дерево.'),
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
          content: Text('Ошибка: Не удается определить текущее дерево.'),
        ),
      );
      return;
    }

    final currentUserId = _authService.currentUserId;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: Пользователь не авторизован.')),
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

  bool _isSpouseRelation(FamilyRelation relation) {
    return relation.relation1to2 == RelationType.spouse ||
        relation.relation2to1 == RelationType.spouse ||
        relation.relation1to2 == RelationType.partner ||
        relation.relation2to1 == RelationType.partner;
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

  Set<String> _buildBranchVisiblePersonIds(String branchRootPersonId) {
    final personIds = _relativesData
        .map((entry) => entry['person'])
        .whereType<FamilyPerson>()
        .map((person) => person.id)
        .toSet();
    if (!personIds.contains(branchRootPersonId)) {
      return personIds;
    }

    final childrenByParent = <String, Set<String>>{};
    final spousesByPerson = <String, Set<String>>{};
    for (final relation in _relationsData) {
      final parentId = _parentIdFromRelation(relation);
      final childId = _childIdFromRelation(relation);
      if (parentId != null && childId != null) {
        childrenByParent.putIfAbsent(parentId, () => <String>{}).add(childId);
      }
      if (_isSpouseRelation(relation)) {
        spousesByPerson
            .putIfAbsent(relation.person1Id, () => <String>{})
            .add(relation.person2Id);
        spousesByPerson
            .putIfAbsent(relation.person2Id, () => <String>{})
            .add(relation.person1Id);
      }
    }

    final visibleIds = <String>{branchRootPersonId};
    final queue = <String>[branchRootPersonId];
    while (queue.isNotEmpty) {
      final currentId = queue.removeAt(0);
      for (final spouseId in spousesByPerson[currentId] ?? const <String>{}) {
        if (visibleIds.add(spouseId)) {
          queue.add(spouseId);
        }
      }
      for (final childId in childrenByParent[currentId] ?? const <String>{}) {
        if (visibleIds.add(childId)) {
          queue.add(childId);
        }
      }
    }

    return visibleIds;
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

    final title = 'Ветка ${branchRootPerson.name}';
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
