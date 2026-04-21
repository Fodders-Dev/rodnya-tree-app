import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart'; // Импортируем Provider
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../models/family_person.dart';
import '../models/family_tree.dart';
import '../models/person_dossier.dart';
import '../models/profile_contribution.dart';
import '../models/account_linking_status.dart';
import '../models/user_profile.dart';
import '../providers/tree_provider.dart'; // Импортируем TreeProvider
import 'dart:async'; // Для Future
import 'package:get_it/get_it.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/profile_service_interface.dart';
import '../backend/interfaces/post_service_interface.dart';
import '../backend/interfaces/story_service_interface.dart';
import '../models/post.dart';
import '../models/story.dart';
import '../widgets/post_card.dart';
import '../widgets/post_card_shimmer.dart';
import '../widgets/person_dossier_view.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/story_rail.dart';
import '../widgets/tree_history_sheet.dart';
import '../widgets/glass_panel.dart';
import '../widgets/account_trust_summary_card.dart';
import '../backend/backend_runtime_config.dart';
import '../services/app_status_service.dart';
import '../services/custom_api_post_service.dart';
import '../utils/user_facing_error.dart';

// Примерный виджет для отображения статистики (можно вынести в отдельный файл)

part 'profile_screen_sections.dart';

class _ProfileStatItem extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileStatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _ProfileActionButton extends StatelessWidget {
  const _ProfileActionButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        child: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

String _getSafeDisplayName(UserProfile profile) {
  final rawDisplayName = profile.displayName.trim();

  // Если displayName пустой или равен "Профиль", используем альтернативные источники
  if (rawDisplayName.isEmpty || rawDisplayName == 'Профиль') {
    final parts = <String>[];
    final firstName = profile.firstName.trim();
    if (firstName.isNotEmpty) {
      parts.add(firstName);
    }

    final middleName = profile.middleName.trim();
    if (middleName.isNotEmpty) {
      parts.add(middleName);
    }

    final lastName = profile.lastName.trim();
    if (lastName.isNotEmpty) {
      parts.add(lastName);
    }

    if (parts.isNotEmpty) {
      return parts.join(' ');
    }

    final username = profile.username.trim();
    if (username.isNotEmpty) {
      return username;
    }

    final email = profile.email.trim();
    if (email.isNotEmpty) {
      return email;
    }
  } else {
    // Проверяем, является ли displayName мусорным
    bool looksBad(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return true;
      if (trimmed.length > 80) return true;

      final badWords = ['example.com', 'test123', 'codex', 'mcp', '2026'];
      for (final word in badWords) {
        if (trimmed.toLowerCase().contains(word)) return true;
      }

      final digitCount = RegExp(r'\d').allMatches(trimmed).length;
      if (digitCount >= 6) return true;

      return false;
    }

    if (!looksBad(rawDisplayName)) {
      return rawDisplayName;
    }
  }

  return 'Профиль';
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();
  final FamilyTreeServiceInterface _familyService =
      GetIt.I<FamilyTreeServiceInterface>();
  final ProfileServiceInterface _profileService =
      GetIt.I<ProfileServiceInterface>();
  final PostServiceInterface _postService = GetIt.I<PostServiceInterface>();
  final StoryServiceInterface _storyService = GetIt.I<StoryServiceInterface>();
  final AppStatusService _appStatusService = GetIt.I<AppStatusService>();
  UserProfile? _userProfile;
  String? _currentUserId; // Храним ID текущего пользователя
  int _treeCount = 0;
  int _relativeCount = 0;
  int _postCount = 0;
  List<Post> _userPosts = [];
  List<Story> _userStories = [];
  List<ProfileContribution> _pendingContributions = [];
  FamilyPerson? _selectedTreePerson;
  AccountLinkingStatus? _accountLinkingStatus;
  bool _isLoading = true;
  bool _isLoadingContributions = false;
  String _errorMessage = '';
  bool _postsUnavailable = false;
  bool _isLoadingStories = false;
  bool _storiesUnavailable = false;
  String? _lastStoriesTreeId;

  bool _isWideLayout(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1600;

  TreeKind? _selectedTreeKind(BuildContext context) =>
      context.select<TreeProvider, TreeKind?>(
        (provider) => provider.selectedTreeKind,
      );

  bool _isFriendsTree(BuildContext context) =>
      _selectedTreeKind(context) == TreeKind.friends;

  String _graphStatLabel(BuildContext context) =>
      _isFriendsTree(context) ? 'Связи' : 'Родственники';

  String _graphProfilesLabel(BuildContext context) =>
      _isFriendsTree(context) ? 'Карточки' : 'Профили';

  String _graphPostsTitle(BuildContext context) =>
      _isFriendsTree(context) ? 'Лента круга' : 'Посты';

  String _graphPostsEmptyMessage(BuildContext context) =>
      _isFriendsTree(context)
          ? 'Здесь появятся заметки и фото.'
          : 'Появятся после первой публикации.';

  String _graphSelectionHint(BuildContext context) => _isFriendsTree(context)
      ? 'Сначала выберите активный круг друзей на вкладке "Дерево" или "Родные"'
      : 'Сначала выберите активное дерево на вкладке "Дерево" или "Родные"';

  String get _appBarTitle {
    final profile = _userProfile;
    if (profile == null) {
      return 'Профиль';
    }

    final displayName = _getSafeDisplayName(profile).trim();
    return displayName.isEmpty ? 'Профиль' : displayName;
  }

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final selectedTreeId = context.read<TreeProvider>().selectedTreeId;
    if (_currentUserId == null || _isLoading) {
      return;
    }
    if (_lastStoriesTreeId != selectedTreeId) {
      _lastStoriesTreeId = selectedTreeId;
      unawaited(
        _loadSelectedTreePerson(
          selectedTreeId: selectedTreeId,
          currentUserId: _currentUserId!,
        ),
      );
      unawaited(
        _loadStoriesForContext(
          selectedTreeId: selectedTreeId,
          currentUserId: _currentUserId!,
        ),
      );
    }
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    if (GetIt.I.isRegistered<TreeProvider>()) {
      await GetIt.I<TreeProvider>().clearSelection();
    }
    if (mounted) {
      context.go('/login');
    }
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _postsUnavailable = false;
      _storiesUnavailable = false;
      _selectedTreePerson = null;
      _pendingContributions = [];
      _isLoadingContributions = true;
    });

    try {
      final userId = _authService.currentUserId;
      if (userId == null) {
        throw Exception("Пользователь не авторизован");
      }
      _currentUserId = userId; // Сохраняем ID

      // Загружаем профиль пользователя ИСПОЛЬЗУЯ СЕРВИС
      _userProfile = await _profileService.getUserProfile(_currentUserId!);
      if (_userProfile == null) {
        throw Exception("Профиль пользователя не найден");
      }

      // Загружаем количество деревьев
      final trees = await _familyService.getUserTrees();
      _treeCount = trees.length;
      _relativeCount = await _loadRelativeCount(
        currentUserId: userId,
        trees: trees,
      );

      try {
        _userPosts = await _postService.getPosts(authorId: userId);
        _postCount = _userPosts.length;
      } on CustomApiPostException catch (error) {
        if (error.statusCode == 404) {
          _userPosts = [];
          _postCount = 0;
          _postsUnavailable = true;
        } else {
          rethrow;
        }
      }

      try {
        _pendingContributions =
            await _profileService.getPendingProfileContributions();
      } catch (error) {
        debugPrint('Не удалось загрузить предложения по профилю: $error');
        _pendingContributions = [];
      }

      try {
        _accountLinkingStatus =
            await _profileService.getCurrentAccountLinkingStatus();
      } catch (error) {
        debugPrint('Не удалось загрузить trusted-channel summary: $error');
        _accountLinkingStatus = null;
      }

      if (!mounted) {
        return;
      }
      final selectedTreeId = context.read<TreeProvider>().selectedTreeId;
      _lastStoriesTreeId = selectedTreeId;
      await _loadSelectedTreePerson(
        selectedTreeId: selectedTreeId,
        currentUserId: userId,
      );
      await _loadStoriesForContext(
        selectedTreeId: selectedTreeId,
        currentUserId: userId,
      );
    } catch (e) {
      _appStatusService.reportError(
        e,
        fallbackMessage: 'Не удалось загрузить профиль.',
      );
      if (mounted) {
        setState(() {
          _errorMessage = describeUserFacingError(
            authService: _authService,
            error: e,
            fallbackMessage: _appStatusService.isOffline
                ? 'Нет соединения. Профиль обновится, когда интернет вернётся.'
                : 'Не удалось загрузить профиль.',
          );
        });
      }
      debugPrint('Ошибка при загрузке данных пользователя: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingContributions = false;
        });
      }
    }
  }

  Future<void> _copyProfileConnectionLink(Uri link) async {
    await Clipboard.setData(ClipboardData(text: link.toString()));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ссылка для связи скопирована')),
    );
  }

  Future<void> _shareProfileConnectionLink(Uri link) async {
    final displayName =
        _userProfile == null ? 'Я' : _getSafeDisplayName(_userProfile!).trim();
    await Share.share(
      '$displayName в Родне\n$link\n\n'
      'Откройте ссылку, чтобы перейти к поиску по профильному коду, invite или claim flow.',
    );
  }

  Uri? _buildProfileConnectionLink(String? treeId, String profileCode) {
    final normalizedTreeId = treeId?.trim() ?? '';
    final normalizedProfileCode = profileCode.trim().replaceFirst('@', '');
    if (normalizedTreeId.isEmpty || normalizedProfileCode.isEmpty) {
      return null;
    }

    final baseUri = Uri.parse(BackendRuntimeConfig.current.publicAppUrl);
    return baseUri.replace(
      fragment:
          '/relatives/find/$normalizedTreeId?profileCode=${Uri.encodeQueryComponent(normalizedProfileCode)}',
    );
  }

  String _buildProfileHeroSummary({required String? selectedTreeName}) {
    final treeName = selectedTreeName?.trim();
    if (_selectedTreePerson != null &&
        treeName != null &&
        treeName.isNotEmpty) {
      return 'Эта карточка видна семье в “$treeName”. Здесь вы управляете тем, кто вы на дереве, как с вами связаться и что семье видно о вас.';
    }

    final status = _accountLinkingStatus;
    final summaryTitle = status?.summaryTitle?.trim() ?? '';
    final summaryDetail = status?.summaryDetail?.trim() ?? '';
    if (summaryTitle.isNotEmpty && summaryDetail.isNotEmpty) {
      return '$summaryTitle. $summaryDetail.';
    }
    if (summaryTitle.isNotEmpty) {
      return summaryTitle;
    }
    if (summaryDetail.isNotEmpty) {
      return summaryDetail;
    }

    return 'Заполните досье, чтобы семье было проще узнать вас, связаться с вами и связать ваш профиль с нужной карточкой на дереве.';
  }

  Future<int> _loadRelativeCount({
    required String currentUserId,
    required List<FamilyTree> trees,
  }) async {
    final relativeIds = <String>{};

    for (final tree in trees) {
      try {
        final relatives = await _familyService.getRelatives(tree.id);
        for (final person in relatives) {
          if (person.userId == currentUserId) {
            continue;
          }
          relativeIds.add(person.id);
        }
      } catch (e) {
        debugPrint('Ошибка при загрузке родственников для профиля: $e');
      }
    }

    return relativeIds.length;
  }

  Future<void> _loadStoriesForContext({
    required String? selectedTreeId,
    required String currentUserId,
  }) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoadingStories = true;
      _storiesUnavailable = false;
    });

    try {
      final stories = await _storyService.getStories(
        treeId: selectedTreeId,
        authorId: currentUserId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _userStories = stories;
        _isLoadingStories = false;
      });
    } catch (error) {
      debugPrint('Ошибка загрузки stories в профиле: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _userStories = [];
        _storiesUnavailable = true;
        _isLoadingStories = false;
      });
    }
  }

  Future<void> _loadSelectedTreePerson({
    required String? selectedTreeId,
    required String currentUserId,
  }) async {
    if (!mounted) {
      return;
    }

    if (selectedTreeId == null || selectedTreeId.isEmpty) {
      setState(() {
        _selectedTreePerson = null;
      });
      return;
    }

    try {
      final relatives = await _familyService.getRelatives(selectedTreeId);
      final person = relatives.cast<FamilyPerson?>().firstWhere(
            (candidate) => candidate?.userId == currentUserId,
            orElse: () => null,
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedTreePerson = person;
      });
    } catch (error) {
      debugPrint('Ошибка загрузки карточки пользователя в дереве: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedTreePerson = null;
      });
    }
  }

  void _showSelectedTreePersonGallery(FamilyPerson person) {
    final gallery = person.photoGallery;
    if (gallery.isEmpty) {
      return;
    }

    final pageController = PageController();
    var currentIndex = 0;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final media = gallery[currentIndex];
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
                                  : 'Фото из карточки',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: pageController,
                        itemCount: gallery.length,
                        onPageChanged: (index) {
                          setDialogState(() {
                            currentIndex = index;
                          });
                        },
                        itemBuilder: (context, index) {
                          final itemUrl =
                              gallery[index]['url']?.toString() ?? '';
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
                            '${currentIndex + 1} из ${gallery.length}',
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

  Future<void> _showSelectedTreePersonHistory(FamilyPerson person) async {
    final treeProvider = context.read<TreeProvider>();
    final treeId = treeProvider.selectedTreeId;
    if (treeId == null || treeId.isEmpty) {
      return;
    }

    final historyFuture = _familyService.getTreeHistory(
      treeId: treeId,
      personId: person.id,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return TreeHistorySheet(
          historyFuture: historyFuture,
          title: 'История изменений',
          subtitle: person.displayName,
          currentUserId: _authService.currentUserId,
          emptyMessage: 'Для этой карточки пока нет записей в журнале.',
          errorBuilder: (error) => describeUserFacingError(
            authService: _authService,
            error: error,
            fallbackMessage: 'Не удалось загрузить историю изменений.',
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

  @override
  Widget build(BuildContext context) {
    final treeProvider = Provider.of<TreeProvider>(context);
    final selectedTreeId = treeProvider.selectedTreeId;
    final selectedTreeKind = treeProvider.selectedTreeKind;
    final selectedTreeName = treeProvider.selectedTreeName;
    final isFriendsTree = selectedTreeKind == TreeKind.friends;

    return Scaffold(
      appBar: AppBar(
        title: Text(_appBarTitle),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'settings') {
                context.push('/profile/settings');
              } else if (value == 'about') {
                context.push('/profile/about');
              } else if (value == 'logout') {
                _signOut();
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                PopupMenuItem<String>(
                  value: 'settings',
                  child: Text('Настройки'),
                ),
                PopupMenuItem<String>(
                  value: 'about',
                  child: Text('О приложении'),
                ),
                PopupMenuItem<String>(value: 'logout', child: Text('Выйти')),
              ];
            },
          ),
        ],
      ),
      body: _isLoading
          ? _buildProfileStateCard(
              icon: Icons.person_search_outlined,
              title: 'Собираем профиль',
              message:
                  'Подтягиваем досье, доверенные каналы и семейный контекст.',
              showProgress: true,
            )
          : _errorMessage.isNotEmpty
              ? _buildProfileStateCard(
                  icon: _appStatusService.isOffline
                      ? Icons.cloud_off_outlined
                      : Icons.person_outline_rounded,
                  title: _appStatusService.isOffline
                      ? 'Нет соединения'
                      : 'Профиль временно недоступен',
                  message: _errorMessage,
                  actions: [
                    FilledButton.icon(
                      onPressed: () {
                        _appStatusService.requestRetry();
                        unawaited(_loadUserData());
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Повторить'),
                    ),
                  ],
                )
              : _userProfile == null ||
                      _currentUserId == null // Проверяем и userId
                  ? _buildProfileStateCard(
                      icon: Icons.person_off_outlined,
                      title: 'Профиль не собрался',
                      message:
                          'Не удалось получить досье пользователя. Попробуйте обновить экран ещё раз.',
                      actions: [
                        FilledButton.icon(
                          onPressed: () {
                            _appStatusService.requestRetry();
                            unawaited(_loadUserData());
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Повторить'),
                        ),
                      ],
                    )
                  : RefreshIndicator(
                      onRefresh: _loadUserData,
                      child: CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 1180),
                                child: GlassPanel(
                                  padding: const EdgeInsets.all(24),
                                  borderRadius: BorderRadius.circular(32),
                                  child: _isWideLayout(context)
                                      ? Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              flex: 2,
                                              child: Column(
                                                children: [
                                                  CircleAvatar(
                                                    radius: 52,
                                                    backgroundImage:
                                                        _userProfile!
                                                                    .photoURL !=
                                                                null
                                                            ? NetworkImage(
                                                                _userProfile!
                                                                    .photoURL!,
                                                              )
                                                            : null,
                                                    child: _userProfile!
                                                                .photoURL ==
                                                            null
                                                        ? Icon(
                                                            Icons.person,
                                                            size: 52,
                                                          )
                                                        : null,
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Text(
                                                    _getSafeDisplayName(
                                                      _userProfile!,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .headlineSmall
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 10),
                                                  Text(
                                                    _buildProfileHeroSummary(
                                                      selectedTreeName:
                                                          selectedTreeName,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.copyWith(
                                                          color: Theme.of(
                                                            context,
                                                          )
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                          height: 1.35,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 24),
                                            Expanded(
                                              flex: 5,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  if (selectedTreeName !=
                                                      null) ...[
                                                    _buildGraphContextBanner(
                                                      context,
                                                      isFriendsTree:
                                                          isFriendsTree,
                                                      selectedTreeName:
                                                          selectedTreeName,
                                                      selectedTreePerson:
                                                          _selectedTreePerson,
                                                    ),
                                                    const SizedBox(height: 16),
                                                  ],
                                                  if ((_userProfile!.city !=
                                                              null &&
                                                          _userProfile!.city!
                                                              .isNotEmpty) ||
                                                      (_userProfile!.country !=
                                                              null &&
                                                          _userProfile!.country!
                                                              .isNotEmpty))
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.location_on,
                                                          size: 16,
                                                          color: Theme.of(
                                                            context,
                                                          )
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                        ),
                                                        const SizedBox(
                                                            width: 4),
                                                        Text(
                                                          '${_userProfile!.city ?? ''}${(_userProfile!.city != null && _userProfile!.city!.isNotEmpty && _userProfile!.country != null && _userProfile!.country!.isNotEmpty) ? ', ' : ''}${_userProfile!.country ?? ''}',
                                                          style: Theme.of(
                                                            context,
                                                          )
                                                              .textTheme
                                                              .bodyMedium
                                                              ?.copyWith(
                                                                color: Theme.of(
                                                                  context,
                                                                )
                                                                    .colorScheme
                                                                    .onSurfaceVariant,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  const SizedBox(height: 20),
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      _ProfileStatItem(
                                                        label: 'Постов',
                                                        value: _postCount
                                                            .toString(),
                                                      ),
                                                      _ProfileStatItem(
                                                        label: _graphStatLabel(
                                                          context,
                                                        ),
                                                        value: _relativeCount
                                                            .toString(),
                                                      ),
                                                      _ProfileStatItem(
                                                        label: 'Деревья',
                                                        value: _treeCount
                                                            .toString(),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 24),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child:
                                                            _ProfileActionButton(
                                                          label:
                                                              _graphProfilesLabel(
                                                            context,
                                                          ),
                                                          onPressed: () {
                                                            final currentSelectedTreeId =
                                                                treeProvider
                                                                    .selectedTreeId;
                                                            if (currentSelectedTreeId ==
                                                                null) {
                                                              ScaffoldMessenger
                                                                  .of(
                                                                context,
                                                              ).showSnackBar(
                                                                SnackBar(
                                                                  content: Text(
                                                                    _graphSelectionHint(
                                                                      context,
                                                                    ),
                                                                  ),
                                                                  action:
                                                                      SnackBarAction(
                                                                    label:
                                                                        'Выбрать',
                                                                    onPressed: () =>
                                                                        context
                                                                            .go(
                                                                      '/tree',
                                                                    ),
                                                                  ),
                                                                ),
                                                              );
                                                            } else {
                                                              context.push(
                                                                '/profile/offline_profiles',
                                                              );
                                                            }
                                                          },
                                                        ),
                                                      ),
                                                      const SizedBox(width: 16),
                                                      Expanded(
                                                        child:
                                                            _ProfileActionButton(
                                                          label:
                                                              'Редактировать',
                                                          filled: true,
                                                          onPressed: () =>
                                                              context.push(
                                                            '/profile/edit',
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        )
                                      : Column(
                                          children: [
                                            if (selectedTreeName != null) ...[
                                              _buildGraphContextBanner(
                                                context,
                                                isFriendsTree: isFriendsTree,
                                                selectedTreeName:
                                                    selectedTreeName,
                                                selectedTreePerson:
                                                    _selectedTreePerson,
                                              ),
                                              const SizedBox(height: 16),
                                            ],
                                            CircleAvatar(
                                              radius: 50,
                                              backgroundImage:
                                                  _userProfile!.photoURL != null
                                                      ? NetworkImage(
                                                          _userProfile!
                                                              .photoURL!,
                                                        )
                                                      : null,
                                              child:
                                                  _userProfile!.photoURL == null
                                                      ? Icon(
                                                          Icons.person,
                                                          size: 50,
                                                        )
                                                      : null,
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              _getSafeDisplayName(
                                                  _userProfile!),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .headlineSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              _buildProfileHeroSummary(
                                                selectedTreeName:
                                                    selectedTreeName,
                                              ),
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                    height: 1.35,
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            if ((_userProfile!.city != null &&
                                                    _userProfile!
                                                        .city!.isNotEmpty) ||
                                                (_userProfile!.country !=
                                                        null &&
                                                    _userProfile!
                                                        .country!.isNotEmpty))
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.location_on,
                                                    size: 16,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '${_userProfile!.city ?? ''}${(_userProfile!.city != null && _userProfile!.city!.isNotEmpty && _userProfile!.country != null && _userProfile!.country!.isNotEmpty) ? ', ' : ''}${_userProfile!.country ?? ''}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.copyWith(
                                                          color: Theme.of(
                                                            context,
                                                          )
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            const SizedBox(height: 16),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceEvenly,
                                              children: [
                                                _ProfileStatItem(
                                                  label: 'Постов',
                                                  value: _postCount.toString(),
                                                ),
                                                _ProfileStatItem(
                                                  label: _graphStatLabel(
                                                    context,
                                                  ),
                                                  value:
                                                      _relativeCount.toString(),
                                                ),
                                                _ProfileStatItem(
                                                  label: 'Деревья',
                                                  value: _treeCount.toString(),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 24),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: _ProfileActionButton(
                                                    label: _graphProfilesLabel(
                                                      context,
                                                    ),
                                                    onPressed: () {
                                                      final currentSelectedTreeId =
                                                          treeProvider
                                                              .selectedTreeId;
                                                      if (currentSelectedTreeId ==
                                                          null) {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                              _graphSelectionHint(
                                                                context,
                                                              ),
                                                            ),
                                                            action:
                                                                SnackBarAction(
                                                              label: 'Выбрать',
                                                              onPressed: () =>
                                                                  context.go(
                                                                '/tree',
                                                              ),
                                                            ),
                                                          ),
                                                        );
                                                      } else {
                                                        context.push(
                                                          '/profile/offline_profiles',
                                                        );
                                                      }
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: _ProfileActionButton(
                                                    label: 'Редактировать',
                                                    filled: true,
                                                    onPressed: () => context
                                                        .push('/profile/edit'),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),
                          if (_accountLinkingStatus != null)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16.0,
                                  16.0,
                                  16.0,
                                  0,
                                ),
                                child: _buildTrustSummarySection(),
                              ),
                            ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16.0,
                                16.0,
                                16.0,
                                0,
                              ),
                              child: _buildStoriesRailSection(),
                            ),
                          ),
                          if (_profileCodeLabel() != null)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16.0,
                                  16.0,
                                  16.0,
                                  0,
                                ),
                                child: _buildProfileConnectionSection(
                                  selectedTreeId: selectedTreeId,
                                  selectedTreeName: selectedTreeName,
                                ),
                              ),
                            ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16.0,
                                16.0,
                                16.0,
                                0,
                              ),
                              child: PersonDossierView(
                                dossier: PersonDossier.fromProfile(
                                  _userProfile!,
                                  treePerson: _selectedTreePerson,
                                  isSelf: true,
                                ),
                                headerChips: [
                                  if (selectedTreeName != null)
                                    Chip(
                                      avatar: const Icon(
                                        Icons.account_tree_outlined,
                                        size: 18,
                                      ),
                                      label: Text(selectedTreeName),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(
                              16.0,
                              16.0,
                              16.0,
                              0,
                            ),
                            sliver: SliverToBoxAdapter(
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Предложения от семьи',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_isLoadingContributions)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  0,
                                ),
                                child: _buildProfileStateCard(
                                  icon: Icons.edit_note_outlined,
                                  title: 'Проверяем семейные правки',
                                  message:
                                      'Смотрим, не прислали ли родственники новые предложения по вашему профилю.',
                                  showProgress: true,
                                ),
                              ),
                            )
                          else if (_pendingContributions.isEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  0,
                                ),
                                child: _buildContributionEmptyState(),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                0,
                              ),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (BuildContext context, int index) {
                                    final contribution =
                                        _pendingContributions[index];
                                    return Padding(
                                      padding: EdgeInsets.only(
                                        bottom: index ==
                                                _pendingContributions.length - 1
                                            ? 0
                                            : 10,
                                      ),
                                      child:
                                          _buildContributionCard(contribution),
                                    );
                                  },
                                  childCount: _pendingContributions.length,
                                ),
                              ),
                            ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(
                                16.0, 24.0, 16.0, 8.0),
                            sliver: SliverToBoxAdapter(
                              child: Text(
                                _graphPostsTitle(context),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                          if (_isLoading && _userPosts.isEmpty)
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) => const PostCardShimmer(),
                                childCount: 2,
                              ),
                            )
                          else if (_userPosts.isEmpty)
                            SliverToBoxAdapter(
                              child: EmptyStateWidget(
                                icon: Icons.post_add_outlined,
                                title: _postsUnavailable
                                    ? 'Посты недоступны'
                                    : 'Постов нет',
                                message: _postsUnavailable
                                    ? 'Попробуйте позже.'
                                    : _graphPostsEmptyMessage(context),
                                actionLabel:
                                    _postsUnavailable ? 'Обновить' : 'Создать',
                                onAction: () async {
                                  if (_postsUnavailable) {
                                    _loadUserData();
                                    return;
                                  }
                                  final result =
                                      await context.push('/post/create');
                                  if (result == true) {
                                    _loadUserData();
                                  }
                                },
                              ),
                            )
                          else
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  return PostCard(
                                    post: _userPosts[index],
                                    onDeleted: () => _loadUserData(),
                                  );
                                },
                                childCount: _userPosts.length,
                              ),
                            ),
                          const SliverToBoxAdapter(child: SizedBox(height: 40)),
                        ],
                      ),
                    ),
    );
  }
}
