// Profile Phase 2b-1 (2026-05-29): photo block for the article editor.
// Full-width image (url-addressed, cached) + optional caption + dateTaken
// chip + overflow menu (заменить / дата / удалить).
//
// Read mode (Viewer phase): pass readOnly:true and omit the edit
// callbacks — the ⋮ menu disappears and caption + date render as static
// text, so the same widget is the single source of photo rendering in
// both the editor and the read-only article view.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../backend/models/profile_article.dart';
import '../utils/photo_url.dart';
import 'photo_date_picker_sheet.dart';

class ArticlePhotoBlock extends StatelessWidget {
  const ArticlePhotoBlock({
    super.key,
    required this.block,
    this.captionController,
    this.busy = false,
    this.onCaptionChanged,
    this.onSetDate,
    this.onReplace,
    this.onDelete,
    this.readOnly = false,
  });

  final ArticleBlock block;

  /// Edit mode only — the caption's controller (null in read mode).
  final TextEditingController? captionController;

  /// Upload / patch in flight — overlays a spinner, locks the menu.
  final bool busy;
  final VoidCallback? onCaptionChanged;
  final VoidCallback? onSetDate;
  final VoidCallback? onReplace;
  final VoidCallback? onDelete;

  /// Read mode — hide the ⋮ menu; caption + date become static text.
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = normalizePhotoUrl(block.content['url']?.toString());
    final dateLabel = formatPhotoDate(
      block.content['dateTaken']?.toString(),
      block.content['dateTakenAccuracy']?.toString(),
    );
    final caption = block.content['caption']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
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
                if (busy)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black45,
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                  ),
                if (!readOnly)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: PopupMenuButton<String>(
                        key: Key('article-photo-menu-${block.id}'),
                        icon: const Icon(Icons.more_horiz, color: Colors.white),
                        tooltip: 'Действия с фото',
                        enabled: !busy,
                        onSelected: (value) {
                          switch (value) {
                            case 'replace':
                              onReplace?.call();
                              break;
                            case 'date':
                              onSetDate?.call();
                              break;
                            case 'delete':
                              onDelete?.call();
                              break;
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'replace',
                            child: Text('Заменить'),
                          ),
                          PopupMenuItem(
                            value: 'date',
                            child: Text('Дата съёмки'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Удалить'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (readOnly) ...[
            if (caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'Lora',
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (dateLabel != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.event_outlined,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      dateLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ] else ...[
            TextField(
              key: Key('article-photo-caption-${block.id}'),
              controller: captionController,
              textAlign: TextAlign.center,
              maxLines: null,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'Lora',
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Подпись (необязательно)',
              ),
              onChanged: (_) => onCaptionChanged?.call(),
            ),
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                key: Key('article-photo-date-${block.id}'),
                onPressed: busy ? null : onSetDate,
                icon: const Icon(Icons.event_outlined, size: 16),
                label: Text(dateLabel ?? 'Указать дату съёмки'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
