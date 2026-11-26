// ignore_for_file: library_private_types_in_public_api
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:share_plus/share_plus.dart';
import '../utils/date_parser.dart';
import '../utils/invitation_share.dart';
import 'package:get_it/get_it.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/identity_conflicts_capable_family_tree_service.dart';
import '../backend/interfaces/identity_service_interface.dart';
import '../backend/interfaces/identity_duplicate_capable_family_tree_service.dart';
import '../backend/interfaces/person_tree_resolution_capable_family_tree_service.dart';
import '../backend/interfaces/semya_capable_family_tree_service.dart';
import '../backend/interfaces/story_request_capable_family_tree_service.dart';
import '../backend/models/identity_field_conflict.dart';
import '../backend/models/semya.dart';
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
import '../utils/image_decode.dart';
import '../utils/photo_url.dart';
import '../utils/relative_details_route.dart';
import '../utils/user_facing_error.dart';
import '../widgets/profile_biography_section.dart';
import '../widgets/family_story_questions_sheet.dart';
import '../widgets/story_request_status_line.dart';
import '../models/family_story_question.dart';
import 'profile_all_photos_screen.dart';
import 'profile_article_editor_screen.dart';
import 'profile_article_history_screen.dart';
import 'profile_visibility_screen.dart';
import 'profile_voice_recordings_screen.dart';

part 'relative_details/relative_details_data.dart';
part 'relative_details/relative_details_mutations.dart';
part 'relative_details/relative_details_hero.dart';
part 'relative_details/relative_details_dossier.dart';
part 'relative_details/relative_details_gallery.dart';
part 'relative_details/relative_details_stories.dart';
part 'relative_details/relative_details_relations.dart';
part 'relative_details/relative_details_widgets.dart';

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

  bool _dossierLoadFailed = false;

  FamilyPerson? _person;

  List<FamilyPerson> _treePeople = [];

  // MVP-1.1 «Спросить историю»: члены семьи текущего дерева (не только те,
  // у кого есть своя персона) — резолвится один раз здесь, чтобы
  // _buildStoryAskTargets оставался синхронным и не дёргал сеть на тап.
  // Бэкенд уже принимает любого члена семьи как адресата
  // (store._isUserInTreeOrSemya) — правок бэкенда это не требует.
  List<SemyaMembership> _semyaMembers = [];

  // MVP-1 «Спросить историю»: bumped after a story-request is sent from
  // this screen so StoryRequestStatusLine's key changes and it remounts
  // (fresh fetch) instead of showing stale «нет открытых вопросов».
  int _storyRequestStatusTick = 0;

  int _biographyRefreshVersion = 0;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_person?.displayName ?? 'Профиль'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          tooltip: 'Назад',
          onPressed: _navigateBack,
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

  _RelativeContactStatus _getContactStatus() {
    if (_person?.id == _currentUserPersonId) {
      return const _RelativeContactStatus(
        label: 'Это вы',
        description:
            'Эта карточка уже связана с вашим профилем и показывает семье актуальные данные о вас.',
        icon: Icons.person,
        color: Colors.blue,
      );
    }

    if (_canStartChatWithPerson()) {
      return _RelativeContactStatus(
        label: 'Есть аккаунт в Родне',
        description:
            'Сейчас проще всего быстро выйти на контакт: написать человеку или помочь с обновлением профиля.',
        icon: Icons.verified_user_outlined,
        color: Colors.green.shade700,
      );
    }

    if (_canInvitePerson()) {
      return _RelativeContactStatus(
        label: 'Пока без аккаунта',
        description:
            'Сначала отправьте приглашение, чтобы человек подключился к дереву, чату и своему профилю.',
        icon: Icons.person_add_alt_1_outlined,
        color: Colors.orange.shade700,
      );
    }

    return _RelativeContactStatus(
      label: 'Карточка в дереве',
      description:
          'Пока это только карточка в дереве. Здесь лучше всего собирать семейные сведения, фотографии и память о человеке.',
      icon: Icons.visibility_outlined,
      color: Colors.grey.shade700,
    );
  }

  Color _graphWarningAccent(TreeGraphWarning warning) {
    final colorScheme = Theme.of(context).colorScheme;
    switch ((warning.severity).trim().toLowerCase()) {
      case 'error':
        return colorScheme.error;
      case 'info':
        return colorScheme.primary;
      default:
        return colorScheme.tertiary;
    }
  }

  IconData _graphWarningIcon(TreeGraphWarning warning) {
    switch ((warning.severity).trim().toLowerCase()) {
      case 'error':
        return Icons.error_outline_rounded;
      case 'info':
        return Icons.info_outline_rounded;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  void _updateRelativeDetailsState(VoidCallback fn) {
    setState(fn);
  }
}
