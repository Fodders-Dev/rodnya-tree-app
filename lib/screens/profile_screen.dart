import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart'; // Импортируем Provider
import '../models/family_person.dart';
import '../models/family_tree.dart';
import '../models/user_profile.dart';
import '../models/profile_note.dart'; // Импортируем модель заметки
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
import '../widgets/empty_state_widget.dart';
import '../widgets/story_rail.dart';
import '../widgets/tree_history_sheet.dart';
import '../widgets/glass_panel.dart';
import '../services/custom_api_post_service.dart';

// Примерный виджет для отображения статистики (можно вынести в отдельный файл)
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
  UserProfile? _userProfile;
  String? _currentUserId; // Храним ID текущего пользователя
  int _treeCount = 0;
  int _relativeCount = 0;
  int _postCount = 0;
  List<Post> _userPosts = [];
  List<Story> _userStories = [];
  FamilyPerson? _selectedTreePerson;
  bool _isLoading = true;
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
      if (mounted) {
        setState(() {
          _errorMessage = 'Ошибка загрузки данных: $e';
        });
      }
      debugPrint('Ошибка при загрузке данных пользователя: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
          errorBuilder: (error) => 'Не удалось загрузить историю: $error',
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

  // Функция для показа диалога добавления/редактирования заметки
  void _showAddEditNoteDialog({ProfileNote? note}) {
    final titleController = TextEditingController(text: note?.title ?? '');
    final contentController = TextEditingController(text: note?.content ?? '');
    final formKey = GlobalKey<FormState>();
    final bool isEditing = note != null;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEditing ? 'Редактировать заметку' : 'Добавить заметку'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              // Добавим прокрутку на случай длинного контента
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: titleController,
                    decoration: InputDecoration(labelText: 'Заголовок'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Пожалуйста, введите заголовок';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 16),
                  TextFormField(
                    controller: contentController,
                    decoration: InputDecoration(
                      labelText: 'Содержание',
                      alignLabelWithHint: true, // Выравниваем метку по верху
                    ),
                    maxLines: 5, // Больше строк для удобства
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Пожалуйста, введите содержание';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (isEditing) // Кнопка удаления только при редактировании
              TextButton(
                child: Text('Удалить', style: TextStyle(color: Colors.red)),
                onPressed: () async {
                  // Запрос подтверждения перед удалением
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('Подтверждение'),
                      content: Text(
                        'Вы уверены, что хотите удалить эту заметку?',
                      ),
                      actions: [
                        TextButton(
                          child: Text('Отмена'),
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                        TextButton(
                          child: Text('Удалить'),
                          onPressed: () => Navigator.of(context).pop(true),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true && _currentUserId != null) {
                    try {
                      await _profileService.deleteProfileNote(
                        _currentUserId!,
                        note.id,
                      );
                      if (!context.mounted) return;
                      Navigator.of(
                        context,
                      ).pop(); // Закрываем диалог редактирования
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Заметка удалена')),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ошибка удаления: $e')),
                      );
                    }
                  }
                },
              ),
            TextButton(
              child: Text('Отмена'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text(isEditing ? 'Сохранить' : 'Добавить'),
              onPressed: () async {
                if (formKey.currentState!.validate() &&
                    _currentUserId != null) {
                  try {
                    if (isEditing) {
                      // Создаем обновленную заметку (со старым id и createdAt)
                      final updatedNote = ProfileNote(
                        id: note.id,
                        title: titleController.text,
                        content: contentController.text,
                        createdAt:
                            note.createdAt, // Сохраняем исходную дату создания
                      );
                      await _profileService.updateProfileNote(
                        _currentUserId!,
                        updatedNote,
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Заметка обновлена')),
                      );
                    } else {
                      await _profileService.addProfileNote(
                        _currentUserId!,
                        titleController.text,
                        contentController.text,
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Заметка добавлена')),
                      );
                    }
                    Navigator.of(context).pop(); // Закрываем диалог
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка сохранения: $e')),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final treeProvider = Provider.of<TreeProvider>(context);
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
          ? Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    // Добавим отступы для ошибки
                    padding: const EdgeInsets.all(16.0),
                    child: Text(_errorMessage, textAlign: TextAlign.center),
                  ),
                )
              : _userProfile == null ||
                      _currentUserId == null // Проверяем и userId
                  ? Center(child: Text('Не удалось загрузить профиль.'))
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
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16.0,
                                0,
                                16.0,
                                0,
                              ),
                              child: _buildStoriesRailSection(),
                            ),
                          ),
                          // --- НАЧАЛО: Секция для заметок ---
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
                                    'Заметки',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: () => _showAddEditNoteDialog(),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Добавить'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          StreamBuilder<List<ProfileNote>>(
                            stream: _profileService.getProfileNotesStream(
                              _currentUserId!,
                            ),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              if (snapshot.hasError) {
                                return SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    child: Text(
                                      'Заметки временно недоступны.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                );
                              }
                              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                                return SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    child: Text(
                                      'Пока пусто.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                );
                              }

                              final notes = snapshot.data!;

                              return SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  0,
                                ),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (BuildContext context, int index) {
                                      final note = notes[index];
                                      return Padding(
                                        padding: EdgeInsets.only(
                                          bottom: index == notes.length - 1
                                              ? 0
                                              : 10,
                                        ),
                                        child: _buildNotePreviewCard(note),
                                      );
                                    },
                                    childCount: notes.length,
                                  ),
                                ),
                              );
                            },
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

  Widget _buildStoriesRailSection() {
    return StoryRail(
      title: 'Истории',
      currentUserId: _currentUserId ?? '',
      stories: _userStories,
      isLoading: _isLoadingStories,
      unavailable: _storiesUnavailable,
      onRetry: () {
        if (_currentUserId != null) {
          _loadStoriesForContext(
            selectedTreeId: context.read<TreeProvider>().selectedTreeId,
            currentUserId: _currentUserId!,
          );
        }
      },
      onCreateStory: () async {
        final result = await context.push('/stories/create');
        if (!mounted) {
          return;
        }
        if (result == true && _currentUserId != null) {
          _loadStoriesForContext(
            selectedTreeId: context.read<TreeProvider>().selectedTreeId,
            currentUserId: _currentUserId!,
          );
        }
      },
      onOpenStories: (stories) async {
        if (stories.isEmpty) {
          return;
        }
        final story = stories.last;
        final route = '/stories/view/${story.treeId}/${story.authorId}';
        await context.push(
          route,
        );
        if (!mounted) {
          return;
        }
        if (_currentUserId != null) {
          _loadStoriesForContext(
            selectedTreeId: context.read<TreeProvider>().selectedTreeId,
            currentUserId: _currentUserId!,
          );
        }
      },
      emptyLabel: 'Добавьте первую историю.',
    );
  }

  Widget _buildNotePreviewCard(ProfileNote note) {
    final theme = Theme.of(context);
    final previewText =
        note.content.trim().isEmpty ? 'Без текста' : note.content.trim();
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _showAddEditNoteDialog(note: note),
      child: GlassPanel(
        padding: const EdgeInsets.all(16),
        borderRadius: BorderRadius.circular(24),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.note_alt_outlined,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title.trim().isEmpty ? 'Без названия' : note.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    previewText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContextBadge({
    required BuildContext context,
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraphContextBanner(
    BuildContext context, {
    required bool isFriendsTree,
    required String selectedTreeName,
    FamilyPerson? selectedTreePerson,
  }) {
    final theme = Theme.of(context);
    final personPhotoUrl = selectedTreePerson?.primaryPhotoUrl;
    final photoCount = selectedTreePerson?.photoGallery.length ?? 0;
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isFriendsTree
                    ? Icons.diversity_3_outlined
                    : Icons.account_tree_outlined,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isFriendsTree ? 'Активен круг' : 'Активно дерево',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildContextBadge(
                context: context,
                icon: isFriendsTree
                    ? Icons.diversity_3_outlined
                    : Icons.account_tree_outlined,
                label: selectedTreeName,
              ),
              _buildContextBadge(
                context: context,
                icon: Icons.person_outline,
                label: 'Мой профиль',
              ),
              FilledButton.tonalIcon(
                onPressed: () => context.go('/tree'),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Дерево'),
              ),
            ],
          ),
          if (selectedTreePerson != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSecondaryContainer
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.onSecondaryContainer
                      .withValues(alpha: 0.12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundImage: personPhotoUrl != null
                            ? NetworkImage(personPhotoUrl)
                            : null,
                        child: personPhotoUrl == null
                            ? Text(
                                selectedTreePerson.initials,
                                style: const TextStyle(fontSize: 14),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Карточка в дереве',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              selectedTreePerson.displayName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildContextBadge(
                                  context: context,
                                  icon: Icons.photo_library_outlined,
                                  label: photoCount == 0
                                      ? 'Без фото'
                                      : photoCount == 1
                                          ? '1 фото'
                                          : '$photoCount фото',
                                ),
                                if (selectedTreePerson.primaryPhotoUrl != null)
                                  _buildContextBadge(
                                    context: context,
                                    icon: Icons.star_outline,
                                    label: 'Основное фото',
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => context
                            .push('/relative/details/${selectedTreePerson.id}'),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Открыть'),
                      ),
                      OutlinedButton.icon(
                        onPressed: photoCount == 0
                            ? null
                            : () => _showSelectedTreePersonGallery(
                                selectedTreePerson),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(
                          photoCount == 0 ? 'Фото' : 'Фото ($photoCount)',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _showSelectedTreePersonHistory(selectedTreePerson),
                        icon: const Icon(Icons.history_outlined),
                        label: const Text('История'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
