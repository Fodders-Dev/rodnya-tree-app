// Viewer phase — SUB-CHUNK 1 (2026-06-01): read-only article renderer.
//
// Renders an ordered List<ArticleBlock> with NO edit affordances — no
// controllers, no ⋮ menus, no autosave. Text blocks (paragraph / header /
// quote / divider) render as plain Text / Divider; media blocks reuse the
// editor's own widgets in readOnly mode (single source of render), so a
// photo / gallery / audio looks identical to the editor minus the edit
// chrome. Playback (audio) and full-screen (gallery) stay available.

import 'package:flutter/material.dart';

import '../backend/models/profile_article.dart';
import 'article_audio_block.dart';
import 'article_gallery_block.dart';
import 'article_photo_block.dart';

class ArticleReadView extends StatelessWidget {
  const ArticleReadView({super.key, required this.blocks});

  final List<ArticleBlock> blocks;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final block in blocks) _block(context, block),
      ],
    );
  }

  Widget _block(BuildContext context, ArticleBlock block) {
    final theme = Theme.of(context);
    final key = Key('read-block-${block.id}');

    if (block.isHeader) {
      return Padding(
        key: key,
        padding: const EdgeInsets.only(top: 18, bottom: 2),
        child: Text(
          block.headerText,
          style: theme.textTheme.titleLarge?.copyWith(
            fontFamily: 'Lora',
            fontWeight: FontWeight.w700,
            fontSize: block.headerLevel == 1 ? 24 : 20,
          ),
        ),
      );
    }

    if (block.isQuote) {
      return _quote(context, block, key);
    }

    if (block.isDivider) {
      return Padding(
        key: key,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Divider(
          thickness: 1,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      );
    }

    if (block.type == 'photo') {
      return ArticlePhotoBlock(key: key, block: block, readOnly: true);
    }

    if (block.isGallery) {
      return ArticleGalleryBlock(key: key, block: block, readOnly: true);
    }

    if (block.isAudio) {
      return ArticleAudioBlock(key: key, block: block, readOnly: true);
    }

    // Paragraph (default). Empty paragraphs render nothing.
    final text = block.plainText;
    if (text.isEmpty) return SizedBox.shrink(key: key);
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Text(
        text,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontFamily: 'Lora',
          fontSize: 18,
          height: 1.55,
        ),
      ),
    );
  }

  Widget _quote(BuildContext context, ArticleBlock block, Key key) {
    final theme = Theme.of(context);
    final attribution = block.quoteAttribution;
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Container(
        padding: const EdgeInsets.only(left: 14),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.primary.withValues(alpha: 0.55),
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              block.quoteText,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontFamily: 'Lora',
                fontSize: 18,
                height: 1.5,
                fontStyle: FontStyle.italic,
              ),
            ),
            if (attribution != null && attribution.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '— $attribution',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'Lora',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
