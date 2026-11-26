import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:collection' show Queue;
import 'dart:ui';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import '../utils/date_parser.dart';
import '../utils/invitation_share.dart';

import '../theme/app_theme.dart';
import '../models/family_tree.dart';
import '../models/family_person.dart';
import '../models/family_relation.dart';
import '../models/chat_preview.dart';
import '../providers/tree_provider.dart';
import '../widgets/glass_panel.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/chat_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/identity_conflicts_capable_family_tree_service.dart';
import '../backend/interfaces/invitation_link_service_interface.dart';
import '../backend/interfaces/semya_capable_family_tree_service.dart';
import '../backend/interfaces/tree_graph_capable_family_tree_service.dart';
import '../backend/models/identity_field_conflict.dart';
import '../backend/models/semya.dart';
import '../models/tree_graph_snapshot.dart';
import '../services/app_status_service.dart';
import '../utils/photo_url.dart';
import '../utils/relative_details_route.dart';
import '../utils/snackbar.dart';
import '../utils/user_facing_error.dart';
import '../widgets/branch_switcher_chip.dart';
import '../widgets/identity_conflicts_badge.dart';
import '../widgets/identity_conflicts_sheet.dart';
import '../widgets/relation_picker_sheet.dart';

part 'relatives/relatives_data.dart';
part 'relatives/relatives_actions.dart';
part 'relatives/relatives_header_section.dart';
part 'relatives/relatives_list_section.dart';
part 'relatives/relatives_widgets.dart';

class RelativesScreen extends StatefulWidget {
  const RelativesScreen({super.key});

  /// F3: сброс session-состояния свёртки «Нужно пригласить» между
  /// тестами (паттерн session-dismiss баннеров).
  @visibleForTesting
  static void debugResetPendingSectionState() {
    _RelativesScreenState._pendingSectionExpandedThisSession = false;
  }

  @override
  State<RelativesScreen> createState() => _RelativesScreenState();
}

class _RelativesScreenState extends State<RelativesScreen> {
  final FamilyTreeServiceInterface _familyService =
      GetIt.I<FamilyTreeServiceInterface>();

  final ChatServiceInterface _chatService = GetIt.I<ChatServiceInterface>();

  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();

  final InvitationLinkServiceInterface _invitationLinkService =
      GetIt.I<InvitationLinkServiceInterface>();

  final AppStatusService _appStatusService = GetIt.I<AppStatusService>();

  StreamSubscription? _relativesSubscription;

  StreamSubscription? _relationsSubscription;

  StreamSubscription? _chatsSubscription;

  TreeProvider? _treeProviderInstance;

  bool _isLoading = true;

  String? _currentTreeId;

  String? _currentUserId;

  String _errorMessage = '';

  int _pendingRequestsCount = 0;

  List<FamilyPerson> _allRelatives = [];

  List<FamilyRelation> _relations = [];

  String? _currentUserPersonId;

  SemyaRole? _callerSemyaRole;

  List<ChatPreview> _chatPreviews = [];

  bool _isRelationsReady = false;

  bool _isChatsReady = false;

  bool _isPendingRequestsLoading = true;

  String _searchQuery = '';

  late final TextEditingController _searchController;

  // Мобильный поиск живёт в топбаре за иконкой (как в чатах) и
  // раскрывается на месте заголовка — отдельной строки поиска нет.
  final FocusNode _searchFocusNode = FocusNode();

  bool _isSearchOpen = false;

  // F3: «Нужно пригласить» свёрнута по умолчанию; решение пользователя
  // живёт сессию (static — переживает переключение вкладок/экранов).
  static bool _pendingSectionExpandedThisSession = false;

  // Phase 3.4 chunk 5: per-row + header conflict badges.
  // `_conflictCounts` keyed by personId → unresolved count.
  // `_treeConflictsCache` — flat list для sheet'а (filtered by
  // targetPersonId при открытии).
  Map<String, int> _conflictCounts = const <String, int>{};

  List<IdentityFieldConflict> _treeConflictsCache =
      const <IdentityFieldConflict>[];

  Map<String, TreeGraphViewerDescriptor> _viewerDescriptorsByPersonId =
      const <String, TreeGraphViewerDescriptor>{};

  @override
  void initState() {
    super.initState();

    debugPrint('[_RelativesScreenState initState] called');

    _searchController = TextEditingController();
    _searchController.addListener(() {
      final next = _searchController.text;
      if (next != _searchQuery) {
        setState(() => _searchQuery = next);
      }
    });

    _currentUserId = _authService.currentUserId;
    debugPrint(
      '[_RelativesScreenState initState] Current User ID: $_currentUserId',
    );

    if (_currentUserId == null) {
      debugPrint('Ошибка: Пользователь не аутентифицирован!');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Пользователь не аутентифицирован.';
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _treeProviderInstance = Provider.of<TreeProvider>(context, listen: false);
      _treeProviderInstance!.addListener(_handleTreeChange);
      _currentTreeId = _treeProviderInstance!.selectedTreeId;
      // Объясняющий диалог «Проверить родство» при первом входе убран
      // (02.09.2026): подсказку несёт tooltip самой кнопки, а модалка
      // перекрывала список людей в первую же секунду.
      if (_currentTreeId != null) {
        _loadDataForSelectedTree(_currentTreeId!);
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    _treeProviderInstance?.removeListener(_handleTreeChange);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final treeProvider = Provider.of<TreeProvider>(context);
    final selectedTreeId = treeProvider.selectedTreeId;
    final selectedTreeName = treeProvider.selectedTreeName ??
        (_isFriendsTree(treeProvider) ? 'Круг друзей' : 'Родственники');
    final isFriendsTree = _isFriendsTree(treeProvider);

    // --- ФИЛЬТРАЦИЯ СПИСКОВ ---
    final String currentUserId = _authService.currentUserId ?? '';
    final List<FamilyPerson> baseRelatives =
        _allRelatives.where((p) => p.userId != currentUserId).toList();
    final String trimmedQuery = _searchQuery.trim().toLowerCase();
    final List<FamilyPerson> visibleRelatives = trimmedQuery.isEmpty
        ? baseRelatives
        : baseRelatives.where((p) {
            final name = p.displayName.toLowerCase();
            final relation = (p.relation ?? '').toLowerCase();
            return name.contains(trimmedQuery) ||
                relation.contains(trimmedQuery);
          }).toList();
    final totalChatReadyCount =
        baseRelatives.where((person) => _canStartChat(person)).length;
    final totalInviteReadyCount =
        baseRelatives.where((person) => _canInviteRelative(person)).length;
    final totalInAppCount = baseRelatives.where((p) {
      final id = p.userId;
      return id != null && id.isNotEmpty;
    }).length;
    // -------------------------

    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    final isWideLayout = _isWideLayout(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(AppTheme.topbarHeight(context)),
        child: _buildRelativesTopbar(
          theme: theme,
          tokens: tokens,
          treeProvider: treeProvider,
          selectedTreeId: selectedTreeId,
          isFriendsTree: isFriendsTree,
        ),
      ),
      body: selectedTreeId == null
          ? _buildNoTreeSelected()
          : _isLoading
              ? _buildLoadingState()
              : _errorMessage.isNotEmpty && _allRelatives.isEmpty
                  ? _buildErrorState(selectedTreeId)
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1420),
                        child: Padding(
                          // На телефоне список идёт сразу под шапкой:
                          // строка поиска переехала в топбар.
                          padding: isWideLayout
                              ? const EdgeInsets.fromLTRB(16, 12, 16, 16)
                              : const EdgeInsets.fromLTRB(10, 0, 10, 8),
                          child: isWideLayout
                              ? Column(
                                  children: [
                                    _buildGraphContextBanner(
                                      treeName: selectedTreeName,
                                      isFriendsTree: isFriendsTree,
                                      relativesCount: baseRelatives.length,
                                      inAppCount: totalInAppCount,
                                      totalTreePeopleCount:
                                          _allRelatives.length,
                                    ),
                                    _maybeConflictTreeBanner(),
                                    if (_showSecondaryLoadingStrip) ...[
                                      const SizedBox(height: 12),
                                      _buildSecondaryLoadingStrip(),
                                    ],
                                    const SizedBox(height: 12),
                                    _buildRelativesSearchField(
                                      theme: theme,
                                      tokens: tokens,
                                    ),
                                    const SizedBox(height: 16),
                                    Expanded(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: _buildRelativesList(
                                              key: ValueKey(
                                                'relatives_$selectedTreeId',
                                              ),
                                              relativesForTab: visibleRelatives,
                                              isOnlineTab: false,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          SizedBox(
                                            width: 320,
                                            child: _buildRelativesSidePanel(
                                              relativesCount:
                                                  baseRelatives.length,
                                              chatReadyCount:
                                                  totalChatReadyCount,
                                              inviteReadyCount:
                                                  totalInviteReadyCount,
                                              treeName: selectedTreeName,
                                              isFriendsTree: isFriendsTree,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : PopScope(
                                  canPop: !_isSearchOpen,
                                  onPopInvokedWithResult: (didPop, _) {
                                    if (!didPop) _closeSearch();
                                  },
                                  child: Column(
                                    children: [
                                      _maybeConflictTreeBanner(),
                                      if (_showSecondaryLoadingStrip) ...[
                                        const SizedBox(height: 10),
                                        _buildSecondaryLoadingStrip(),
                                      ],
                                      Expanded(
                                        child: _buildRelativesList(
                                          key: ValueKey(
                                            'relatives_$selectedTreeId',
                                          ),
                                          relativesForTab: visibleRelatives,
                                          isOnlineTab: false,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                    ),
      // On phones the actions occupy their own row below the list. The old
      // stacked FABs covered a relative card and competed with the shell nav.
      // Wide layout keeps using the labelled actions in its side panel.
      bottomNavigationBar: selectedTreeId == null || isWideLayout
          ? null
          : _buildRelativesPrimaryActionBar(selectedTreeId, treeProvider),
    );
  }

  _ContactStatus _getContactStatus(FamilyPerson relative) {
    if (_canStartChat(relative)) {
      return _ContactStatus(
        label: 'Можно написать',
        color: Colors.green.shade700,
      );
    }

    if (_canInviteRelative(relative)) {
      return _ContactStatus(
        label: 'Нужно пригласить',
        color: Colors.orange.shade700,
      );
    }

    return _ContactStatus(
      label: 'Только просмотр',
      color: Colors.grey.shade600,
    );
  }

  void _updateRelativesState(VoidCallback fn) {
    setState(fn);
  }
}
