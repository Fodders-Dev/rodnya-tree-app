// Profile Phase 2b-1 (2026-05-29): editable photo block for the article
// editor. Full-width image (url-addressed, cached) + optional caption +
// dateTaken chip + overflow menu (заменить / дата / удалить).
//
// Editor-side render only — the polished read-only article viewer is
// Phase 3. Caption edits are debounced-saved by the editor (same path
// as paragraph text); date / replace / delete call back to the editor.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../backend/models/profile_article.dart';
import '../utils/photo_url.dart';
import 'photo_date_picker_sheet.dart';

class ArticlePhotoBlock extends StatelessWidget {
  const ArticlePhotoBlock({
    super.key,
    required this.block,
    required this.captionController,
    required this.busy,
    required this.onCaptionChanged,
    required this.onSetDate,
    required this.onReplace,
    required this.onDelete,
  });

  final ArticleBlock block;
  final TextEditingController captionController;

  /// Upload / patch in flight — overlays a spinner, locks the menu.
  final bool busy;
  final VoidCallback onCaptionChanged;
  final VoidCallback onSetDate;
  final VoidCallback onReplace;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = normalizePhotoUrl(block.content['url']?.toString());
    final dateLabel = formatPhotoDate(
      block.content['dateTaken']?.toString(),
      block.content['dateTakenAccuracy']?.toString(),
    );

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
                            onReplace();
                            break;
                          case 'date':
                            onSetDate();
                            break;
                          case 'delete':
                            onDelete();
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
            onChanged: (_) => onCaptionChanged(),
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
      ),
    );
  }
}
