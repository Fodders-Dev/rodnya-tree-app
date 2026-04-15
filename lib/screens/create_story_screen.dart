import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../backend/interfaces/story_service_interface.dart';
import '../models/story.dart';
import '../providers/tree_provider.dart';
import '../widgets/glass_panel.dart';
import '../widgets/story_visuals.dart';

class CreateStoryScreen extends StatefulWidget {
  const CreateStoryScreen({super.key});

  @override
  State<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends State<CreateStoryScreen> {
  final StoryServiceInterface _storyService = GetIt.I<StoryServiceInterface>();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _textController = TextEditingController();

  StoryType _storyType = StoryType.text;
  XFile? _selectedMedia;
  String? _currentTreeId;
  String? _currentTreeName;
  bool _isSubmitting = false;

  bool get _needsMedia => _storyType != StoryType.text;
  StoryVisualPalette get _palette => storyPaletteForSeed(
        '${_currentTreeId ?? 'story'}:${_storyType.name}:${_textController.text.trim()}',
      );
  String get _storyText => _textController.text.trim().isEmpty
      ? 'Поделитесь моментом'
      : _textController.text.trim();

  @override
  void initState() {
    super.initState();
    final treeProvider = Provider.of<TreeProvider>(context, listen: false);
    _currentTreeId = treeProvider.selectedTreeId;
    _currentTreeName = treeProvider.selectedTreeName;
    _textController.addListener(_handleDraftChanged);
  }

  @override
  void dispose() {
    _textController
      ..removeListener(_handleDraftChanged)
      ..dispose();
    super.dispose();
  }

  void _handleDraftChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _pickImage() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1440,
      );
      if (picked == null || !mounted) {
        return;
      }
      setState(() {
        _storyType = StoryType.image;
        _selectedMedia = picked;
      });
    } catch (error) {
      _showError('Не удалось выбрать изображение: $error');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picked = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 2),
      );
      if (picked == null || !mounted) {
        return;
      }
      setState(() {
        _storyType = StoryType.video;
        _selectedMedia = picked;
      });
    } catch (error) {
      _showError('Не удалось выбрать видео: $error');
    }
  }

  Future<void> _submitStory() async {
    final text = _textController.text.trim();
    if (_currentTreeId == null || _currentTreeId!.isEmpty) {
      _showError(
        'Сначала выберите дерево, для которого хотите опубликовать историю.',
      );
      return;
    }
    if (_storyType == StoryType.text && text.isEmpty) {
      _showError('Для текстовой истории нужен хотя бы короткий текст.');
      return;
    }
    if (_needsMedia && _selectedMedia == null) {
      _showError('Добавьте файл для истории.');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await _storyService.createStory(
        treeId: _currentTreeId!,
        type: _storyType,
        text: text.isEmpty ? null : text,
        media: _selectedMedia,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('История опубликована на 24 часа')),
      );
      context.pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError('Не удалось опубликовать историю: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _setStoryType(StoryType type) {
    setState(() {
      _storyType = type;
      if (type == StoryType.text) {
        _selectedMedia = null;
      } else if (_selectedMedia != null) {
        final isImageStory = type == StoryType.image;
        final mimeType = _selectedMedia?.mimeType ?? '';
        final isImageFile = mimeType.startsWith('image/');
        if (isImageStory != isImageFile) {
          _selectedMedia = null;
        }
      }
    });
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('История'),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : _submitStory,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Поделиться'),
          ),
        ],
      ),
      body: _currentTreeId == null
          ? _buildMissingTreeState()
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 960;
                final preview = _buildStoryCanvas();
                final controls = _buildControls();

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
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
                                label:
                                    _currentTreeName?.trim().isNotEmpty == true
                                        ? _currentTreeName!
                                        : 'Текущее дерево',
                              ),
                              _buildMetaPill(
                                icon: Icons.schedule_outlined,
                                label: '24 часа',
                              ),
                              _buildMetaPill(
                                icon: _storyType == StoryType.text
                                    ? Icons.notes_outlined
                                    : (_storyType == StoryType.image
                                        ? Icons.image_outlined
                                        : Icons.videocam_outlined),
                                label: _storyTypeLabel(_storyType),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (isWide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 7, child: preview),
                                const SizedBox(width: 16),
                                Expanded(flex: 4, child: controls),
                              ],
                            )
                          else ...[
                            preview,
                            const SizedBox(height: 16),
                            controls,
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStoryCanvas() {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Превью',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          StoryPosterCardFrame(
            palette: _palette,
            child: Stack(
              children: [
                Positioned.fill(child: _buildCanvasContent()),
                Align(
                  alignment: Alignment.topLeft,
                  child: StoryMediaBadge(
                    icon: _storyType == StoryType.video
                        ? Icons.videocam_rounded
                        : _storyType == StoryType.image
                            ? Icons.image_rounded
                            : Icons.text_fields_rounded,
                    label: _storyTypeLabel(_storyType),
                    emphasized: true,
                  ),
                ),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      StoryMediaBadge(
                        icon: Icons.schedule_outlined,
                        label: '24 часа',
                      ),
                      StoryMediaBadge(
                        icon: Icons.remove_red_eye_outlined,
                        label: 'Только свои',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvasContent() {
    if (_storyType == StoryType.image) {
      if (_selectedMedia == null) {
        return _StoryCanvasPlaceholder(
          icon: Icons.add_photo_alternate_outlined,
          title: 'Добавьте фото',
          subtitle: 'История будет выглядеть как poster.',
        );
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          _PickedStoryImagePreview(image: _selectedMedia!),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.08),
                  Colors.black.withValues(alpha: 0.42),
                ],
              ),
            ),
          ),
          if (_textController.text.trim().isNotEmpty)
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: StoryPosterText(
                  primaryText: _storyText,
                  maxLines: 5,
                ),
              ),
            ),
        ],
      );
    }

    if (_storyType == StoryType.video) {
      if (_selectedMedia == null) {
        return _StoryCanvasPlaceholder(
          icon: Icons.videocam_outlined,
          title: 'Добавьте видео',
          subtitle: 'Короткий ролик до двух минут.',
        );
      }

      return Stack(
        fit: StackFit.expand,
        children: [
          StoryPosterBackground(
            palette: _palette,
            dimmed: true,
          ),
          Center(
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.18),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: StoryPosterText(
                primaryText: _textController.text.trim().isEmpty
                    ? _selectedMedia!.name
                    : _storyText,
                secondaryText:
                    _textController.text.trim().isEmpty ? 'Видео' : 'Видео',
                maxLines: 4,
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        StoryPosterBackground(
          palette: _palette,
        ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Align(
            alignment: Alignment.center,
            child: StoryPosterText(
              primaryText: _storyText,
              centered: true,
              maxLines: 8,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Формат',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildTypeChip(
                    icon: Icons.text_fields_rounded,
                    label: 'Текст',
                    value: StoryType.text,
                  ),
                  _buildTypeChip(
                    icon: Icons.image_rounded,
                    label: 'Фото',
                    value: StoryType.image,
                  ),
                  _buildTypeChip(
                    icon: Icons.videocam_rounded,
                    label: 'Видео',
                    value: StoryType.video,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _storyType == StoryType.text ? 'Текст' : 'Подпись',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest
                      .withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: TextField(
                  controller: _textController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: _storyType == StoryType.text
                        ? 'Короткий момент'
                        : 'Подпись',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(18),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Медиа',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Фото'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _pickVideo,
                    icon: const Icon(Icons.video_library_outlined),
                    label: const Text('Видео'),
                  ),
                  if (_selectedMedia != null)
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedMedia = null;
                          if (_storyType != StoryType.text) {
                            _storyType = StoryType.text;
                          }
                        });
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Убрать'),
                    ),
                ],
              ),
              if (_selectedMedia != null) ...[
                const SizedBox(height: 12),
                Text(
                  _selectedMedia!.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTypeChip({
    required IconData icon,
    required String label,
    required StoryType value,
  }) {
    final theme = Theme.of(context);
    final isSelected = _storyType == value;

    return ChoiceChip(
      selected: isSelected,
      onSelected: (_) => _setStoryType(value),
      avatar: Icon(
        icon,
        size: 18,
        color: isSelected
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurfaceVariant,
      ),
      label: Text(label),
      labelStyle: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor:
          theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.88),
      selectedColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.9),
      side: BorderSide(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.18)
            : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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

  String _storyTypeLabel(StoryType type) {
    switch (type) {
      case StoryType.text:
        return 'Текст';
      case StoryType.image:
        return 'Фото';
      case StoryType.video:
        return 'Видео';
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
}

class _StoryCanvasPlaceholder extends StatelessWidget {
  const _StoryCanvasPlaceholder({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 40),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.86),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PickedStoryImagePreview extends StatelessWidget {
  const _PickedStoryImagePreview({required this.image});

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
