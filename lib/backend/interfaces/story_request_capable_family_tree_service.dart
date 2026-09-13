import '../../models/story_request.dart';

/// «Спросить историю» MVP-1 (STORY-REQUEST-MVP1-BRIEF.md §1 + §3.2):
/// capability mixin для `/v1/story-requests` endpoints.
///
/// Implementation lives in [CustomApiFamilyTreeService] — mirrors
/// [KinshipCheckCapableFamilyTreeService] 1:1 (same pending → terminal
/// state-machine shape, same "throw on known business error, degrade to
/// null/empty on network failure" contract). Older backends without the
/// route → caps detection `service is StoryRequestCapableFamilyTreeService`
/// returns false → UI hides the «Кого спросить» step and behaves exactly
/// like before this feature existed.
abstract class StoryRequestCapableFamilyTreeService {
  /// `POST /v1/story-requests`. Initiator must already hold person-edit
  /// rights on [personId] (checked server-side via
  /// `requireGraphPersonEdit`) — the request itself is what lets the
  /// addressee write into the article later without that right.
  ///
  /// Throws [StoryRequestError] with code INVALID_REQUEST for both of
  /// these (backend answers both with 400 and no separate machine code,
  /// only a distinguishing `message`):
  ///   - SELF_REQUEST_FORBIDDEN (targetUserId == caller)
  ///   - INVALID_QUESTION (trimmed text outside 3…500 chars)
  ///
  /// Also throws for:
  ///   - FORBIDDEN (caller can't edit [personId])
  ///   - NOT_FOUND (person unknown, or target not a member of this
  ///     tree/семья — contract §1 distinguishes these only by message
  ///     text, not by a separate machine code)
  ///   - DUPLICATE_PENDING (already a pending request for this
  ///     initiator+target+person triple)
  ///   - TOO_MANY_PENDING (>20 open requests issued by the caller)
  Future<StoryRequest?> createStoryRequest({
    required String treeId,
    required String personId,
    required String targetUserId,
    required StoryRequestQuestion question,
  });

  /// `GET /v1/me/story-requests?role=<role>&status=<status?>`.
  /// `role` is `'received'` (caller is the addressee — needs to answer)
  /// or `'issued'` (caller is the initiator — tracking their own asks).
  /// Expired-but-still-pending requests are lazily flipped server-side
  /// on this read, mirroring kinship-checks.
  Future<List<StoryRequest>> listStoryRequests({
    required String role,
    StoryRequestStatus? status,
  });

  /// `GET /v1/story-requests/:id`. Visible only to the initiator or the
  /// addressee — a third viewer gets [StoryRequestError] NOT_FOUND
  /// (contract deliberately doesn't leak existence to non-participants).
  Future<StoryRequest?> getStoryRequest({required String requestId});

  /// `POST /v1/story-requests/:id/answer`. Only the addressee may call
  /// this — and, per DECISIONS.md 2026-09-13, WITHOUT needing person-edit
  /// rights of their own: the pending request is itself the one-shot
  /// permission to write a block into the hero's article. On success the
  /// backend appends an article block carrying `source` (this request's
  /// id + question + asker) and flips status → answered.
  ///
  /// Throws [StoryRequestError] for:
  ///   - NOT_TARGET (caller isn't the addressee)
  ///   - NOT_PENDING (already answered/declined/expired/revoked)
  ///   - INVALID_ANSWER (missing/malformed fields for the given kind)
  Future<StoryRequest?> answerStoryRequest({
    required String requestId,
    required StoryRequestAnswerInput answer,
  });

  /// `POST /v1/story-requests/:id/decline`. Addressee says «не хочу
  /// отвечать» — terminal, initiator gets `story_request_declined`.
  ///
  /// Throws [StoryRequestError] for NOT_TARGET / NOT_PENDING.
  Future<StoryRequest?> declineStoryRequest({required String requestId});

  /// `POST /v1/story-requests/:id/revoke`. Initiator cancels their own
  /// pending ask — terminal, addressee gets `story_request_revoked`.
  ///
  /// Throws [StoryRequestError] for NOT_INITIATOR / NOT_PENDING.
  Future<StoryRequest?> revokeStoryRequest({required String requestId});
}
