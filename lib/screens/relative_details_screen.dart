// ignore_for_file: library_private_types_in_public_api
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rodnya/models/family_person.dart';
import '../models/family_relation.dart'; // Добавляем импорт

import '../models/family_tree.dart';
import '../models/person_dossier.dart';
import '../models/person_duplicate_suggestion.dart';
import '../models/user_profile.dart';
import '../providers/tree_provider.dart'; // Для treeId
import '../services/custom_api_auth_service.dart' show CustomApiException;
import '../services/tree_mutation_history.dart';
import 'package:go_router/go_router.dart';
import '../utils/invitation_share.dart';
import 'package:get_it/get_it.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/identity_conflicts_capable_family_tree_service.dart';
import '../backend/interfaces/identity_service_interface.dart';
import '../backend/interfaces/identity_duplicate_capable_family_tree_service.dart';
import '../backend/interfaces/person_tree_resolution_capable_family_tree_service.dart';
import '../backend/models/identity_field_conflict.dart';
import '../backend/interfaces/invitation_link_service_interface.dart';
import '../backend/interfaces/profile_service_interface.dart';
import '../backend/interfaces/storage_service_interface.dart';
import '../backend/interfaces/tree_graph_capable_family_tree_service.dart';
import '../models/tree_change_record.dart';
import '../models/tree_graph_snapshot.dart';
import '../widgets/custom_relation_label_dialog.dart';
import '../widgets/glass_panel.dart';
import '../widgets/identity_conflicts_badge.dart';
import '../widgets/identity_conflicts_sheet.dart';
import '../widgets/media_lightbox.dart';
import '../widgets/profile_redesign.dart';
import '../widgets/sensitive_contacts_section.dart';
import '../widgets/tree_history_sheet.dart';
import '../theme/app_theme.dart';
import '../utils/photo_url.dart';
import '../utils/relative_details_route.dart';
import '../utils/user_facing_error.dart';
import '../widgets/profile_biography_section.dart';
import 'profile_all_photos_screen.dart';
import 'profile_article_editor_screen.dart';
import 'profile_article_history_screen.dart';
import 'profile_visibility_screen.dart';
import 'profile_voice_recordings_screen.dart';

part 'relative_details_screen_sections.dart';

class _RelativeContactStatus {
  const _RelativeContactStatus({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String label;
  final String description;
  final IconData icon;
  final Color color;
}

enum _RelativeGalleryAction {
  makePrimary,
  delete,
}

/// P0b: честная классификация отказа загрузки КРИТИЧЕСКОЙ части карточки
/// (резолв дерева / сам человек). Второстепенные данные деградируют
/// секциями и сюда не попадают.
enum _CardErrorKind {
  /// Сеть/сервер не ответили — лечится повтором.
  network,

  /// Человека нет ни в одном доступном дереве (удалён или ссылка устарела).
  notFound,

  /// Бэк ответил «нельзя» — карточка закрыта настройками доступа.
  accessDenied,
}

class _EditableRelationLink {
  const _EditableRelationLink({
    required this.relation,
    required this.relatedPerson,
    required this.relationFromRelatedPerson,
  });

  final FamilyRelation relation;
  final FamilyPerson relatedPerson;
  final RelationType relationFromRelatedPerson;
}

/// Результат резолва «в каком дереве живёт человек» (P0). Если по пути
/// человек уже был загружен — несём его с собой, чтобы не дёргать GET
/// второй раз.
class _PersonTreeResolution {
  const _PersonTreeResolution({this.treeId, this.person});

  final String? treeId;
  final FamilyPerson? person;
}

class RelativeDetailsScreen extends StatefulWidget {
  final String personId;

  /// P0 (мамин баг): дерево, из которого пришли на карточку. Когда задан —
  /// все загрузки идут по нему. Когда нет (старые ссылки, уведомления без
  /// контекста) — экран резолвит дерево сам: кэш person→tree → выбранное
  /// дерево → обход деревьев пользователя.
  final String? treeId;
  final String? initialAction;

  const RelativeDetailsScreen({
    required this.personId,
    this.treeId,
    this.initialAction,
    super.key,
  });

  @override
  _RelativeDetailsScreenState createState() => _RelativeDetailsScreenState();
}

class _RelativeDetailsScreenState extends State<RelativeDetailsScreen> {
  // Используем widget.personId для доступа к ID
  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();
  final FamilyTreeServiceInterface _familyService =
      GetIt.I<FamilyTreeServiceInterface>();
  final ProfileServiceInterface _profileService =
      GetIt.I<ProfileServiceInterface>();
  final InvitationLinkServiceInterface _invitationLinkService =
      GetIt.I<InvitationLinkServiceInterface>();
  final StorageServiceInterface _storageService =
      GetIt.I<StorageServiceInterface>();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isGeneratingLink = false;
  bool _isUpdatingGallery = false;
  bool _isLoadingHistory = false;
  bool _isUpdatingIdentity = false;
  bool _isUpdatingPrivacy = false;

  FamilyPerson? _person;
  List<FamilyPerson> _treePeople = [];
  List<FamilyRelation> _relations = [];
  List<TreeChangeRecord> _historyRecords = [];
  UserProfile? _userProfile;
  // Phase 3.4 chunk 5: unresolved conflicts на этом person'е,
  // фильтрованные по targetPersonId. Загружаются в _loadData;
  // banner + badge сами рендерят SizedBox.shrink если пусто.
  List<IdentityFieldConflict> _personConflicts =
      const <IdentityFieldConflict>[];
  PersonDossier? _dossier;
  List<PersonDuplicateSuggestion> _duplicateSuggestions =
      const <PersonDuplicateSuggestion>[];
  RelationType? _relationToCurrentUser;
  TreeGraphSnapshot? _graphSnapshot;
  TreeGraphViewerDescriptor? _viewerDescriptor;
  String? _viewerRelationLabel;
  bool _isLoading = true;
  _CardErrorKind? _errorKind;
  // Дерево, по которому реально грузится карточка (результат резолва) —
  // НЕ обязательно выбранное в приложении.
  String? _currentTreeId;
  // Выбранное дерево на момент открытия — один из шагов резолва.
  String? _selectedTreeIdAtOpen;
  String? _currentUserPersonId;
  bool _initialActionHandled = false;

  TreeGraphCapableFamilyTreeService? get _graphTreeService {
    final service = _familyService;
    if (service is TreeGraphCapableFamilyTreeService) {
      return service as TreeGraphCapableFamilyTreeService;
    }
    return null;
  }

  IdentityDuplicateCapableFamilyTreeService? get _identityDuplicateService {
    final service = _familyService;
    if (service is IdentityDuplicateCapableFamilyTreeService) {
      return service as IdentityDuplicateCapableFamilyTreeService;
    }
    return null;
  }

  IdentityServiceInterface? get _identityService =>
      GetIt.I.isRegistered<IdentityServiceInterface>()
          ? GetIt.I<IdentityServiceInterface>()
          : null;

  @override
  void initState() {
    super.initState();
    // Запоминаем выбранное дерево ПОСЛЕ построения виджета — это один из
    // шагов резолва (явный treeId роута имеет приоритет).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _selectedTreeIdAtOpen = Provider.of<TreeProvider>(
          context,
          listen: false,
        ).selectedTreeId;
      } catch (_) {
        _selectedTreeIdAtOpen = null;
      }
      _loadData();
    });
  }

  /// P0: определяем дерево человека. Порядок: явный treeId из роута →
  /// кэш person→tree сервиса → выбранное дерево (с проверкой, что человек
  /// там есть) → полный обход деревьев пользователя. Если по пути человек
  /// уже загрузился — возвращаем и его, чтобы не дёргать GET повторно.
  /// Сетевые ошибки пробрасываются (их различает _loadData), «не в этом
  /// дереве» (404/403/410) — гасятся и ведут к следующему шагу.
  Future<_PersonTreeResolution> _resolvePersonContext() async {
    final personId = widget.personId;
    final service = _familyService;
    // Деревья провайдера читаем синхронно, до await'ов (контекст через
    // async-gap не трогаем).
    var providerTrees = const <FamilyTree>[];
    try {
      providerTrees =
          Provider.of<TreeProvider>(context, listen: false).availableTrees;
    } catch (_) {
      providerTrees = const <FamilyTree>[];
    }

    bool isMissingOnTree(Object error) =>
        error is CustomApiException &&
        (error.statusCode == 404 ||
            error.statusCode == 403 ||
            error.statusCode == 410);

    // 1. Явный контекст из точки входа.
    final explicit = widget.treeId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return _PersonTreeResolution(treeId: explicit);
    }

    final resolution = service is PersonTreeResolutionCapableFamilyTreeService
        ? service as PersonTreeResolutionCapableFamilyTreeService
        : null;

    // 2. Кэш сервиса. Проверяем GET'ом: кэш может протухнуть (человека
    // удалили) — тогда честно идём дальше по цепочке.
    final cached = resolution?.cachedTreeIdForPerson(personId);
    if (cached != null && cached.isNotEmpty) {
      try {
        final person = await service.getPersonById(cached, personId);
        return _PersonTreeResolution(treeId: cached, person: person);
      } catch (error) {
        if (!isMissingOnTree(error)) rethrow;
      }
    }

    // 3. Выбранное дерево.
    final selected = _selectedTreeIdAtOpen;
    if (selected != null && selected.isNotEmpty && selected != cached) {
      try {
        final person = await service.getPersonById(selected, personId);
        return _PersonTreeResolution(treeId: selected, person: person);
      } catch (error) {
        if (!isMissingOnTree(error)) rethrow;
      }
    }

    // 4. Полный обход. Предпочитаем сервисный резолв (кэш + локальное
    // хранилище + деревья); без capability — обходим деревья провайдера
    // вручную.
    if (resolution != null) {
      final resolved = await resolution.resolveTreeIdForPerson(personId);
      if (resolved != null && resolved.isNotEmpty) {
        return _PersonTreeResolution(treeId: resolved);
      }
      return const _PersonTreeResolution();
    }

    var trees = providerTrees;
    if (trees.isEmpty) {
      try {
        trees = await service.getUserTrees();
      } catch (_) {
        trees = const <FamilyTree>[];
      }
    }
    for (final tree in trees) {
      if (tree.id == selected || tree.id == cached) continue;
      try {
        final person = await service.getPersonById(tree.id, personId);
        return _PersonTreeResolution(treeId: tree.id, person: person);
      } catch (error) {
        if (!isMissingOnTree(error)) rethrow;
      }
    }
    return const _PersonTreeResolution();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorKind = null;
      _person = null;
      _treePeople = [];
      _relations = [];
      _historyRecords = [];
      _userProfile = null;
      _dossier = null;
      _duplicateSuggestions = const <PersonDuplicateSuggestion>[];
      _relationToCurrentUser = null;
      _graphSnapshot = null;
      _viewerDescriptor = null;
      _viewerRelationLabel = null;
      _currentUserPersonId = null;
      _isLoadingHistory = true;
      _personConflicts = const <IdentityFieldConflict>[];
    });

    // ── Критическая часть: дерево + сам человек. Только её отказ даёт
    // полноэкранную заглушку; всё остальное деградирует секциями. ──
    final _PersonTreeResolution resolved;
    try {
      // P0 (мамин баг): сперва определяем дерево ЧЕЛОВЕКА, а не берём
      // слепо выбранное — карточка из другого дерева раньше падала в 404
      // и показывала заглушку.
      resolved = await _resolvePersonContext();
    } catch (e) {
      debugPrint('Не удалось определить дерево для ${widget.personId}: $e');
      _failLoad(_classifyCriticalError(e));
      return;
    }
    _currentTreeId = resolved.treeId;
    if (_currentTreeId == null) {
      _failLoad(_CardErrorKind.notFound);
      return;
    }

    try {
      _person = resolved.person ??
          await _familyService.getPersonById(_currentTreeId!, widget.personId);
    } catch (e) {
      debugPrint('Ошибка загрузки данных родственника ${widget.personId}: $e');
      _failLoad(_classifyCriticalError(e));
      return;
    }

    // ── Второстепенное: каждый блок в своём try — отказ гасит секцию
    // (подписи связей, биографию, историю…), но карточка живёт. ──

    // 0. Профиль ТЕКУЩЕГО пользователя (нужен для getReciprocalType).
    final currentUserId = _authService.currentUserId;
    if (currentUserId != null) {
      try {
        await _profileService.getUserProfile(currentUserId);
      } catch (profileError) {
        debugPrint(
          'Не удалось загрузить профиль текущего пользователя: $profileError',
        );
        // Не считаем критичной ошибкой для отображения деталей родственника
      }
    }

    // 1. Люди и связи дерева — без них карточка остаётся без подписей
    // родства, но открывается.
    try {
      final relatives = await _familyService.getRelatives(_currentTreeId!);
      _relations = await _familyService.getRelations(_currentTreeId!);
      _treePeople = relatives;
      final currentUserPerson =
          relatives.where((p) => p.userId == currentUserId);
      _currentUserPersonId =
          currentUserPerson.isNotEmpty ? currentUserPerson.first.id : null;
    } catch (relativesError) {
      debugPrint(
        'Не удалось загрузить родственников/связи дерева $_currentTreeId: $relativesError',
      );
      _treePeople = [];
      _relations = [];
      _currentUserPersonId = null;
    }

    try {
      _dossier = await _familyService.getPersonDossier(
        _currentTreeId!,
        widget.personId,
      );
      _person = _dossier!.person;
      _userProfile = _dossier!.linkedProfile;
    } catch (_) {
      _dossier = null;
    }

    // 2. Если есть userId, пытаемся загрузить UserProfile
    if (_userProfile == null &&
        _person!.userId != null &&
        _person!.userId!.isNotEmpty) {
      try {
        _userProfile = await _profileService.getUserProfile(_person!.userId!);
      } catch (profileError) {
        // Не критично: карточка живёт без привязанного профиля.
        debugPrint(
          'Не удалось загрузить профиль ${_person!.userId}: $profileError',
        );
        _userProfile = null;
      }
    }

    // 3. Определяем родственную связь с текущим пользователем
    if (_currentUserPersonId != null && _person != null) {
      try {
        _relationToCurrentUser = await _familyService.getRelationBetween(
          _currentTreeId!,
          _currentUserPersonId!,
          _person!.id,
        );
        debugPrint(
          'Связь ${widget.personId} с текущим пользователем ($_currentUserPersonId): $_relationToCurrentUser',
        );
      } catch (relationError) {
        debugPrint(
          'Не удалось определить связь с ${widget.personId}: $relationError',
        );
        _relationToCurrentUser = null;
      }
    }
    if (_graphTreeService != null && _person != null) {
      try {
        final snapshot =
            await _graphTreeService!.getTreeGraphSnapshot(_currentTreeId!);
        _graphSnapshot = snapshot;
        _viewerDescriptor = snapshot.findViewerDescriptor(_person!.id);
        _viewerRelationLabel = _viewerDescriptor?.primaryRelationLabel?.trim();
      } catch (snapshotError) {
        debugPrint(
          'Не удалось загрузить graph snapshot для $_currentTreeId: $snapshotError',
        );
        _graphSnapshot = null;
        _viewerDescriptor = null;
        _viewerRelationLabel = null;
      }
    }

    if (_identityDuplicateService != null && _person != null) {
        try {
          final suggestions = await _identityDuplicateService!
              .getDuplicateSuggestions(_currentTreeId!);
          _duplicateSuggestions = suggestions
              .where((suggestion) => suggestion.involves(_person!.id))
              .toList(growable: false);
        } catch (duplicateError) {
          debugPrint(
            'Не удалось загрузить возможные совпадения для ${widget.personId}: $duplicateError',
          );
          _duplicateSuggestions = const <PersonDuplicateSuggestion>[];
        }
      }

      // Phase 3.4 chunk 5: load identity conflicts for this person.
      // Best-effort — failure ничего не блокирует (badge/banner
      // просто не появятся). Filter by targetPersonId — это
      // конкретный person на текущей tree'е.
      if (_person != null && _familyService is IdentityConflictsCapableFamilyTreeService) {
        try {
          final capable =
              _familyService as IdentityConflictsCapableFamilyTreeService;
          final allConflicts = await capable.getIdentityConflictsForTree(
            treeId: _currentTreeId!,
          );
          _personConflicts = allConflicts
              .where((c) => c.targetPersonId == _person!.id && !c.isResolved)
              .toList(growable: false);
        } catch (conflictsError) {
          debugPrint(
            'Не удалось загрузить расхождения для ${widget.personId}: $conflictsError',
          );
          _personConflicts = const <IdentityFieldConflict>[];
        }
      }

    try {
      if (_person != null) {
        _historyRecords = await _familyService.getTreeHistory(
          treeId: _currentTreeId!,
          personId: _person!.id,
        );
      }
    } catch (historyError) {
      debugPrint(
        'Не удалось загрузить историю изменений для ${widget.personId}: $historyError',
      );
      _historyRecords = [];
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isLoadingHistory = false;
      });
      _maybeHandleInitialAction();
    }
  }

  void _failLoad(_CardErrorKind kind) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _isLoadingHistory = false;
      _errorKind = kind;
    });
  }

  /// Классификация отказа критической части. HTTP-статусы различаем по
  /// [CustomApiException]; всё остальное (socket, timeout, 5xx) считаем
  /// «не дозвонились» — это лечится повтором.
  _CardErrorKind _classifyCriticalError(Object error) {
    if (error is CustomApiException) {
      final status = error.statusCode;
      if (status == 404 || status == 410) {
        return _CardErrorKind.notFound;
      }
      if (status == 403 || status == 401) {
        return _CardErrorKind.accessDenied;
      }
    }
    return _CardErrorKind.network;
  }

  void _maybeHandleInitialAction() {
    if (!mounted || _initialActionHandled) {
      return;
    }
    final action = widget.initialAction?.trim().toLowerCase();
    if (action == null || action.isEmpty) {
      return;
    }

    VoidCallback? handler;
    switch (action) {
      case 'path':
        handler = _showRelationPathSheet;
        break;
      case 'parents':
        if (_hasAdditionalParentSets()) {
          handler = _showOtherParentsSheet;
        }
        break;
      case 'relations':
        if (_canEditOrDelete()) {
          handler = _showRelationManagementSheet;
        }
        break;
    }

    if (handler == null) {
      return;
    }

    _initialActionHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      handler!();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_person?.displayName ?? 'Профиль'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          tooltip: 'Назад',
          onPressed: () => context.pop(),
        ),
        actions: [
          // §3.1 top-right: ✏️ (structured-field edit) + ⋯ (everything
          // else). Отвязать / Удалить / Приватность / claim / Предложить
          // правку moved into the ⋯ sheet so nothing is lost (full §3.2
          // menu is sub-chunk 2b).
          if (_canDirectEditProfile())
            IconButton(
              key: const Key('profile-appbar-edit'),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Редактировать данные',
              onPressed: _editRelative,
            ),
          if (_person != null)
            IconButton(
              key: const Key('profile-appbar-menu'),
              icon: const Icon(Icons.more_horiz),
              tooltip: 'Ещё',
              onPressed: _openActionsMenu,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Future<void> _showQuickAddRelativeSheet() async {
    if (_person == null || _currentTreeId == null) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Добавить к карточке',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Новый человек будет сразу привязан к ${_person!.displayName}.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[700],
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 12),
                _buildQuickAddOption(
                  sheetContext: sheetContext,
                  icon: Icons.arrow_upward,
                  label: 'Добавить родителя',
                  relationType: RelationType.parent,
                ),
                _buildQuickAddOption(
                  sheetContext: sheetContext,
                  icon: Icons.favorite_border,
                  label: 'Добавить супруга или партнёра',
                  relationType: RelationType.spouse,
                ),
                _buildQuickAddOption(
                  sheetContext: sheetContext,
                  icon: Icons.arrow_downward,
                  label: 'Добавить ребёнка',
                  relationType: RelationType.child,
                ),
                _buildQuickAddOption(
                  sheetContext: sheetContext,
                  icon: Icons.people_outline,
                  label: 'Добавить брата или сестру',
                  relationType: RelationType.sibling,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickAddOption({
    required BuildContext sheetContext,
    required IconData icon,
    required String label,
    required RelationType relationType,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      onTap: () {
        Navigator.of(sheetContext).pop();
        _openContextualAddRelative(relationType);
      },
    );
  }

  void _openContextualAddRelative(RelationType relationType) {
    if (_person == null || _currentTreeId == null) {
      return;
    }
    context.push(
      '/relatives/add/$_currentTreeId',
      extra: {
        'contextPersonId': _person!.id,
        'relationType': relationType,
        'quickAddMode': true,
      },
    );
  }

  bool _canEditOrDelete() {
    return _person != null && (_dossier?.canEditFamilyFields ?? true);
  }

  /// Phase 3.4 chunk 5: открывает reusable conflict-resolution
  /// sheet для текущего person'а. После choice'а — refetch
  /// conflicts (and full data on overwrite, чтобы поля обновились).
  Future<void> _showPersonConflictsSheet() async {
    final treeId = _currentTreeId;
    final service = _familyService;
    if (treeId == null ||
        _person == null ||
        service is! IdentityConflictsCapableFamilyTreeService ||
        _personConflicts.isEmpty) {
      return;
    }
    final capable = service as IdentityConflictsCapableFamilyTreeService;
    await showIdentityConflictsSheet(
      context: context,
      conflicts: _personConflicts,
      onChoice: (sheetContext, conflict, choice) async {
        try {
          await capable.resolveIdentityConflict(
            treeId: treeId,
            conflictId: conflict.id,
            choice: choice,
          );
        } catch (error) {
          if (sheetContext.mounted) {
            ScaffoldMessenger.of(sheetContext).showSnackBar(
              SnackBar(content: Text('Не удалось применить выбор: $error')),
            );
          }
          return;
        }
        if (sheetContext.mounted) {
          Navigator.of(sheetContext).pop();
        }
        // overwrite → данные person'а изменились, full reload.
        // keep → достаточно re-fetch'а conflicts.
        if (choice == 'overwrite') {
          await _loadData();
        } else if (mounted) {
          try {
            final fresh = await capable.getIdentityConflictsForTree(
              treeId: treeId,
            );
            if (!mounted) return;
            setState(() {
              _personConflicts = fresh
                  .where((c) =>
                      c.targetPersonId == _person!.id && !c.isResolved)
                  .toList(growable: false);
            });
          } catch (_) {
            // best-effort: refetch failed — sheet всё равно закрыт,
            // badge обновится на следующем _loadData.
          }
        }
      },
    );
  }

  /// Phase 3.4 chunk 4 (PHASE-3.4-UI-PROPOSAL §2.4): true когда
  /// карта связана с user-аккаунтом, и viewer — этот же аккаунт.
  /// Используется для gating'а sensitive contacts section: phone/
  /// email лежат в собственном UserProfile, и показывать их можно
  /// только себе (даже creator'у чужой карточки нельзя — это его
  /// данные не его).
  bool _isViewerOwnPerson(FamilyPerson person) {
    final ownerId = person.userId;
    final viewerId = _authService.currentUserId;
    if (ownerId == null || ownerId.isEmpty) return false;
    if (viewerId == null || viewerId.isEmpty) return false;
    return ownerId == viewerId;
  }

  /// Phase 3.4 chunk 4: build «city, country» либо single component
  /// либо null. UserProfile не имеет точного «адреса» поля —
  /// city+country это самое близкое к локации. Если оба пусты —
  /// addressLine null, sensitive section покажет empty-state с
  /// invite to «Добавить» (ведёт в profile editor).
  String? _composeAddressLine(UserProfile? profile) {
    if (profile == null) return null;
    final parts = <String>[];
    final city = profile.city?.trim();
    final country = profile.country?.trim();
    if (city != null && city.isNotEmpty) parts.add(city);
    if (country != null && country.isNotEmpty) parts.add(country);
    if (parts.isEmpty) return null;
    return parts.join(', ');
  }

  bool _canDirectEditProfile() {
    return _person != null &&
        (_person!.userId == null ||
            _person!.userId!.isEmpty ||
            !_person!.isAlive) &&
        _canEditOrDelete();
  }

  bool _canSuggestProfileEdits() {
    return _person != null && (_dossier?.canSuggestOwnerFields ?? false);
  }

  bool _canStartChatWithPerson() {
    final userId = _person?.userId;
    return userId != null &&
        userId.isNotEmpty &&
        _person?.isAlive == true &&
        userId != _authService.currentUserId;
  }

  bool _canInvitePerson() {
    final userId = _person?.userId;
    return _person != null &&
        _person!.isAlive &&
        (userId == null || userId.isEmpty) &&
        _person!.id != _currentUserPersonId;
  }

  /// Кнопка «Отвязать пользователя» доступна когда:
  /// 1) к слоту привязан какой-то аккаунт (есть userId)
  /// 2) этот аккаунт — НЕ текущий юзер (себя нельзя)
  ///
  /// Дополнительный гейт по правам — на бэкенде: эндпоинт
  /// `DELETE /v1/trees/.../user-link` сам отдаёт 403 если caller
  /// не tree.creatorId. Раньше я гейтил здесь по `_canEditOrDelete()`
  /// который зависит от поля `canEditFamilyFields` в dossier — а
  /// dossier для чужой карточки в чужом дереве может вернуться
  /// с false. Из-за этого кнопка не показывалась владельцу дерева.
  /// Теперь показываем оптимистично, бэкенд отшибёт несанкционированных
  /// с понятным toast'ом.
  bool _canUnlinkUser() {
    final userId = _person?.userId;
    if (userId == null || userId.isEmpty) {
      return false;
    }
    if (userId == _authService.currentUserId) {
      return false;
    }
    return true;
  }

  String _describeRelativeActionError(
    Object error, {
    required String fallbackMessage,
  }) {
    return describeUserFacingError(
      authService: _authService,
      error: error,
      fallbackMessage: fallbackMessage,
    );
  }

  void _showRelativeSnackBar(
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
      ),
    );
  }

  Future<void> _requestIdentityClaim() async {
    final service = _identityService;
    if (service == null || _currentTreeId == null || _person == null) {
      return;
    }

    setState(() {
      _isUpdatingIdentity = true;
    });
    try {
      final claim = await service.createIdentityClaim(
        treeId: _currentTreeId!,
        personId: _person!.id,
      );
      if (!mounted) {
        return;
      }
      _showRelativeSnackBar(
        claim.isApproved
            ? 'Карточка привязана к вашему аккаунту.'
            : 'Запрос отправлен ответственным за карточку.',
      );
      await _loadData();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showRelativeSnackBar(
        _describeRelativeActionError(
          error,
          fallbackMessage:
              'Не удалось отправить запрос личности. Попробуйте ещё раз.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingIdentity = false;
        });
      }
    }
  }

  Future<void> _showPrivacySettings() async {
    final service = _identityService;
    if (service == null || _currentTreeId == null || _person == null) {
      return;
    }

    setState(() {
      _isUpdatingPrivacy = true;
    });

    try {
      final attributes = await service.getPersonAttributes(
        treeId: _currentTreeId!,
        personId: _person!.id,
      );
      if (!mounted) {
        return;
      }

      final fieldLabels = <String, String>{
        'name': 'Имя и фамилия',
        'photo': 'Фото',
        'birthDate': 'Полная дата рождения',
        'birthYear': 'Год рождения',
        'places': 'Места',
        'contacts': 'Контакты',
        'notes': 'Заметки',
        'relations': 'Связи',
      };
      final visibilityLabels = <String, String>{
        'private': 'Только ответственные',
        'tree': 'Участники дерева',
        'cross-tree': 'Связанные деревья',
        'public': 'Публично',
      };
      var cardVisibility = _person!.visibility;
      final fieldVisibility = <String, String>{
        for (final attribute in attributes)
          attribute.field: attribute.visibility,
      };

      final shouldSave = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 20,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Приватность карточки',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'По умолчанию живые люди закрыты. Для кросс-деревьев раскрывайте только то, что действительно можно показывать родственникам из другой ветки.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue:
                              visibilityLabels.containsKey(cardVisibility)
                                  ? cardVisibility
                                  : 'private',
                          decoration: const InputDecoration(
                            labelText: 'Видимость карточки',
                            border: OutlineInputBorder(),
                          ),
                          items: visibilityLabels.entries
                              .map(
                                (entry) => DropdownMenuItem<String>(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setSheetState(() => cardVisibility = value);
                          },
                        ),
                        const SizedBox(height: 16),
                        ...fieldLabels.entries.map((entry) {
                          final value = fieldVisibility[entry.key] ??
                              (entry.key == 'contacts'
                                  ? 'private'
                                  : cardVisibility);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: DropdownButtonFormField<String>(
                              initialValue: visibilityLabels.containsKey(value)
                                  ? value
                                  : 'private',
                              decoration: InputDecoration(
                                labelText: entry.value,
                                border: const OutlineInputBorder(),
                              ),
                              items: visibilityLabels.entries
                                  .map(
                                    (visibilityEntry) =>
                                        DropdownMenuItem<String>(
                                      value: visibilityEntry.key,
                                      child: Text(visibilityEntry.value),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: (nextValue) {
                                if (nextValue == null) {
                                  return;
                                }
                                setSheetState(
                                  () => fieldVisibility[entry.key] = nextValue,
                                );
                              },
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(false),
                                child: const Text('Отмена'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(true),
                                child: const Text('Сохранить'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

      if (shouldSave != true || !mounted) {
        return;
      }

      await service.updatePersonAttributeVisibility(
        treeId: _currentTreeId!,
        personId: _person!.id,
        visibility: cardVisibility,
        attributes: fieldVisibility,
      );
      if (!mounted) {
        return;
      }
      _showRelativeSnackBar('Приватность карточки обновлена.');
      await _loadData();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showRelativeSnackBar(
        _describeRelativeActionError(
          error,
          fallbackMessage:
              'Не удалось обновить приватность. Попробуйте ещё раз.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingPrivacy = false;
        });
      }
    }
  }

  Future<void> _showOtherParentsSheet() async {
    if (_person == null) {
      return;
    }
    final units = _parentFamilyUnitsForCurrentPerson();
    if (units.isEmpty || !mounted) {
      return;
    }

    final peopleById = {
      for (final person in (_graphSnapshot?.people ?? _treePeople))
        person.id: person,
    };

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Другие родители',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Здесь показаны все родительские наборы для этой карточки. На основном полотне дерево использует основной набор, остальные раскрываются здесь.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[700],
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 16),
                ...units.map((unit) {
                  final adultNames = unit.adultIds
                      .map((personId) =>
                          peopleById[personId]?.displayName ?? personId)
                      .toList();
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          adultNames.isEmpty
                              ? 'Родители не указаны'
                              : adultNames.join(' • '),
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          unit.label,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[700],
                                  ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildPathInfoChip(
                              icon: unit.isPrimaryParentSet
                                  ? Icons.star_outline
                                  : Icons.layers_outlined,
                              label: unit.isPrimaryParentSet
                                  ? 'Основной набор'
                                  : 'Дополнительный набор',
                            ),
                            if (_normalizeOptionalText(unit.parentSetType) !=
                                null)
                              _buildPathInfoChip(
                                icon: Icons.family_restroom_outlined,
                                label: FamilyRelation.getParentSetTypeLabel(
                                  unit.parentSetType,
                                ),
                              ),
                            if (_normalizeOptionalText(unit.unionType) != null)
                              _buildPathInfoChip(
                                icon: Icons.favorite_border,
                                label: FamilyRelation.getUnionTypeLabel(
                                    unit.unionType),
                              ),
                            if (_normalizeOptionalText(unit.unionStatus) !=
                                null)
                              _buildPathInfoChip(
                                icon: Icons.schedule_outlined,
                                label: FamilyRelation.getUnionStatusLabel(
                                    unit.unionStatus),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showRelationPathSheet() async {
    if (_currentTreeId == null ||
        _person == null ||
        _graphTreeService == null) {
      return;
    }

    final descriptor =
        _viewerDescriptor ?? _graphSnapshot?.findViewerDescriptor(_person!.id);
    final pathPersonIds = (descriptor?.primaryPathPersonIds.isNotEmpty ?? false)
        ? descriptor!.primaryPathPersonIds
        : await _graphTreeService!.getRelationPath(
            treeId: _currentTreeId!,
            targetPersonId: _person!.id,
          );
    final peopleById = {
      for (final person in (_graphSnapshot?.people ?? _treePeople))
        person.id: person,
    };

    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Путь родства',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_normalizeOptionalText(
                            descriptor?.primaryRelationLabel) !=
                        null)
                      _buildPathInfoChip(
                        icon: Icons.badge_outlined,
                        label: descriptor!.primaryRelationLabel!.trim(),
                      ),
                    if (descriptor != null)
                      _buildPathInfoChip(
                        icon: descriptor.isBlood
                            ? Icons.favorite_outline
                            : Icons.link_outlined,
                        label: descriptor.isBlood
                            ? 'Кровная связь'
                            : 'Родство по браку',
                      ),
                    if (pathPersonIds.isNotEmpty)
                      _buildPathInfoChip(
                        icon: Icons.stairs_outlined,
                        label: 'Шагов: ${pathPersonIds.length - 1}',
                      ),
                    if ((descriptor?.alternatePathCount ?? 0) > 0)
                      _buildPathInfoChip(
                        icon: Icons.alt_route_outlined,
                        label: 'Еще путей: ${descriptor!.alternatePathCount}',
                      ),
                  ],
                ),
                if (_normalizeOptionalText(descriptor?.pathSummary) !=
                    null) ...[
                  const SizedBox(height: 12),
                  Text(
                    descriptor!.pathSummary!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[700],
                          height: 1.35,
                        ),
                  ),
                ],
                const SizedBox(height: 16),
                if (pathPersonIds.isEmpty)
                  const Text(
                    'Backend пока не вернул путь родства для этого человека.',
                  )
                else
                  ...List<Widget>.generate(pathPersonIds.length, (index) {
                    final personId = pathPersonIds[index];
                    final person = peopleById[personId];
                    final isViewer = personId ==
                        (_graphSnapshot?.viewerPersonId ??
                            _currentUserPersonId);
                    final isTarget = personId == _person!.id;
                    final widgets = <Widget>[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 16,
                              child: Text('${index + 1}'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    person?.displayName ?? personId,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  if (isViewer || isTarget) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (isViewer)
                                          _buildPathInfoChip(
                                            icon: Icons.person_outline,
                                            label: 'Это вы',
                                          ),
                                        if (isTarget)
                                          _buildPathInfoChip(
                                            icon: Icons.adjust_outlined,
                                            label: 'Выбранный человек',
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ];
                    if (index < pathPersonIds.length - 1) {
                      final nextPersonId = pathPersonIds[index + 1];
                      final relation =
                          _findDirectRelation(personId, nextPersonId);
                      final relationContext = relation == null
                          ? null
                          : _describeRelationContext(relation);
                      widgets.add(
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(
                                width: 32,
                                child: Center(
                                  child: Icon(Icons.south, size: 18),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _buildPathStepLabel(
                                        fromPersonId: personId,
                                        toPersonId: nextPersonId,
                                        peopleById: peopleById,
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                    if (relationContext != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        relationContext,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: Colors.grey[700]),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: widgets,
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _disconnectRelation(_EditableRelationLink link) async {
    if (_currentTreeId == null || _graphTreeService == null) {
      return;
    }
    // Снапшот связи ДО удаления — нужен для undo (восстановить с
    // теми же person'ами и типом).
    final relationSnapshot = link.relation;
    await _graphTreeService!.disconnectRelation(
      treeId: _currentTreeId!,
      relationId: link.relation.id,
    );
    if (GetIt.I.isRegistered<TreeMutationHistory>()) {
      GetIt.I<TreeMutationHistory>().recordRelationDeleted(
        treeId: _currentTreeId!,
        deleted: relationSnapshot,
      );
    }
    if (!mounted) {
      return;
    }
    await _loadData();
  }

  Future<void> _changeRelationType(
    _EditableRelationLink link,
    RelationType relationType,
  ) async {
    if (_currentTreeId == null ||
        _graphTreeService == null ||
        _person == null) {
      return;
    }
    CustomRelationLabels? customLabels;
    if (relationType == RelationType.other) {
      customLabels = await showCustomRelationLabelDialog(
        context: context,
        person1Name: link.relatedPerson.displayName,
        person2Name: _person!.displayName,
        person1Gender: link.relatedPerson.gender,
        person2Gender: _person!.gender,
        initialRelation1to2: link.relation.customLabelToPerson(_person!.id),
        initialRelation2to1: link.relation.customLabelFromPerson(_person!.id),
      );
      if (customLabels == null) {
        return;
      }
    }
    await _graphTreeService!.setRelationType(
      treeId: _currentTreeId!,
      anchorPerson: _person!,
      targetPerson: link.relatedPerson,
      relationType: FamilyRelation.relationTypeToString(relationType),
      customRelationLabel1to2: customLabels?.relation1to2,
      customRelationLabel2to1: customLabels?.relation2to1,
    );
    if (!mounted) {
      return;
    }
    await _loadData();
  }

  Future<void> _showRelationManagementSheet() async {
    final links = _buildEditableRelationLinks();
    final warnings = _graphWarningsForRelationManagement(links);
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Исправить связи',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                if (warnings.isNotEmpty) ...[
                  ...warnings.map(
                    (warning) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildGraphWarningCard(warning, compact: true),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                if (links.isEmpty)
                  const Text(
                      'У этого человека пока нет прямых связей для редактирования.')
                else
                  ...links.map((link) {
                    final relationLabel =
                        link.relation.customLabelToPerson(_person!.id) ??
                            FamilyRelation.getRelationName(
                              link.relationFromRelatedPerson,
                              link.relatedPerson.gender,
                            );
                    final relationContext =
                        _describeRelationContext(link.relation);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(link.relatedPerson.displayName),
                      subtitle: relationContext == null
                          ? Text(relationLabel)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(relationLabel),
                                const SizedBox(height: 2),
                                Text(
                                  relationContext,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.grey[700]),
                                ),
                              ],
                            ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PopupMenuButton<RelationType>(
                            tooltip: 'Сменить тип родства',
                            onSelected: (value) async {
                              Navigator.of(context).pop();
                              await _changeRelationType(link, value);
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: RelationType.parent,
                                child: Text('Родитель'),
                              ),
                              PopupMenuItem(
                                value: RelationType.child,
                                child: Text('Ребенок'),
                              ),
                              PopupMenuItem(
                                value: RelationType.sibling,
                                child: Text('Брат / сестра'),
                              ),
                              PopupMenuItem(
                                value: RelationType.spouse,
                                child: Text('Супруг'),
                              ),
                              PopupMenuItem(
                                value: RelationType.partner,
                                child: Text('Партнер'),
                              ),
                              PopupMenuItem(
                                value: RelationType.other,
                                child: Text('Другое...'),
                              ),
                            ],
                            icon: const Icon(Icons.swap_horiz_outlined),
                          ),
                          IconButton(
                            tooltip: 'Разорвать связь',
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await _disconnectRelation(link);
                            },
                            icon: const Icon(Icons.link_off_outlined),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _editRelative() {
    if (!_canDirectEditProfile() || _currentTreeId == null) return;

    debugPrint(
      'Переход на редактирование: personId=${_person!.id}, treeId=$_currentTreeId',
    );
    context
        .push(
      '/relatives/edit/${_currentTreeId!}/${_person!.id}',
      extra: _person,
    )
        .then((result) {
      if (result == true && mounted) {
        debugPrint('Возврат с экрана редактирования, перезагрузка данных...');
        _loadData();
      }
    });
  }

  Future<void> _suggestProfileChanges() async {
    if (!_canSuggestProfileEdits() ||
        _currentTreeId == null ||
        _person == null) {
      return;
    }

    final summaryController = TextEditingController(
      text: _dossier?.familySummary ?? '',
    );
    final bioController = TextEditingController(text: _dossier?.bio ?? '');
    final workController = TextEditingController(text: _dossier?.work ?? '');
    final messageController = TextEditingController();

    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Предложить правку профиля'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: summaryController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Семейная справка',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bioController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'О человеке',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: workController,
                decoration: const InputDecoration(
                  labelText: 'Работа и дело',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Комментарий для владельца',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );

    if (approved != true) {
      summaryController.dispose();
      bioController.dispose();
      workController.dispose();
      messageController.dispose();
      return;
    }

    try {
      await _familyService.proposePersonProfileContribution(
        treeId: _currentTreeId!,
        personId: _person!.id,
        fields: {
          'bio': bioController.text.trim(),
          'work': workController.text.trim(),
          'aboutFamily': summaryController.text.trim(),
        },
        message: messageController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      _showRelativeSnackBar('Предложение отправлено владельцу профиля.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showRelativeSnackBar(
        _describeRelativeActionError(
          error,
          fallbackMessage:
              'Не удалось отправить правку. Попробуйте ещё раз чуть позже.',
        ),
      );
    } finally {
      summaryController.dispose();
      bioController.dispose();
      workController.dispose();
      messageController.dispose();
    }
  }

  Future<void> _deleteRelative() async {
    if (!_canDirectEditProfile() || _currentTreeId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подтверждение удаления'),
        content: Text(
          'Вы уверены, что хотите удалить профиль '
          '${_person!.displayName}'
          '? Это действие необратимо.',
        ),
        actions: [
          TextButton(
            child: const Text('Отмена'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: const Text(
              'Удалить',
              style: TextStyle(color: Colors.redAccent),
            ),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _isLoading = true;
      });
      try {
        // Snapshot ДО удаления — для undo'а через
        // TreeMutationHistory. Связи каскадно стираются на
        // backend'е и undo их НЕ восстановит — только сам person
        // вернётся как новая карточка с новым id (пустыми связями).
        final personSnapshot = _person;
        await _familyService.deleteRelative(_currentTreeId!, widget.personId);
        if (personSnapshot != null &&
            GetIt.I.isRegistered<TreeMutationHistory>()) {
          GetIt.I<TreeMutationHistory>().recordPersonDeleted(
            treeId: _currentTreeId!,
            deleted: personSnapshot,
          );
        }
        if (mounted) {
          _showRelativeSnackBar('Карточка ${_person!.displayName} удалена.');
          context.pop();
        }
      } catch (e) {
        debugPrint('Ошибка удаления родственника: $e');
        if (mounted) {
          _showRelativeSnackBar(
            _describeRelativeActionError(
              e,
              fallbackMessage:
                  'Не удалось удалить карточку. Попробуйте ещё раз.',
            ),
          );
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _unlinkUser() async {
    if (!_canUnlinkUser() || _currentTreeId == null) return;

    final personLabel = _person!.displayName.trim().isEmpty
        ? 'этого человека'
        : _person!.displayName;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отвязать пользователя?'),
        content: Text(
          'Аккаунт, привязанный к карточке «$personLabel», '
          'будет отвязан от дерева. Сама карточка останется на месте — '
          'имя, фото и связи не изменятся, можно будет пригласить '
          'другого человека или этого же заново.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Отвязать',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final updated = await _familyService.unlinkUserFromPerson(
        treeId: _currentTreeId!,
        personId: _person!.id,
      );
      if (!mounted) return;
      setState(() {
        _person = updated;
        _isLoading = false;
      });
      _showRelativeSnackBar(
        'Аккаунт отвязан от карточки «$personLabel». '
        'Теперь можно пригласить нужного человека.',
      );
    } catch (error, stackTrace) {
      debugPrint('Ошибка отвязки пользователя: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showRelativeSnackBar(
        _describeRelativeActionError(
          error,
          fallbackMessage:
              'Не удалось отвязать пользователя. Попробуйте ещё раз.',
        ),
      );
    }
  }

  Future<void> _generateAndShareInviteLink() async {
    if (_person == null || _currentTreeId == null) return;

    setState(() {
      _isGeneratingLink = true;
    });

    try {
      final inviteUrl = _invitationLinkService.buildInvitationLink(
        treeId: _currentTreeId!,
        personId: _person!.id,
      );

      if (mounted) {
        await showInviteShareSheet(
          context,
          inviteUrl: inviteUrl,
          message:
              'Присоединяйтесь к нашему семейному древу в Родне! ${inviteUrl.toString()}',
          subject: 'Приглашение в Родню',
        );
      }
    } catch (e) {
      debugPrint('Ошибка при генерации или отправке ссылки: $e');
      if (mounted) {
        _showRelativeSnackBar(
          _describeRelativeActionError(
            e,
            fallbackMessage:
                'Не удалось подготовить приглашение. Попробуйте ещё раз.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingLink = false;
        });
      }
    }
  }

  void _openChatWithPerson() {
    if (!_canStartChatWithPerson() || _person == null) {
      return;
    }

    final displayName = _userProfile?.displayName ?? _person!.displayName;
    final photoUrl = _person!.primaryPhotoUrl ?? _userProfile?.photoURL;

    try {
      final nameParam = Uri.encodeComponent(displayName);
      final photoParam = photoUrl != null ? Uri.encodeComponent(photoUrl) : '';
      final relativeIdParam = Uri.encodeComponent(_person!.id);
      context.push(
        '/relatives/chat/${_person!.userId}?name=$nameParam&photo=$photoParam&relativeId=$relativeIdParam',
      );
    } catch (e) {
      debugPrint('Ошибка при переходе в чат: $e');
      if (!mounted) {
        return;
      }
      _showRelativeSnackBar(
        _describeRelativeActionError(
          e,
          fallbackMessage: 'Не удалось открыть чат. Попробуйте ещё раз.',
        ),
      );
    }
  }

  Future<void> _pickAndUploadGalleryImage() async {
    if (_person == null ||
        _currentTreeId == null ||
        !_canEditOrDelete() ||
        _isUpdatingGallery) {
      return;
    }

    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (image == null) {
      return;
    }

    setState(() {
      _isUpdatingGallery = true;
    });

    try {
      final uploadedUrl = await _storageService.uploadImage(image, 'relatives');
      if (uploadedUrl == null || uploadedUrl.isEmpty) {
        throw Exception('backend не вернул URL после загрузки фото');
      }

      final updatedPerson = await _familyService.addRelativeMedia(
        treeId: _currentTreeId!,
        personId: _person!.id,
        mediaData: {
          'url': uploadedUrl,
          'type': 'image',
          'contentType': image.mimeType,
          'isPrimary': _person!.photoGallery.isEmpty,
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _person = updatedPerson;
      });
      await _refreshHistory();
      if (!mounted) {
        return;
      }
      _showRelativeSnackBar('Фото добавлено в галерею.');
    } catch (e) {
      debugPrint('Ошибка загрузки фото родственника: $e');
      if (mounted) {
        _showRelativeSnackBar(
          _describeRelativeActionError(
            e,
            fallbackMessage:
                'Не удалось добавить фото. Попробуйте выбрать другой файл или повторить позже.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingGallery = false;
        });
      }
    }
  }

  Future<void> _setPrimaryGalleryMedia(Map<String, dynamic> media) async {
    final mediaId = media['id']?.toString();
    if (_person == null ||
        _currentTreeId == null ||
        !_canEditOrDelete() ||
        _isUpdatingGallery ||
        mediaId == null ||
        mediaId.isEmpty ||
        media['isPrimary'] == true) {
      return;
    }

    setState(() {
      _isUpdatingGallery = true;
    });

    try {
      final updatedPerson = await _familyService.updateRelativeMedia(
        treeId: _currentTreeId!,
        personId: _person!.id,
        mediaId: mediaId,
        mediaData: const {'isPrimary': true},
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _person = updatedPerson;
      });
      await _refreshHistory();
      if (!mounted) {
        return;
      }
      _showRelativeSnackBar('Основное фото обновлено.');
    } catch (e) {
      debugPrint('Ошибка обновления основного фото: $e');
      if (mounted) {
        _showRelativeSnackBar(
          _describeRelativeActionError(
            e,
            fallbackMessage:
                'Не удалось сменить основное фото. Попробуйте ещё раз.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingGallery = false;
        });
      }
    }
  }

  Future<void> _deleteGalleryMedia(Map<String, dynamic> media) async {
    final mediaId = media['id']?.toString();
    if (_person == null ||
        _currentTreeId == null ||
        !_canEditOrDelete() ||
        _isUpdatingGallery ||
        mediaId == null ||
        mediaId.isEmpty) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить фото?'),
        content: const Text(
          'Фотография исчезнет из карточки родственника и из списка дерева.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Удалить',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    setState(() {
      _isUpdatingGallery = true;
    });

    try {
      final updatedPerson = await _familyService.deleteRelativeMedia(
        treeId: _currentTreeId!,
        personId: _person!.id,
        mediaId: mediaId,
        // Send URL as fallback for clients that cached synthetic IDs (photo-1, etc.)
        fallbackUrl: media['url']?.toString(),
      );

      final deletedUrl = media['url']?.toString();
      if (deletedUrl != null && deletedUrl.isNotEmpty) {
        try {
          await _storageService.deleteImage(deletedUrl);
        } catch (storageError) {
          debugPrint('Не удалось удалить файл из storage: $storageError');
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _person = updatedPerson;
      });
      await _refreshHistory();
      if (!mounted) {
        return;
      }
      _showRelativeSnackBar('Фото удалено из галереи.');
    } catch (e) {
      debugPrint('Ошибка удаления фото родственника: $e');
      if (mounted) {
        _showRelativeSnackBar(
          _describeRelativeActionError(
            e,
            fallbackMessage:
                'Не удалось удалить фото. Попробуйте ещё раз чуть позже.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingGallery = false;
        });
      }
    }
  }

  Future<void> _refreshHistory() async {
    if (_currentTreeId == null || _person == null) {
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingHistory = true;
      });
    }

    try {
      final records = await _familyService.getTreeHistory(
        treeId: _currentTreeId!,
        personId: _person!.id,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _historyRecords = records;
        _isLoadingHistory = false;
      });
    } catch (e) {
      debugPrint('Ошибка обновления истории изменений: $e');
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
        });
      }
    }
  }

  void _openHistorySheet() {
    if (_currentTreeId == null || _person == null) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return TreeHistorySheet(
          historyFuture: _historyRecords.isNotEmpty && !_isLoadingHistory
              ? Future.value(_historyRecords)
              : _familyService.getTreeHistory(
                  treeId: _currentTreeId!,
                  personId: _person!.id,
                ),
          title: 'История изменений',
          subtitle: _person!.displayName,
          currentUserId: _authService.currentUserId,
          emptyMessage: 'Для этой карточки пока нет записей в журнале.',
          onOpenPerson: (personId) {
            Navigator.of(sheetContext).pop();
            if (!mounted || personId == _person!.id) {
              return;
            }
            context.push(
              relativeDetailsRoute(personId, treeId: _currentTreeId),
            );
          },
        );
      },
    );
  }

  void _openGalleryViewer(
    List<Map<String, dynamic>> galleryEntries, {
    required int initialIndex,
  }) {
    // Profile Redesign: route through the shared MediaLightbox so the
    // relative gallery, the post feed, and chat attachments all use
    // the same fullscreen viewer (pinch-to-zoom, swipe-to-dismiss,
    // dark scrim, caption rail). Removes ~150 LOC of bespoke
    // PageView + Dialog plumbing that lived here.
    if (galleryEntries.isEmpty) return;

    final items = <MediaLightboxItem>[];
    for (var i = 0; i < galleryEntries.length; i++) {
      final entry = galleryEntries[i];
      final url = entry['url']?.toString() ?? '';
      if (url.isEmpty) continue;
      final captionRaw = entry['caption']?.toString().trim() ?? '';
      final isPrimary = entry['isPrimary'] == true;
      final positionLabel = '${i + 1} / ${galleryEntries.length}';
      final caption = [
        if (isPrimary) 'Основное фото',
        if (captionRaw.isNotEmpty) captionRaw,
        positionLabel,
      ].join(' · ');
      items.add(MediaLightboxItem(
        imageUrl: normalizePhotoUrl(url) ?? url,
        caption: caption.isEmpty ? null : caption,
      ));
    }
    if (items.isEmpty) return;
    final clampedIndex = initialIndex.clamp(0, items.length - 1);
    MediaLightbox.show(
      context,
      items: items,
      initialIndex: clampedIndex,
    );
  }

  IconData _historyIcon(TreeChangeRecord record) {
    switch (record.type) {
      case 'person_media.created':
        return Icons.add_photo_alternate_outlined;
      case 'person_media.updated':
        return Icons.star_outline;
      case 'person_media.deleted':
        return Icons.delete_outline;
      case 'person.created':
        return Icons.person_add_alt_1_outlined;
      case 'person.updated':
        return Icons.edit_outlined;
      case 'person.deleted':
        return Icons.person_remove_outlined;
      case 'relation.created':
        return Icons.device_hub_outlined;
      case 'relation.deleted':
        return Icons.link_off_outlined;
      default:
        return Icons.history_outlined;
    }
  }

  String _historyTitle(TreeChangeRecord record) {
    switch (record.type) {
      case 'person_media.created':
        return 'Добавлено фото';
      case 'person_media.updated':
        return 'Обновлено фото';
      case 'person_media.deleted':
        return 'Удалено фото';
      case 'person.created':
        return 'Создан профиль';
      case 'person.updated':
        return 'Обновлён профиль';
      case 'person.deleted':
        return 'Профиль удалён';
      case 'relation.created':
        return 'Добавлена связь';
      case 'relation.deleted':
        return 'Удалена связь';
      default:
        return 'Изменение в дереве';
    }
  }

  String _historySubtitle(TreeChangeRecord record) {
    final who = record.actorId == null || record.actorId!.isEmpty
        ? 'Действие в дереве'
        : record.actorId == _authService.currentUserId
            ? 'Вы'
            : 'Участник дерева';
    final when = DateFormat('d MMM, HH:mm', 'ru').format(record.createdAt);
    return '$who · $when';
  }
}
