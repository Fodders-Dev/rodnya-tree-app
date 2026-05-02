import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/circle_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/post_service_interface.dart';
import '../models/circle.dart';
import '../models/family_person.dart';
import '../models/family_tree.dart';
import '../models/post.dart';
import '../providers/tree_provider.dart';
import '../services/app_status_service.dart';
import '../services/local_storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/user_facing_error.dart';
import '../widgets/audience_picker.dart';
import '../widgets/glass_panel.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _contentController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();
  final FamilyTreeServiceInterface _familyTreeService =
      GetIt.I<FamilyTreeServiceInterface>();
  final PostServiceInterface _postService = GetIt.I<PostServiceInterface>();
  final CircleServiceInterface? _circleService =
      GetIt.I.isRegistered<CircleServiceInterface>()
          ? GetIt.I<CircleServiceInterface>()
          : null;
  final LocalStorageService _localStorageService =
      GetIt.I<LocalStorageService>();
  final AppStatusService _appStatusService = GetIt.I<AppStatusService>();

  bool _isPublic = false;
  bool _isLoading = false;
  bool _isLoadingCircles = false;
  bool _isLoadingPeople = false;
  bool _circlesUnavailable = false;
  bool _branchCandidatesUnavailable = false;
  List<XFile> _selectedImages = <XFile>[];
  List<FamilyCircle> _audienceCircles = <FamilyCircle>[];
  List<FamilyPerson> _availablePeople = <FamilyPerson>[];
  final Set<String> _selectedBranchPersonIds = <String>{};
  TreeContentScopeType _scopeType = TreeContentScopeType.wholeTree;
  String? _selectedCircleId;
  String? _currentTreeId;
  FamilyTree? _currentTreeMeta;

  bool get _isFriendsTree => _currentTreeMeta?.isFriendsTree == true;

  String get _selectedAudienceLabel {
    final selectedCircle = _selectedCircle;
    if (_scopeType == TreeContentScopeType.branches &&
        _selectedBranchPersonIds.isNotEmpty) {
      return _isFriendsTree
          ? '${_selectedBranchPersonIds.length} круг(а)'
          : '${_selectedBranchPersonIds.length} ветк(и)';
    }
    if (selectedCircle != null) {
      return selectedCircle.name;
    }
    return _isFriendsTree ? 'Весь круг' : 'Всё дерево';
  }

  String get _selectedAudienceDetail {
    final selectedCircle = _selectedCircle;
    final parts = <String>[];
    if (_scopeType == TreeContentScopeType.branches &&
        _selectedBranchPersonIds.isNotEmpty) {
      parts.add(
        _isFriendsTree
            ? 'выбранные люди и их круги'
            : 'выбранные люди и их ветки',
      );
    } else if (selectedCircle != null) {
      parts.add(_memberLabel(selectedCircle.memberCount));
      if ((selectedCircle.description ?? '').trim().isNotEmpty) {
        parts.add(selectedCircle.description!.trim());
      } else if (selectedCircle.isAllTree) {
        parts.add(_isFriendsTree ? 'весь круг' : 'вся семья');
      } else if (selectedCircle.isAuto) {
        parts.add('автоматический круг по ветке');
      }
    } else {
      parts.add(_isFriendsTree ? 'внутри текущего круга' : 'внутри дерева');
    }
    if (_isPublic) {
      parts.add('публично по ссылке');
    }
    return parts.join(' · ');
  }

  FamilyCircle? get _selectedCircle {
    final selectedId = _selectedCircleId;
    if (selectedId == null) {
      return null;
    }
    for (final circle in _audienceCircles) {
      if (circle.id == selectedId) {
        return circle;
      }
    }
    return null;
  }

  List<FamilyCircle> get _quickAudienceCircles {
    if (_audienceCircles.isEmpty) {
      return const <FamilyCircle>[];
    }

    final selected = _selectedCircle;
    final result = <FamilyCircle>[];
    void addIfMissing(FamilyCircle? circle) {
      if (circle == null) {
        return;
      }
      if (result.any((entry) => entry.id == circle.id)) {
        return;
      }
      result.add(circle);
    }

    addIfMissing(_firstCircleWhere((circle) => circle.isAllTree));
    addIfMissing(
      _firstCircleWhere((circle) => circle.isFavorites),
    );
    addIfMissing(
      _firstCircleWhere((circle) => circle.isAuto),
    );
    addIfMissing(selected);
    for (final circle in _audienceCircles) {
      if (result.length >= 4) {
        break;
      }
      addIfMissing(circle);
    }
    return result.take(4).toList(growable: false);
  }

  FamilyCircle? _firstCircleWhere(bool Function(FamilyCircle) test) {
    for (final circle in _audienceCircles) {
      if (test(circle)) {
        return circle;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _currentTreeId = Provider.of<TreeProvider>(
      context,
      listen: false,
    ).selectedTreeId;
    _loadCurrentTreeMeta();
    _loadAudienceCircles();
    _loadBranchCandidates();
  }

  Future<void> _loadCurrentTreeMeta() async {
    final treeId = _currentTreeId;
    if (treeId == null) {
      return;
    }
    final treeMeta = await _localStorageService.getTree(treeId);
    if (!mounted) {
      return;
    }
    setState(() {
      _currentTreeMeta = treeMeta;
    });
  }

  Future<void> _loadBranchCandidates() async {
    if (_currentTreeId == null) {
      return;
    }

    setState(() {
      _isLoadingPeople = true;
    });

    try {
      final people = await _familyTreeService.getRelatives(_currentTreeId!);
      final sortedPeople = List<FamilyPerson>.from(people)
        ..sort(
          (left, right) => left.displayName.toLowerCase().compareTo(
                right.displayName.toLowerCase(),
              ),
        );
      if (!mounted) {
        return;
      }
      setState(() {
        _availablePeople = sortedPeople;
        _branchCandidatesUnavailable = false;
      });
    } catch (error) {
      _appStatusService.reportError(
        error,
        fallbackMessage: 'Не удалось загрузить список веток для публикации.',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _branchCandidatesUnavailable = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPeople = false;
        });
      }
    }
  }

  Future<void> _loadAudienceCircles() async {
    final treeId = _currentTreeId;
    final circleService = _circleService;
    if (treeId == null || circleService == null) {
      return;
    }

    setState(() {
      _isLoadingCircles = true;
    });

    try {
      final circles = await circleService.getCircles(treeId);
      if (!mounted) {
        return;
      }
      setState(() {
        _audienceCircles = circles;
        _selectedCircleId = _resolveSelectedCircleId(circles);
        _circlesUnavailable = false;
      });
    } catch (error) {
      _appStatusService.reportError(
        error,
        fallbackMessage: 'Не удалось загрузить круги для публикации.',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _circlesUnavailable = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCircles = false;
        });
      }
    }
  }

  String? _resolveSelectedCircleId(List<FamilyCircle> circles) {
    final selectedId = _selectedCircleId;
    if (selectedId != null &&
        circles.any((circle) => circle.id == selectedId)) {
      return selectedId;
    }
    for (final circle in circles) {
      if (circle.isAllTree) {
        return circle.id;
      }
    }
    return circles.isEmpty ? null : circles.first.id;
  }

  Future<void> _pickImages() async {
    try {
      final pickedFiles = await _picker.pickMultiImage(
        imageQuality: 80,
        maxWidth: 1080,
      );
      if (pickedFiles.isEmpty || !mounted) {
        return;
      }

      final willBeTrimmed = _selectedImages.length + pickedFiles.length > 5;
      setState(() {
        final nextImages = <XFile>[..._selectedImages, ...pickedFiles];
        _selectedImages = nextImages.take(5).toList();
      });
      if (willBeTrimmed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Можно прикрепить не более 5 изображений.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Ошибка выбора изображений: $e');
      if (mounted) {
        _showMessage('Не удалось выбрать изображения.');
      }
    }
  }

  Future<void> _createPost() async {
    final content = _contentController.text.trim();
    if (content.isEmpty && _selectedImages.isEmpty) {
      _showMessage('Добавьте текст или хотя бы одно фото.');
      return;
    }
    if (_scopeType == TreeContentScopeType.branches &&
        _selectedBranchPersonIds.isEmpty) {
      _showMessage(
        _isFriendsTree
            ? 'Выберите хотя бы один круг для публикации.'
            : 'Выберите хотя бы одну ветку для публикации.',
      );
      return;
    }

    if (_currentTreeId == null) return;

    setState(() => _isLoading = true);

    try {
      await _postService.createPost(
        treeId: _currentTreeId!,
        content: content,
        images: _selectedImages,
        isPublic: _isPublic,
        scopeType: _scopeType,
        anchorPersonIds: _selectedBranchPersonIds.toList(),
        circleId: _selectedCircleId,
      );

      if (mounted) {
        _showMessage('Запись опубликована.');
        context.pop(true); // Return true to signal refresh
      }
    } catch (error) {
      _appStatusService.reportError(
        error,
        fallbackMessage: 'Не удалось опубликовать запись.',
      );
      if (mounted) {
        setState(() => _isLoading = false);
        _showMessage(
          describeUserFacingError(
            authService: _authService,
            error: error,
            fallbackMessage: _appStatusService.isOffline
                ? 'Нет соединения. Проверьте интернет и отправьте запись ещё раз.'
                : 'Не удалось опубликовать запись. Попробуйте ещё раз.',
          ),
        );
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWideLayout = width >= 900;
    final composeTheme = Theme.of(context).copyWith(
      splashFactory: InkRipple.splashFactory,
    );

    final composeTokens = composeTheme.extension<RodnyaDesignTokens>() ??
        (composeTheme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Theme(
      data: composeTheme,
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(76),
          child: _buildComposeTopbar(
            theme: composeTheme,
            tokens: composeTokens,
          ),
        ),
        body: _currentTreeId == null
            ? _buildMissingTreeState()
            : SafeArea(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: isWideLayout ? 1180 : 680,
                          ),
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              isWideLayout ? 24 : 14,
                              isWideLayout ? 18 : 12,
                              isWideLayout ? 24 : 14,
                              116,
                            ),
                            child: isWideLayout
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: _buildEditorCard(compact: false),
                                      ),
                                      const SizedBox(width: 16),
                                      SizedBox(
                                        width: 370,
                                        child: _buildAudiencePanel(),
                                      ),
                                    ],
                                  )
                                : _buildEditorCard(compact: true),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: _buildComposeToolDock(compact: !isWideLayout),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildComposeToolDock({required bool compact}) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 24,
        0,
        compact ? 12 : 24,
        compact ? 12 : 18,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          color: tokens.surfaceStrong.withValues(alpha: 0.94),
          borderColor: tokens.surfaceLine,
          child: Row(
            children: [
              _buildToolButton(
                icon: Icons.photo_library_outlined,
                label: _selectedImages.isEmpty
                    ? 'Фото'
                    : '${_selectedImages.length}/5',
                active: _selectedImages.isNotEmpty,
                onPressed: _pickImages,
              ),
              _buildToolButton(
                icon: Icons.group_work_outlined,
                label: 'Кому',
                active: _selectedCircleId != null,
                onPressed: _showAudienceSheet,
              ),
              _buildToolButton(
                icon: Icons.alt_route_outlined,
                label: _isFriendsTree ? 'Круги' : 'Ветки',
                active: _scopeType == TreeContentScopeType.branches,
                onPressed: () {
                  setState(() {
                    _scopeType = TreeContentScopeType.branches;
                  });
                  _showAudienceSheet();
                },
              ),
              _buildToolButton(
                icon: _isPublic ? Icons.public : Icons.lock_outline,
                label: _isPublic ? 'Публично' : 'Внутри',
                active: _isPublic,
                onPressed: () {
                  setState(() {
                    _isPublic = !_isPublic;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final foreground = active ? tokens.accentStrong : tokens.inkSecondary;

    return Expanded(
      child: Material(
        color: active ? tokens.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: foreground, size: 21),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAudienceSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, sheetSetState) {
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.86,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
                  child: _buildAudiencePanelContent(
                    sheetSetState: sheetSetState,
                    inSheet: true,
                    onDone: () => Navigator.of(sheetContext).pop(),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _updateAudienceState(VoidCallback update, [StateSetter? sheetSetState]) {
    if (!mounted) {
      return;
    }
    setState(update);
    sheetSetState?.call(() {});
  }

  Widget _buildAudiencePanel() {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: _buildAudiencePanelContent(inSheet: false),
    );
  }

  Widget _buildAudiencePanelContent({
    required bool inSheet,
    StateSetter? sheetSetState,
    VoidCallback? onDone,
  }) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Кто увидит пост?',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: tokens.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Выбор аудитории сохраняется вместе с постом. При необходимости круг можно поменять перед публикацией.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.inkSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        AudiencePicker(
          circles: _audienceCircles,
          selectedCircleId: _selectedCircleId,
          onChanged: (circleId) {
            _updateAudienceState(() {
              _selectedCircleId = circleId;
              if (_scopeType == TreeContentScopeType.branches &&
                  _selectedBranchPersonIds.isEmpty) {
                _scopeType = TreeContentScopeType.wholeTree;
              }
            }, sheetSetState);
          },
          isLoading: _isLoadingCircles,
          isUnavailable: _circlesUnavailable,
          isFriendsTree: _isFriendsTree,
          onRetry: _loadAudienceCircles,
        ),
        const SizedBox(height: 16),
        _buildBranchAudienceSection(sheetSetState: sheetSetState),
        const SizedBox(height: 16),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('По публичной ссылке'),
          subtitle: Text(
            _isPublic
                ? 'Пост можно будет открыть по ссылке.'
                : 'Пост останется внутри выбранной аудитории.',
          ),
          value: _isPublic,
          onChanged: (value) {
            _updateAudienceState(() {
              _isPublic = value;
            }, sheetSetState);
          },
        ),
        if (inSheet) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onDone,
              child: const Text('Готово'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBranchAudienceSection({StateSetter? sheetSetState}) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _isFriendsTree ? 'Отдельные круги' : 'Отдельные ветки',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: tokens.ink,
                ),
              ),
            ),
            if (_selectedBranchPersonIds.isNotEmpty)
              TextButton(
                onPressed: () {
                  _updateAudienceState(() {
                    _selectedBranchPersonIds.clear();
                    _scopeType = TreeContentScopeType.wholeTree;
                  }, sheetSetState);
                },
                child: const Text('Сбросить'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _isFriendsTree
              ? 'Можно сузить видимость до выбранных людей и их кругов.'
              : 'Можно сузить видимость до выбранных людей и их веток.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.inkSecondary,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 10),
        if (_isLoadingPeople)
          _buildScopeState(
            icon: Icons.sync,
            title: 'Подбираем ветки',
            message:
                'Проверяем, какие люди доступны для выборочной публикации.',
            showProgress: true,
          )
        else if (_branchCandidatesUnavailable)
          _buildScopeState(
            icon: _appStatusService.isOffline
                ? Icons.cloud_off_outlined
                : Icons.error_outline,
            title: _appStatusService.isOffline
                ? 'Нет соединения'
                : 'Ветки сейчас недоступны',
            message: _appStatusService.isOffline
                ? 'Список веток вернётся, когда интернет снова появится.'
                : 'Не удалось обновить список веток. Попробуйте ещё раз.',
            actions: [
              OutlinedButton.icon(
                onPressed: _loadBranchCandidates,
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
              ),
            ],
          )
        else if (_availablePeople.isEmpty)
          _buildScopeState(
            icon: Icons.alt_route,
            title: _isFriendsTree ? 'Кругов пока нет' : 'Веток пока нет',
            message: _isFriendsTree
                ? 'Сначала добавьте людей в круг.'
                : 'Сначала добавьте людей и связи в дерево.',
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availablePeople.map((person) {
              final isSelected = _selectedBranchPersonIds.contains(person.id);
              return FilterChip(
                avatar: CircleAvatar(
                  backgroundColor: isSelected
                      ? tokens.accent.withValues(alpha: 0.18)
                      : tokens.surface,
                  child: Text(
                    person.initials,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isSelected ? tokens.accentStrong : tokens.inkMuted,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                label: Text(person.displayName),
                selected: isSelected,
                onSelected: (selected) {
                  _updateAudienceState(() {
                    if (selected) {
                      _selectedBranchPersonIds.add(person.id);
                      _scopeType = TreeContentScopeType.branches;
                    } else {
                      _selectedBranchPersonIds.remove(person.id);
                      if (_selectedBranchPersonIds.isEmpty) {
                        _scopeType = TreeContentScopeType.wholeTree;
                      }
                    }
                  }, sheetSetState);
                },
              );
            }).toList(),
          ),
      ],
    );
  }

  String _memberLabel(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    final suffix = mod10 == 1 && mod100 != 11
        ? 'человек'
        : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
            ? 'человека'
            : 'человек';
    return '$count $suffix';
  }

  Widget _buildEditorCard({required bool compact}) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return GlassPanel(
      padding: EdgeInsets.all(compact ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAuthorRow(compact: compact),
          const SizedBox(height: 14),
          _buildAudienceStrip(),
          const SizedBox(height: 18),
          DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.surface.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(tokens.radiusLg),
              border: Border.all(color: tokens.surfaceLine),
            ),
            child: TextField(
              controller: _contentController,
              decoration: InputDecoration(
                hintText: 'О чём хотите рассказать родне?',
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(compact ? 16 : 18),
                hintStyle: theme.textTheme.titleMedium?.copyWith(
                  color: tokens.inkMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              maxLines: compact ? 9 : 12,
              minLines: compact ? 7 : 10,
              style: theme.textTheme.titleMedium?.copyWith(
                color: tokens.ink,
                height: 1.35,
              ),
            ),
          ),
          if (_selectedImages.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildImagePreviews(),
          ],
        ],
      ),
    );
  }

  Widget _buildAuthorRow({required bool compact}) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Row(
      children: [
        _buildAuthorAvatar(),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: tokens.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _selectedAudienceDetail,
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.inkSecondary,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: _showAudienceSheet,
          icon: const Icon(Icons.expand_more, size: 18),
          label: Text(_selectedAudienceLabel),
        ),
      ],
    );
  }

  Widget _buildAuthorAvatar() {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final photoUrl = _authService.currentUserPhotoUrl?.trim();

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: tokens.accentSoft,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.surfaceLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: photoUrl != null && photoUrl.isNotEmpty
          ? Image.network(
              photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildAuthorInitials(tokens),
            )
          : _buildAuthorInitials(tokens),
    );
  }

  Widget _buildAuthorInitials(RodnyaDesignTokens tokens) {
    return Center(
      child: Text(
        _authorInitials,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: tokens.accentStrong,
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }

  String get _authorName {
    final displayName = _authService.currentUserDisplayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    final email = _authService.currentUserEmail?.trim();
    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }
    return 'Родня';
  }

  String get _authorInitials {
    final words =
        _authorName.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
    final initials = words
        .take(2)
        .map((word) => String.fromCharCode(word.runes.first).toUpperCase())
        .join();
    return initials.isEmpty ? 'Р' : initials;
  }

  Widget _buildAudienceStrip() {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final circles = _quickAudienceCircles;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final circle in circles) ...[
            _buildAudienceQuickChip(
              label: circle.name,
              icon: _circleIcon(circle),
              accent: _circleAccent(circle, tokens),
              active: _scopeType == TreeContentScopeType.wholeTree &&
                  _selectedCircleId == circle.id,
              onTap: () {
                setState(() {
                  _selectedCircleId = circle.id;
                  _scopeType = TreeContentScopeType.wholeTree;
                  _selectedBranchPersonIds.clear();
                });
              },
            ),
            const SizedBox(width: 8),
          ],
          _buildAudienceQuickChip(
            label: _isFriendsTree ? 'Круг' : 'Ветка',
            icon: Icons.alt_route_outlined,
            accent: tokens.warm,
            active: _scopeType == TreeContentScopeType.branches,
            onTap: () {
              setState(() {
                _scopeType = TreeContentScopeType.branches;
              });
              _showAudienceSheet();
            },
          ),
          const SizedBox(width: 8),
          _buildAudienceQuickChip(
            label: 'ещё',
            icon: Icons.tune,
            accent: tokens.inkSecondary,
            active: false,
            onTap: _showAudienceSheet,
          ),
          if (_isLoadingCircles) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAudienceQuickChip({
    required String label,
    required IconData icon,
    required Color accent,
    required bool active,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Material(
      color: active ? accent.withValues(alpha: 0.13) : tokens.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color:
                  active ? accent.withValues(alpha: 0.55) : tokens.surfaceLine,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: active ? accent : tokens.inkMuted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: active ? accent : tokens.inkSecondary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _circleIcon(FamilyCircle circle) {
    switch (circle.kind) {
      case FamilyCircleKind.allTree:
        return Icons.account_tree_outlined;
      case FamilyCircleKind.favorites:
        return Icons.favorite_border;
      case FamilyCircleKind.descendantsOf:
      case FamilyCircleKind.ancestorsOf:
        return Icons.alt_route_outlined;
      case FamilyCircleKind.pair:
        return Icons.people_outline;
      case FamilyCircleKind.custom:
        return Icons.group_work_outlined;
    }
  }

  Color _circleAccent(FamilyCircle circle, RodnyaDesignTokens tokens) {
    switch (circle.kind) {
      case FamilyCircleKind.favorites:
        return tokens.warm;
      case FamilyCircleKind.descendantsOf:
      case FamilyCircleKind.ancestorsOf:
      case FamilyCircleKind.pair:
        return tokens.accentStrong;
      case FamilyCircleKind.allTree:
      case FamilyCircleKind.custom:
        return tokens.accent;
    }
  }

  Widget _buildMissingTreeState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GlassPanel(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Сначала выберите дерево',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Сначала выберите дерево, чтобы было понятно, кому показывать публикацию.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => context.go('/tree?selector=1'),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Выбрать дерево'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScopeState({
    required IconData icon,
    required String title,
    required String message,
    bool showProgress = false,
    List<Widget> actions = const <Widget>[],
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (showProgress)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }

  Widget _buildImagePreviews() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _selectedImages.length,
      itemBuilder: (context, index) {
        final image = _selectedImages[index];
        return Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox.expand(
                child: _PickedImagePreview(image: image),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.cancel, color: Colors.black54),
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.7),
              ),
              onPressed: () {
                setState(() {
                  _selectedImages.removeAt(index);
                });
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildComposeTopbar({
    required ThemeData theme,
    required RodnyaDesignTokens tokens,
  }) {
    final canPublish = !_isLoading && _currentTreeId != null;
    return ClipRect(
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
          padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: tokens.ink),
                  tooltip: 'Назад',
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                ),
                const SizedBox(width: 4),
                Text(
                  'Новый пост',
                  style: AppTheme.serif(
                    color: tokens.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.22,
                  ),
                ),
                const Spacer(),
                Material(
                  color: canPublish ? tokens.accent : tokens.surfaceLine,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: canPublish ? _createPost : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      child: _isLoading
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: tokens.accentInk,
                              ),
                            )
                          : Text(
                              'Опубликовать',
                              style: AppTheme.sans(
                                color: canPublish
                                    ? tokens.accentInk
                                    : tokens.inkMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickedImagePreview extends StatelessWidget {
  const _PickedImagePreview({required this.image});

  final XFile image;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: image.readAsBytes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const ColoredBox(
            color: Color(0x11000000),
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const ColoredBox(
            color: Color(0x11000000),
            child: Center(child: Icon(Icons.broken_image_outlined)),
          ),
        );
      },
    );
  }
}
