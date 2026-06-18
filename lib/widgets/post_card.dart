import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/post_service_interface.dart';
import '../models/post.dart';
import '../models/reaction_summary.dart';
import '../theme/app_theme.dart';
import 'comment_sheet.dart';
import 'feed_media_gallery.dart';
import 'glass_panel.dart';
import 'media_lightbox.dart';
import 'reaction_chip_strip.dart';
import 'reaction_picker.dart';
import 'rodnya_avatar.dart';
import 'safe_delete_confirmation_dialog.dart';

class PostCard extends StatefulWidget {
  const PostCard({super.key, required this.post, this.onDeleted});

  final Post post;
  final VoidCallback? onDeleted;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with SingleTickerProviderStateMixin {
  final String? _currentUserId = GetIt.I<AuthServiceInterface>().currentUserId;
  final PostServiceInterface _postService = GetIt.I<PostServiceInterface>();

  late bool _isLikedByCurrentUser;
  late int _likeCount;
  late int _commentCount;
  late List<ReactionSummary> _reactions;

  late AnimationController _likeAnimationController;
  late Animation<double> _likeScaleAnimation;

  @override
  void initState() {
    super.initState();
    _syncLocalState();
    _likeAnimationController = AnimationController(
        duration: const Duration(milliseconds: 200), vsync: this);
    _likeScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(
        parent: _likeAnimationController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _likeAnimationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id ||
        oldWidget.post.likeCount != widget.post.likeCount ||
        oldWidget.post.commentCount != widget.post.commentCount ||
        oldWidget.post.likedBy != widget.post.likedBy) {
      _syncLocalState();
    }
  }

  void _syncLocalState() {
    _isLikedByCurrentUser =
        _currentUserId != null && widget.post.likedBy.contains(_currentUserId!);
    _likeCount = widget.post.likeCount;
    _commentCount = widget.post.commentCount;
    _reactions = List<ReactionSummary>.from(widget.post.reactions);
  }

  Future<void> _openReactionPicker() async {
    final emoji = await ReactionPicker.show(context);
    if (emoji == null || !mounted) return;
    await _toggleReaction(emoji);
  }

  Future<void> _toggleReaction(String emoji) async {
    final beforeReactions = List<ReactionSummary>.from(_reactions);
    // Optimistic update — add or remove the current user's reaction
    // locally, then reconcile with server response. Mirrors what the
    // chat-side reaction handler does.
    HapticFeedback.lightImpact();
    final next = _applyOptimisticReaction(beforeReactions, emoji);
    setState(() => _reactions = next);
    try {
      final fromServer = await _postService.togglePostReaction(
        postId: widget.post.id,
        emoji: emoji,
      );
      if (!mounted) return;
      setState(() => _reactions = fromServer);
    } catch (e) {
      if (!mounted) return;
      setState(() => _reactions = beforeReactions);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить реакцию: $e')),
      );
    }
  }

  /// Optimistic toggle: if the current user already reacted with this
  /// emoji, remove them; otherwise add them. Removes the entry if its
  /// count would drop to zero.
  List<ReactionSummary> _applyOptimisticReaction(
    List<ReactionSummary> input,
    String emoji,
  ) {
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) return input;
    final next = List<ReactionSummary>.from(input);
    final existingIndex = next.indexWhere((r) => r.emoji == emoji);
    if (existingIndex == -1) {
      next.add(ReactionSummary(
        emoji: emoji,
        userIds: <String>[userId],
        count: 1,
      ));
    } else {
      final entry = next[existingIndex];
      final wasMine = entry.userIds.contains(userId);
      final updatedUsers = List<String>.from(entry.userIds);
      if (wasMine) {
        updatedUsers.remove(userId);
      } else {
        updatedUsers.add(userId);
      }
      if (updatedUsers.isEmpty) {
        next.removeAt(existingIndex);
      } else {
        next[existingIndex] = ReactionSummary(
          emoji: emoji,
          userIds: updatedUsers,
          count: updatedUsers.length,
        );
      }
    }
    return next;
  }

  Future<void> _toggleLike() async {
    if (_currentUserId == null) return;

    final wasLiked = _isLikedByCurrentUser;
    final previousLikeCount = _likeCount;
    // Tactile blip on every like — keeps the action feeling alive
    // even when the network is slow.
    HapticFeedback.lightImpact();
    setState(() {
      _isLikedByCurrentUser = !wasLiked;
      _likeCount = (previousLikeCount + (wasLiked ? -1 : 1)).clamp(0, 1 << 30);
    });

    if (!wasLiked) {
      _likeAnimationController.forward(from: 0);
    }

    try {
      final updatedPost = await _postService.toggleLike(widget.post.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _isLikedByCurrentUser = updatedPost.likedBy.contains(_currentUserId!);
        _likeCount = updatedPost.likeCount;
        _commentCount = updatedPost.commentCount;
      });
    } catch (e) {
      // Revert to the last confirmed state if the backend rejected the like.
      setState(() {
        _isLikedByCurrentUser = wasLiked;
        _likeCount = previousLikeCount;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось обновить реакцию: $e')),
        );
      }
    }
  }

  void _openAuthorProfile() {
    if (widget.post.authorId.isEmpty) {
      return;
    }
    if (_currentUserId == widget.post.authorId) {
      context.push('/profile');
      return;
    }
    context.push('/user/${widget.post.authorId}');
  }

  Future<void> _sharePost() async {
    final buffer = StringBuffer()
      ..writeln(widget.post.authorName)
      ..writeln(
        DateFormat('d MMMM yyyy в HH:mm', 'ru').format(widget.post.createdAt),
      );

    if (widget.post.content.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(widget.post.content.trim());
    }

    final imageUrls = widget.post.renderableImageUrls;
    if (imageUrls.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Фото: ${imageUrls.join('\n')}');
    }

    await SharePlus.instance.share(
      ShareParams(text: buffer.toString().trim()),
    );
  }

  /// Copy a shareable deep-link to the post. Frontend-only: builds
  /// `<publicAppUrl>/post/<id>` and drops it on the clipboard.
  Future<void> _copyPostLink() async {
    final base = BackendRuntimeConfig.current.publicAppUrl
        .replaceAll(RegExp(r'/+$'), '');
    final link = '$base/post/${widget.post.id}';
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ссылка на пост скопирована')),
      );
    }
  }

  String get _audienceLabel {
    if (widget.post.circleId?.trim().isNotEmpty == true) {
      return 'Круг';
    }
    if (widget.post.scopeType == TreeContentScopeType.branches) {
      return 'Ветки';
    }
    if (widget.post.isPublic) {
      return 'Публично';
    }
    return 'Семья';
  }

  IconData get _audienceIcon {
    if (widget.post.circleId?.trim().isNotEmpty == true) {
      return Icons.diversity_3_outlined;
    }
    if (widget.post.scopeType == TreeContentScopeType.branches) {
      return Icons.alt_route;
    }
    if (widget.post.isPublic) {
      return Icons.public;
    }
    // Reference uses a leaf glyph for the family-scope post audience.
    return Icons.eco_outlined;
  }

  Future<void> _showCommentsSheet() async {
    // CommentSheet now pops with the final loaded count (int?) so we
    // can sync the inline counter without a server round-trip.
    final finalCount = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommentSheet(post: widget.post),
    );

    if (finalCount != null && mounted && finalCount != _commentCount) {
      setState(() => _commentCount = finalCount);
    }
  }

  Future<void> _deletePost() async {
    // Ship 2026-05-26 (UX audit Screen 3.5 polish): уровнить delete UX
    // с Q4 tree person pattern. Pre-fix: plain AlertDialog с TextButton
    // в красном цвете, barrierDismissible=true (tap-outside cancels —
    // плохо для destructive), consequence copy generic. Post-fix: shared
    // SafeDeleteConfirmationDialog (severity icon + destructive filled
    // tonal button + barrierDismissible=false + audit-aligned copy
    // mentioning «у всех родственников» reach).
    //
    // Ship Q4a frontend (2026-05-28, Ship 31): backend now soft-deletes
    // через deletedPosts collection с 30-day retention + Settings →
    // Корзина restore. Copy обновлён — «нельзя отменить» был ложью.
    final confirmed = await showSafeDeleteConfirmation(
      context,
      title: 'Удалить публикацию?',
      body: 'Пост исчезнет у всех родственников и переедет в корзину. '
          'Восстановить можно в течение 30 дней в Настройки → Корзина.',
    );
    if (!confirmed || !mounted) return;

    try {
      await _postService.deletePost(widget.post.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Публикация удалена')),
        );
        if (widget.onDeleted != null) {
          widget.onDeleted!();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при удалении: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final renderableImageUrls = widget.post.renderableImageUrls;
    final hasInvalidOnlyImages = renderableImageUrls.isEmpty &&
        (widget.post.imageUrls?.isNotEmpty ?? false);
    final theme = Theme.of(context);
    final tokens = _tokensFor(theme);

    return GlassPanel(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
      borderRadius: BorderRadius.circular(tokens.radiusMd + 2),
      plain: true,
      child: GestureDetector(
        // Long-press anywhere on the card opens the emoji reaction
        // picker — IG / FB pattern. Tap behaviour stays delegated to
        // children (header / images / action buttons) so we don't
        // intercept their semantics.
        behavior: HitTestBehavior.translucent,
        onLongPress: _openReactionPicker,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPostHeader(),
            if (widget.post.content.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(
                    tokens.space16, 0, tokens.space16, tokens.space12),
                child: Text(
                  widget.post.content,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.45,
                  ),
                ),
              ),
            if (renderableImageUrls.isNotEmpty)
              _buildPostImages(renderableImageUrls)
            else if (hasInvalidOnlyImages)
              _buildInvalidPostImageFallback(),
            if (_reactions.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(tokens.space16, tokens.space4,
                    tokens.space16, tokens.space4),
                child: ReactionChipStrip(
                  reactions: _reactions,
                  currentUserId: _currentUserId,
                  onToggle: _toggleReaction,
                ),
              ),
            _buildPostActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildPostHeader() {
    final theme = Theme.of(context);
    final tokens = _tokensFor(theme);
    final authorPhotoUrl = widget.post.renderableAuthorPhotoUrl;
    final timeText = DateFormat('d MMM • HH:mm', 'ru').format(
      widget.post.createdAt,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.space16,
        tokens.space12,
        tokens.space12,
        tokens.space12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: _openAuthorProfile,
            child: RodnyaAvatar(
              photoUrl: authorPhotoUrl,
              name: widget.post.authorName,
              size: 40,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: _openAuthorProfile,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: AppTheme.sans(
                        color: tokens.ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                      children: [
                        TextSpan(text: widget.post.authorName),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  DefaultTextStyle.merge(
                    style: AppTheme.sans(
                      color: tokens.inkMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      children: [
                        Text(timeText),
                        const Text('·'),
                        Icon(_audienceIcon, size: 11, color: tokens.inkMuted),
                        Text(_audienceLabel),
                        if (widget.post.scopeType ==
                            TreeContentScopeType.branches) ...[
                          const Text('·'),
                          Icon(Icons.alt_route,
                              size: 11, color: tokens.inkMuted),
                          Text('Ветки: ${widget.post.anchorPersonIds.length}'),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Overflow menu shows for everyone now: «Скопировать ссылку» is
          // available to any viewer; «Удалить» stays author-only.
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            // ≥44dp tap target for the overflow menu (was 32×32).
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: Icon(
              Icons.more_horiz_rounded,
              color: tokens.inkMuted,
              size: 18,
            ),
            onSelected: (value) {
              if (value == 'copy-link') {
                _copyPostLink();
              } else if (value == 'delete') {
                _deletePost();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'copy-link',
                child: Row(
                  children: [
                    Icon(Icons.link_rounded, size: 20),
                    SizedBox(width: 8),
                    Text('Скопировать ссылку'),
                  ],
                ),
              ),
              if (_currentUserId == widget.post.authorId)
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text('Удалить', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPostImages(List<String> images) {
    final lightboxItems = images
        .map(
          (url) => isFeedVideoUrl(url)
              ? MediaLightboxItem(videoUrl: url)
              : MediaLightboxItem(imageUrl: url),
        )
        .toList(growable: false);

    void openLightbox(int initialIndex) {
      MediaLightbox.show(
        context,
        items: lightboxItems,
        initialIndex: initialIndex,
        // Surface post-level actions inside the fullscreen viewer so
        // the user can like / read comments / forward without bouncing
        // back to the feed. The parent (this PostCard) is the source
        // of truth for like/count state — the lightbox keeps an
        // optimistic local copy until it's dismissed.
        initialLiked: _isLikedByCurrentUser,
        likeCount: _likeCount,
        commentCount: _commentCount,
        onLike: _toggleLike,
        onComment: () {
          // Pop the lightbox first so the comments bottom sheet sits
          // on the post (not on top of a black scrim).
          Navigator.of(context, rootNavigator: true).pop();
          _showCommentsSheet();
        },
        onShare: (_) => _sharePost(),
      );
    }

    // Rendering (single tile / carousel + page-dots / video tiles /
    // shimmer / fallback / video-sniffing) lives in the shared
    // FeedMediaGallery; this card just owns the post-level lightbox.
    return FeedMediaGallery(
      imageUrls: images,
      onTap: openLightbox,
      caption: widget.post.content,
      captionPrefix: 'Фото к посту',
    );
  }

  Widget _buildInvalidPostImageFallback() {
    final tokens = _tokensFor(Theme.of(context));
    return Padding(
      padding: EdgeInsets.fromLTRB(
          tokens.space12, 0, tokens.space12, tokens.space12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          child: const FeedMediaFallback(),
        ),
      ),
    );
  }

  Widget _buildPostActions() {
    final theme = Theme.of(context);
    final tokens = _tokensFor(theme);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_likeCount > 0 || _commentCount > 0)
          Padding(
            padding: EdgeInsets.fromLTRB(
                tokens.space16, 0, tokens.space16, tokens.space8),
            child: Row(
              children: [
                if (_likeCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.surface.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: tokens.surfaceLine),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Unified «тепло» vocabulary: the same warm
                        // Material heart the action button uses, not a
                        // stray white-heart emoji.
                        Icon(Icons.favorite, size: 11, color: tokens.warm),
                        const SizedBox(width: 4),
                        Text(
                          _likeCount.toString(),
                          style: AppTheme.sans(
                            color: tokens.inkSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                if (_commentCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.surface.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: tokens.surfaceLine),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.mode_comment_outlined,
                          size: 12,
                          color: tokens.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _commentCount.toString(),
                          style: AppTheme.sans(
                            color: tokens.inkSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        Container(
          height: 0.7,
          margin: EdgeInsets.symmetric(horizontal: tokens.space16),
          color: tokens.surfaceLine,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: _PostActionButton(
                  onPressed: _toggleLike,
                  icon: ScaleTransition(
                    scale: _likeScaleAnimation,
                    child: Icon(
                      _isLikedByCurrentUser
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: _isLikedByCurrentUser
                          ? tokens.warm
                          : tokens.inkSecondary,
                      size: 18,
                    ),
                  ),
                  label: 'Тепло',
                  active: _isLikedByCurrentUser,
                ),
              ),
              Expanded(
                child: _PostActionButton(
                  onPressed: _showCommentsSheet,
                  icon: Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: tokens.inkSecondary,
                    size: 18,
                  ),
                  label: 'Ответить',
                ),
              ),
              Expanded(
                child: _PostActionButton(
                  onPressed: _sharePost,
                  icon: Icon(
                    Icons.share_outlined,
                    color: tokens.inkSecondary,
                    size: 18,
                  ),
                  // Was labelled «Сохранить» with a bookmark glyph but
                  // wired to _sharePost, and there's no save feature in
                  // PostServiceInterface — relabel to match the action.
                  label: 'Поделиться',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  RodnyaDesignTokens _tokensFor(ThemeData theme) {
    return theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
  }
}

class _PostActionButton extends StatelessWidget {
  const _PostActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.active = false,
  });

  final VoidCallback onPressed;
  final Widget icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 6),
            // S1 (попутный прод-баг): на ширине A50 длинный лейбл
            // переполнял Row на 15–41px — обрезаем честно.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.sans(
                  color: active ? tokens.warm : tokens.inkSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
