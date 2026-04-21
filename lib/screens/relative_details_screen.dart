// ignore_for_file: library_private_types_in_public_api
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rodnya/models/family_person.dart';
import '../models/family_relation.dart'; // Добавляем импорт

import '../models/person_dossier.dart';
import '../models/user_profile.dart';
import '../providers/tree_provider.dart'; // Для treeId
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:get_it/get_it.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/invitation_link_service_interface.dart';
import '../backend/interfaces/profile_service_interface.dart';
import '../backend/interfaces/storage_service_interface.dart';
import '../backend/interfaces/tree_graph_capable_family_tree_service.dart';
import '../models/tree_change_record.dart';
import '../models/tree_graph_snapshot.dart';
import '../widgets/custom_relation_label_dialog.dart';
import '../widgets/glass_panel.dart';
import '../widgets/person_dossier_view.dart';
import '../widgets/tree_history_sheet.dart';
import '../utils/user_facing_error.dart';

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

class RelativeDetailsScreen extends StatefulWidget {
  final String personId;
  final String? initialAction;

  const RelativeDetailsScreen({
    required this.personId,
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

  FamilyPerson? _person;
  List<FamilyPerson> _treePeople = [];
  List<FamilyRelation> _relations = [];
  List<TreeChangeRecord> _historyRecords = [];
  UserProfile? _userProfile;
  PersonDossier? _dossier;
  RelationType? _relationToCurrentUser;
  TreeGraphSnapshot? _graphSnapshot;
  TreeGraphViewerDescriptor? _viewerDescriptor;
  String? _viewerRelationLabel;
  bool _isLoading = true;
  String _errorMessage = '';
  String? _currentTreeId;
  String? _currentUserPersonId;
  bool _initialActionHandled = false;

  TreeGraphCapableFamilyTreeService? get _graphTreeService {
    final service = _familyService;
    if (service is TreeGraphCapableFamilyTreeService) {
      return service as TreeGraphCapableFamilyTreeService;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    // Получаем treeId из провайдера ПОСЛЕ построения виджета
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _currentTreeId = Provider.of<TreeProvider>(
        context,
        listen: false,
      ).selectedTreeId;
      _loadData();
    });
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _person = null;
      _treePeople = [];
      _relations = [];
      _historyRecords = [];
      _userProfile = null;
      _dossier = null;
      _relationToCurrentUser = null;
      _graphSnapshot = null;
      _viewerDescriptor = null;
      _viewerRelationLabel = null;
      _currentUserPersonId = null;
      _isLoadingHistory = true;
    });

    if (_currentTreeId == null) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Не удалось определить активное дерево. Откройте карточку ещё раз из дерева или списка родственников.';
      });
      return;
    }

    try {
      // 0. Загружаем профиль ТЕКУЩЕГО пользователя (нужен для getReciprocalType)
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

      final relatives = await _familyService.getRelatives(_currentTreeId!);
      _relations = await _familyService.getRelations(_currentTreeId!);
      _treePeople = relatives;
      final currentUserPerson =
          relatives.where((p) => p.userId == currentUserId);
      _currentUserPersonId =
          currentUserPerson.isNotEmpty ? currentUserPerson.first.id : null;

      _person =
          await _familyService.getPersonById(_currentTreeId!, widget.personId);

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
        _userProfile = await _profileService.getUserProfile(_person!.userId!);
        // Ошибку загрузки профиля пока не считаем критичной
      }

      // 3. Определяем родственную связь с текущим пользователем
      if (_currentUserPersonId != null && _person != null) {
        _relationToCurrentUser = await _familyService.getRelationBetween(
          _currentTreeId!,
          _currentUserPersonId!,
          _person!.id,
        );
        debugPrint(
          'Связь ${widget.personId} с текущим пользователем ($_currentUserPersonId): $_relationToCurrentUser',
        );
        debugPrint('Пол родственника ${_person!.id}: ${_person!.gender}');
      }
      if (_graphTreeService != null && _person != null) {
        final snapshot =
            await _graphTreeService!.getTreeGraphSnapshot(_currentTreeId!);
        _graphSnapshot = snapshot;
        _viewerDescriptor = snapshot.findViewerDescriptor(_person!.id);
        _viewerRelationLabel = _viewerDescriptor?.primaryRelationLabel?.trim();
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
    } catch (e) {
      debugPrint('Ошибка загрузки данных родственника ${widget.personId}: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingHistory = false;
          _errorMessage = 'Не удалось загрузить данные родственника.';
        });
      }
    }
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
          onPressed: () => context.pop(),
        ),
        actions: [
          if (_canDirectEditProfile())
            IconButton(
              icon: Icon(Icons.edit_outlined),
              tooltip: 'Редактировать профиль',
              onPressed: _editRelative,
            ),
          if (_canDirectEditProfile())
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Удалить профиль',
              onPressed: _deleteRelative,
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
    await _graphTreeService!.disconnectRelation(
      treeId: _currentTreeId!,
      relationId: link.relation.id,
    );
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
        await _familyService.deleteRelative(_currentTreeId!, widget.personId);
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
        final box = context.findRenderObject() as RenderBox?;
        // Используем share_plus для отправки ссылки
        await Share.share(
          'Присоединяйтесь к нашему семейному древу в Родне! ${inviteUrl.toString()}',
          subject: 'Приглашение в Родню',
          sharePositionOrigin:
              box!.localToGlobal(Offset.zero) & box.size, // Позиция для iPad
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
            context.push('/relative/details/$personId');
          },
        );
      },
    );
  }

  void _openGalleryViewer(
    List<Map<String, dynamic>> galleryEntries, {
    required int initialIndex,
  }) {
    if (galleryEntries.isEmpty) {
      return;
    }

    final pageController = PageController(initialPage: initialIndex);
    var currentIndex = initialIndex;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final media = galleryEntries[currentIndex];
            final caption = media['caption']?.toString();

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              backgroundColor: Colors.black,
              child: SizedBox(
                width: 520,
                height: 520,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              media['isPrimary'] == true
                                  ? 'Основное фото'
                                  : 'Фото',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: pageController,
                        itemCount: galleryEntries.length,
                        onPageChanged: (index) {
                          setDialogState(() {
                            currentIndex = index;
                          });
                        },
                        itemBuilder: (context, index) {
                          final itemUrl =
                              galleryEntries[index]['url']?.toString() ?? '';
                          return InteractiveViewer(
                            child: itemUrl.isEmpty
                                ? const Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.white,
                                      size: 40,
                                    ),
                                  )
                                : Image.network(
                                    itemUrl,
                                    fit: BoxFit.contain,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: Colors.white,
                                        size: 40,
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        children: [
                          Text(
                            '${currentIndex + 1} из ${galleryEntries.length}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          if (caption != null && caption.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              caption,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                          if (galleryEntries.length > 1) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 52,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: galleryEntries.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final itemUrl = galleryEntries[index]['url']
                                          ?.toString() ??
                                      '';
                                  final isSelected = index == currentIndex;

                                  return InkWell(
                                    onTap: () {
                                      pageController.jumpToPage(index);
                                      setDialogState(() {
                                        currentIndex = index;
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      width: 52,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isSelected
                                              ? Colors.white
                                              : Colors.white24,
                                          width: isSelected ? 2 : 1,
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: itemUrl.isEmpty
                                          ? const ColoredBox(
                                              color: Colors.black54,
                                              child: Icon(
                                                Icons.image_not_supported,
                                                color: Colors.white54,
                                              ),
                                            )
                                          : Image.network(
                                              itemUrl,
                                              fit: BoxFit.cover,
                                            ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
