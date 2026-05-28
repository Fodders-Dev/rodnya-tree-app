// Profile Phase 2 (2026-05-29): article service seam.
//
// Editor depends on this interface (test seam) — production resolves
// CustomApiProfileArticleService via GetIt. Mirrors the Phase 1 backend
// per-block API (POST append / PATCH edit / DELETE / PUT order).

import '../models/profile_article.dart';

abstract class ProfileArticleServiceInterface {
  Future<ProfileArticle> getArticle(String personId);

  Future<ArticleBlock> appendBlock(
    String personId, {
    required String type,
    required Map<String, dynamic> content,
  });

  Future<ArticleBlockUpdateResult> updateBlock(
    String personId,
    String blockId, {
    required Map<String, dynamic> content,
    String? baseUpdatedAt,
  });

  Future<void> removeBlock(String personId, String blockId);

  Future<ProfileArticle> reorderBlocks(
    String personId,
    List<String> orderedBlockIds,
  );
}

class ProfileArticleException implements Exception {
  const ProfileArticleException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
