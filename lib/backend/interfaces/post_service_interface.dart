import 'package:image_picker/image_picker.dart';
import '../../models/post.dart';
import '../../models/comment.dart';
import '../../models/reaction_summary.dart';

abstract class PostServiceInterface {
  /// Fetch posts for a specific tree, author, or globally.
  /// [onlyBranches] if true, fetches only posts scoped to specific branches.
  Future<List<Post>> getPosts(
      {String? treeId, String? authorId, bool onlyBranches = false});

  /// Create a new family post.
  /// [images] optional attachments for the post.
  Future<Post> createPost({
    required String treeId,
    required String content,
    List<XFile> images = const [],
    bool isPublic = false,
    TreeContentScopeType scopeType = TreeContentScopeType.wholeTree,
    List<String> anchorPersonIds = const [],
    String? circleId,
  });

  /// Delete a post by ID.
  Future<void> deletePost(String postId);

  /// Toggle like status for a post and return the server-truth snapshot.
  Future<Post> toggleLike(String postId);

  /// Substring search across post content + author name. Returns
  /// posts the current user can see, ordered newest-first. Default
  /// impl returns empty so older adapters compile without a search
  /// backend.
  Future<List<Post>> searchPosts({
    required String query,
    String? treeId,
    int limit = 50,
  }) async {
    return const <Post>[];
  }

  /// Toggle the current user's emoji reaction on a post. Mirrors the
  /// chat-side `toggleMessageReaction` shape so frontend code can
  /// share the picker UI. Returns the updated reaction summaries
  /// straight from the server (so optimistic clients can reconcile).
  Future<List<ReactionSummary>> togglePostReaction({
    required String postId,
    required String emoji,
  }) {
    throw UnsupportedError('togglePostReaction is not supported');
  }

  /// Toggle the current user's emoji reaction on a comment. Same
  /// shape as [togglePostReaction] but scoped to a comment instead.
  Future<List<ReactionSummary>> toggleCommentReaction({
    required String postId,
    required String commentId,
    required String emoji,
  }) {
    throw UnsupportedError('toggleCommentReaction is not supported');
  }

  /// Fetch comments for a specific post.
  Future<List<Comment>> getComments(String postId);

  /// Add a comment to a post.
  Future<Comment> addComment(String postId, String content);

  /// Delete a comment.
  Future<void> deleteComment(String postId, String commentId);
}
