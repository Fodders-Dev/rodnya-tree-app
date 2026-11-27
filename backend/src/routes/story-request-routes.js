// «Спросить историю» MVP-1 (STORY-REQUEST-MVP1-BRIEF.md §1/§2). Pattern
// mirrors kinship-checks-routes.js (pending → terminal state machine,
// permission pre-check in routes + store re-validates), but the ask is
// richer: dynamic RU copy embedding the actor's name, and person/
// requester/target attachments on the read endpoints.
//
// State machine: pending → answered | declined | expired (30d, lazy on
// read) | revoked (initiator). Permission: the INITIATOR needs
// requireGraphPersonEdit on the hero person BEFORE the request is ever
// created (checked here); the TARGET does NOT need their own edit grant
// to answer — the pending request itself is the one-time permission slip
// (see store.answerStoryRequest's comment for why).
//
// Notification types (5, §1 table). RU copy is deliberately gender-neutral
// (decision in the brief: no «(а)» forms) — every dynamic-name notification
// below uses a present-tense verb or a passive construction that doesn't
// inflect on the OTHER person's gender.
//   story_request_received  — target gets on create.
//   story_request_answered  — initiator gets on answer.
//   story_request_declined  — initiator gets on decline.
//   story_request_expired   — initiator gets ONCE, on lazy expiry. Fired
//     from whichever endpoint's sweep happens to claim it first (any
//     authenticated user's list/find/mutate call can trigger another
//     user's expiry sweep — see store._sweepExpiredStoryRequests for the
//     atomic one-shot claim that makes this safe under concurrency).
//   story_request_revoked   — target gets on initiator revoke.

const crypto = require("node:crypto");
const {
  composeDisplayName,
  sanitizeUserProfilePreview,
  normalizePublicUrl,
} = require("../profile-utils");
const {
  normalizeStoryAudio,
  transcribeStoryAudio,
} = require("../services/story-audio-service");
const {
  buildPublicStoryUrl,
  MAX_GUEST_STORY_MEDIA_BYTES,
  ALLOWED_AUDIO_MIME_TO_EXT,
  ALLOWED_PHOTO_MIME_TO_EXT,
  readBinaryStreamWithLimit,
} = require("./public-story-routes");

function registerStoryRequestRoutes(
  app,
  {
    store,
    config,
    mediaStorage = null,
    requireAuth,
    requireTreeAccess,
    requireGraphPersonEdit,
    createAndDispatchNotification,
  },
) {
  function truncate(text, max) {
    const value = String(text || "");
    return value.length > max ? `${value.slice(0, max - 1)}…` : value;
  }

  // Mirrors the authorName fallback chain used by gathering/post routes
  // (profile.displayName → composed first/last/middle → email → generic).
  function actorDisplayName(user) {
    return (
      user?.profile?.displayName ||
      composeDisplayName(user?.profile || {}) ||
      user?.email ||
      "Кто-то из родных"
    );
  }

  function mapPersonSummary(person) {
    if (!person) return null;
    return {
      id: person.id,
      name: person.name || null,
      photoUrl: normalizePublicUrl(person.photoUrl || null),
    };
  }

  // Dispatches `story_request_expired` for requests the lazy sweep just
  // transitioned (or previously transitioned but never got to notify —
  // see store._sweepExpiredStoryRequests). These may belong to a DIFFERENT
  // user than req.auth.user — the sweep runs over the whole collection,
  // not just the caller's own rows. A push hiccup here must not fail the
  // caller's own create/list/answer/decline/revoke response.
  async function notifyExpired(newlyExpired) {
    for (const request of newlyExpired || []) {
      try {
        await createAndDispatchNotification({
          userId: request.requesterUserId,
          type: "story_request_expired",
          title: "Вопрос остался без ответа",
          body: request.question?.text || "",
          data: {
            requestId: request.id,
            treeId: request.treeId,
            personId: request.personId,
          },
        });
      } catch (error) {
        console.warn("[story-requests] expired notification failed", error);
      }
    }
  }

  // §1: GET list + GET :id return the request "с теми же вложениями" —
  // person/requester/target summaries. Best-effort per field (a dangling
  // personId from a hard-deleted hero still returns the bare request
  // instead of failing the whole response).
  async function attachViewerContext(request, req = null, viewerUserId = null) {
    const [person, requester, target] = await Promise.all([
      store.findPerson(request.treeId, request.personId).catch(() => null),
      store.findUserById(request.requesterUserId).catch(() => null),
      request.targetUserId
        ? store.findUserById(request.targetUserId).catch(() => null)
        : Promise.resolve(null),
    ]);
    const copy = {...request};
    const isRequester = viewerUserId && copy.requesterUserId === viewerUserId;
    const shareUrl =
      isRequester && copy.shareToken
        ? buildPublicStoryUrl(req, config, copy.shareToken)
        : null;
    delete copy.shareToken;
    delete copy.guestUploads;
    return {
      ...copy,
      ...(shareUrl ? {shareUrl} : {}),
      person: mapPersonSummary(person),
      requester: requester ? sanitizeUserProfilePreview(requester) : null,
      target: target ? sanitizeUserProfilePreview(target) : null,
    };
  }

  function sanitizeRequestForRequester(request, req) {
    const copy = {...request};
    const shareUrl = copy.shareToken
      ? buildPublicStoryUrl(req, config, copy.shareToken)
      : null;
    delete copy.shareToken;
    delete copy.guestUploads;
    return shareUrl ? {...copy, shareUrl} : copy;
  }

  // POST /v1/story-requests — initiator creates a pending request (in_app or public_link).
  app.post("/v1/story-requests", requireAuth, async (req, res) => {
    const treeId = String(req.body?.treeId || "").trim();
    const personId = String(req.body?.personId || "").trim();
    const deliveryMode =
      String(req.body?.deliveryMode || "in_app").trim() === "public_link"
        ? "public_link"
        : "in_app";
    const targetUserId = String(req.body?.targetUserId || "").trim();
    const targetName = String(req.body?.targetName || "").trim() || null;
    const questionText = String(req.body?.question?.text || "").trim();

    if (!treeId || !personId || (deliveryMode === "in_app" && !targetUserId)) {
      res.status(400).json({
        message:
          deliveryMode === "public_link"
            ? "Нужны treeId и personId"
            : "Нужны treeId, personId и targetUserId",
      });
      return;
    }
    if (deliveryMode === "in_app" && targetUserId === req.auth.user.id) {
      res.status(400).json({message: "Нельзя спросить историю у самого себя"});
      return;
    }
    if (questionText.length < 3 || questionText.length > 500) {
      res.status(400).json({message: "Вопрос должен быть от 3 до 500 символов"});
      return;
    }

    const tree = await requireTreeAccess(req, res, treeId, {
      requiredRole: "viewer",
    });
    if (!tree) return;

    const person = await store.findPerson(
      tree.id,
      personId,
      req.storeSnapshot || null,
    );
    if (!person) {
      res.status(404).json({message: "Человек не найден"});
      return;
    }
    const isTargetOwnerAboutSelf =
      deliveryMode === "in_app" &&
      Boolean(person.userId) &&
      person.userId === targetUserId;
    if (!isTargetOwnerAboutSelf) {
      // Asking a third person or creating a guest share link requires edit rights on that person.
      const gate = await requireGraphPersonEdit(req, res, treeId, personId, "edit");
      if (!gate) return;
    }

    const outcome = await store.createStoryRequest({
      treeId,
      personId,
      requesterUserId: req.auth.user.id,
      targetUserId: deliveryMode === "in_app" ? targetUserId : null,
      targetName,
      deliveryMode,
      question: {
        text: questionText,
        themeKey: req.body?.question?.themeKey,
        sourceQuestionId: req.body?.question?.sourceQuestionId,
      },
    });
    await notifyExpired(outcome.newlyExpired);

    if (outcome.error === "SELF_REQUEST_FORBIDDEN") {
      res.status(400).json({message: "Нельзя спросить историю у самого себя"});
      return;
    }
    if (outcome.error === "INVALID_QUESTION") {
      res.status(400).json({message: "Вопрос должен быть от 3 до 500 символов"});
      return;
    }
    if (outcome.error === "PERSON_NOT_FOUND") {
      res.status(404).json({message: "Человек не найден"});
      return;
    }
    if (outcome.error === "TARGET_NOT_IN_TREE") {
      res.status(404).json({message: "Этот человек не участник вашего дерева"});
      return;
    }
    if (outcome.error === "DUPLICATE_PENDING") {
      res.status(409).json({message: "Такой вопрос уже ждёт ответа"});
      return;
    }
    if (outcome.error === "TOO_MANY_PENDING") {
      res.status(429).json({
        message: "Слишком много открытых вопросов — дождитесь ответов на прежние",
      });
      return;
    }
    if (outcome.error) {
      res.status(500).json({message: "Не удалось создать запрос"});
      return;
    }

    if (deliveryMode === "in_app") {
      const requesterName = actorDisplayName(req.auth.user);
      await createAndDispatchNotification({
        userId: targetUserId,
        type: "story_request_received",
        title: `${requesterName} хочет узнать историю`,
        body: outcome.request.question.text,
        data: {
          requestId: outcome.request.id,
          treeId: outcome.request.treeId,
          personId: outcome.request.personId,
        },
      });
    }

    res.status(201).json({
      request: sanitizeRequestForRequester(outcome.request, req),
    });
  });

  // GET /v1/me/story-requests?role=received|issued&status= — lists with
  // lazy expiry sweep + person/requester/target attachments.
  app.get("/v1/me/story-requests", requireAuth, async (req, res) => {
    const role = String(req.query.role || "").trim();
    if (role !== "received" && role !== "issued") {
      res.status(400).json({message: "role должен быть 'received' либо 'issued'"});
      return;
    }
    const status = req.query.status ? String(req.query.status) : null;

    const outcome = await store.listStoryRequestsForUser({
      userId: req.auth.user.id,
      role,
      status,
    });
    await notifyExpired(outcome.newlyExpired);

    const requests = await Promise.all(
      outcome.requests.map((r) => attachViewerContext(r, req, req.auth.user.id)),
    );
    res.json({requests});
  });

  // GET /v1/story-requests/:id — visible only to requester or target;
  // both "not found" and "found but not yours" answer identically (404) so
  // a third tree member can't probe for a request's existence.
  app.get("/v1/story-requests/:id", requireAuth, async (req, res) => {
    const outcome = await store.findStoryRequest({
      requestId: req.params.id,
      viewerUserId: req.auth.user.id,
    });
    await notifyExpired(outcome.newlyExpired);

    if (!outcome.request) {
      res.status(404).json({message: "Запрос не найден"});
      return;
    }
    res.json({
      request: await attachViewerContext(outcome.request, req, req.auth.user.id),
    });
  });

  // PATCH /v1/story-requests/:id — initiator updates questionText/targetName
  // while pending.
  app.patch("/v1/story-requests/:id", requireAuth, async (req, res) => {
    const questionText =
      req.body?.questionText !== undefined
        ? req.body.questionText
        : req.body?.question?.text;
    const outcome = await store.updateStoryRequest({
      requestId: req.params.id,
      actorUserId: req.auth.user.id,
      questionText,
      targetName: req.body?.targetName,
    });
    await notifyExpired(outcome.newlyExpired);

    if (outcome.error === "NOT_FOUND") {
      res.status(404).json({message: "Запрос не найден"});
      return;
    }
    if (outcome.error === "NOT_INITIATOR") {
      res.status(403).json({message: "Редактировать можно только свой запрос"});
      return;
    }
    if (outcome.error === "NOT_PENDING") {
      res.status(409).json({
        message: "Нельзя изменить запрос после ответа или отзыва",
      });
      return;
    }
    if (outcome.error === "DUPLICATE_PENDING") {
      res.status(409).json({
        message: "Такой открытый вопрос уже есть",
      });
      return;
    }
    if (outcome.error === "INVALID_QUESTION" || outcome.error === "INVALID_INPUT") {
      res.status(400).json({message: "Вопрос должен содержать от 3 до 500 символов"});
      return;
    }
    if (outcome.error) {
      res.status(500).json({message: "Не удалось обновить вопрос"});
      return;
    }

    res.json({
      request: await attachViewerContext(
        sanitizeRequestForRequester(outcome.request, req),
        req,
        req.auth.user.id,
      ),
    });
  });

  // PUT /v1/story-requests/:id/media?kind=audio|photo — authenticated target
  // uploads answer media with ffmpeg normalization + STT transcription parity
  // alongside guest /story/:token/media.
  app.put("/v1/story-requests/:id/media", requireAuth, async (req, res) => {
    if (!mediaStorage) {
      res.status(503).json({message: "Загрузка медиа недоступна"});
      return;
    }
    const kind = String(req.query?.kind || "").trim().toLowerCase();
    if (kind !== "audio" && kind !== "photo") {
      res.status(400).json({message: "kind должен быть 'audio' или 'photo'"});
      return;
    }

    const lookup = await store.findStoryRequest({
      requestId: req.params.id,
      viewerUserId: req.auth.user.id,
    });
    await notifyExpired(lookup.newlyExpired);
    if (!lookup.request) {
      res.status(404).json({message: "Запрос не найден"});
      return;
    }
    if (lookup.request.targetUserId !== req.auth.user.id) {
      res.status(403).json({message: "Отвечать может только адресат вопроса"});
      return;
    }
    if (lookup.request.status !== "pending") {
      res.status(409).json({message: "На этот вопрос уже ответили или его отозвали"});
      return;
    }

    const rawContentType = String(req.headers["content-type"] || "")
      .split(";")[0]
      .trim()
      .toLowerCase();
    const allowMap =
      kind === "audio" ? ALLOWED_AUDIO_MIME_TO_EXT : ALLOWED_PHOTO_MIME_TO_EXT;
    const ext = allowMap.get(rawContentType);
    if (!ext) {
      res.status(400).json({message: "Неподдерживаемый формат файла"});
      return;
    }

    const readResult = await readBinaryStreamWithLimit(
      req,
      res,
      MAX_GUEST_STORY_MEDIA_BYTES,
    );
    if (readResult.tooLarge) {
      res.status(413).json({message: "Файл не должен превышать 20 МБ"});
      return;
    }
    const rawBuffer = readResult.buffer;
    if (!rawBuffer || rawBuffer.length === 0) {
      res.status(400).json({message: "Файл пустой"});
      return;
    }

    let finalBuffer = rawBuffer;
    let finalContentType = rawContentType;
    let finalExt = ext;
    if (kind === "audio") {
      const normalized = await normalizeStoryAudio({
        buffer: rawBuffer,
        contentType: rawContentType,
        originalExt: ext,
      });
      finalBuffer = normalized.buffer;
      finalContentType = normalized.contentType;
      finalExt = normalized.ext;
    }

    const relativePath = `${lookup.request.id}/${crypto.randomUUID()}.${finalExt}`;
    const saved = await mediaStorage.saveObject({
      req,
      bucket: "story-answers",
      relativePath,
      contentType: finalContentType,
      fileBuffer: finalBuffer,
      uploaderUserId: req.auth.user.id,
    });

    let transcript = null;
    if (kind === "audio" && config?.sttEnabled) {
      transcript = await transcribeStoryAudio({
        buffer: finalBuffer,
        contentType: finalContentType,
        filename: `story.${finalExt}`,
        config,
      });
    }

    res.status(201).json({
      url: saved.url,
      contentType: finalContentType,
      size: saved.size,
      kind,
      transcript,
    });
  });

  // POST /v1/story-requests/:id/answer — target answers with legacy
  // single-kind OR combined v2 ({audio, text, photo}).
  app.post("/v1/story-requests/:id/answer", requireAuth, async (req, res) => {
    const rawKind = String(req.body?.kind || "").trim();
    const hasCombinedPayload =
      (req.body?.audio && typeof req.body.audio === "object") ||
      (req.body?.photo && typeof req.body.photo === "object") ||
      (!rawKind && req.body?.text !== undefined);
    if (!hasCombinedPayload && !["audio", "text", "photo"].includes(rawKind)) {
      res.status(400).json({message: "kind должен быть 'audio', 'text' либо 'photo'"});
      return;
    }

    const mediaUrlRaw =
      req.body?.mediaUrl ?? req.body?.audioUrl ?? req.body?.photoUrl;
    const rawDurationMs = req.body?.audioDurationMs;
    let durationSec = req.body?.durationSec;
    if (rawDurationMs !== undefined && rawDurationMs !== null) {
      const parsedMs = Number(rawDurationMs);
      if (!Number.isFinite(parsedMs) || parsedMs < 0 || parsedMs > 36_000_000) {
        res.status(400).json({message: "Некорректная длительность аудио"});
        return;
      }
      if (durationSec === undefined || durationSec === null) {
        durationSec = Math.round(parsedMs / 1000);
      }
    }

    const outcome = await store.answerStoryRequest({
      requestId: req.params.id,
      actorUserId: req.auth.user.id,
      answer: {
        kind: rawKind || null,
        mediaUrl: mediaUrlRaw,
        durationSec,
        transcript: req.body?.transcript ?? req.body?.audio?.transcript,
        text: req.body?.text,
        caption: req.body?.caption,
        audio: req.body?.audio,
        photo: req.body?.photo,
      },
    });
    await notifyExpired(outcome.newlyExpired);

    if (outcome.error === "NOT_FOUND") {
      res.status(404).json({message: "Запрос не найден"});
      return;
    }
    if (outcome.error === "NOT_TARGET") {
      res.status(403).json({message: "Отвечать может только тот, кому задали вопрос"});
      return;
    }
    if (
      outcome.error === "FORBIDDEN_BLOCKED" ||
      outcome.error === "FORBIDDEN_NOT_MEMBER"
    ) {
      res.status(403).json({message: "Доступ к этому запросу больше недоступен"});
      return;
    }
    if (outcome.error === "NOT_PENDING") {
      res.status(409).json({message: "На этот вопрос уже ответили или его отозвали"});
      return;
    }
    if (outcome.error === "INVALID_ANSWER" || outcome.error === "INVALID_INPUT") {
      res.status(400).json({message: "Некорректный ответ"});
      return;
    }
    if (outcome.error) {
      res.status(500).json({message: "Не удалось сохранить ответ"});
      return;
    }

    const responderName = actorDisplayName(req.auth.user);
    await createAndDispatchNotification({
      userId: outcome.request.requesterUserId,
      type: "story_request_answered",
      // Без рода и без склонения имени: настоящее время «делится» не
      // зависит ни от пола адресата, ни от падежа (имя — в именительном).
      title: `${responderName} делится историей`,
      body: truncate(outcome.request.question.text, 80),
      data: {
        requestId: outcome.request.id,
        treeId: outcome.request.treeId,
        personId: outcome.request.personId,
        articleBlockId: outcome.block.id,
      },
    });

    res.json({
      request: outcome.request,
      block: outcome.block,
      blocks: outcome.blocks || [outcome.block],
    });
  });

  // POST /v1/story-requests/:id/decline — target declines.
  app.post("/v1/story-requests/:id/decline", requireAuth, async (req, res) => {
    const outcome = await store.declineStoryRequest({
      requestId: req.params.id,
      actorUserId: req.auth.user.id,
    });
    await notifyExpired(outcome.newlyExpired);

    if (outcome.error === "NOT_FOUND") {
      res.status(404).json({message: "Запрос не найден"});
      return;
    }
    if (outcome.error === "NOT_TARGET") {
      res.status(403).json({message: "Отклонить может только тот, кому задали вопрос"});
      return;
    }
    if (outcome.error === "NOT_PENDING") {
      res.status(409).json({message: "Этот запрос уже обработан"});
      return;
    }
    if (outcome.error) {
      res.status(500).json({message: "Не удалось отклонить запрос"});
      return;
    }

    const targetName = actorDisplayName(req.auth.user);
    await createAndDispatchNotification({
      userId: outcome.request.requesterUserId,
      type: "story_request_declined",
      // Gender-neutral (§1 decision) — "может" doesn't inflect by gender.
      title: `${targetName} пока не может ответить`,
      body: outcome.request.question.text,
      data: {
        requestId: outcome.request.id,
        treeId: outcome.request.treeId,
        personId: outcome.request.personId,
      },
    });

    res.json({request: outcome.request});
  });

  // POST /v1/story-requests/:id/revoke — initiator revokes own pending
  // request.
  app.post("/v1/story-requests/:id/revoke", requireAuth, async (req, res) => {
    const outcome = await store.revokeStoryRequest({
      requestId: req.params.id,
      actorUserId: req.auth.user.id,
    });
    await notifyExpired(outcome.newlyExpired);

    if (outcome.error === "NOT_FOUND") {
      res.status(404).json({message: "Запрос не найден"});
      return;
    }
    if (outcome.error === "NOT_INITIATOR") {
      res.status(403).json({message: "Отозвать можно только свой запрос"});
      return;
    }
    if (outcome.error === "NOT_PENDING") {
      res.status(409).json({message: "Этот запрос уже обработан либо отозван"});
      return;
    }
    if (outcome.error) {
      res.status(500).json({message: "Не удалось отозвать запрос"});
      return;
    }

    if (outcome.request.targetUserId) {
      const requesterName = actorDisplayName(req.auth.user);
      await createAndDispatchNotification({
        userId: outcome.request.targetUserId,
        type: "story_request_revoked",
        // Настоящее время «отзывает» — без рода и без склонения имени.
        title: `${requesterName} отзывает свой вопрос`,
        body: outcome.request.question.text,
        data: {requestId: outcome.request.id},
      });
    }

    res.json({request: sanitizeRequestForRequester(outcome.request, req)});
  });
}

module.exports = {registerStoryRequestRoutes};
