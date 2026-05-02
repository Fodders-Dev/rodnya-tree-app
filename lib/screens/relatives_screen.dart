import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:ui';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

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
import '../backend/interfaces/invitation_link_service_interface.dart';
import '../services/app_status_service.dart';
import '../utils/photo_url.dart';
import '../utils/snackbar.dart';
import '../utils/user_facing_error.dart';

part 'relatives_screen_sections.dart';

class _ContactStatus {
  const _ContactStatus({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;
}

String _countLabel(
  int count, {
  required String one,
  required String few,
  required String many,
}) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  if (mod10 == 1 && mod100 != 11) {
    return '$count $one';
  }
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return '$count $few';
  }
  return '$count $many';
}

class RelativesScreen extends StatefulWidget {
  const RelativesScreen({super.key});

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
  List<ChatPreview> _chatPreviews = [];
  bool _isRelationsReady = false;
  bool _isChatsReady = false;
  bool _isPendingRequestsLoading = true;

  @override
  void initState() {
    super.initState();

    debugPrint('[_RelativesScreenState initState] called');

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
      _treeProviderInstance = Provider.of<TreeProvider>(context, listen: false);
      _treeProviderInstance!.addListener(_handleTreeChange);
      _currentTreeId = _treeProviderInstance!.selectedTreeId;
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
    super.dispose();
  }

  void _handleTreeChange() {
    if (!mounted) return;
    final newTreeId = _treeProviderInstance?.selectedTreeId;
    if (_currentTreeId != newTreeId) {
      _currentTreeId = newTreeId;
      _cancelSubscriptions();
      if (_currentTreeId != null) {
        _loadDataForSelectedTree(_currentTreeId!);
      } else {
        setState(() {
          _isLoading = false;
          _allRelatives = [];
          _relations = [];
          _currentUserPersonId = null;
          _chatPreviews = [];
          _pendingRequestsCount = 0;
          _errorMessage = '';
        });
      }
    }
  }

  Future<void> _loadDataForSelectedTree(String treeId) async {
    if (!mounted || _currentUserId == null) return;
    debugPrint('RelativesScreen: Загрузка данных для дерева $treeId');
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _allRelatives = [];
      _relations = [];
      _currentUserPersonId = null;
      _chatPreviews = [];
      _pendingRequestsCount = 0;
      _isRelationsReady = false;
      _isChatsReady = false;
      _isPendingRequestsLoading = true;
    });

    unawaited(_checkPendingRequests(treeId));
    try {
      await _setupDataListeners(treeId, _currentUserId!);
    } catch (e) {
      debugPrint('Ошибка при инициализации данных для дерева $treeId: $e');
      _appStatusService.reportError(
        e,
        fallbackMessage: 'Не удалось загрузить список родных.',
      );
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_allRelatives.isEmpty) {
            _errorMessage = _appStatusService.isOffline
                ? 'Нет соединения. Родные появятся, когда интернет вернётся.'
                : 'Ошибка загрузки данных дерева.';
          }
        });
      }
    }
  }

  Future<void> _checkPendingRequests(String treeId) async {
    try {
      final requests = await _familyService.getRelationRequests(treeId: treeId);
      if (mounted) {
        setState(() {
          _pendingRequestsCount = requests.length;
        });
      }
    } catch (e) {
      debugPrint('Ошибка проверки запросов: $e');
      _appStatusService.reportError(
        e,
        fallbackMessage: 'Не удалось обновить запросы по дереву.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPendingRequestsLoading = false;
        });
      }
    }
  }

  Future<void> _setupDataListeners(String treeId, String currentUserId) async {
    _cancelSubscriptions();

    final completerRelatives = Completer<void>();

    _relativesSubscription = _familyService.getRelativesStream(treeId).listen(
      (relatives) {
        String? currentUserPersonId;
        for (final person in relatives) {
          if (person.userId == _currentUserId) {
            currentUserPersonId = person.id;
            break;
          }
        }

        if (mounted) {
          setState(() {
            _allRelatives = relatives;
            _currentUserPersonId = currentUserPersonId;
            _errorMessage = '';
            _isLoading = false;
          });
          if (!completerRelatives.isCompleted) completerRelatives.complete();
        }
      },
      onError: (error, stackTrace) {
        if (mounted) {
          _handleStreamError(
            error,
            stackTrace,
            'RelativesStreamError',
            completerRelatives,
          );
        }
      },
      cancelOnError: false,
    );

    _relationsSubscription = _familyService.getRelationsStream(treeId).listen(
      (relations) {
        if (mounted) {
          setState(() {
            _relations = relations;
            _isRelationsReady = true;
          });
        }
      },
      onError: (error, stackTrace) {
        if (mounted) {
          debugPrint('Ошибка в Stream связей: $error');
          _handleStreamError(
            error,
            stackTrace,
            'RelationsStreamError',
            null,
          );
        }
      },
      cancelOnError: false,
    );

    _chatsSubscription = _chatService.getUserChatsStream(currentUserId).listen(
      (chatPreviews) {
        if (mounted) {
          setState(() {
            _chatPreviews = chatPreviews;
            _isChatsReady = true;
          });
        }
      },
      onError: (error, stackTrace) {
        if (mounted) {
          debugPrint('Ошибка в Stream чатов: $error');
          _handleStreamError(
            error,
            stackTrace,
            'ChatsStreamError',
            null,
          );
        }
      },
      cancelOnError: false,
    );

    try {
      await completerRelatives.future.timeout(const Duration(seconds: 10));
    } catch (e, stackTrace) {
      debugPrint('Ошибка или таймаут при ожидании данных: $e');
      debugPrint('Error: $e\n$stackTrace');
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
          _errorMessage = _appStatusService.isOffline
              ? 'Нет соединения. Проверьте интернет и попробуйте ещё раз.'
              : 'Не удалось загрузить список родных. Попробуйте ещё раз.';
        });
      }
    }
  }

  void _cancelSubscriptions() {
    _relativesSubscription?.cancel();
    _relationsSubscription?.cancel();
    _chatsSubscription?.cancel();
    _relativesSubscription = null;
    _relationsSubscription = null;
    _chatsSubscription = null;
    debugPrint('RelativesScreen: Подписки на данные отменены');
  }

  bool _isWideLayout(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1500;

  bool _isFriendsTree(TreeProvider provider) =>
      provider.selectedTreeKind == TreeKind.friends;

  String _graphAddLabel(TreeProvider provider) =>
      _isFriendsTree(provider) ? 'Добавить человека' : 'Добавить родственника';

  String _graphFindLabel(TreeProvider provider) =>
      _isFriendsTree(provider) ? 'Найти человека' : 'Найти родственника';

  @override
  Widget build(BuildContext context) {
    final treeProvider = Provider.of<TreeProvider>(context);
    final selectedTreeId = treeProvider.selectedTreeId;
    final selectedTreeName = treeProvider.selectedTreeName ??
        (_isFriendsTree(treeProvider) ? 'Круг друзей' : 'Родственники');
    final isFriendsTree = _isFriendsTree(treeProvider);

    // --- ФИЛЬТРАЦИЯ СПИСКОВ ---
    final String currentUserId = _authService.currentUserId ?? '';
    final List<FamilyPerson> visibleRelatives =
        _allRelatives.where((p) => p.userId != currentUserId).toList();
    final chatReadyCount =
        visibleRelatives.where((person) => _canStartChat(person)).length;
    final inviteReadyCount =
        visibleRelatives.where((person) => _canInviteRelative(person)).length;
    // -------------------------

    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(76),
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
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: _isWideLayout(context)
                              ? Column(
                                  children: [
                                    _buildGraphContextBanner(
                                      treeName: selectedTreeName,
                                      isFriendsTree: isFriendsTree,
                                      relativesCount: visibleRelatives.length,
                                    ),
                                    if (_showSecondaryLoadingStrip) ...[
                                      const SizedBox(height: 12),
                                      _buildSecondaryLoadingStrip(),
                                    ],
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
                                                  visibleRelatives.length,
                                              chatReadyCount: chatReadyCount,
                                              inviteReadyCount:
                                                  inviteReadyCount,
                                              treeName: selectedTreeName,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _buildGraphContextBanner(
                                      treeName: selectedTreeName,
                                      isFriendsTree: isFriendsTree,
                                      relativesCount: visibleRelatives.length,
                                    ),
                                    if (_showSecondaryLoadingStrip) ...[
                                      const SizedBox(height: 10),
                                      _buildSecondaryLoadingStrip(),
                                    ],
                                    const SizedBox(height: 12),
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
      floatingActionButton: selectedTreeId == null
          ? null
          : FloatingActionButton(
              heroTag: 'add_relative_fab',
              onPressed: () {
                context.push('/relatives/add/$selectedTreeId');
              },
              tooltip: _graphAddLabel(treeProvider),
              child: Icon(Icons.add),
            ),
    );
  }

  bool get _showSecondaryLoadingStrip =>
      !_isRelationsReady || !_isChatsReady || _isPendingRequestsLoading;

  Widget _buildLoadingState() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: GlassPanel(
          padding: const EdgeInsets.all(24),
          borderRadius: BorderRadius.circular(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Загружаем родных',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Сначала подтянем список, остальное догрузим следом.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String selectedTreeId) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: GlassPanel(
            padding: const EdgeInsets.all(24),
            borderRadius: BorderRadius.circular(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _appStatusService.isOffline
                      ? Icons.cloud_off_outlined
                      : Icons.people_outline_rounded,
                  size: 40,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 14),
                Text(
                  _appStatusService.isOffline
                      ? 'Нет соединения'
                      : 'Родные временно недоступны',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    _appStatusService.requestRetry();
                    unawaited(_loadDataForSelectedTree(selectedTreeId));
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryLoadingStrip() {
    final theme = Theme.of(context);
    final labels = <String>[
      if (!_isRelationsReady) 'связи',
      if (!_isChatsReady) 'чаты',
      if (_isPendingRequestsLoading) 'запросы',
    ];
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      borderRadius: BorderRadius.circular(22),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Догружаем: ${labels.join(', ')}.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoTreeSelected() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: GlassPanel(
          padding: const EdgeInsets.all(24),
          borderRadius: BorderRadius.circular(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_tree_outlined,
                size: 42,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 14),
              Text(
                'Выберите дерево',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Здесь появятся люди и действия.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Открыть'),
                onPressed: () => context.go('/tree?selector=1'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRelativesSidePanel({
    required int relativesCount,
    required int chatReadyCount,
    required int inviteReadyCount,
    required String treeName,
  }) {
    final treeProvider = Provider.of<TreeProvider>(context, listen: false);
    final isFriendsTree = _isFriendsTree(treeProvider);
    final peopleLabel = isFriendsTree ? 'в круге' : 'в дереве';
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSideStatChip(
                icon: isFriendsTree
                    ? Icons.diversity_3_outlined
                    : Icons.account_tree_outlined,
                label: treeName,
              ),
              _buildSideStatChip(
                icon: Icons.people_outline,
                label: '$relativesCount $peopleLabel',
              ),
              if (chatReadyCount > 0)
                _buildSideStatChip(
                  icon: Icons.chat_bubble_outline,
                  label: _countLabel(
                    chatReadyCount,
                    one: 'чат',
                    few: 'чата',
                    many: 'чатов',
                  ),
                ),
              if (inviteReadyCount > 0)
                _buildSideStatChip(
                  icon: Icons.person_add_alt_1_outlined,
                  label: 'Пригласить $inviteReadyCount',
                ),
              if (_pendingRequestsCount > 0)
                _buildSideStatChip(
                  icon: Icons.notifications_none,
                  label: 'Запросы $_pendingRequestsCount',
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _currentTreeId == null
                    ? null
                    : () => context.push('/relatives/add/${_currentTreeId!}'),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Добавить'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go('/tree'),
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Дерево'),
              ),
              OutlinedButton.icon(
                onPressed: _currentTreeId == null
                    ? null
                    : () => context.push('/relatives/find/${_currentTreeId!}'),
                icon: const Icon(Icons.search),
                label: const Text('Найти'),
              ),
              if (_pendingRequestsCount > 0)
                OutlinedButton.icon(
                  onPressed: _currentTreeId == null
                      ? null
                      : () => context
                          .push('/relatives/requests/${_currentTreeId!}'),
                  icon: const Icon(Icons.mark_email_unread_outlined),
                  label: const Text('Запросы'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSideStatChip({
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraphContextBanner({
    required String treeName,
    required bool isFriendsTree,
    required int relativesCount,
  }) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final inAppCount = _allRelatives.where((p) {
      final id = p.userId;
      return id != null && id.isNotEmpty;
    }).length;

    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceStrong,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tokens.surfaceLine),
        boxShadow: tokens.panelShadow(theme.brightness),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isFriendsTree
                  ? Icons.diversity_3_outlined
                  : Icons.account_tree_outlined,
              color: tokens.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isFriendsTree ? 'АКТИВНЫЙ КРУГ' : 'АКТИВНОЕ ДЕРЕВО',
                  style: AppTheme.sans(
                    color: tokens.inkMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  treeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.serif(
                    color: tokens.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.18,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$inAppCount из $relativesCount в приложении',
                  style: AppTheme.sans(
                    color: tokens.inkMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: tokens.accent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            child: InkWell(
              onTap: () => context.go('/tree'),
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Дерево',
                      style: AppTheme.sans(
                        color: tokens.accentInk,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: tokens.accentInk,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRelativesList({
    required Key key,
    required List<FamilyPerson> relativesForTab,
    required bool isOnlineTab,
  }) {
    debugPrint(
      '[_buildRelativesList called] isOnlineTab: $isOnlineTab, relatives count: ${relativesForTab.length}',
    );

    if (relativesForTab.isEmpty) {
      final treeProvider = Provider.of<TreeProvider>(context, listen: false);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassPanel(
            padding: const EdgeInsets.all(16),
            borderRadius: BorderRadius.circular(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isOnlineTab
                      ? Icons.chat_bubble_outline
                      : Icons.people_outline,
                  size: 32,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 10),
                Text(
                  isOnlineTab
                      ? 'Чатов нет'
                      : _isFriendsTree(Provider.of<TreeProvider>(
                          context,
                          listen: false,
                        ))
                          ? 'Людей пока нет'
                          : 'Родных пока нет',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (!isOnlineTab) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Добавьте первого человека.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _currentTreeId == null
                        ? null
                        : () =>
                            context.push('/relatives/add/${_currentTreeId!}'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: Text(_graphAddLabel(treeProvider)),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    int byName(FamilyPerson a, FamilyPerson b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());

    final pendingPeople = <FamilyPerson>[];
    final joinedPeople = <FamilyPerson>[];
    for (final relative in relativesForTab) {
      if (_canInviteRelative(relative)) {
        pendingPeople.add(relative);
      } else {
        joinedPeople.add(relative);
      }
    }
    pendingPeople.sort(byName);
    joinedPeople.sort(byName);

    final List<dynamic> flatList = [];
    if (!isOnlineTab && pendingPeople.isNotEmpty) {
      flatList.add(_RelativesSectionHeader(
        title: 'Нужно пригласить',
        count: pendingPeople.length,
      ));
      flatList.addAll(pendingPeople);
    }
    if (joinedPeople.isNotEmpty) {
      flatList.add(_RelativesSectionHeader(
        title: isOnlineTab ? 'Чаты' : 'В приложении',
      ));
      flatList.addAll(joinedPeople);
    }
    if (!isOnlineTab && pendingPeople.isEmpty && joinedPeople.isEmpty) {
      flatList.addAll(relativesForTab);
    }

    return ListView.builder(
      key: key,
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      itemCount: flatList.length,
      itemBuilder: (context, index) {
        final item = flatList[index];

        if (item is _RelativesSectionHeader) {
          final theme = Theme.of(context);
          final tokens = theme.extension<RodnyaDesignTokens>() ??
              (theme.brightness == Brightness.dark
                  ? RodnyaDesignTokens.dark
                  : RodnyaDesignTokens.light);
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    style: AppTheme.serif(
                      color: tokens.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.18,
                    ),
                  ),
                ),
                if (item.count != null && item.count! > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.warmSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${item.count}',
                      style: AppTheme.sans(
                        color: tokens.warm,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          );
        } else if (item is FamilyPerson) {
          final relative = item;
          final relationDescription = _getRelationDescription(relative);

          ChatPreview? chatPreview;
          if (isOnlineTab && relative.userId != null) {
            try {
              chatPreview = _chatPreviews.firstWhere(
                (preview) => preview.otherUserId == relative.userId,
              );
            } catch (e) {
              chatPreview = null;
            }
          }

          final String lastMessageText = chatPreview?.lastMessage ?? '';
          final DateTime? lastMessageTimestamp = chatPreview?.lastMessageTime;
          final int unreadCount = chatPreview?.unreadCount ?? 0;
          final bool isLastMessageFromMe =
              chatPreview?.lastMessageSenderId == _currentUserId;
          final bool canStartChat = _canStartChat(relative);
          final bool canInvite = _canInviteRelative(relative);
          final contactStatus = _getContactStatus(relative);
          final int photoCount = relative.photoGallery.length;
          final bool hasGallery = photoCount > 0;
          final avatarImage =
              buildAvatarImageProvider(relative.primaryPhotoUrl);

          final theme = Theme.of(context);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.20),
                ),
              ),
              child: ListTile(
                leading: GestureDetector(
                  onTap: () {
                    debugPrint(
                      'Avatar tapped for ${relative.displayName}, navigating to details...',
                    );
                    context.push('/relative/details/${relative.id}');
                  },
                  child: CircleAvatar(
                    radius: 25,
                    backgroundImage: avatarImage,
                    child: avatarImage == null
                        ? Text(relative.initials,
                            style: TextStyle(fontSize: 18))
                        : null,
                  ),
                ),
                title: Text(
                  relative.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color:
                        unreadCount > 0 ? Theme.of(context).primaryColor : null,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      relationDescription,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                    if (!isOnlineTab || hasGallery)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            // Skip the per-tile invite-status chip for the
                            // pending section since the section header already
                            // says "Нужно пригласить". Keep "Можно написать"
                            // and "Только просмотр" so chat-ready and view-only
                            // states stay scannable per row.
                            if (!isOnlineTab && !canInvite)
                              _buildRelativeInfoChip(
                                context,
                                icon: Icons.circle,
                                label: contactStatus.label,
                                color: contactStatus.color,
                                iconSize: 8,
                              ),
                            if (hasGallery)
                              _buildRelativeInfoChip(
                                context,
                                icon: Icons.photo_library_outlined,
                                label: _countLabel(
                                  photoCount,
                                  one: 'фото',
                                  few: 'фото',
                                  many: 'фото',
                                ),
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            if (relative.primaryPhotoUrl != null)
                              _buildRelativeInfoChip(
                                context,
                                icon: Icons.star_outline,
                                label: 'Основное фото',
                                color: Theme.of(context).colorScheme.primary,
                              ),
                          ],
                        ),
                      ),
                    if (isOnlineTab && lastMessageText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Row(
                          children: [
                            if (isLastMessageFromMe)
                              Text(
                                'Вы: ',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            Expanded(
                              child: Text(
                                lastMessageText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: unreadCount > 0
                                      ? Colors.black87
                                      : Colors.black54,
                                  fontWeight: unreadCount > 0
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (isOnlineTab &&
                        lastMessageText.isEmpty &&
                        relative.userId != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Text(
                          'Нет сообщений',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[500],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
                trailing: isOnlineTab && lastMessageTimestamp != null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatTimestamp(lastMessageTimestamp),
                            style: TextStyle(
                              fontSize: 12,
                              color: unreadCount > 0
                                  ? Theme.of(context).primaryColor
                                  : Colors.grey,
                              fontWeight: unreadCount > 0
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          if (unreadCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: CircleAvatar(
                                radius: 9,
                                backgroundColor: Theme.of(context).primaryColor,
                                child: Text(
                                  unreadCount.toString(),
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.onPrimary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (canStartChat)
                            IconButton(
                              icon: const Icon(Icons.message_outlined),
                              tooltip: 'Написать ${relative.displayName}',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _openChatWithRelative(relative),
                            ),
                          if (canInvite)
                            IconButton(
                              icon: const Icon(Icons.person_add_alt_1_outlined),
                              tooltip: 'Пригласить ${relative.displayName}',
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  _shareInviteForRelative(relative),
                            ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                onTap: () {
                  if (isOnlineTab) {
                    if (canStartChat) {
                      _openChatWithRelative(relative);
                    } else {
                      debugPrint(
                        'Cannot chat with self or invalid user, navigating to details for ${relative.displayName}',
                      );
                      context.push('/relative/details/${relative.id}');
                    }
                  } else {
                    debugPrint(
                      'Offline tab, navigating to details for ${relative.displayName}',
                    );
                    context.push('/relative/details/${relative.id}');
                  }
                },
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          );
        }
        return SizedBox.shrink();
      },
    );
  }

  String _getRelationDescription(FamilyPerson relative) {
    final currentUserPersonId = _currentUserPersonId;
    if (_currentUserId == null || currentUserPersonId == null) {
      return 'Родственник';
    }

    if (relative.id == currentUserPersonId) {
      return 'Вы';
    }

    final directRelation = _relations.firstWhere(
      (r) =>
          (r.person1Id == currentUserPersonId && r.person2Id == relative.id) ||
          (r.person1Id == relative.id && r.person2Id == currentUserPersonId),
      orElse: () => FamilyRelation(
        id: '',
        person1Id: '',
        person2Id: '',
        relation1to2: RelationType.other,
        relation2to1: RelationType.other,
        treeId: _currentTreeId ?? '',
        isConfirmed: false,
        createdAt: DateTime(0),
      ),
    );

    if (directRelation.id.isNotEmpty) {
      final bool userIsPerson1 =
          directRelation.person1Id == currentUserPersonId;
      final RelationType relevantRelationType = userIsPerson1
          ? directRelation.relation2to1
          : directRelation.relation1to2;
      final relationLabel = FamilyRelation.getRelationName(
        relevantRelationType,
        relative.gender,
      );
      if (relationLabel.isNotEmpty &&
          relationLabel !=
              FamilyRelation.getGenericRelationTypeStringRu(
                RelationType.other,
              )) {
        return relationLabel;
      }
    }

    final treeProvider = _treeProviderInstance;
    if (treeProvider?.selectedTreeKind == TreeKind.friends) {
      return 'Связь';
    }
    return 'Родственник';
  }

  Widget _buildRelativeInfoChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    double iconSize = 14,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  bool _canStartChat(FamilyPerson relative) {
    final userId = relative.userId;
    return userId != null &&
        userId.isNotEmpty &&
        userId != _authService.currentUserId;
  }

  bool _canInviteRelative(FamilyPerson relative) {
    final userId = relative.userId;
    return (userId == null || userId.isEmpty) &&
        relative.id != _currentUserPersonId &&
        _currentTreeId != null;
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

  void _openChatWithRelative(FamilyPerson relative) {
    final userId = relative.userId;
    if (userId == null || userId.isEmpty) {
      return;
    }

    final nameParam = Uri.encodeComponent(relative.displayName);
    final photoUrl = relative.primaryPhotoUrl;
    final photoParam = (photoUrl != null && photoUrl.isNotEmpty)
        ? Uri.encodeComponent(photoUrl)
        : '';
    debugPrint(
      'Navigating to chat with ${relative.displayName} (ID: $userId)',
    );
    context.push(
      '/relatives/chat/$userId?name=$nameParam&photo=$photoParam&relativeId=${relative.id}',
    );
  }

  Future<void> _shareInviteForRelative(FamilyPerson relative) async {
    if (!_canInviteRelative(relative) || _currentTreeId == null) {
      return;
    }

    try {
      final inviteUrl = _invitationLinkService.buildInvitationLink(
        treeId: _currentTreeId!,
        personId: relative.id,
      );
      await Share.share(
        (_treeProviderInstance?.selectedTreeKind == TreeKind.friends)
            ? 'Присоединяйтесь к нашему кругу друзей в Родне: ${inviteUrl.toString()}'
            : 'Присоединяйтесь к нашему семейному древу в Родне: ${inviteUrl.toString()}',
        subject: _treeProviderInstance?.selectedTreeKind == TreeKind.friends
            ? 'Приглашение в круг друзей'
            : 'Приглашение в Родню',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось подготовить приглашение.'),
        ),
      );
    }
  }

  String _formatTimestamp(DateTime dateTime) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime yesterday = today.subtract(const Duration(days: 1));

    final DateTime messageDate = DateTime(
      dateTime.year,
      dateTime.month,
      dateTime.day,
    );

    if (messageDate == today) {
      return DateFormat.Hm('ru').format(dateTime);
    } else if (messageDate == yesterday) {
      return 'Вчера';
    } else if (now.difference(dateTime).inDays < 7) {
      return DateFormat.E('ru').format(dateTime);
    } else {
      return DateFormat('dd.MM.yyyy', 'ru').format(dateTime);
    }
  }

  void _handleStreamError(
    dynamic error,
    StackTrace stackTrace,
    String reason,
    Completer<void>? completer,
  ) {
    debugPrint('Ошибка при загрузке данных: $error\n$stackTrace');
    _appStatusService.reportError(
      error,
      fallbackMessage: 'Не удалось обновить данные на экране родных.',
    );
    if (mounted) {
      setState(() {
        if (reason == 'RelationsStreamError') {
          _isRelationsReady = true;
        }
        if (reason == 'ChatsStreamError') {
          _isChatsReady = true;
        }
        if (_allRelatives.isNotEmpty) {
          return;
        }
        _errorMessage = describeUserFacingError(
          authService: _authService,
          error: error,
          fallbackMessage: 'Ошибка при загрузке данных ($reason).',
        );
      });
    }
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  }

  Widget _buildRelativesTopbar({
    required ThemeData theme,
    required RodnyaDesignTokens tokens,
    required TreeProvider treeProvider,
    required String? selectedTreeId,
    required bool isFriendsTree,
  }) {
    return SizedBox.expand(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
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
            padding: const EdgeInsets.fromLTRB(18, 12, 12, 14),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  Text(
                    isFriendsTree ? 'Круг' : 'Родные',
                    style: AppTheme.serif(
                      color: tokens.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.22,
                    ),
                  ),
                  const Spacer(),
                  ..._buildRelativesAppBarActions(
                    treeProvider: treeProvider,
                    selectedTreeId: selectedTreeId,
                    isFriendsTree: isFriendsTree,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RelativesSectionHeader {
  const _RelativesSectionHeader({required this.title, this.count});

  final String title;
  final int? count;
}
