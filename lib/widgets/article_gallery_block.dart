// Profile Phase 2c gallery (v2, 2026-06-02): multi-photo block for the
// article. A square thumbnail grid (url-addressed, cached) with per-item
// captions (overlaid on the thumb, edited in the full-screen pager),
// long-press drag-reorder in edit mode, and a full-screen pinch-zoom
// viewer (swipe + index + caption). The editor owns pick / upload / save;
// this widget renders + fires callbacks (add / remove / reorder / caption
// / delete).
//
// Read mode (readOnly:true) drops every edit affordance — ⋮ menu, ✕,
// add-tile, reorder, caption editing — but still SHOWS captions. Merely
// rendering never hits the network (CachedNetworkImage placeholder in
// tests); full-screen view is a user gesture.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../backend/models/profile_article.dart';
import '../utils/photo_url.dart';

class ArticleGalleryBlock extends StatelessWidget {
  const ArticleGalleryBlock({
    super.key,
    required this.block,
    this.busy = false,
    this.onAddMore,
    this.onRemoveItem,
    this.onReorder,
    this.onCaptionChanged,
    this.onDelete,
    this.readOnly = false,
  });

  final ArticleBlock block;

  /// Add / remove / reorder / caption / delete in flight — overlays a
  /// spinner, locks actions.
  final bool busy;
  final VoidCallback? onAddMore;
  final void Function(int index)? onRemoveItem;

  /// Long-press drag-reorder: the item at [oldIndex] is moved so it lands
  /// at [newIndex] in the resulting list.
  final void Function(int oldIndex, int newIndex)? onReorder;

  /// A photo's caption was edited in the full-screen viewer.
  final void Function(int index, String caption)? onCaptionChanged;
  final VoidCallback? onDelete;

  /// Read mode — hide every edit affordance; captions still show.
  final bool readOnly;

  bool get _canReorder => !readOnly && onReorder != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = block.galleryItems;
    final count = items.length;

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
                'Галерея · $count фото',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFamily: 'Lora',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (!readOnly)
                PopupMenuButton<String>(
                  key: Key('article-gallery-menu-${block.id}'),
                  tooltip: 'Действия с галереей',
                  enabled: !busy,
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.6),
                  ),
                  onSelected: (value) {
                    if (value == 'add') onAddMore?.call();
                    if (value == 'delete') onDelete?.call();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'add', child: Text('Добавить фото')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Удалить галерею'),
                    ),
                  ],
                ),
            ],
          ),
          if (_canReorder && count > 1)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 2),
              child: Text(
                'Удерживайте фото, чтобы поменять порядок',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.7),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  const cols = 3;
                  const gap = 8.0;
                  final size = (constraints.maxWidth - gap * (cols - 1)) / cols;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        _reorderableThumb(context, theme, items, i, size),
                      if (!readOnly) _addTile(theme, size),
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

  // Wraps a thumbnail as a drag source + drop target when reordering is
  // allowed; otherwise returns the plain thumbnail.
  Widget _reorderableThumb(
    BuildContext context,
    ThemeData theme,
    List<Map<String, dynamic>> items,
    int index,
    double size,
  ) {
    final tile = _thumb(context, theme, items, index, size);
    if (!_canReorder) return tile;
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => onReorder!(details.data, index),
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        return LongPressDraggable<int>(
          data: index,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.9,
              child: SizedBox(
                width: size,
                height: size,
                child: _thumbImage(theme, items[index], size),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: tile),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: highlighted
                  ? Border.all(color: theme.colorScheme.primary, width: 2.5)
                  : null,
            ),
            child: tile,
          ),
        );
      },
    );
  }

  Widget _thumb(
    BuildContext context,
    ThemeData theme,
    List<Map<String, dynamic>> items,
    int index,
    double size,
  ) {
    final item = items[index];
    final caption = (item['caption']?.toString() ?? '').trim();
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              key: Key('article-gallery-photo-${block.id}-$index'),
              onTap: () => _openViewer(context, items, index),
              child: _thumbImage(theme, item, size),
            ),
            if (caption.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black54],
                    ),
                  ),
                  child: Text(
                    caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
            if (!readOnly)
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  key: Key('article-gallery-remove-${block.id}-$index'),
                  onTap: busy ? null : () => onRemoveItem?.call(index),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(3),
                    child:
                        const Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _thumbImage(ThemeData theme, Map<String, dynamic> item, double size) {
    final url = normalizePhotoUrl(item['url']?.toString());
    if (url == null) {
      return Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.broken_image_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return CachedNetworkImage(
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
    );
  }

  Widget _addTile(ThemeData theme, double size) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: Key('article-gallery-add-${block.id}'),
          onTap: busy ? null : onAddMore,
          borderRadius: BorderRadius.circular(12),
          child: Icon(
            Icons.add_photo_alternate_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  void _openViewer(
    BuildContext context,
    List<Map<String, dynamic>> items,
    int index,
  ) {
    if (items.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _GalleryViewer(
          items: items,
          initialIndex: index.clamp(0, items.length - 1),
          readOnly: readOnly,
          onCaptionChanged: onCaptionChanged,
        ),
      ),
    );
  }
}

/// Full-screen, swipeable, pinch-zoom viewer. Shows the index («2 / 5»)
/// and the per-photo caption; in edit mode the caption is an editable
/// field that commits (onCaptionChanged) on submit / page-change / close.
class _GalleryViewer extends StatefulWidget {
  const _GalleryViewer({
    required this.items,
    required this.initialIndex,
    required this.readOnly,
    this.onCaptionChanged,
  });

  final List<Map<String, dynamic>> items;
  final int initialIndex;
  final bool readOnly;
  final void Function(int index, String caption)? onCaptionChanged;

  @override
  State<_GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<_GalleryViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  late final List<String> _captions = [
    for (final it in widget.items) (it['caption']?.toString() ?? ''),
  ];
  late final TextEditingController _captionController =
      TextEditingController(text: _captions[widget.initialIndex]);

  void _commit(int index) {
    if (widget.readOnly || widget.onCaptionChanged == null) return;
    widget.onCaptionChanged!(index, _captions[index]);
  }

  void _onPageChanged(int i) {
    // Commit the page we're leaving, then load the new one.
    _captions[_index] = _captionController.text;
    _commit(_index);
    setState(() => _index = i);
    _captionController.text = _captions[i];
  }

  @override
  void dispose() {
    _captions[_index] = _captionController.text;
    _commit(_index);
    _captionController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final caption = _captions[_index].trim();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('${_index + 1} / ${widget.items.length}'),
      ),
      bottomNavigationBar: (widget.readOnly && caption.isEmpty)
          ? null
          : Container(
              color: Colors.black,
              padding: EdgeInsets.fromLTRB(
                16,
                10,
                16,
                10 + MediaQuery.of(context).padding.bottom,
              ),
              child: widget.readOnly
                  ? Text(
                      caption,
                      key: const Key('gallery-viewer-caption'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Lora',
                        fontSize: 15,
                        height: 1.3,
                      ),
                    )
                  : TextField(
                      key: const Key('gallery-viewer-caption-field'),
                      controller: _captionController,
                      onChanged: (t) => _captions[_index] = t,
                      onSubmitted: (_) => _commit(_index),
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Подпись к фото…',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
            ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.items.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (_, i) {
          final url = normalizePhotoUrl(widget.items[i]['url']?.toString());
          return InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: url == null
                  ? const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 48,
                    )
                  : CachedNetworkImage(
                      imageUrl: url,
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
          );
        },
      ),
    );
  }
}
