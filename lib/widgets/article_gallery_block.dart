// Profile Phase 2c gallery (2026-06-01): multi-photo block for the
// article editor. A square thumbnail grid (url-addressed, cached); tap a
// photo for a full-screen, pinch-zoom pager. Per-item delete (✕ overlay),
// «добавить ещё» (an add tile + the ⋮ menu), and delete-whole-block via
// the ⋮ menu. Mirrors article_photo_block.dart; the editor owns the
// pick / upload / save — this widget only renders + fires callbacks.
//
// Editor-side render only (the polished read-only viewer is Phase 3).
// Merely rendering never hits the network — CachedNetworkImage shows a
// placeholder in tests; full-screen view is a user gesture.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../backend/models/profile_article.dart';
import '../utils/photo_url.dart';

class ArticleGalleryBlock extends StatelessWidget {
  const ArticleGalleryBlock({
    super.key,
    required this.block,
    required this.busy,
    required this.onAddMore,
    required this.onRemoveItem,
    required this.onDelete,
  });

  final ArticleBlock block;

  /// Add / remove / delete in flight — overlays a spinner, locks actions.
  final bool busy;
  final VoidCallback onAddMore;
  final void Function(int index) onRemoveItem;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = block.galleryItems;
    final urls = [
      for (final it in items) normalizePhotoUrl(it['url']?.toString()),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.collections_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Галерея · ${items.length}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFamily: 'Lora',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                key: Key('article-gallery-menu-${block.id}'),
                tooltip: 'Действия с галереей',
                enabled: !busy,
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 18,
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                onSelected: (value) {
                  if (value == 'add') onAddMore();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'add', child: Text('Добавить фото')),
                  PopupMenuItem(value: 'delete', child: Text('Удалить галерею')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  const cols = 3;
                  const gap = 6.0;
                  final size = (constraints.maxWidth - gap * (cols - 1)) / cols;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (var i = 0; i < urls.length; i++)
                        _thumb(context, theme, urls, i, size),
                      _addTile(theme, size),
                    ],
                  );
                },
              ),
              if (busy)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black26,
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _thumb(
    BuildContext context,
    ThemeData theme,
    List<String?> urls,
    int index,
    double size,
  ) {
    final url = urls[index];
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              key: Key('article-gallery-photo-${block.id}-$index'),
              onTap: url == null ? null : () => _openViewer(context, urls, index),
              child: url == null
                  ? Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                key: Key('article-gallery-remove-${block.id}-$index'),
                onTap: busy ? null : () => onRemoveItem(index),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(3),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addTile(ThemeData theme, double size) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: Key('article-gallery-add-${block.id}'),
          onTap: busy ? null : onAddMore,
          borderRadius: BorderRadius.circular(10),
          child: Icon(
            Icons.add_photo_alternate_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, List<String?> urls, int index) {
    final visible = urls.whereType<String>().toList(growable: false);
    if (visible.isEmpty) return;
    // Map the tapped grid index onto the filtered (non-null) list.
    var start = 0;
    for (var i = 0; i < index && i < urls.length; i++) {
      if (urls[i] != null) start++;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _GalleryViewer(
          urls: visible,
          initialIndex: start.clamp(0, visible.length - 1),
        ),
      ),
    );
  }
}

/// Full-screen, swipeable, pinch-zoom viewer over the gallery's photos.
class _GalleryViewer extends StatefulWidget {
  const _GalleryViewer({required this.urls, required this.initialIndex});

  final List<String> urls;
  final int initialIndex;

  @override
  State<_GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<_GalleryViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('${_index + 1} / ${widget.urls.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: CachedNetworkImage(
              imageUrl: widget.urls[i],
              fit: BoxFit.contain,
              placeholder: (_, __) => const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
              errorWidget: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
