import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/post_service_interface.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../models/reaction_summary.dart';
import '../theme/app_theme.dart';
import 'loading_indicator.dart';
import 'reaction_chip_strip.dart';
import 'reaction_picker.dart';

class CommentSheet extends StatefulWidget {
  const CommentSheet({super.key, required this.post});

  final Post post;

  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  final PostServiceInterface _postService = GetIt.I<PostServiceInterface>();
  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Comment>? _comments;
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final comments = await _postService.getComments(widget.post.id);
      if (mounted) {
        setState(() {
          _comments = comments;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Ошибка при загрузке комментариев: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    try {
      final newComment = await _postService.addComment(widget.post.id, text);
      if (mounted) {
        setState(() {
          _comments?.add(newComment);
          _commentController.clear();
          _isSending = false;
        });
        // Scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при добавлении комментария: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          _buildHandle(),
          _buildHeader(),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: LoadingIndicator())
                : _error != null
                    ? _buildErrorView()
                    : _buildCommentsList(),
          ),
          const Divider(height: 1),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    // User feedback was: "в комментариях нет счетчика комметариев". The
    // count comes from the loaded list once the sheet has its data; while
    // loading we fall back to the post's stored commentCount so the
    // header doesn't flicker between empty and the real number.
    final loadedCount = _comments?.length;
    final displayCount = loadedCount ?? widget.post.commentCount;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                'Комментарии',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (displayCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.accentSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$displayCount',
                    style: TextStyle(
                      color: tokens.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context, _comments?.length),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadComments,
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsList() {
    if (_comments == null || _comments!.isEmpty) {
      return const Center(
        child: Text('Комментариев пока нет. Будьте первым!'),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _comments!.length,
      itemBuilder: (context, index) {
        final comment = _comments![index];
        return _buildCommentItem(comment);
      },
    );
  }

  Widget _buildCommentItem(Comment comment) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        // Long-press → reaction picker. Same gesture pattern as the
        // post card so users build muscle memory across surfaces.
        behavior: HitTestBehavior.translucent,
        onLongPress: () => _openCommentReactionPicker(comment),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAuthorAvatar(comment),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        comment.authorName ?? 'Аноним',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('d MMM в HH:mm', 'ru')
                            .format(comment.createdAt),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(comment.content),
                  if (comment.reactions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    ReactionChipStrip(
                      reactions: comment.reactions,
                      currentUserId: _authService.currentUserId,
                      onToggle: (emoji) =>
                          _toggleCommentReaction(comment, emoji),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCommentReactionPicker(Comment comment) async {
    final emoji = await ReactionPicker.show(context);
    if (emoji == null || !mounted) return;
    await _toggleCommentReaction(comment, emoji);
  }

  Future<void> _toggleCommentReaction(Comment comment, String emoji) async {
    final userId = _authService.currentUserId;
    if (userId == null || userId.isEmpty) return;
    final originalReactions =
        List<ReactionSummary>.from(comment.reactions);
    // Optimistic local toggle so the chip flickers in immediately.
    final next = _applyOptimisticReaction(originalReactions, emoji, userId);
    setState(() {
      _comments = _comments?.map((c) {
        if (c.id == comment.id) return c.copyWithReactions(next);
        return c;
      }).toList();
    });
    try {
      final fromServer = await _postService.toggleCommentReaction(
        postId: widget.post.id,
        commentId: comment.id,
        emoji: emoji,
      );
      if (!mounted) return;
      setState(() {
        _comments = _comments?.map((c) {
          if (c.id == comment.id) return c.copyWithReactions(fromServer);
          return c;
        }).toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _comments = _comments?.map((c) {
          if (c.id == comment.id) return c.copyWithReactions(originalReactions);
          return c;
        }).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить реакцию: $e')),
      );
    }
  }

  /// Same shape as the post-card optimistic toggle. Kept here as a
  /// local copy because pulling it into a shared util would mean
  /// teaching the util about the (currentUserId) parameter, and the
  /// Comment / Post call-sites differ enough that the small dupe is
  /// cheaper than the abstraction.
  List<ReactionSummary> _applyOptimisticReaction(
    List<ReactionSummary> input,
    String emoji,
    String userId,
  ) {
    final next = List<ReactionSummary>.from(input);
    final existingIndex = next.indexWhere((r) => r.emoji == emoji);
    if (existingIndex == -1) {
      next.add(ReactionSummary(
        emoji: emoji,
        userIds: <String>[userId],
        count: 1,
      ));
      return next;
    }
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
    return next;
  }

  /// Avatar fallback chain for a comment author:
  /// 1. comment.authorPhotoUrl (server-provided)
  /// 2. authService.currentUserPhotoUrl if comment.authorId == self —
  ///    the backend sometimes omits the photo on freshly-created
  ///    comments, this catches "your own avatar isn't pulling from
  ///    your profile" which the user reported.
  /// 3. First letter of authorName in a tinted circle (more
  ///    identifiable than a generic person icon).
  Widget _buildAuthorAvatar(Comment comment) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    String? photoUrl = (comment.authorPhotoUrl ?? '').trim().isEmpty
        ? null
        : comment.authorPhotoUrl;
    if (photoUrl == null && comment.authorId == _authService.currentUserId) {
      final selfPhoto = _authService.currentUserPhotoUrl?.trim();
      if (selfPhoto != null && selfPhoto.isNotEmpty) {
        photoUrl = selfPhoto;
      }
    }

    if (photoUrl != null) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: tokens.accentSoft,
        backgroundImage: CachedNetworkImageProvider(photoUrl),
        // Reuse the initial fallback if the network image fails to
        // resolve — onBackgroundImageError fires on 404 / TLS errors.
        onBackgroundImageError: (_, __) {},
        child: const SizedBox.shrink(),
      );
    }

    return CircleAvatar(
      radius: 18,
      backgroundColor: tokens.accentSoft,
      child: Text(
        _initialFor(comment.authorName ?? ''),
        style: TextStyle(
          color: tokens.accent,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _initialFor(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  Widget _buildInputArea() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              decoration: InputDecoration(
                hintText: 'Оставьте комментарий...',
                hintStyle: TextStyle(color: Colors.grey.shade500),
                fillColor: theme.colorScheme.surfaceContainerHighest,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          const SizedBox(width: 8),
          _isSending
              ? const SizedBox(
                  width: 48,
                  height: 48,
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  onPressed: _addComment,
                  icon: Icon(
                    Icons.send,
                    color: theme.colorScheme.primary,
                  ),
                ),
        ],
      ),
    );
  }
}
