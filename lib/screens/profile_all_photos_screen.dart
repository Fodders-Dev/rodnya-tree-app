// Viewer §3.2.6 (sub-chunk 2b, 2026-06-02): «Все фото» — a grid of every
// photo in a person's biography article (standalone photo blocks + every
// gallery item). Tap → the shared MediaLightbox (pinch-zoom, swipe), the
// same fullscreen viewer the rest of the app uses.
//
// Self-loads the article via ProfileArticleServiceInterface (mirrors
// ProfileBiographySection). Read-only.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../backend/interfaces/profile_article_service_interface.dart';
import '../backend/models/profile_article.dart';
import '../utils/photo_url.dart';
import '../widgets/media_lightbox.dart';

class _Photo {
  const _Photo({required this.url, this.caption});
  final String url;
  final String? caption;
}

class ProfileAllPhotosScreen extends StatefulWidget {
  const ProfileAllPhotosScreen({
    super.key,
    required this.personId,
    required this.personName,
    this.serviceOverride,
  });

  final String personId;
  final String personName;

  /// Test seam — production resolves the service via GetIt.
  final ProfileArticleServiceInterface? serviceOverride;

  @override
  State<ProfileAllPhotosScreen> createState() =>
      _ProfileAllPhotosScreenState();
}

class _ProfileAllPhotosScreenState extends State<ProfileAllPhotosScreen> {
  bool _loading = true;
  List<_Photo> _photos = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  ProfileArticleServiceInterface? _service() {
    if (widget.serviceOverride != null) return widget.serviceOverride;
    if (GetIt.I.isRegistered<ProfileArticleServiceInterface>()) {
      return GetIt.I<ProfileArticleServiceInterface>();
    }
    return null;
  }

  Future<void> _load() async {
    final svc = _service();
    if (svc == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final article = await svc.getArticle(widget.personId);
      if (!mounted) return;
      setState(() {
        _photos = _collect(article.blocks);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Every standalone photo block + every gallery item, in document order.
  List<_Photo> _collect(List<ArticleBlock> blocks) {
    final out = <_Photo>[];
    void add(Object? rawUrl, Object? rawCaption) {
      final url = normalizePhotoUrl(rawUrl?.toString());
      if (url == null || url.isEmpty) return;
      final caption = rawCaption?.toString().trim();
      out.add(_Photo(url: url, caption: (caption?.isEmpty ?? true) ? null : caption));
    }

    for (final b in blocks) {
      if (b.type == 'photo') {
        add(b.content['url'], b.content['caption']);
      } else if (b.isGallery) {
        for (final item in b.galleryItems) {
          add(item['url'], item['caption']);
        }
      }
    }
    return out;
  }

  void _openLightbox(int index) {
    if (_photos.isEmpty) return;
    MediaLightbox.show(
      context,
      items: [
        for (final p in _photos)
          MediaLightboxItem(imageUrl: p.url, caption: p.caption),
      ],
      initialIndex: index.clamp(0, _photos.length - 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _photos.isEmpty ? 'Все фото' : 'Все фото (${_photos.length})';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _photos.isEmpty
              ? _empty(theme)
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _photos.length,
                  itemBuilder: (_, i) => _thumb(theme, i),
                ),
    );
  }

  Widget _thumb(ThemeData theme, int index) {
    final photo = _photos[index];
    return GestureDetector(
      key: Key('all-photos-thumb-$index'),
      onTap: () => _openLightbox(index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: photo.url,
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
    );
  }

  Widget _empty(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              'Пока нет фотографий',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: 'Lora',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Добавьте фото в биографию — они соберутся здесь.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
