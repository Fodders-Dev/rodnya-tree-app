import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/post_service_interface.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../models/reaction_summary.dart';
import '../theme/app_theme.dart';
import 'empty_state_widget.dart';
import 'loading_indicator.dart';
import 'reaction_chip_strip.dart';
import 'reaction_picker.dart';
import 'rodnya_avatar.dart';

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

  /// When set, the next send goes out as a reply under this top-level
  /// comment. Cleared after a successful send or by tapping the X in the
  /// "Отвечаем X" banner above the input.
  Comment? _replyingTo;
  final FocusNode _commentFocusNode = FocusNode();

  /// Threads with more than [_repliesPreviewLimit] replies are collapsed
  /// by default — we show the first two and a "Показать ещё N ответов"
  /// pill. Tapping the pill puts the parent comment id into this set
  /// and the full chain expands. Brand-new replies the user just posted
  /// auto-expand their parent thread (handled in [_addComment]).
  static const int _repliesPreviewLimit = 2;
  final Set<String> _expandedThreads = <String>{};

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  /// Walk the loaded comments and build top-level → replies groupings
  /// keeping load order. We look up the top-level parent both by
  /// matching ids in the same list AND by trusting parentCommentId
  /// from the server — the server collapses chains, but if the parent
  /// happens to have been deleted we still want the orphaned reply to
  /// surface as a top-level entry rather than vanish silently.
  List<_CommentGroup> _groupComments(List<Comment> comments) {
    final byId = {for (final c in comments) c.id: c};
    final groups = <_CommentGroup>[];
    final indexById = <String, int>{};
    for (final c in comments) {
      if (!c.isReply) {
        indexById[c.id] = groups.length;
        groups.add(_CommentGroup(parent: c, replies: <Comment>[]));
      }
    }
    for (final c in comments) {
      if (!c.isReply) continue;
      final parentId = c.parentCommentId!;
      final parentIndex = indexById[parentId];
      if (parentIndex != null) {
        groups[parentIndex].replies.add(c);
      } else if (!byId.containsKey(parentId)) {
        // Orphaned reply (parent deleted): promote to top-level so the
        // text isn't lost. The user-facing label still reads "Ответил X"
        // because the metadata is preserved.
        indexById[c.id] = groups.length;
        groups.add(_CommentGroup(parent: c, replies: <Comment>[]));
      }
    }
    return groups;
  }

  void _startReplyTo(Comment comment) {
    setState(() {
      _replyingTo = comment;
    });
    _commentFocusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyingTo = null;
    });
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

    HapticFeedback.lightImpact();
    final replyTarget = _replyingTo;
    setState(() => _isSending = true);

    try {
      final newComment = await _postService.addComment(
        widget.post.id,
        text,
        parentCommentId: replyTarget?.id,
      );
      if (mounted) {
        setState(() {
          _comments?.add(newComment);
          _commentController.clear();
          _replyingTo = null;
          _isSending = false;
          // Auto-expand the thread the user just posted into so their
          // reply doesn't hide behind the collapsed-thread pill.
          final parentId = newComment.parentCommentId;
          if (parentId != null && parentId.isNotEmpty) {
            _expandedThreads.add(parentId);
          }
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
            tooltip: 'Закрыть комментарии',
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
      return EmptyStateWidget(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Пока тишина',
        message: 'Никто ещё не написал. Самое время задать тон —\n'
            'оставьте первый комментарий.',
        actionLabel: null,
        onAction: null,
      );
    }

    final groups = _groupComments(_comments!);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return _buildCommentGroup(group);
      },
    );
  }

  Widget _buildCommentGroup(_CommentGroup group) {
    final isExpanded = _expandedThreads.contains(group.parent.id);
    final allReplies = group.replies;
    final shouldCollapse =
        !isExpanded && allReplies.length > _repliesPreviewLimit;
    final visibleReplies = shouldCollapse
        ? allReplies.take(_repliesPreviewLimit).toList()
        : allReplies;
    final hiddenCount = allReplies.length - visibleReplies.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCommentItem(group.parent, isReply: false),
          if (allReplies.isNotEmpty) ...[
            const SizedBox(height: 12),
            // Indent so a thread visually attaches to its parent
            // without screaming for attention.
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final reply in visibleReplies)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildCommentItem(reply, isReply: true),
                    ),
                  if (hiddenCount > 0)
                    _buildShowMorePill(group.parent.id, hiddenCount),
                  if (isExpanded && allReplies.length > _repliesPreviewLimit)
                    _buildCollapsePill(group.parent.id),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Pill at the bottom of a collapsed thread — "Показать ещё N
  /// ответов". Tap expands the thread permanently for this sheet
  /// session (state is local so a fresh sheet starts collapsed again).
  Widget _buildShowMorePill(String parentId, int hiddenCount) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _expandedThreads.add(parentId);
          });
        },
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.expand_more_rounded,
                size: 16,
                color: tokens.accent,
              ),
              const SizedBox(width: 4),
              Text(
                'Показать ещё ${_pluralizeReplies(hiddenCount)}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: tokens.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Counterpart to the show-more pill: hides expanded replies again.
  /// Only rendered when the thread had more than the preview limit to
  /// begin with — short threads never collapse.
  Widget _buildCollapsePill(String parentId) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _expandedThreads.remove(parentId);
          });
        },
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.expand_less_rounded,
                size: 16,
                color: tokens.inkMuted,
              ),
              const SizedBox(width: 4),
              Text(
                'Свернуть',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: tokens.inkMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "1 ответ" / "2 ответа" / "5 ответов" — Russian plural forms.
  /// Same shape as `_activityEventCountLabel` in notifications_screen.
  String _pluralizeReplies(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    String word;
    if (mod10 == 1 && mod100 != 11) {
      word = 'ответ';
    } else if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      word = 'ответа';
    } else {
      word = 'ответов';
    }
    return '$count $word';
  }

  Widget _buildCommentItem(Comment comment, {required bool isReply}) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return GestureDetector(
      // Long-press → reaction picker. Same gesture pattern as the
      // post card so users build muscle memory across surfaces.
      behavior: HitTestBehavior.translucent,
      onLongPress: () => _openCommentReactionPicker(comment),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAuthorAvatar(comment, isReply: isReply),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.authorName ?? 'Аноним',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
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
                // Inline "Ответить" affordance — shown for any comment
                // (replies anchor to the top-level parent automatically).
                // We hide the button on the comment the user is currently
                // replying to so the "active reply" lives in the input
                // banner instead.
                if (_replyingTo?.id != comment.id) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => _startReplyTo(comment),
                    borderRadius: BorderRadius.circular(8),
                    // Wider hit area (8 horizontal × 6 vertical) so the
                    // inline button satisfies Android's recommended
                    // ~36dp tap-target on a compact comment row.
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Text(
                        'Ответить',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: tokens.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
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
    HapticFeedback.lightImpact();
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

  /// Avatar with the same fallback chain that lived inline before:
  /// 1. comment.authorPhotoUrl
  /// 2. authService.currentUserPhotoUrl when the author is the self
  ///    (backend sometimes omits the photo on freshly-created
  ///    comments — this catches "ава не подсасывается с профиля")
  /// 3. First letter / generic icon (handled inside RodnyaAvatar)
  Widget _buildAuthorAvatar(Comment comment, {bool isReply = false}) {
    String? photoUrl = (comment.authorPhotoUrl ?? '').trim().isEmpty
        ? null
        : comment.authorPhotoUrl;
    if (photoUrl == null && comment.authorId == _authService.currentUserId) {
      final selfPhoto = _authService.currentUserPhotoUrl?.trim();
      if (selfPhoto != null && selfPhoto.isNotEmpty) {
        photoUrl = selfPhoto;
      }
    }
    return RodnyaAvatar(
      photoUrl: photoUrl,
      name: comment.authorName,
      // Slightly smaller avatars for replies — visual rhythm reinforces
      // the indent / thread relationship without an explicit guide line.
      size: isReply ? 28 : 36,
    );
  }

  Widget _buildInputArea() {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_replyingTo != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                color: tokens.accentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.reply, size: 16, color: tokens.accentStrong),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Отвечаем ',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: tokens.inkSecondary,
                            ),
                          ),
                          TextSpan(
                            text: _replyingTo!.authorName ?? 'Аноним',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: tokens.ink,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Отменить ответ',
                    child: InkWell(
                      key: const ValueKey('comment-reply-cancel'),
                      onTap: _cancelReply,
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: tokens.inkMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  focusNode: _commentFocusNode,
                  decoration: InputDecoration(
                    hintText: _replyingTo != null
                        ? 'Ваш ответ…'
                        : 'Оставьте комментарий...',
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
                      tooltip: 'Отправить комментарий',
                      onPressed: _addComment,
                      icon: Icon(
                        Icons.send,
                        color: theme.colorScheme.primary,
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One top-level comment plus its replies, in load order. Used only
/// internally by [_CommentSheetState] to render threaded groups.
class _CommentGroup {
  _CommentGroup({required this.parent, required this.replies});
  final Comment parent;
  final List<Comment> replies;
}
