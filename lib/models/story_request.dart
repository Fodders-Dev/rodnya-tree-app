// «Спросить историю» MVP-1 (STORY-REQUEST-MVP1-BRIEF.md §1): DTOs for
// the `storyRequests` collection. Mirrors backend contract 1:1 — see
// docs/connected-trees-refactor/STORY-REQUEST-MVP1-BRIEF.md §1 for the
// route table, error codes and notification payloads this parses.
//
// A request is the addressee's one-shot licence to write into someone
// else's article: the INITIATOR must hold person-edit rights at create
// time (checked server-side), the ADDRESSEE answers without ever needing
// edit rights of their own — the request itself is the grant. See
// answerStoryRequest on CustomApiFamilyTreeService for the client half
// of that invariant.

import '../backend/models/user_facing_exception.dart';

class StoryRequest {
  const StoryRequest({
    required this.id,
    required this.treeId,
    required this.personId,
    required this.requesterUserId,
    required this.targetUserId,
    required this.question,
    required this.status,
    this.answer,
    required this.createdAt,
    this.updatedAt,
    required this.expiresAt,
    this.respondedAt,
    this.person,
    this.requester,
    this.target,
  });

  final String id;
  final String treeId;

  /// Герой статьи — не обязательно совпадает с адресатом («расскажи о
  /// своём детстве» — совпадает; «как познакомились бабушка и дедушка»,
  /// адресат дедушка — не совпадает).
  final String personId;
  final String requesterUserId;
  final String targetUserId;
  final StoryRequestQuestion question;
  final StoryRequestStatus status;

  /// `null`, пока запрос не отвечен (pending/declined/expired/revoked
  /// никогда не несут answer).
  final StoryRequestAnswer? answer;
  final String createdAt;
  final String? updatedAt;

  /// 30 дней от createdAt (§0.2) — MVP1-BRIEF §0: у пожилых родных нужен
  /// запас, поэтому дольше, чем у kinship-check (14 дней).
  final String expiresAt;
  final String? respondedAt;

  /// Вложения из `GET /v1/me/story-requests` и `GET /v1/story-requests/:id`
  /// (контракт §1: `person:{id,name,photoUrl}`, `requester`/`target`:
  /// `{id,displayName,photoUrl}`). `null`, когда backend их не прислал
  /// (например, ответ на create возвращает голый request).
  final StoryRequestPersonSummary? person;
  final StoryRequestPersonSummary? requester;
  final StoryRequestPersonSummary? target;

  bool get isPending => status == StoryRequestStatus.pending;

  factory StoryRequest.fromJson(Map<String, dynamic> json) {
    final questionRaw = json['question'];
    final answerRaw = json['answer'];
    return StoryRequest(
      id: (json['id'] ?? '').toString(),
      treeId: (json['treeId'] ?? '').toString(),
      personId: (json['personId'] ?? '').toString(),
      requesterUserId: (json['requesterUserId'] ?? '').toString(),
      targetUserId: (json['targetUserId'] ?? '').toString(),
      question: questionRaw is Map
          ? StoryRequestQuestion.fromJson(
              Map<String, dynamic>.from(questionRaw),
            )
          : const StoryRequestQuestion(text: ''),
      status: StoryRequestStatus.fromServerValue(json['status']),
      answer: answerRaw is Map
          ? StoryRequestAnswer.fromJson(Map<String, dynamic>.from(answerRaw))
          : null,
      createdAt: (json['createdAt'] ?? '').toString(),
      updatedAt: _nullableString(json['updatedAt']),
      expiresAt: (json['expiresAt'] ?? '').toString(),
      respondedAt: _nullableString(json['respondedAt']),
      person: _personFrom(json['person']),
      requester: _personFrom(json['requester']),
      target: _personFrom(json['target']),
    );
  }

  static StoryRequestPersonSummary? _personFrom(Object? raw) {
    if (raw is Map) {
      return StoryRequestPersonSummary.fromJson(
        Map<String, dynamic>.from(raw),
      );
    }
    return null;
  }
}

class StoryRequestQuestion {
  const StoryRequestQuestion({
    required this.text,
    this.themeKey,
    this.sourceQuestionId,
  });

  final String text;
  final String? themeKey;

  /// id вопроса из `family_story_questions` (`FamilyStoryQuestion.id`) —
  /// когда вопрос выбран из готового банка, а не написан свой.
  final String? sourceQuestionId;

  factory StoryRequestQuestion.fromJson(Map<String, dynamic> json) {
    return StoryRequestQuestion(
      text: (json['text'] ?? '').toString(),
      themeKey: _nullableString(json['themeKey']),
      sourceQuestionId: _nullableString(json['sourceQuestionId']),
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        if (themeKey != null) 'themeKey': themeKey,
        if (sourceQuestionId != null) 'sourceQuestionId': sourceQuestionId,
      };
}

enum StoryRequestStatus {
  pending,
  answered,
  declined,
  expired,
  revoked,
  unknown;

  String get serverValue {
    switch (this) {
      case StoryRequestStatus.pending:
        return 'pending';
      case StoryRequestStatus.answered:
        return 'answered';
      case StoryRequestStatus.declined:
        return 'declined';
      case StoryRequestStatus.expired:
        return 'expired';
      case StoryRequestStatus.revoked:
        return 'revoked';
      case StoryRequestStatus.unknown:
        return 'unknown';
    }
  }

  static StoryRequestStatus fromServerValue(Object? raw) {
    switch (raw?.toString()) {
      case 'pending':
        return StoryRequestStatus.pending;
      case 'answered':
        return StoryRequestStatus.answered;
      case 'declined':
        return StoryRequestStatus.declined;
      case 'expired':
        return StoryRequestStatus.expired;
      case 'revoked':
        return StoryRequestStatus.revoked;
      default:
        return StoryRequestStatus.unknown;
    }
  }
}

/// MVP-1 поддерживает только audio|text|photo (§0.4 — video это MVP-2).
/// `unknown` — задел на будущие виды ответа, чтобы старый клиент не падал
/// на новом значении с бэкенда.
enum StoryRequestAnswerKind {
  audio,
  text,
  photo,
  unknown;

  String get serverValue {
    switch (this) {
      case StoryRequestAnswerKind.audio:
        return 'audio';
      case StoryRequestAnswerKind.text:
        return 'text';
      case StoryRequestAnswerKind.photo:
        return 'photo';
      case StoryRequestAnswerKind.unknown:
        return 'unknown';
    }
  }

  static StoryRequestAnswerKind fromServerValue(Object? raw) {
    switch (raw?.toString()) {
      case 'audio':
        return StoryRequestAnswerKind.audio;
      case 'text':
        return StoryRequestAnswerKind.text;
      case 'photo':
        return StoryRequestAnswerKind.photo;
      default:
        return StoryRequestAnswerKind.unknown;
    }
  }
}

class StoryRequestAnswer {
  const StoryRequestAnswer({
    required this.articleBlockId,
    required this.kind,
    this.answeredByUserId,
    required this.answeredAt,
  });

  final String articleBlockId;
  final StoryRequestAnswerKind kind;
  final String? answeredByUserId;
  final String answeredAt;

  factory StoryRequestAnswer.fromJson(Map<String, dynamic> json) {
    return StoryRequestAnswer(
      articleBlockId: (json['articleBlockId'] ?? '').toString(),
      kind: StoryRequestAnswerKind.fromServerValue(json['kind']),
      answeredByUserId: _nullableString(json['answeredByUserId']),
      answeredAt: (json['answeredAt'] ?? '').toString(),
    );
  }
}

/// Lightweight person/requester/target attachment (контракт §1). Одна
/// форма на оба варианта ключа: `person` присылает `name`, `requester`/
/// `target` — `displayName`.
class StoryRequestPersonSummary {
  const StoryRequestPersonSummary({
    required this.id,
    this.displayName,
    this.photoUrl,
  });

  final String id;
  final String? displayName;
  final String? photoUrl;

  factory StoryRequestPersonSummary.fromJson(Map<String, dynamic> json) {
    return StoryRequestPersonSummary(
      id: (json['id'] ?? '').toString(),
      displayName: _nullableString(json['displayName'] ?? json['name']),
      photoUrl: _nullableString(json['photoUrl']),
    );
  }
}

/// Payload для `POST /v1/story-requests/:id/answer` (контракт §1: три
/// формы тела запроса по `kind`). Именованные фабрики вместо Dart 3
/// sealed-иерархии — SDK floor ≥2.17 <4.0 (CLAUDE.md запрещает records/
/// patterns/sealed для этого клиента).
class StoryRequestAnswerInput {
  const StoryRequestAnswerInput._({
    required this.kind,
    this.mediaUrl,
    this.durationSec,
    this.text,
    this.caption,
  });

  factory StoryRequestAnswerInput.audio({
    required String mediaUrl,
    required int durationSec,
  }) {
    return StoryRequestAnswerInput._(
      kind: StoryRequestAnswerKind.audio,
      mediaUrl: mediaUrl,
      durationSec: durationSec,
    );
  }

  factory StoryRequestAnswerInput.text(String text) {
    return StoryRequestAnswerInput._(
      kind: StoryRequestAnswerKind.text,
      text: text,
    );
  }

  factory StoryRequestAnswerInput.photo({
    required String mediaUrl,
    String? caption,
  }) {
    return StoryRequestAnswerInput._(
      kind: StoryRequestAnswerKind.photo,
      mediaUrl: mediaUrl,
      caption: caption,
    );
  }

  final StoryRequestAnswerKind kind;
  final String? mediaUrl;
  final int? durationSec;
  final String? text;
  final String? caption;

  Map<String, dynamic> toJson() {
    switch (kind) {
      case StoryRequestAnswerKind.audio:
        return {
          'kind': 'audio',
          'mediaUrl': mediaUrl,
          'durationSec': durationSec,
        };
      case StoryRequestAnswerKind.text:
        return {'kind': 'text', 'text': text};
      case StoryRequestAnswerKind.photo:
        return {
          'kind': 'photo',
          'mediaUrl': mediaUrl,
          if (caption != null && caption!.trim().isNotEmpty)
            'caption': caption!.trim(),
        };
      case StoryRequestAnswerKind.unknown:
        return {'kind': 'unknown'};
    }
  }
}

/// Error codes mirror backend (story-request-routes.js, contract §1).
/// Implements [UserFacingApiException] — the shared `humanizeError`
/// helper (lib/utils/user_facing_error.dart) already knows how to
/// render this family of exceptions, which is the pattern every other
/// domain exception in the app follows (CustomApiPostException,
/// CustomApiStoryException, …).
///
/// The brief text names `describeUserFacingError` as the intended path,
/// but that helper is wired specifically to auth/login copy (see
/// CustomApiAuthService.describeError — it returns login-flow fallback
/// strings for most status codes, wrong tone here). `humanizeError` is
/// the general-purpose counterpart built for exactly this — documented
/// discrepancy, see MVP-1 client report.
class StoryRequestError implements UserFacingApiException, Exception {
  const StoryRequestError({
    required this.code,
    required this.message,
    this.statusCode,
  });

  /// INVALID_REQUEST (create 400 — covers both SELF_REQUEST_FORBIDDEN and
  /// INVALID_QUESTION, contract doesn't distinguish by status) |
  /// FORBIDDEN | NOT_FOUND (герой либо адресат не найдены/не в дереве —
  /// тоже различаются только текстом `message`, как и у kinship-checks)
  /// | DUPLICATE_PENDING | TOO_MANY_PENDING | NOT_TARGET | NOT_INITIATOR
  /// | NOT_PENDING | INVALID_ANSWER | NETWORK | UNKNOWN.
  final String code;
  @override
  final String message;
  @override
  final int? statusCode;

  @override
  String toString() => 'StoryRequestError($code): $message';
}

String? _nullableString(Object? raw) {
  if (raw == null) return null;
  final s = raw.toString();
  if (s.isEmpty || s == 'null') return null;
  return s;
}
