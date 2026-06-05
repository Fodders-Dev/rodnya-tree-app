import '../utils/url_utils.dart';
import 'post.dart' show TreeContentScopeType;

/// Phase E: a «Встреча» (Gathering) — a family-event invitation. Mirrors
/// [Post] for the shared audience fields (treeId, branchIds, author*,
/// scopeType, anchorPersonIds, circleId) so the same audience UI applies,
/// plus event-specific fields (title, start/end, all-day, place). RSVP
/// rows are carried opaquely until Phase E3 models them.
class Gathering {
  final String id;
  final String treeId;

  /// Branch ids the gathering is published into. The primary [treeId] is
  /// implicit; older payloads without the field deserialise as `[treeId]`.
  final List<String> branchIds;
  final String authorId;
  final String authorName;
  final String? _authorPhotoUrl;
  final String title;
  final String? description;
  final DateTime startAt;
  final DateTime? endAt;
  final bool isAllDay;
  final String? place;
  final TreeContentScopeType scopeType;
  final List<String> anchorPersonIds;
  final String? circleId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Opaque RSVP rows from the server — modelled in Phase E3. Empty in E1.
  final List<Map<String, dynamic>> rsvps;

  String? get authorPhotoUrl => _authorPhotoUrl;
  String? get renderableAuthorPhotoUrl =>
      UrlUtils.isRenderableNetworkImageUrl(_authorPhotoUrl)
          ? _authorPhotoUrl
          : null;

  // ── RSVP tallies (Phase E3) ──
  // «Going» counts each yes-responder plus the extra people they bring
  // (headcount); maybe / no are responder counts only.
  int get goingCount =>
      _rsvpsWithStatus('yes').fold(0, (sum, r) => sum + 1 + _headcountOf(r));
  int get maybeCount => _rsvpsWithStatus('maybe').length;
  int get notGoingCount => _rsvpsWithStatus('no').length;

  /// The given user's RSVP status ('yes' | 'maybe' | 'no'), or null.
  String? myRsvpStatus(String? userId) {
    if (userId == null || userId.isEmpty) return null;
    for (final r in rsvps) {
      if (r['userId']?.toString() == userId) {
        return r['status']?.toString();
      }
    }
    return null;
  }

  /// The given user's extra-headcount (people besides themselves), or 0.
  int headcountFor(String? userId) {
    if (userId == null || userId.isEmpty) return 0;
    for (final r in rsvps) {
      if (r['userId']?.toString() == userId) return _headcountOf(r);
    }
    return 0;
  }

  Iterable<Map<String, dynamic>> _rsvpsWithStatus(String status) =>
      rsvps.where((r) => r['status']?.toString() == status);

  static int _headcountOf(Map<String, dynamic> r) {
    final raw = r['headcount'];
    final value = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
    return value > 0 ? value : 0;
  }

  /// Copy with a replaced RSVP list — used for optimistic UI updates.
  Gathering copyWith({List<Map<String, dynamic>>? rsvps}) {
    return Gathering(
      id: id,
      treeId: treeId,
      branchIds: branchIds,
      authorId: authorId,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      title: title,
      description: description,
      startAt: startAt,
      endAt: endAt,
      isAllDay: isAllDay,
      place: place,
      scopeType: scopeType,
      anchorPersonIds: anchorPersonIds,
      circleId: circleId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      rsvps: rsvps ?? this.rsvps,
    );
  }

  Gathering({
    required this.id,
    required this.treeId,
    required this.authorId,
    required this.authorName,
    String? authorPhotoUrl,
    required this.title,
    this.description,
    required this.startAt,
    this.endAt,
    this.isAllDay = false,
    this.place,
    this.scopeType = TreeContentScopeType.wholeTree,
    List<String>? anchorPersonIds,
    this.circleId,
    required this.createdAt,
    this.updatedAt,
    List<Map<String, dynamic>>? rsvps,
    List<String>? branchIds,
  })  : _authorPhotoUrl = UrlUtils.normalizeImageUrl(authorPhotoUrl),
        anchorPersonIds = anchorPersonIds ?? [],
        rsvps = rsvps ?? const <Map<String, dynamic>>[],
        branchIds =
            (branchIds == null || branchIds.isEmpty) ? [treeId] : branchIds;

  factory Gathering.fromJson(Map<String, dynamic> json) {
    final rawBranchIds = (json['branchIds'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .where((s) => s.isNotEmpty)
        .toList();
    final rawRsvps = (json['rsvps'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return Gathering(
      id: json['id']?.toString() ?? '',
      treeId: json['treeId']?.toString() ?? '',
      branchIds: rawBranchIds,
      authorId: json['authorId']?.toString() ?? '',
      authorName: json['authorName']?.toString() ?? 'Аноним',
      authorPhotoUrl: json['authorPhotoUrl'] as String?,
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      startAt: _parseDate(json['startAt']) ?? DateTime.now(),
      endAt: _parseDate(json['endAt']),
      isAllDay: json['isAllDay'] == true,
      place: json['place']?.toString(),
      scopeType: _scopeTypeFromString(json['scopeType']?.toString()),
      anchorPersonIds: (json['anchorPersonIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      circleId: json['circleId']?.toString(),
      createdAt: _parseDate(json['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updatedAt']),
      rsvps: rawRsvps,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'treeId': treeId,
      'branchIds': branchIds,
      'authorId': authorId,
      'authorName': authorName,
      'authorPhotoUrl': authorPhotoUrl,
      'title': title,
      'description': description,
      'startAt': startAt.toIso8601String(),
      'endAt': endAt?.toIso8601String(),
      'isAllDay': isAllDay,
      'place': place,
      'scopeType': _scopeTypeToString(scopeType),
      'anchorPersonIds': anchorPersonIds,
      'circleId': circleId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'rsvps': rsvps,
    };
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final raw = value.toString();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static TreeContentScopeType _scopeTypeFromString(String? value) {
    return value == 'branches'
        ? TreeContentScopeType.branches
        : TreeContentScopeType.wholeTree;
  }

  static String _scopeTypeToString(TreeContentScopeType value) {
    return value == TreeContentScopeType.branches ? 'branches' : 'wholeTree';
  }
}
