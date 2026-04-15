import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:video_player/video_player.dart';

import '../backend/interfaces/story_service_interface.dart';
import '../backend/backend_runtime_config.dart';
import '../models/story.dart';
import '../utils/e2e_state_bridge.dart';
import '../widgets/story_visuals.dart';

class StoryViewerEntryScreen extends StatefulWidget {
  const StoryViewerEntryScreen({
    super.key,
    required this.treeId,
    required this.authorId,
    required this.currentUserId,
  });

  final String treeId;
  final String authorId;
  final String currentUserId;

  @override
  State<StoryViewerEntryScreen> createState() => _StoryViewerEntryScreenState();
}

class _StoryViewerEntryScreenState extends State<StoryViewerEntryScreen> {
  final StoryServiceInterface _storyService = GetIt.I<StoryServiceInterface>();

  bool _isLoading = true;
  Object? _error;
  List<Story> _stories = const <Story>[];

  @override
  void initState() {
    super.initState();
    unawaited(_loadStories());
  }

  Future<void> _loadStories() async {
    E2EStateBridge.publish(
      screen: 'storyViewerEntry',
      state: <String, dynamic>{
        'status': 'loading',
        'treeId': widget.treeId,
        'authorId': widget.authorId,
      },
    );
    try {
      final stories = await _storyService.getStories(
        treeId: widget.treeId,
        authorId: widget.authorId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _stories = stories;
        _error = null;
        _isLoading = false;
      });
      E2EStateBridge.publish(
        screen: 'storyViewerEntry',
        state: <String, dynamic>{
          'status': stories.isEmpty ? 'empty' : 'loaded',
          'treeId': widget.treeId,
          'authorId': widget.authorId,
          'storyCount': stories.length,
        },
      );
      E2EStateBridge.publish(
        screen: 'storyViewer',
        state: <String, dynamic>{
          'treeId': widget.treeId,
          'authorId': widget.authorId,
          'storyCount': stories.length,
          'currentStoryId': stories.isEmpty ? null : stories.first.id,
          'types': stories
              .map((story) => Story.storyTypeToString(story.type))
              .toList(),
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _isLoading = false;
      });
      E2EStateBridge.publish(
        screen: 'storyViewerEntry',
        state: <String, dynamic>{
          'status': 'error',
          'treeId': widget.treeId,
          'authorId': widget.authorId,
          'error': error.toString(),
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_error != null || _stories.isEmpty) {
      final theme = Theme.of(context);
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'История недоступна',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: _loadStories,
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return StoryViewerScreen(
      stories: _stories,
      currentUserId: widget.currentUserId,
    );
  }
}

class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.stories,
    required this.currentUserId,
  });

  final List<Story> stories;
  final String currentUserId;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  final StoryServiceInterface _storyService = GetIt.I<StoryServiceInterface>();

  late final AnimationController _progressController;
  late List<Story> _stories;
  VideoPlayerController? _videoController;
  int _currentIndex = 0;
  int _activeSession = 0;
  bool _isPreparingStory = true;
  bool _isDeleting = false;
  bool _isHolding = false;

  Story get _currentStory => _stories[_currentIndex];
  int get _viewerCount => _currentStory.viewedBy
      .where((userId) => userId != _currentStory.authorId)
      .length;
  bool get _isOwnStory => _currentStory.authorId == widget.currentUserId;
  String get _statusLabel => _isOwnStory
      ? 'Просмотров: $_viewerCount'
      : _currentStory.isViewedBy(widget.currentUserId)
          ? 'Просмотрено'
          : 'Новая история';
  StoryVisualPalette get _palette =>
      storyPaletteForSeed('${_currentStory.authorId}:${_currentStory.id}');

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _goNext();
        }
      });
    _stories = List<Story>.from(widget.stories)
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    _currentIndex = _resolveInitialIndex();
    unawaited(_prepareCurrentStory());
  }

  @override
  void dispose() {
    _progressController.dispose();
    unawaited(_disposeVideoController());
    super.dispose();
  }

  int _resolveInitialIndex() {
    final firstUnseenIndex = _stories.indexWhere(
      (story) =>
          story.authorId != widget.currentUserId &&
          !story.isViewedBy(widget.currentUserId),
    );
    if (firstUnseenIndex >= 0) {
      return firstUnseenIndex;
    }
    return 0;
  }

  Future<void> _prepareCurrentStory() async {
    if (_stories.isEmpty || !mounted) {
      return;
    }

    final sessionId = ++_activeSession;
    await _disposeVideoController();
    if (!mounted || sessionId != _activeSession || _stories.isEmpty) {
      return;
    }

    setState(() {
      _isPreparingStory = true;
    });

    var story = _currentStory;
    if (story.authorId != widget.currentUserId &&
        !story.isViewedBy(widget.currentUserId)) {
      try {
        final updatedStory = await _storyService.markViewed(story.id);
        if (!mounted || sessionId != _activeSession || _stories.isEmpty) {
          return;
        }
        _stories[_currentIndex] = updatedStory;
        story = updatedStory;
      } catch (error) {
        debugPrint('Не удалось отметить историю как просмотренную: $error');
      }
    }

    var duration = const Duration(seconds: 5);
    if (story.type == StoryType.video &&
        story.mediaUrl != null &&
        story.mediaUrl!.isNotEmpty) {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(story.mediaUrl!),
      );
      try {
        await controller.initialize();
        await controller.play();
        await controller.setLooping(false);
        if (!mounted || sessionId != _activeSession || _stories.isEmpty) {
          await controller.dispose();
          return;
        }
        _videoController = controller;
        if (controller.value.duration > Duration.zero) {
          duration = controller.value.duration;
        }
      } catch (error) {
        debugPrint('Ошибка инициализации видео в stories: $error');
        await controller.dispose();
      }
    }

    _progressController
      ..stop()
      ..duration = duration
      ..value = 0;

    if (!mounted || sessionId != _activeSession || _stories.isEmpty) {
      return;
    }

    setState(() {
      _isPreparingStory = false;
    });

    if (!_isHolding) {
      _progressController.forward();
    }
  }

  Future<void> _disposeVideoController() async {
    final controller = _videoController;
    _videoController = null;
    if (controller != null) {
      await controller.dispose();
    }
  }

  void _pausePlayback() {
    _progressController.stop();
    _videoController?.pause();
    if (mounted) {
      setState(() {
        _isHolding = true;
      });
    }
  }

  void _resumePlayback() {
    if (!mounted) {
      return;
    }
    setState(() {
      _isHolding = false;
    });
    if (!_isPreparingStory) {
      _progressController.forward();
      _videoController?.play();
    }
  }

  void _goPrevious() {
    if (_currentIndex == 0) {
      return;
    }
    setState(() {
      _currentIndex -= 1;
    });
    unawaited(_prepareCurrentStory());
  }

  void _goNext() {
    if (_currentIndex >= _stories.length - 1) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }
    setState(() {
      _currentIndex += 1;
    });
    unawaited(_prepareCurrentStory());
  }

  Future<void> _deleteCurrentStory() async {
    if (_isDeleting) {
      return;
    }

    setState(() {
      _isDeleting = true;
    });

    try {
      await _storyService.deleteStory(_currentStory.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _stories.removeAt(_currentIndex);
        if (_currentIndex >= _stories.length && _currentIndex > 0) {
          _currentIndex -= 1;
        }
      });
      if (_stories.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      await _prepareCurrentStory();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить историю: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = _currentStory;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Semantics(
        label: 'story-viewer',
        child: GestureDetector(
          onLongPressStart: (_) => _pausePlayback(),
          onLongPressEnd: (_) => _resumePlayback(),
          child: SafeArea(
            child: Stack(
              children: [
                const Positioned.fill(
                  child: ColoredBox(color: Colors.black),
                ),
                Positioned.fill(
                  child: _buildStoryContent(story),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.36),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.38),
                        ],
                        stops: const [0, 0.35, 1],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _goPrevious,
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _goNext,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: List.generate(
                          _stories.length,
                          (index) => Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: index == _stories.length - 1 ? 0 : 4,
                              ),
                              child: _StoryProgressSegment(
                                isCurrent: index == _currentIndex,
                                isCompleted: index < _currentIndex,
                                animation: _progressController,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildHeader(story),
                    ],
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 20,
                  child: _buildBottomTray(story),
                ),
                if (BackendRuntimeConfig.current.enableE2e)
                  Positioned(
                    right: 16,
                    bottom: 92,
                    child: IgnorePointer(
                      child: _buildE2EViewerOverlay(story),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Story story) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white12,
            backgroundImage:
                story.authorPhotoUrl != null && story.authorPhotoUrl!.isNotEmpty
                    ? NetworkImage(story.authorPhotoUrl!)
                    : null,
            child: story.authorPhotoUrl == null || story.authorPhotoUrl!.isEmpty
                ? Text(
                    storyInitialsFor(story.authorName),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isOwnStory ? 'Ваша история' : story.authorName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatTimestamp(story.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          StoryMediaBadge(
            icon: story.type == StoryType.video
                ? Icons.videocam_rounded
                : story.type == StoryType.image
                    ? Icons.image_rounded
                    : Icons.text_fields_rounded,
            label: story.type == StoryType.video
                ? 'Видео'
                : story.type == StoryType.image
                    ? 'Фото'
                    : 'Текст',
          ),
          const SizedBox(width: 8),
          if (_isOwnStory)
            Semantics(
              button: true,
              label: 'story-viewer-delete',
              child: _buildIconAction(
                onTap: _isDeleting ? null : _deleteCurrentStory,
                child: _isDeleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                      ),
              ),
            ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'story-viewer-close',
            child: _buildIconAction(
              onTap: () => Navigator.of(context).pop(),
              child: const Icon(Icons.close, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconAction({
    required VoidCallback? onTap,
    required Widget child,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Center(child: child),
      ),
    );
  }

  Widget _buildBottomTray(Story story) {
    final theme = Theme.of(context);
    final hasCaption = story.type != StoryType.text && story.hasText;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: hasCaption
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        story.text!.trim(),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          if (hasCaption) const SizedBox(width: 12),
          StoryMediaBadge(
            icon: _isOwnStory
                ? Icons.remove_red_eye_outlined
                : _currentStory.isViewedBy(widget.currentUserId)
                    ? Icons.check_circle_outline
                    : Icons.fiber_manual_record_rounded,
            label: _statusLabel,
            emphasized: true,
          ),
        ],
      ),
    );
  }

  Widget _buildE2EViewerOverlay(Story story) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF34D399), width: 1.4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'E2E STORY VIEWER',
                style: TextStyle(
                  color: Color(0xFF34D399),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 6),
              Text(_isOwnStory ? 'Ваша история' : story.authorName),
              const SizedBox(height: 2),
              Text(
                Story.storyTypeToString(story.type),
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStoryContent(Story story) {
    switch (story.type) {
      case StoryType.image:
        return _buildImageStory(story);
      case StoryType.video:
        return _buildVideoStory(story);
      case StoryType.text:
        return _buildTextStory(story);
    }
  }

  Widget _buildImageStory(Story story) {
    if (story.mediaUrl == null || story.mediaUrl!.isEmpty) {
      return _buildUnavailableStory();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        StoryPosterBackground(
          palette: _palette,
          imageUrl: story.mediaUrl,
          dimmed: true,
        ),
        Image.network(
          story.mediaUrl!,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) {
              return child;
            }
            return const Center(child: CircularProgressIndicator());
          },
          errorBuilder: (_, __, ___) => _buildUnavailableStory(),
        ),
      ],
    );
  }

  Widget _buildVideoStory(Story story) {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      if (_isPreparingStory) {
        return StoryPosterBackground(
          palette: _palette,
          imageUrl: story.thumbnailUrl,
          dimmed: true,
        );
      }
      return _buildUnavailableStory();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        StoryPosterBackground(
          palette: _palette,
          imageUrl: story.thumbnailUrl ?? story.mediaUrl,
          dimmed: true,
        ),
        Center(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextStory(Story story) {
    return StoryPosterCardFrame(
      palette: _palette,
      aspectRatio: 9 / 16,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 34),
      child: Align(
        alignment: Alignment.center,
        child: StoryPosterText(
          primaryText: (story.text ?? '').trim().isEmpty
              ? 'История без текста'
              : story.text!.trim(),
          centered: true,
          maxLines: 8,
        ),
      ),
    );
  }

  Widget _buildUnavailableStory() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: StoryPosterCardFrame(
          palette: _palette,
          child: Center(
            child: StoryPosterText(
              primaryText: 'Не удалось загрузить',
              secondaryText: 'Попробуйте следующую историю',
              centered: true,
              maxLines: 4,
            ),
          ),
        ),
      ),
    );
  }

  static String _formatTimestamp(DateTime dateTime) {
    final local = dateTime.toLocal();
    final hours = local.hour.toString().padLeft(2, '0');
    final minutes = local.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }
}

class _StoryProgressSegment extends StatelessWidget {
  const _StoryProgressSegment({
    required this.isCurrent,
    required this.isCompleted,
    required this.animation,
  });

  final bool isCurrent;
  final bool isCompleted;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Colors.white24;
    if (!isCurrent) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: isCompleted ? 1 : 0,
          minHeight: 4,
          backgroundColor: backgroundColor,
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: animation.value,
          minHeight: 4,
          backgroundColor: backgroundColor,
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      ),
    );
  }
}
