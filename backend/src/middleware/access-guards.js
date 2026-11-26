const {deriveSessionPublicId} = require("../store");

function createAccessGuards({
  store,
  config,
  useSemyaModel,
  findFreshCall,
}) {
  function scheduleSessionTouch(res, token, {requestId, userId} = {}) {
    if (typeof store?.touchSession !== "function") {
      return;
    }

    let started = false;
    const runTouch = () => {
      if (started) {
        return;
      }
      started = true;
      void Promise.resolve()
        .then(() => store.touchSession(token))
        .catch((error) => {
          console.warn(
            "[backend] touch session failed",
            JSON.stringify({
              requestId: requestId || null,
              userId: userId || null,
              message: String(error?.message || error || "unknown_error"),
            }),
          );
        });
    };

    res.once("finish", runTouch);
    res.once("close", runTouch);
  }

  async function requirePublicTree(req, res, publicTreeId) {
    const tree = await store.findPublicTreeByRouteId(publicTreeId);
    if (!tree) {
      res.status(404).json({message: "Публичное дерево не найдено"});
      return null;
    }
    return tree;
  }

  function readClientInstanceId(req) {
    const raw = req.headers?.["x-client-instance-id"];
    if (Array.isArray(raw)) {
      return String(raw[0] || "").trim();
    }
    return String(raw || "").trim();
  }

  function readDeviceContext(req) {
    const deviceInfoFromBody =
      req?.body && typeof req.body === "object" && req.body.deviceInfo
        ? req.body.deviceInfo
        : {};
    const deviceInfoFromQuery =
      req?.query && typeof req.query === "object" ? req.query : {};

    function pickString(...candidates) {
      for (const candidate of candidates) {
        if (typeof candidate === "string" && candidate.trim()) {
          return candidate.trim();
        }
      }
      return null;
    }

    return {
      // Header takes priority (set by the Flutter HTTP client). For OAuth
      // start endpoints — which are loaded by an in-app browser, not the
      // Flutter HTTP client — fall back to a query param so the start URL
      // can carry the instance id forward into the callback's handoff.
      instanceId:
        readClientInstanceId(req) ||
        pickString(deviceInfoFromQuery.instanceId, deviceInfoFromQuery.instance_id),
      deviceName: pickString(
        deviceInfoFromBody.deviceName,
        deviceInfoFromQuery.deviceName,
        deviceInfoFromQuery.device_name,
      ),
      platform: pickString(
        deviceInfoFromBody.platform,
        deviceInfoFromQuery.platform,
      ),
      // Additive (post multi-device-session shipping): old clients simply
      // don't send it, old stored sessions simply don't have it — both
      // tolerated as null all the way to the sessions-list UI.
      osVersion: pickString(
        deviceInfoFromBody.osVersion,
        deviceInfoFromQuery.osVersion,
        deviceInfoFromQuery.os_version,
      ),
      appVersion: pickString(
        deviceInfoFromBody.appVersion,
        deviceInfoFromQuery.appVersion,
        deviceInfoFromQuery.app_version,
      ),
    };
  }

  async function requireAuth(req, res, next) {
    const header = req.headers.authorization || "";
    const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";

    if (!token) {
      res.status(401).json({message: "Требуется Bearer token"});
      return;
    }

    const session = await store.findSession(token);
    if (!session) {
      res.status(401).json({message: "Сессия не найдена или истекла"});
      return;
    }

    const user = await store.findUserById(session.userId);
    if (!user) {
      res.status(401).json({message: "Пользователь сессии не найден"});
      return;
    }

    req.auth = {
      token,
      session,
      user,
      sessionPublicId: deriveSessionPublicId(
        token,
        readClientInstanceId(req),
      ),
    };
    scheduleSessionTouch(res, token, {
      requestId: req.requestId,
      userId: user.id,
    });
    next();
  }

  function requireOwnUser(req, res) {
    if (req.params.userId !== req.auth.user.id) {
      res.status(403).json({message: "Доступ к чужим данным запрещен"});
      return false;
    }
    return true;
  }


  async function requireTreeAccess(req, res, treeId, {requiredRole = "viewer"} = {}) {
    const tree = await store.findTree(treeId);
    if (!tree) {
      res.status(404).json({message: "Семейное дерево не найдено"});
      return null;
    }

    // Phase B Ship 5: если feature flag ON и tree bound к семья —
    // gate via семья membership. Иначе fallback к legacy
    // (creator + tree.memberIds) для backward compat пока migration
    // не накатилась и frontend клиентов не обновили (Week 8 staged
    // rollout). Без этого dual-path existing endpoints ломаются
    // на pre-Phase-B users чьи trees not yet bound.
    if (useSemyaModel && tree.semyaId) {
      // SPEED-9 B: findMembership не переопределён в PostgresStore —
      // на федеративном (сегодня — прод-default) пути это единственный
      // полный _read() блоба внутри requireTreeAccess (сам tree найден
      // scoped SQL в findTree). Читаем блоб один раз здесь и кладём на
      // req.storeSnapshot — burst-маршруты входа (persons/graph/
      // gatherings/polls/stories) переиспользуют этот снимок вместо
      // собственного _read(). Если снимок уже лежит на req (например,
      // requireTreeAccess вызван дважды за один запрос — так делает
      // link-identity для source+target дерева), читаем блоб только
      // один раз на весь HTTP-запрос. ВАЖНО: это снимок ТОЛЬКО для
      // чтения — обработчик, который после requireTreeAccess мутирует
      // блоб через _mutate, не должен отдавать клиенту данные из этого
      // снимка (см. docs/speed_measurement.md, SPEED-9 B).
      //
      // SPEED-11: readSharedSnapshot() вместо _read() — на PostgresStore
      // попадание в кэш отдаёт общий замороженный снимок без
      // structuredClone ~480 КБ и без SQL сессий (см. docs/speed_measurement.md,
      // SPEED-11). Безопасно ровно потому, что все шесть store-методов
      // ниже по цепочке этого снимка read-only и не трогают db.sessions —
      // это доказано аудитом и тестами SPEED-11, а не предположением.
      const db = req.storeSnapshot || (await store.readSharedSnapshot());
      if (!req.storeSnapshot) {
        req.storeSnapshot = db;
      }
      const membership = await store.findMembership(
        tree.semyaId,
        req.auth.user.id,
        db,
      );
      if (!membership) {
        res.status(403).json({message: "Доступ к дереву запрещён"});
        return null;
      }
      const roleRank = {viewer: 1, editor: 2, owner: 3};
      const actorRank = roleRank[membership.role] ?? 0;
      const requiredRank = roleRank[requiredRole] ?? 1;
      if (actorRank < requiredRank) {
        res.status(403).json({
          message: "Недостаточно прав для этого действия",
          requiredRole,
          actorRole: membership.role,
        });
        return null;
      }
      req.semyaMembership = membership;
      return tree;
    }

    req.semyaMembership = null;
    const memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
    const hasAccess =
      tree.creatorId === req.auth.user.id || memberIds.includes(req.auth.user.id);

    if (!hasAccess) {
      res.status(403).json({message: "Доступ к дереву запрещён"});
      return null;
    }

    return tree;
  }

  // Phase B (ENTITY-DESIGN §2): unified gate для семья endpoints.
  // requiredRole — minimum role chain: viewer < editor < owner.
  // Returns {semya, membership} либо null after sending 403/404.
  //
  // Role hierarchy (per ENTITY-DESIGN §2.1):
  //   viewer  → read семья + tree (no mutations)
  //   editor  → viewer + add/edit persons + invite (if hasInviteGrant)
  //   owner   → editor + rename/delete семья + role transitions
  //
  // Soft-deleted семьи treat как not-found (404), не denied (403).
  async function requireSemyaAccess(req, res, semyaId, {requiredRole = "viewer"} = {}) {
    const semya = await store.findSemyaById(semyaId);
    if (!semya || semya.deletedAt) {
      res.status(404).json({message: "Семья не найдена"});
      return null;
    }
    const membership = await store.findMembership(semyaId, req.auth.user.id);
    if (!membership) {
      res.status(403).json({message: "Доступ к семье запрещён"});
      return null;
    }
    const roleRank = {viewer: 0, editor: 1, owner: 2};
    const actorRank = roleRank[membership.role] ?? -1;
    const requiredRank = roleRank[requiredRole] ?? 0;
    if (actorRank < requiredRank) {
      res.status(403).json({
        message: "Недостаточно прав для этого действия",
        requiredRole,
        actorRole: membership.role,
      });
      return null;
    }
    return {semya, membership};
  }

  // Phase 3.2 (DECISIONS.md 2026-05-10 ответы C/Q1): owner-model
  // gate для mutate-routes на graphPerson canonical / soft-delete /
  // merge. Layered:
  //   1. requireTreeAccess(treeId) — viewer должен быть на дереве
  //      (creator/member). Без этого даже active grant не открывает
  //      route — grants выписываются на graphPerson, но HTTP-shape
  //      требует tree-context.
  //   2. graphPerson lookup. Если null (между migration и первым
  //      sync'ом) — fall through на legacy gate (tree-access уже
  //      пройден); claimed-protection кикnется на следующем read'е.
  //   3. Backward-compat: anonymous (graphPerson.userId === null) —
  //      tree-access достаточен (collaborative editing на «общими
  //      усилиями» dummy slots). Claimed (userId !== null) — только
  //      owner или active grant per scope. Это ровно то поведение,
  //      которое Артём защитил `additive: true` фиксом + ответом
  //      Q1 от 2026-05-10.
  async function requireGraphPersonEdit(req, res, treeId, personId, scope) {
    const normalizedScope = String(scope || "edit").trim();
    const tree = await requireTreeAccess(req, res, treeId, {requiredRole: "viewer"});
    if (!tree) return null;

    const legacyPerson = await store.findPerson(treeId, personId);
    if (!legacyPerson) {
      res.status(404).json({message: "Человек не найден"});
      return null;
    }

    const isViewerOnly = req.semyaMembership?.role === "viewer";

    // SPEED-12: requireTreeAccess выше уже мог положить снимок на
    // req.storeSnapshot (федеративный путь) — переиспользуем его вместо
    // нового readSharedSnapshot()/_read(). Read-only ниже по цепочке.
    const graphPerson = await store.findGraphPersonByLegacy(
      personId,
      req.storeSnapshot,
    );
    if (!graphPerson) {
      if (isViewerOnly && legacyPerson.userId !== req.auth.user.id) {
        res.status(403).json({
          message: "Наблюдатель не может редактировать чужие карточки",
        });
        return null;
      }
      // Edge case — graph mirror ещё не догнал legacy write.
      // Tree-access уже пройден; на anonymous этого достаточно по
      // backward-compat правилу. Возвращаем legacy-only context.
      return {tree, legacyPerson, graphPerson: null};
    }

    const isAnonymous = !graphPerson.userId;
    if (isAnonymous) {
      if (isViewerOnly) {
        res.status(403).json({
          message: "Наблюдатель не может редактировать карточки в дереве",
        });
        return null;
      }
      return {tree, legacyPerson, graphPerson};
    }

    const owner = graphPerson.userId || graphPerson.createdBy || null;
    if (owner === req.auth.user.id) {
      return {tree, legacyPerson, graphPerson};
    }

    // Claimed: только active grant per scope. SPEED-12: тот же снимок
    // (req.storeSnapshot, если requireTreeAccess его уже положил) —
    // read-only проверка гранта, не мутирует.
    const dbForGrants = req.storeSnapshot || (await store.readSharedSnapshot());
    const grants = Array.isArray(dbForGrants.graphPersonEditGrants)
      ? dbForGrants.graphPersonEditGrants
      : [];
    const hasGrant = grants.some(
      (entry) =>
        entry.graphPersonId === graphPerson.id &&
        entry.granteeUserId === req.auth.user.id &&
        entry.scope === normalizedScope &&
        !entry.revokedAt,
    );
    if (hasGrant) {
      return {tree, legacyPerson, graphPerson};
    }

    res.status(403).json({
      message:
        normalizedScope === "soft-delete"
          ? "Только владелец карточки может удалить её"
          : normalizedScope === "merge-consent"
              ? "Объединение требует согласия владельца карточки"
              : "Только владелец карточки может её редактировать",
    });
    return null;
  }

  // Cross-tree READ gate: один graphPerson по id, без tree-context.
  // Используется new graph-person endpoints + future cross-tree
  // chain hydration. Read paths которые list'ят (search,
  // identity-suggestions) не вызывают этот helper напрямую — они
  // фильтруют через `_userCanSeeGraphPerson` в bulk, чтобы скрытый
  // person тихо выпал из результата, а не вернул 403 (последнее
  // leak'ает существование).
  async function requireGraphPersonRead(req, res, graphPersonId) {
    // SPEED-12: один readSharedSnapshot() вместо findGraphPersonById
    // (свой _read()) + отдельного _read() для visibility-гейта ниже —
    // нет treeId-контекста (cross-tree), поэтому req.storeSnapshot
    // здесь взять неоткуда, но снимок один на оба вызова.
    const db = await store.readSharedSnapshot();
    const graphPerson = await store.findGraphPersonById(graphPersonId, db);
    if (!graphPerson || graphPerson.deletedAt) {
      res.status(404).json({message: "Карточка не найдена"});
      return null;
    }
    if (!store._userCanSeeGraphPerson(db, graphPerson, req.auth.user.id)) {
      res.status(403).json({message: "Карточка скрыта приватностью"});
      return null;
    }
    return graphPerson;
  }

  async function requireChatAccess(req, res, chatId) {
    const chat = await store.findChat(chatId);
    if (!chat) {
      res.status(404).json({message: "Чат не найден"});
      return null;
    }

    const participantIds = Array.isArray(chat.participantIds)
      ? chat.participantIds
      : [];
    if (!participantIds.includes(req.auth.user.id)) {
      res.status(403).json({message: "Доступ к чату запрещён"});
      return null;
    }

    return chat;
  }

  async function requireCallAccess(req, res, callId) {
    const call = await findFreshCall(callId, {
      viewerUserId: req.auth.user.id,
    });
    if (!call) {
      res.status(404).json({message: "Звонок не найден"});
      return null;
    }

    if (!(call.participantIds || []).includes(req.auth.user.id)) {
      res.status(403).json({message: "Доступ к звонку запрещён"});
      return null;
    }

    return call;
  }

  // Group late-join access: unlike requireCallAccess (participantIds only), a
  // caller may "залететь" into a live call when they are a member of the call's
  // CHAT even if they weren't pre-invited. Deliberately SCOPED to POST /join +
  // discovery — the strict participantIds gate stays on /reject //cancel
  // //nudge //add //hangup so a non-participant can never act on someone else's
  // call. Chat membership is read from the authoritative chat record, never
  // from client input.
  async function requireCallJoinAccess(req, res, callId) {
    const call = await findFreshCall(callId, {
      viewerUserId: req.auth.user.id,
    });
    if (!call) {
      res.status(404).json({message: "Звонок не найден"});
      return null;
    }
    const userId = req.auth.user.id;
    if ((call.participantIds || []).includes(userId)) {
      return call;
    }
    const chat = await store.findChat(call.chatId);
    const chatMembers = Array.isArray(chat?.participantIds)
      ? chat.participantIds
      : [];
    if (chatMembers.includes(userId)) {
      return call;
    }
    res.status(403).json({message: "Доступ к звонку запрещён"});
    return null;
  }

  function requireAdmin(req, res) {
    const adminEmails = Array.isArray(config.adminEmails) ? config.adminEmails : [];
    const currentEmail = String(req.auth?.user?.email || "").trim().toLowerCase();
    const isAdmin = Boolean(currentEmail) && adminEmails.includes(currentEmail);

    if (!isAdmin) {
      res.status(403).json({message: "Нужны права модератора"});
      return false;
    }

    return true;
  }

  return {
    scheduleSessionTouch,
    requirePublicTree,
    readClientInstanceId,
    readDeviceContext,
    requireAuth,
    requireOwnUser,
    requireTreeAccess,
    requireSemyaAccess,
    requireGraphPersonEdit,
    requireGraphPersonRead,
    requireChatAccess,
    requireCallAccess,
    requireCallJoinAccess,
    requireAdmin,
  };
}

module.exports = {
  createAccessGuards,
};
