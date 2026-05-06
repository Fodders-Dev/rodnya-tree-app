import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart'; // Импортируем Provider
import 'package:get_it/get_it.dart';

import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/identity_suggestions_capable_family_tree_service.dart';
import '../backend/models/identity_suggestion.dart';
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
import '../theme/app_theme.dart';
import '../utils/user_facing_error.dart';
import '../utils/e2e_state_bridge.dart';
import '../utils/photo_url.dart';

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
  String? _selectedPersonSheetId;
  String? _selectedEditPersonId;
  // After a successful blank-card creation we set this to the new
  // person's id; the InteractiveFamilyTree picks it up via
  // `recenterOnPersonId` and snaps the viewport to center on the
  // newly-dropped card. Without this the user can lose the card
  // when zoomed into another branch.
  String? _recenterOnPersonIdAfterReload;
  // Phase 1.2 voltage-indicator matcher: per-person count of
  // medium+high confidence cross-tree suggestions. Drives the 💡
  // dot on the canvas. Lazily populated after the tree loads —
  // we don't gate the initial render on this.
  Map<String, int> _identitySuggestionCounts = const <String, int>{};
  // Reference design pattern: bottom sheet starts collapsed (peek bar with
  // avatar + name + meta + chevron) and expands on tap to reveal action row
  // and full info. Reset to collapsed whenever selection changes.
  bool _personSheetExpanded = false;
  // Compact (mobile) chrome — info card / quick actions / health panel —
  // is collapsed by default so the canvas takes ~85% of the viewport.
  // Tap on the chevron in the top toolbar toggles it open.
  bool _compactChromeCollapsed = true;
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

  FamilyPerson? get _selectedPersonSheetPerson {
    final selectedId = _selectedPersonSheetId;
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

  void _selectTreePerson(FamilyPerson person) {
    setState(() {
      if (_selectedPersonSheetId == person.id) {
        // Same node tapped twice — close sheet entirely.
        _selectedPersonSheetId = null;
        _personSheetExpanded = false;
      } else {
        _selectedPersonSheetId = person.id;
        _personSheetExpanded = false; // Always start collapsed.
      }
    });
  }

  void _clearSelectedTreePerson() {
    setState(() {
      _selectedPersonSheetId = null;
      _personSheetExpanded = false;
    });
  }

  void _togglePersonSheetExpansion() {
    setState(() {
      _personSheetExpanded = !_personSheetExpanded;
    });
  }

  void _publishTreeE2EState(String? selectedTreeId) {
    if (!E2EStateBridge.isEnabled) {
      return;
    }

    final people = _treePeople;
    final selectedPerson = _selectedEditPerson;
    final selectedSheetPerson = _selectedPersonSheetPerson;
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
          'selectedPersonSheetId': _selectedPersonSheetId,
          'selectedEditPersonId': _selectedEditPersonId,
          'selectedPersonSheet': selectedSheetPerson == null
              ? null
              : <String, dynamic>{
                  'id': selectedSheetPerson.id,
                  'name': selectedSheetPerson.name,
                  'photoCount': selectedSheetPerson.photoGallery.length,
                  'hasPrimaryPhoto':
                      selectedSheetPerson.primaryPhotoUrl != null,
                },
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
    // Desktop convention — ESC clears the branch-focus / edit-selection
    // state without forcing the user to reach for the toolbar pill.
    // Same HardwareKeyboard pattern as the home / lightbox shortcuts:
    // Focus.onKeyEvent is unreliable on Flutter web's CanvasKit, so we
    // attach to the global handler instead.
    HardwareKeyboard.instance.addHandler(_handleTreeKeyEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _treeProviderInstance = Provider.of<TreeProvider>(context, listen: false);
      _treeProviderInstance!.addListener(_handleTreeChange); // Подписываемся
      _syncTreeFromRouteOrProvider();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleTreeKeyEvent);
    _treeProviderInstance?.removeListener(_handleTreeChange); // Отписываемся
    super.dispose();
  }

  /// Returns true to consume the event so it doesn't bubble. We only
  /// consume Esc when there's actually something to clear — otherwise
  /// the back gesture / dialog dismissal still works as expected.
  bool _handleTreeKeyEvent(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    final focused = FocusManager.instance.primaryFocus;
    final inEditable = focused?.context?.widget is EditableText ||
        (focused?.context != null &&
            focused!.context!
                    .findAncestorWidgetOfExactType<EditableText>() !=
                null);
    if (inEditable) return false;
    final hadEditSelection = _selectedEditPersonId != null;
    final hadBranchFocus = _branchRootPersonId != null;
    if (!hadEditSelection && !hadBranchFocus) return false;
    setState(() {
      _selectedEditPersonId = null;
      _branchRootPersonId = null;
    });
    return true;
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
          _selectedPersonSheetId = null;
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
        _selectedPersonSheetId = null;
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
          _selectedPersonSheetId = null;
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
        final selectedSheetPersonStillExists = _selectedPersonSheetId == null ||
            relatives.any((person) => person.id == _selectedPersonSheetId);
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
          if (!selectedSheetPersonStillExists) {
            _selectedPersonSheetId = null;
          }
        });
        // Phase 1.2 voltage-indicator: kick off cross-tree
        // suggestion fetches in the background. Doesn't block
        // first paint — when responses come in we update the
        // counts state and the canvas re-renders the 💡 dots.
        unawaited(_refreshIdentitySuggestionCounts(treeId, relatives));
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

    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    if (selectedTreeId == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(76),
          child: _buildTreeTopbar(
            theme: theme,
            tokens: tokens,
            selectedTreeId: null,
          ),
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
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(76),
        child: _buildTreeTopbar(
          theme: theme,
          tokens: tokens,
          selectedTreeId: selectedTreeId,
          treeName: selectedTreeName,
        ),
      ),
      body: SafeArea(
        child: _buildTreeBody(selectedTreeId: selectedTreeId),
      ),
    );
  }

  Widget _buildTreeTopbar({
    required ThemeData theme,
    required RodnyaDesignTokens tokens,
    required String? selectedTreeId,
    String? treeName,
  }) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            color: tokens.surface.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.74 : 0.78,
            ),
            border: Border(
              bottom: BorderSide(
                color: tokens.surfaceLine.withValues(alpha: 0.5),
                width: 0.6,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 14),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                if (context.canPop())
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: tokens.ink),
                    tooltip: 'Назад',
                    onPressed: () => context.pop(),
                  )
                else
                  const SizedBox(width: 14),
                // "Дерево" / "Круг" gets natural width (short word
                // — never wraps). The tree-name pill takes the rest
                // of the row via Expanded so long names like "Семья
                // Кузнецовых" ellipsise gracefully instead of forcing
                // the title to "Дер..." and the pill to "Семья Ку...".
                Text(
                  _isFriendsTree ? 'Круг' : 'Дерево',
                  style: AppTheme.serif(
                    color: tokens.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.22,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (treeName != null && treeName.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: tokens.accentSoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        treeName,
                        style: AppTheme.sans(
                          color: tokens.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                _TreeTopbarPill(
                  tokens: tokens,
                  tooltip: 'Выбрать дерево',
                  onTap: () => context.go('/tree?selector=1'),
                  child: Icon(
                    Icons.account_tree_outlined,
                    size: 19,
                    color: tokens.ink,
                  ),
                ),
                if (selectedTreeId != null) ...[
                  // The "+ Add person" button used to live here too, but it
                  // duplicated the green circle in the secondary toolbar
                  // and the "Добавить" tile in the Quick Actions card.
                  // Keeping just the toolbar copy — that's the primary
                  // entry point next to the canvas.
                  const SizedBox(width: 8),
                  PopupMenuButton<_TreeToolbarAction>(
                    tooltip: 'Действия дерева',
                    onSelected: (action) =>
                        _handleTreeToolbarAction(selectedTreeId, action),
                    itemBuilder: (context) => _buildTreeToolbarMenuItems(),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: tokens.surfaceStrong,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: tokens.surfaceLine),
                      ),
                      child: Icon(
                        Icons.more_horiz_rounded,
                        size: 19,
                        color: tokens.ink,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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
  // ── Phase 1.2 voltage-indicator matcher handlers ────────────────
  // The canvas reads `_identitySuggestionCounts` to decide where
  // to show the 💡 dot; tap on the dot calls `_handleShowIdentity
  // SuggestionsForPerson` which fetches details, opens a sheet
  // with the suggestion list, dispatches link/dismiss on the
  // service, and refreshes the counts.

  Future<void> _refreshIdentitySuggestionCounts(
    String treeId,
    List<FamilyPerson> relatives,
  ) async {
    final service = _familyService;
    if (service is! IdentitySuggestionsCapableFamilyTreeService) return;
    final capable =
        service as IdentitySuggestionsCapableFamilyTreeService;
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
      setState(() {
        _identitySuggestionCounts = newCounts;
      });
    }
  }

  Future<void> _handleShowIdentitySuggestionsForPerson(String personId) async {
    final treeId = _currentTreeId;
    if (treeId == null) return;
    final service = _familyService;
    if (service is! IdentitySuggestionsCapableFamilyTreeService) return;
    final capable =
        service as IdentitySuggestionsCapableFamilyTreeService;
    List<IdentitySuggestion> suggestions;
    try {
      suggestions = await capable.getIdentitySuggestionsForPerson(
        treeId: treeId,
        personId: personId,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить подсказки: $error')),
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
    final capable =
        service as IdentitySuggestionsCapableFamilyTreeService;
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
        SnackBar(content: Text('Не удалось связать карточки: $error')),
      );
    }
  }

  Future<void> _dismissIdentitySuggestion(IdentitySuggestion suggestion) async {
    final service = _familyService;
    if (service is! IdentitySuggestionsCapableFamilyTreeService) return;
    final capable =
        service as IdentitySuggestionsCapableFamilyTreeService;
    try {
      await capable.dismissIdentitySuggestion(
        sourceTreeId: suggestion.sourceTreeId,
        sourcePersonId: suggestion.sourcePersonId,
        targetPersonId: suggestion.targetPersonId,
      );
      // Optimistically drop the count by one — a fresh fetch
      // confirms after.
      if (mounted) {
        setState(() {
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
        SnackBar(content: Text('Не удалось скрыть подсказку: $error')),
      );
    }
  }

  // Blank-card creator handler. Called when the user tapped the
  // canvas-level "+ Карточка" FAB, filled name + gender in the
  // compact dialog, and pressed Save. We create the person without
  // any relation; the user connects them to the rest of the tree
  // via the edge-first connector. Pairs with the connector to
  // fully replace the form-based add-relative flow.
  Future<void> _handleAddBlankPersonFromTree(
    Map<String, dynamic> personData,
  ) async {
    final treeId = _currentTreeId;
    if (treeId == null) return;
    try {
      // addRelative returns the new person id — we capture it so
      // the tree can auto-center on the new card after the
      // reload (nice UX detail: without this, a freshly-created
      // orphan ends up wherever the layout engine puts it,
      // possibly off-screen if the user is zoomed into another
      // branch).
      final newPersonId =
          await _familyService.addRelative(treeId, personData);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Карточка добавлена. Соедините её длинным нажатием.'),
          duration: const Duration(seconds: 3),
        ),
      );
      // Stamp the recenter id BEFORE the reload — when _loadData
      // sets peopleData the InteractiveFamilyTree's didUpdateWidget
      // sees both the new data + the new recenter target in one
      // pass and schedules the focus once layout is recomputed.
      setState(() {
        _recenterOnPersonIdAfterReload = newPersonId;
      });
      await _loadData(treeId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось добавить карточку: $error')),
      );
    }
  }

  // Edge-first connector handler. Called when the user has dragged
  // one card onto another and picked a relation type from the inline
  // 4-icon picker. Skips the AddRelativeScreen form entirely and
  // creates the relation directly via the family-tree service, then
  // reloads the tree so the new edge appears.
  //
  // The picker only offers four relation types (parent, spouse,
  // sibling, other). For "other" we open a small sheet to ask which
  // long-tail relation (cousin / nephew / step-* / etc.) — better
  // than guessing wrong and silently writing a bad edge.
  Future<void> _handleConnectExistingFromTree(
    String sourcePersonId,
    String targetPersonId,
    RelationType relation1to2,
  ) async {
    final treeId = _currentTreeId;
    if (treeId == null) return;
    if (sourcePersonId.isEmpty || targetPersonId.isEmpty) return;
    if (sourcePersonId == targetPersonId) return;

    // For "other" we DON'T have enough info to create a relation —
    // pop the legacy quick-add sheet pre-anchored on the target so
    // the user can pick the specific long-tail type. This is the
    // only branch where the form is still needed.
    if (relation1to2 == RelationType.other) {
      final sourcePerson = _relativesData
          .map((entry) => entry['person'])
          .whereType<FamilyPerson>()
          .firstWhere(
            (person) => person.id == sourcePersonId,
            orElse: () => FamilyPerson(
              id: sourcePersonId,
              treeId: treeId,
              name: '',
              gender: Gender.unknown,
              isAlive: true,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      _handleAddRelativeFromTree(sourcePerson, relation1to2);
      return;
    }

    try {
      await _familyService.createRelation(
        treeId: treeId,
        person1Id: sourcePersonId,
        person2Id: targetPersonId,
        relation1to2: relation1to2,
        isConfirmed: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Связь создана'),
          duration: const Duration(seconds: 2),
        ),
      );
      // Reload so the new edge renders + layout engine can rebalance.
      await _loadData(treeId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать связь: $error')),
      );
    }
  }

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
      _selectedPersonSheetId = person.id;
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

class _TreeTopbarPill extends StatelessWidget {
  const _TreeTopbarPill({
    required this.tokens,
    required this.child,
    required this.tooltip,
    required this.onTap,
  });

  final RodnyaDesignTokens tokens;
  final Widget child;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: tokens.surfaceStrong,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: tokens.surfaceLine),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet shown when the user taps the 💡 voltage-indicator
/// dot on a card. Lists each suggestion with target person + tree
/// origin + match reasons + confirm/dismiss buttons.
class _IdentitySuggestionsSheet extends StatelessWidget {
  const _IdentitySuggestionsSheet({
    required this.suggestions,
    required this.onConfirm,
    required this.onDismiss,
  });

  final List<IdentitySuggestion> suggestions;
  final Future<void> Function(IdentitySuggestion suggestion) onConfirm;
  final Future<void> Function(IdentitySuggestion suggestion) onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.lightbulb_outline_rounded,
                    color: scheme.tertiary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Возможные дубликаты',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        suggestions.length == 1
                            ? 'Кажется, этот человек уже есть в одном из ваших деревьев. Связать карточки?'
                            : 'Кажется, этот человек уже есть в ${suggestions.length} ваших деревьях. Связать?',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final suggestion in suggestions) ...[
              _SuggestionRow(
                suggestion: suggestion,
                onConfirm: () => onConfirm(suggestion),
                onDismiss: () => onDismiss(suggestion),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.suggestion,
    required this.onConfirm,
    required this.onDismiss,
  });

  final IdentitySuggestion suggestion;
  final Future<void> Function() onConfirm;
  final Future<void> Function() onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reasons = suggestion.reasons.join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: suggestion.targetPhotoUrl != null &&
                        suggestion.targetPhotoUrl!.isNotEmpty
                    ? NetworkImage(suggestion.targetPhotoUrl!)
                    : null,
                backgroundColor: scheme.surfaceContainer,
                child: suggestion.targetPhotoUrl == null
                    ? Text(
                        suggestion.targetDisplayName.isNotEmpty
                            ? suggestion.targetDisplayName[0]
                            : '?',
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suggestion.targetDisplayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (suggestion.targetTreeName.isNotEmpty)
                      Text(
                        'Из «${suggestion.targetTreeName}»',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: suggestion.confidence == 'high'
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${(suggestion.score * 100).round()}%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: suggestion.confidence == 'high'
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              reasons,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Не он'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onConfirm,
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: const Text('Связать'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
