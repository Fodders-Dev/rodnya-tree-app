// Profile Phase 2 (2026-05-29): article DTOs (frontend mirror of the
// Phase 1 backend entity — store.js profileArticles + profile-article-
// routes.js).
//
// Article = ordered content blocks attached to a person. Block.content
// is an opaque-but-typed Map per block type (paragraph / header / photo
// / gallery / audio / quote / divider). Phase 2a renders + edits
// paragraph + header; other types parse + round-trip untouched so the
// editor never drops blocks it can't yet edit (media lands in 2b).

class ProfileArticle {
  const ProfileArticle({
    this.id,
    required this.personId,
    this.treeId,
    this.semyaId,
    required this.blocks,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String personId;
  final String? treeId;
  final String? semyaId;
  final List<ArticleBlock> blocks;
  final String? createdAt;
  final String? updatedAt;

  factory ProfileArticle.fromJson(Map<String, dynamic> json) {
    final rawBlocks = json['blocks'];
    return ProfileArticle(
      id: _nullableString(json['id']),
      personId: (json['personId'] ?? '').toString(),
      treeId: _nullableString(json['treeId']),
      semyaId: _nullableString(json['semyaId']),
      blocks: rawBlocks is List
          ? rawBlocks
              .whereType<Map>()
              .map((b) => ArticleBlock.fromJson(Map<String, dynamic>.from(b)))
              .toList(growable: false)
          : const <ArticleBlock>[],
      createdAt: _nullableString(json['createdAt']),
      updatedAt: _nullableString(json['updatedAt']),
    );
  }
}

class ArticleBlock {
  const ArticleBlock({
    required this.id,
    required this.type,
    required this.content,
    this.createdByUserId,
    this.authorUserId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// paragraph | header | photo | gallery | audio | quote | divider
  final String type;
  final Map<String, dynamic> content;
  final String? createdByUserId;
  final String? authorUserId;
  final String createdAt;
  final String updatedAt;

  /// Plain text of a paragraph — span texts joined (mention → fallback,
  /// link → text). Phase 2a edits collapse to a single text span; the
  /// structured spans (mentions) are preserved on read for 2b.
  String get plainText {
    final spans = content['spans'];
    if (spans is! List) return '';
    final buf = StringBuffer();
    for (final span in spans) {
      if (span is Map) {
        if (span['type'] == 'mention') {
          buf.write(span['fallbackText']?.toString() ?? '');
        } else {
          buf.write(span['text']?.toString() ?? '');
        }
      } else if (span is String) {
        buf.write(span);
      }
    }
    return buf.toString();
  }

  String get headerText => content['text']?.toString() ?? '';

  int get headerLevel => content['level'] == 1 ? 1 : 2;

  bool get isParagraph => type == 'paragraph';
  bool get isHeader => type == 'header';
  bool get isAudio => type == 'audio';
  bool get isQuote => type == 'quote';
  bool get isDivider => type == 'divider';
  bool get isGallery => type == 'gallery';

  /// Gallery items — each a media-item map ({url, caption?, dateTaken?,
  /// dateTakenAccuracy?}), the same shape as a photo block.
  List<Map<String, dynamic>> get galleryItems {
    final raw = content['items'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);
  }

  /// Quote text — the words being quoted.
  String get quoteText => content['text']?.toString() ?? '';

  /// Quote attribution («— кто сказал»), null if absent / empty.
  String? get quoteAttribution {
    final raw = content['attribution'];
    if (raw == null) return null;
    final s = raw.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Audio block url (the saved voice recording), null if absent.
  String? get audioUrl {
    final raw = content['url'];
    return raw is String && raw.isNotEmpty ? raw : null;
  }

  /// Audio block duration in seconds, null if unknown.
  int? get audioDurationSec {
    final raw = content['durationSec'];
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    return null;
  }

  ArticleBlock copyWith({
    Map<String, dynamic>? content,
    String? authorUserId,
    String? updatedAt,
  }) {
    return ArticleBlock(
      id: id,
      type: type,
      content: content ?? this.content,
      createdByUserId: createdByUserId,
      authorUserId: authorUserId ?? this.authorUserId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory ArticleBlock.fromJson(Map<String, dynamic> json) {
    return ArticleBlock(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      content: json['content'] is Map
          ? Map<String, dynamic>.from(json['content'] as Map)
          : const <String, dynamic>{},
      createdByUserId: _nullableString(json['createdByUserId']),
      authorUserId: _nullableString(json['authorUserId']),
      createdAt: (json['createdAt'] ?? '').toString(),
      updatedAt: (json['updatedAt'] ?? '').toString(),
    );
  }

  /// Build paragraph content from plain editor text (2a — single span).
  static Map<String, dynamic> paragraphContent(String text) {
    return {
      'spans': text.isEmpty
          ? const <Map<String, dynamic>>[]
          : [
              {'text': text},
            ],
    };
  }

  /// Build header content.
  static Map<String, dynamic> headerContent(String text, {int level = 2}) {
    return {'text': text, 'level': level == 1 ? 1 : 2};
  }

  /// Build audio block content — the saved voice recording (artifact).
  /// transcript stays null (record-only, no STT — that's the separate
  /// dictate path). Shape mirrors backend normalizeArticleBlockContent
  /// case "audio": {url required, durationSec rounded positive int | null,
  /// transcript string | null}.
  static Map<String, dynamic> audioContent({
    required String url,
    int? durationSec,
    String? transcript,
  }) {
    return {
      'url': url,
      'durationSec':
          (durationSec != null && durationSec > 0) ? durationSec.round() : null,
      'transcript': transcript,
    };
  }

  /// Build quote content. Shape mirrors backend
  /// normalizeArticleBlockContent case "quote": {text trimmed, attribution
  /// string | null (empty → null)}.
  static Map<String, dynamic> quoteContent({
    required String text,
    String? attribution,
  }) {
    final attr = attribution?.trim();
    return {
      'text': text.trim(),
      'attribution': (attr == null || attr.isEmpty) ? null : attr,
    };
  }

  /// Build divider content — empty, mirrors backend case "divider": {}.
  static Map<String, dynamic> dividerContent() => <String, dynamic>{};

  /// Build gallery content. Shape mirrors backend case "gallery":
  /// {items: [<media item>, …]} (server enforces ≥1). Each item is the
  /// same media-item shape as a photo block (url + optional caption /
  /// dateTaken); v1 stores just the url.
  static Map<String, dynamic> galleryContent({
    required List<Map<String, dynamic>> items,
  }) {
    return {'items': items};
  }
}

/// Result of a block update — carries the multi-author conflict flag
/// the backend returns (last-write-wins applied; prior author notified).
class ArticleBlockUpdateResult {
  const ArticleBlockUpdateResult({required this.block, required this.conflict});

  final ArticleBlock block;
  final bool conflict;
}

String? _nullableString(Object? raw) {
  if (raw == null) return null;
  final s = raw.toString();
  if (s.isEmpty || s == 'null') return null;
  return s;
}
