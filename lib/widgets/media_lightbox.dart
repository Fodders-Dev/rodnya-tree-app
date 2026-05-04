import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// One photo/video that the [MediaLightbox] can display.
///
/// Either [imageUrl] or [videoUrl] should be set — `kind` is inferred.
/// `caption` is optional metadata (sender name / date / "1 of 3" hint).
class MediaLightboxItem {
  const MediaLightboxItem({
    this.imageUrl,
    this.videoUrl,
    this.thumbnailUrl,
    this.caption,
    this.heroTag,
  });

  /// Photo URL. When set, the item renders as a zoomable image.
  final String? imageUrl;

  /// Video URL. When set, the item renders as a video_player with controls.
  final String? videoUrl;

  /// Optional poster for video items — shown while the player initializes.
  final String? thumbnailUrl;

  /// Optional small text shown at the bottom of the lightbox over a dim
  /// gradient. Can be the sender name, date, or "1 / 5" position hint.
  final String? caption;

  /// Optional Hero tag for shared-element transitions from the source
  /// thumbnail to the lightbox. Pass the same tag on both ends.
  final Object? heroTag;

  bool get isVideo => (videoUrl ?? '').isNotEmpty;
  bool get isImage => (imageUrl ?? '').isNotEmpty;
}

/// Fullscreen, swipe-paginated lightbox used by both the post feed and
/// the chat attachment viewer. Renders a black scrim, dismiss-via-swipe-
/// down, pinch-to-zoom for photos, and a tap-to-toggle controls layer
/// for video.
///
/// Open via [show] — convenience static that pushes a translucent
/// MaterialPageRoute. Caller passes the items + initial index.
class MediaLightbox extends StatefulWidget {
  const MediaLightbox({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.onDownload,
    this.onShare,
    this.onLike,
    this.onComment,
    this.initialLiked = false,
    this.likeCount = 0,
    this.commentCount = 0,
  });

  final List<MediaLightboxItem> items;
  final int initialIndex;

  /// Optional callbacks. When null, the corresponding action button is
  /// hidden. Hosts wire these to their existing flows so the lightbox
  /// itself stays platform-agnostic.
  final ValueChanged<MediaLightboxItem>? onDownload;
  final ValueChanged<MediaLightboxItem>? onShare;

  /// User feedback was: "при просмотра фото не хватает, чтобы можно
  /// было лайк тут же поставить, комментарии почитать, переслать". So
  /// the lightbox now exposes a like/comment/share row. The parent
  /// (post_card) wires these to the post-level handlers; the lightbox
  /// keeps its own optimistic isLiked state so a tap shows the heart
  /// fill immediately even though the server round-trip happens in the
  /// background.
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final bool initialLiked;
  final int likeCount;
  final int commentCount;

  /// Convenience — push a fullscreen lightbox above the current screen.
  static Future<void> show(
    BuildContext context, {
    required List<MediaLightboxItem> items,
    int initialIndex = 0,
    ValueChanged<MediaLightboxItem>? onDownload,
    ValueChanged<MediaLightboxItem>? onShare,
    VoidCallback? onLike,
    VoidCallback? onComment,
    bool initialLiked = false,
    int likeCount = 0,
    int commentCount = 0,
  }) {
    if (items.isEmpty) return Future.value();
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black87,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (context, animation, secondaryAnimation) =>
            FadeTransition(
          opacity: animation,
          child: MediaLightbox(
            items: items,
            initialIndex: initialIndex,
            onDownload: onDownload,
            onShare: onShare,
            onLike: onLike,
            onComment: onComment,
            initialLiked: initialLiked,
            likeCount: likeCount,
            commentCount: commentCount,
          ),
        ),
      ),
    );
  }

  @override
  State<MediaLightbox> createState() => _MediaLightboxState();
}

class _MediaLightboxState extends State<MediaLightbox> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _showChrome = true;
  // Optimistic local copy. The parent post_card hits the server when
  // onLike fires, but the lightbox lives in a different element tree —
  // so we mirror the state here for instant feedback. Diverges from
  // the parent only briefly until the user dismisses.
  late bool _liked;
  late int _likeCount;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _liked = widget.initialLiked;
    _likeCount = widget.likeCount;
  }

  void _handleLikeTap() {
    if (widget.onLike == null) return;
    setState(() {
      _liked = !_liked;
      _likeCount = (_likeCount + (_liked ? 1 : -1)).clamp(0, 1 << 31);
    });
    widget.onLike!();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    if (!mounted) return;
    setState(() => _currentIndex = index);
  }

  void _toggleChrome() {
    setState(() => _showChrome = !_showChrome);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final currentItem = widget.items[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: _toggleChrome,
        // Drag-down dismiss: only the gesture area at the top half
        // listens; bottom half stays free for in-page video controls.
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity > 600) {
            Navigator.of(context).pop();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Backdrop dimmer — black with a faint vignette gradient.
            const ColoredBox(color: Colors.black),
            PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: widget.items.length,
              itemBuilder: (context, index) {
                final item = widget.items[index];
                if (item.isVideo) {
                  return _LightboxVideoPage(
                    key: ValueKey<String>('lightbox-video-$index'),
                    item: item,
                  );
                }
                return _LightboxPhotoPage(
                  key: ValueKey<String>('lightbox-photo-$index'),
                  item: item,
                );
              },
            ),
            // Chrome — close + counter + actions. Animated for tap-to-toggle.
            AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _showChrome ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_showChrome,
                child: SafeArea(
                  child: Column(
                    children: [
                      _LightboxTopBar(
                        currentIndex: _currentIndex,
                        total: widget.items.length,
                        onClose: () => Navigator.of(context).pop(),
                        onDownload: widget.onDownload == null
                            ? null
                            : () => widget.onDownload!(currentItem),
                        onShare: widget.onShare == null
                            ? null
                            : () => widget.onShare!(currentItem),
                      ),
                      const Spacer(),
                      if ((currentItem.caption ?? '').isNotEmpty)
                        _LightboxCaption(
                          caption: currentItem.caption!,
                          bottomPadding: 0,
                        ),
                      // Action bar at the bottom — only renders if the
                      // host actually wired at least one callback. For
                      // the chat attachment viewer (no onLike/onComment
                      // wired) this stays invisible, preserving the
                      // existing minimal chrome there.
                      if (widget.onLike != null ||
                          widget.onComment != null ||
                          widget.onShare != null)
                        _LightboxActionBar(
                          isLiked: _liked,
                          likeCount: _likeCount,
                          commentCount: widget.commentCount,
                          onLike: widget.onLike == null ? null : _handleLikeTap,
                          onComment: widget.onComment,
                          onShare: widget.onShare == null
                              ? null
                              : () => widget.onShare!(currentItem),
                          bottomPadding: mediaQuery.padding.bottom,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LightboxActionBar extends StatelessWidget {
  const _LightboxActionBar({
    required this.isLiked,
    required this.likeCount,
    required this.commentCount,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.bottomPadding,
  });

  final bool isLiked;
  final int likeCount;
  final int commentCount;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + bottomPadding),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xCC000000)],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (onLike != null)
            _LightboxAction(
              icon: isLiked ? Icons.favorite : Icons.favorite_border,
              activeColor: const Color(0xFFFF7E91),
              active: isLiked,
              count: likeCount,
              label: 'Тепло',
              onTap: onLike!,
            ),
          if (onComment != null)
            _LightboxAction(
              icon: Icons.chat_bubble_outline_rounded,
              count: commentCount,
              label: 'Комменты',
              onTap: onComment!,
            ),
          if (onShare != null)
            _LightboxAction(
              icon: Icons.share_outlined,
              label: 'Переслать',
              onTap: onShare!,
            ),
        ],
      ),
    );
  }
}

class _LightboxAction extends StatelessWidget {
  const _LightboxAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.count = 0,
    this.active = false,
    this.activeColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int count;
  final bool active;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final color = active ? (activeColor ?? Colors.white) : Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 24),
              if (count > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '$count',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.78),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LightboxTopBar extends StatelessWidget {
  const _LightboxTopBar({
    required this.currentIndex,
    required this.total,
    required this.onClose,
    this.onDownload,
    this.onShare,
  });

  final int currentIndex;
  final int total;
  final VoidCallback onClose;
  final VoidCallback? onDownload;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 24),
            tooltip: 'Закрыть',
            onPressed: onClose,
          ),
          if (total > 1)
            Text(
              '${currentIndex + 1} / $total',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          const Spacer(),
          if (onShare != null)
            IconButton(
              icon: const Icon(Icons.share_outlined,
                  color: Colors.white, size: 22),
              tooltip: 'Поделиться',
              onPressed: onShare,
            ),
          if (onDownload != null)
            IconButton(
              icon: const Icon(Icons.download_outlined,
                  color: Colors.white, size: 22),
              tooltip: 'Скачать',
              onPressed: onDownload,
            ),
        ],
      ),
    );
  }
}

class _LightboxCaption extends StatelessWidget {
  const _LightboxCaption({required this.caption, required this.bottomPadding});

  final String caption;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + bottomPadding),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xCC000000)],
        ),
      ),
      child: Text(
        caption,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
      ),
    );
  }
}

class _LightboxPhotoPage extends StatelessWidget {
  const _LightboxPhotoPage({super.key, required this.item});

  final MediaLightboxItem item;

  @override
  Widget build(BuildContext context) {
    final url = item.imageUrl ?? '';
    if (url.isEmpty) {
      return const Center(
        child: Icon(Icons.broken_image_outlined,
            color: Colors.white54, size: 48),
      );
    }

    final image = CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      placeholder: (_, __) => const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      ),
      errorWidget: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_outlined,
            color: Colors.white54, size: 48),
      ),
    );

    final viewer = InteractiveViewer(
      maxScale: 4,
      minScale: 1,
      child: Center(
        child: item.heroTag == null
            ? image
            : Hero(tag: item.heroTag!, child: image),
      ),
    );
    return viewer;
  }
}

class _LightboxVideoPage extends StatefulWidget {
  const _LightboxVideoPage({super.key, required this.item});

  final MediaLightboxItem item;

  @override
  State<_LightboxVideoPage> createState() => _LightboxVideoPageState();
}

class _LightboxVideoPageState extends State<_LightboxVideoPage> {
  VideoPlayerController? _controller;
  bool _initFailed = false;

  @override
  void initState() {
    super.initState();
    _setupController();
  }

  Future<void> _setupController() async {
    final url = widget.item.videoUrl ?? '';
    if (url.isEmpty) {
      setState(() => _initFailed = true);
      return;
    }
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(false);
      await controller.play();
      setState(() => _controller = controller);
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() => _initFailed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initFailed) {
      return const Center(
        child: Icon(Icons.error_outline, color: Colors.white54, size: 48),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      // Show poster while video initializes — better UX than spinner alone.
      final thumb = widget.item.thumbnailUrl;
      return Stack(
        fit: StackFit.expand,
        children: [
          if ((thumb ?? '').isNotEmpty)
            CachedNetworkImage(
              imageUrl: thumb!,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          const Center(
            child: CircularProgressIndicator(color: Colors.white70),
          ),
        ],
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio == 0
            ? 16 / 9
            : controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(controller),
            _VideoControlsOverlay(controller: controller),
          ],
        ),
      ),
    );
  }
}

class _VideoControlsOverlay extends StatefulWidget {
  const _VideoControlsOverlay({required this.controller});

  final VideoPlayerController controller;

  @override
  State<_VideoControlsOverlay> createState() => _VideoControlsOverlayState();
}

class _VideoControlsOverlayState extends State<_VideoControlsOverlay> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = widget.controller.value.isPlaying;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (isPlaying) {
          widget.controller.pause();
        } else {
          widget.controller.play();
        }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: isPlaying
            ? const SizedBox.shrink()
            : Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black54,
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 44),
              ),
      ),
    );
  }
}
