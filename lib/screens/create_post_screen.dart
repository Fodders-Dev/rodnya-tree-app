import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/post_service_interface.dart';
import '../models/family_person.dart';
import '../models/family_tree.dart';
import '../models/post.dart';
import '../providers/tree_provider.dart';
import '../services/local_storage_service.dart';
import '../widgets/glass_panel.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _contentController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final FamilyTreeServiceInterface _familyTreeService =
      GetIt.I<FamilyTreeServiceInterface>();
  final PostServiceInterface _postService = GetIt.I<PostServiceInterface>();
  final LocalStorageService _localStorageService =
      GetIt.I<LocalStorageService>();

  bool _isPublic = false;
  bool _isLoading = false;
  bool _isLoadingPeople = false;
  List<XFile> _selectedImages = <XFile>[];
  List<FamilyPerson> _availablePeople = <FamilyPerson>[];
  final Set<String> _selectedBranchPersonIds = <String>{};
  TreeContentScopeType _scopeType = TreeContentScopeType.wholeTree;
  String? _currentTreeId;
  FamilyTree? _currentTreeMeta;

  bool get _isFriendsTree => _currentTreeMeta?.isFriendsTree == true;

  @override
  void initState() {
    super.initState();
    _currentTreeId = Provider.of<TreeProvider>(
      context,
      listen: false,
    ).selectedTreeId;
    _loadCurrentTreeMeta();
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
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось загрузить список веток для публикации.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPeople = false;
        });
      }
    }
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось выбрать изображения.')),
        );
      }
    }
  }

  Future<void> _createPost() async {
    final content = _contentController.text.trim();
    if (content.isEmpty && _selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Пожалуйста, введите текст или добавьте фото.')),
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
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Запись успешно опубликована!')),
        );
        context.pop(true); // Return true to signal refresh
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при публикации: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWideLayout = MediaQuery.of(context).size.width >= 1100;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Публикация'),
        actions: [
          TextButton(
            onPressed:
                _isLoading || _currentTreeId == null ? null : _createPost,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Готово'),
          ),
        ],
      ),
      body: _currentTreeId == null
          ? _buildMissingTreeState()
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1260),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _buildMetaPill(
                            icon: Icons.account_tree_outlined,
                            label: _currentTreeMeta?.name.isNotEmpty == true
                                ? _currentTreeMeta!.name
                                : 'Текущее дерево',
                          ),
                          _buildMetaPill(
                            icon: _scopeType == TreeContentScopeType.wholeTree
                                ? Icons.groups_2_outlined
                                : Icons.alt_route,
                            label: _scopeType == TreeContentScopeType.wholeTree
                                ? (_isFriendsTree ? 'Весь круг' : 'Всё дерево')
                                : (_isFriendsTree
                                    ? 'Выборочные круги'
                                    : 'Выборочные ветки'),
                          ),
                          _buildMetaPill(
                            icon: Icons.photo_library_outlined,
                            label: _selectedImages.isEmpty
                                ? 'Без фото'
                                : '${_selectedImages.length}/5 фото',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (isWideLayout)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: _buildEditorCard()),
                            const SizedBox(width: 16),
                            Expanded(flex: 2, child: _buildScopeCard()),
                          ],
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildEditorCard(),
                            const SizedBox(height: 16),
                            _buildScopeCard(),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildMetaPill({
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
      ),
    );
  }

  Widget _buildEditorCard() {
    final theme = Theme.of(context);
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Что нового',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildMetaPill(
                icon: Icons.feed_outlined,
                label: _isFriendsTree ? 'Лента круга' : 'Лента семьи',
              ),
              _buildMetaPill(
                icon: Icons.public,
                label: _isPublic ? 'Видно всем' : 'Внутри контекста',
              ),
            ],
          ),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest
                  .withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(24),
            ),
            child: TextField(
              controller: _contentController,
              decoration: const InputDecoration(
                hintText: 'Напишите пост',
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(18),
              ),
              maxLines: 10,
              minLines: 6,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(
              _selectedImages.isEmpty
                  ? 'Фото'
                  : 'Фото ${_selectedImages.length}/5',
            ),
            onPressed: _pickImages,
          ),
          if (_selectedImages.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildImagePreviews(),
          ],
        ],
      ),
    );
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
                  'Нужен активный контекст.',
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

  Widget _buildScopeCard() {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Видимость',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          SegmentedButton<TreeContentScopeType>(
            segments: [
              ButtonSegment<TreeContentScopeType>(
                value: TreeContentScopeType.wholeTree,
                icon: const Icon(Icons.account_tree_outlined),
                label: Text(_isFriendsTree ? 'Весь круг' : 'Всё дерево'),
              ),
              ButtonSegment<TreeContentScopeType>(
                value: TreeContentScopeType.branches,
                icon: const Icon(Icons.alt_route),
                label: Text(
                    _isFriendsTree ? 'Отдельные круги' : 'Отдельные ветки'),
              ),
            ],
            selected: <TreeContentScopeType>{_scopeType},
            onSelectionChanged: (selection) {
              final nextScope = selection.first;
              setState(() {
                _scopeType = nextScope;
                if (nextScope == TreeContentScopeType.wholeTree) {
                  _selectedBranchPersonIds.clear();
                }
              });
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Видно всем'),
            value: _isPublic,
            onChanged: (value) {
              setState(() {
                _isPublic = value;
              });
            },
          ),
          if (_scopeType == TreeContentScopeType.branches) ...[
            const SizedBox(height: 8),
            Text(
              _selectedBranchPersonIds.isEmpty
                  ? (_isFriendsTree ? 'Выберите круги' : 'Выберите ветки')
                  : '${_selectedBranchPersonIds.length} выбрано',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            if (_isLoadingPeople)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_availablePeople.isEmpty)
              Text(
                _isFriendsTree ? 'Кругов пока нет.' : 'Веток пока нет.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availablePeople.map((person) {
                  final isSelected =
                      _selectedBranchPersonIds.contains(person.id);
                  return FilterChip(
                    label: Text(person.name),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedBranchPersonIds.add(person.id);
                        } else {
                          _selectedBranchPersonIds.remove(person.id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
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
