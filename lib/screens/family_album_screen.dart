// Album v1 (album/v1): «Альбом семьи» — every photo from the family's
// posts, collected into one browsable grid so moments don't get lost in
// the feed scroll. Frontend-only: aggregates over the audience scope the
// home feed already uses (getPosts(treeId: null) = union across ALL the
// viewer's branches — a ready scope, no per-branch fan needed), dedups by
// URL, sorts newest-first. Tap → the shared MediaLightbox (swipe between
// every photo in the album). Optional «по автору» filter (client-side —
// posts already carry authorName/authorPhotoUrl, no getRelatives call).
//
// Out of scope (separate arcs): «кто на фото» (needs person-tagging,
// Phase D — anchorPersonIds is audience-scope, not subjects), Круг
// (Phase C), memory-resurfacing (Phase E), backend filters.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import '../backend/interfaces/post_service_interface.dart';
import '../models/post.dart';
import '../services/posts_cache.dart';
import '../theme/app_theme.dart';
import '../widgets/media_lightbox.dart';

class _AlbumPhoto {
  const _AlbumPhoto({
    required this.url,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
  });

  final String url;
  final String authorId;
  final String authorName;
  final DateTime createdAt;
}

/// A photo plus its position in the full (filtered) album, so a thumb in
/// any month section can open the lightbox at the right global index.
class _IndexedPhoto {
  const _IndexedPhoto({required this.photo, required this.globalIndex});

  final _AlbumPhoto photo;
  final int globalIndex;
}

class _MonthSection {
  _MonthSection({required this.month});

  final DateTime month;
  final List<_IndexedPhoto> items = [];
}

class _MonthHeaderDelegate extends SliverPersistentHeaderDelegate {
  _MonthHeaderDelegate({
    required this.label,
    required this.background,
    required this.textStyle,
  });

  final String label;
  final Color background;
  final TextStyle? textStyle;

  static const double _height = 40;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      height: _height,
      color: background,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(label, style: textStyle),
    );
  }

  @override
  bool shouldRebuild(_MonthHeaderDelegate old) =>
      old.label != label || old.background != background;
}

class FamilyAlbumScreen extends StatefulWidget {
  const FamilyAlbumScreen({
    super.key,
    this.serviceOverride,
    this.cacheOverride,
  });

  /// Test seams — production resolves via GetIt.
  final PostServiceInterface? serviceOverride;
  final PostsCache? cacheOverride;

  @override
  State<FamilyAlbumScreen> createState() => _FamilyAlbumScreenState();
}

class _FamilyAlbumScreenState extends State<FamilyAlbumScreen> {
  // The home feed caches its aggregate («Все») batch under this key.
  // Reusing it gives the album instant offline-first photos.
  static const String _audienceCacheKey = '__audience__';

  bool _loading = true;
  List<_AlbumPhoto> _photos = const [];
  String? _authorFilter; // null = все авторы

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  PostServiceInterface? _service() {
    if (widget.serviceOverride != null) return widget.serviceOverride;
    if (GetIt.I.isRegistered<PostServiceInterface>()) {
      return GetIt.I<PostServiceInterface>();
    }
    return null;
  }

  PostsCache? _cache() {
    if (widget.cacheOverride != null) return widget.cacheOverride;
    if (GetIt.I.isRegistered<PostsCache>()) return GetIt.I<PostsCache>();
    return null;
  }

  Future<void> _load() async {
    // Offline-first: hydrate from the audience cache before the network.
    final cache = _cache();
    if (cache != null) {
      try {
        final cached = await cache.read(_audienceCacheKey);
        if (cached.isNotEmpty && mounted) {
          setState(() => _photos = _collect(cached));
        }
      } catch (_) {
        // Cache miss is non-fatal.
      }
    }

    final svc = _service();
    if (svc == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      // treeId: null = audience aggregate across ALL the viewer's
      // branches (same scope the home feed uses in «Все» mode).
      final posts = await svc.getPosts(treeId: null);
      if (!mounted) return;
      setState(() {
        _photos = _collect(posts);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Flatten posts → photos, newest-first, deduped by URL. Videos are
  /// skipped (album v1 is photos; posts store videos in imageUrls too).
  List<_AlbumPhoto> _collect(List<Post> posts) {
    final sorted = [...posts]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final out = <_AlbumPhoto>[];
    final seen = <String>{};
    for (final post in sorted) {
      for (final url in post.renderableImageUrls) {
        if (_isVideoUrl(url)) continue;
        if (!seen.add(url)) continue;
        out.add(_AlbumPhoto(
          url: url,
          authorId: post.authorId,
          authorName: post.authorName,
          createdAt: post.createdAt,
        ));
      }
    }
    return out;
  }

  bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    final q = lower.indexOf('?');
    final path = q >= 0 ? lower.substring(0, q) : lower;
    return path.endsWith('.mp4') ||
        path.endsWith('.mov') ||
        path.endsWith('.webm') ||
        path.endsWith('.m4v') ||
        path.endsWith('.avi');
  }

  /// Distinct authors (id → display name), in first-seen order — drives
  /// the «по автору» filter chips.
  Map<String, String> get _authors {
    final map = <String, String>{};
    for (final p in _photos) {
      map.putIfAbsent(p.authorId, () => p.authorName);
    }
    return map;
  }

  List<_AlbumPhoto> get _visiblePhotos => _authorFilter == null
      ? _photos
      : _photos.where((p) => p.authorId == _authorFilter).toList();

  void _openLightbox(int index) {
    final photos = _visiblePhotos;
    if (photos.isEmpty) return;
    MediaLightbox.show(
      context,
      items: [
        for (final p in photos) MediaLightboxItem(imageUrl: p.url),
      ],
      initialIndex: index.clamp(0, photos.length - 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final visible = _visiblePhotos;
    return Scaffold(
      appBar: AppBar(title: const Text('Альбом семьи')),
      body: _loading && _photos.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildAuthorFilter(theme, tokens),
                Expanded(
                  child: visible.isEmpty
                      ? _buildEmpty(theme, tokens)
                      : _buildSections(theme, tokens, visible),
                ),
              ],
            ),
    );
  }

  Widget _buildAuthorFilter(ThemeData theme, RodnyaDesignTokens tokens) {
    final authors = _authors;
    // Pointless when everything is from one author (or empty).
    if (authors.length < 2) return const SizedBox.shrink();
    final entries = authors.entries.toList();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: tokens.space12, vertical: 6),
        itemCount: entries.length + 1,
        separatorBuilder: (_, __) => SizedBox(width: tokens.space8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return ChoiceChip(
              key: const Key('album-author-all'),
              label: const Text('Все'),
              selected: _authorFilter == null,
              onSelected: (_) => setState(() => _authorFilter = null),
            );
          }
          final entry = entries[index - 1];
          return ChoiceChip(
            label: Text(entry.value),
            selected: _authorFilter == entry.key,
            onSelected: (_) => setState(() => _authorFilter = entry.key),
          );
        },
      ),
    );
  }

  /// Group [photos] (already newest-first) into month buckets — because
  /// the list is date-sorted, every month's photos are contiguous, so a
  /// single pass yields newest-month-first sections without a map. Each
  /// thumb keeps its global index so the lightbox still pages the whole
  /// album in chronology.
  List<_MonthSection> _groupByMonth(List<_AlbumPhoto> photos) {
    final sections = <_MonthSection>[];
    for (var i = 0; i < photos.length; i++) {
      final photo = photos[i];
      final month = DateTime(photo.createdAt.year, photo.createdAt.month);
      if (sections.isEmpty || sections.last.month != month) {
        sections.add(_MonthSection(month: month));
      }
      sections.last.items.add(_IndexedPhoto(photo: photo, globalIndex: i));
    }
    return sections;
  }

  String _monthLabel(DateTime month) {
    // Standalone (nominative) month name: «Июнь 2026», not «июня».
    final raw = DateFormat('LLLL yyyy', 'ru').format(month);
    return raw.isEmpty ? raw : raw[0].toUpperCase() + raw.substring(1);
  }

  Widget _buildSections(
    ThemeData theme,
    RodnyaDesignTokens tokens,
    List<_AlbumPhoto> photos,
  ) {
    final sections = _groupByMonth(photos);
    // Full-screen route (pushed on the root navigator like post/search) →
    // no bottom nav, so we only clear the device safe-area inset.
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return CustomScrollView(
      slivers: [
        for (final section in sections) ...[
          SliverPersistentHeader(
            pinned: true,
            delegate: _MonthHeaderDelegate(
              label: _monthLabel(section.month),
              background: theme.scaffoldBackgroundColor,
              textStyle: theme.textTheme.titleSmall?.copyWith(
                fontFamily: 'Lora',
                fontWeight: FontWeight.w700,
                color: tokens.ink,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final indexed = section.items[i];
                  return _buildThumb(theme, indexed.photo, indexed.globalIndex);
                },
                childCount: section.items.length,
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(child: SizedBox(height: bottomInset)),
      ],
    );
  }

  Widget _buildThumb(ThemeData theme, _AlbumPhoto photo, int globalIndex) {
    return GestureDetector(
      key: Key('album-thumb-$globalIndex'),
      onTap: () => _openLightbox(globalIndex),
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

  Widget _buildEmpty(ThemeData theme, RodnyaDesignTokens tokens) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            SizedBox(height: tokens.space12),
            Text(
              'Пока нет фотографий',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: 'Lora',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: tokens.space8),
            Text(
              'Поделись первым моментом в ленте — фото соберутся здесь.',
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
