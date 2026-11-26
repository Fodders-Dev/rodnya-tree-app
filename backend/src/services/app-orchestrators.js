const {normalizeProfileContributionPolicy, sanitizeProfile} = require("../profile-utils");
const {buildBranchVisiblePersonIds} = require("../store");
const {mapNotification, mapPerson} = require("../mappers");

function createAppOrchestrators({store, realtimeHub = null, pushGateway}) {
  const resolvedPushGateway = pushGateway;

  async function resolveSharedTreeIdsForUsers(viewerUserId, targetUserId) {
    const normalizedViewerUserId = String(viewerUserId || "").trim();
    const normalizedTargetUserId = String(targetUserId || "").trim();
    if (!normalizedViewerUserId || !normalizedTargetUserId) {
      return [];
    }
    if (normalizedViewerUserId === normalizedTargetUserId) {
      return [];
    }

    const [viewerTrees, targetTrees] = await Promise.all([
      store.listUserTrees(normalizedViewerUserId),
      store.listUserTrees(normalizedTargetUserId),
    ]);

    const targetTreeIds = new Set(
      (Array.isArray(targetTrees) ? targetTrees : [])
        .map((tree) => String(tree?.id || "").trim())
        .filter(Boolean),
    );

    return (Array.isArray(viewerTrees) ? viewerTrees : [])
      .map((tree) => String(tree?.id || "").trim())
      .filter((treeId) => treeId && targetTreeIds.has(treeId));
  }

  async function buildProfileViewerContext(viewerUserId, targetUserId) {
    const normalizedViewerUserId = String(viewerUserId || "").trim();
    const normalizedTargetUserId = String(targetUserId || "").trim();
    if (!normalizedViewerUserId || !normalizedTargetUserId) {
      return null;
    }
    if (normalizedViewerUserId === normalizedTargetUserId) {
      return {
        viewerUserId: normalizedViewerUserId,
        targetUserId: normalizedTargetUserId,
        sharedTreeIds: [],
        branchRootMatches: [],
      };
    }

    const sharedTreeIds = await resolveSharedTreeIdsForUsers(
      normalizedViewerUserId,
      normalizedTargetUserId,
    );
    const branchRootMatches = new Set();
    for (const treeId of sharedTreeIds) {
      const [persons, relations] = await Promise.all([
        store.listPersons(treeId),
        store.listRelations(treeId),
      ]);
      const viewerPersonIds = (Array.isArray(persons) ? persons : [])
        .filter(
          (person) =>
            String(person?.userId || "").trim() === normalizedViewerUserId,
        )
        .map((person) => String(person?.id || "").trim())
        .filter(Boolean);
      if (viewerPersonIds.length === 0) {
        continue;
      }

      for (const person of Array.isArray(persons) ? persons : []) {
        const rootPersonId = String(person?.id || "").trim();
        if (!rootPersonId) {
          continue;
        }
        const visibleIds = buildBranchVisiblePersonIds(
          persons,
          relations,
          rootPersonId,
        );
        if (viewerPersonIds.some((personId) => visibleIds.has(personId))) {
          branchRootMatches.add(rootPersonId);
        }
      }
    }

    return {
      viewerUserId: normalizedViewerUserId,
      targetUserId: normalizedTargetUserId,
      sharedTreeIds,
      branchRootMatches: Array.from(branchRootMatches),
    };
  }

  async function buildPersonDossierPayload({
    treeId,
    personId,
    viewerUserId,
  }) {
    const dossier = await store.getPersonDossier(treeId, personId);
    if (!dossier) {
      return null;
    }

    const mappedPerson = mapPerson(dossier.person);
    const linkedUserId = String(dossier.person?.userId || "").trim();
    const viewerContext = linkedUserId
      ? await buildProfileViewerContext(viewerUserId, linkedUserId)
      : null;
    const linkedProfile = dossier.linkedProfile
      ? sanitizeProfile(dossier.linkedProfile, viewerContext)
      : null;
    // BUG3 follow-up: экран профиля читает аватар из user-профиля (пустой у
    // только что вошедшего), но фото есть на граф-персоне (поставлено ДО
    // регистрации). Тот же фолбэк, что в чат/звонок-маппинге — read-time
    // safety поверх ретро-бэкфилла (на случай фото, добавленного персоне
    // уже ПОСЛЕ привязки).
    if (linkedProfile && !linkedProfile.photoUrl && mappedPerson.photoUrl) {
      linkedProfile.photoUrl = mappedPerson.photoUrl;
    }
    const contributionPolicy = normalizeProfileContributionPolicy(
      linkedProfile?.profileContributionPolicy,
    );

    let mode = "offline";
    if (mappedPerson.isAlive === false) {
      mode = "memorial";
    } else if (linkedUserId && linkedUserId === viewerUserId) {
      mode = "self";
    } else if (linkedUserId) {
      mode = "linked";
    }

    return {
      person: mappedPerson,
      linkedProfile,
      mode,
      permissions: {
        canEditFamilyFields: true,
        canSuggestOwnerFields:
          Boolean(linkedUserId) &&
          linkedUserId !== viewerUserId &&
          mappedPerson.isAlive !== false &&
          contributionPolicy === "suggestions",
      },
      hiddenSections: linkedProfile?.hiddenProfileSections || [],
    };
  }

  async function createAndDispatchNotification({
    userId,
    type,
    title,
    body,
    data,
    silent = false,
    targetSessionPublicId = null,
    // FIX A2: latency-чувствительные пути (звонки) ставят awaitPush:false —
    // запись уведомления в БД + realtime остаются синхронными (быстро,
    // онлайн-клиент уже звенит через них), а МЕДЛЕННЫЙ HTTP-пуш (VKPNS на
    // мёртвый токен) уходит в фон и не держит ответ обработчика.
    awaitPush = true,
  }) {
    const notification = await store.createNotification({
      userId,
      type,
      title,
      body,
      data,
      silent,
    });

    if (!notification) {
      return null;
    }

    const mappedNotification = mapNotification(notification);
    realtimeHub?.publishToUser(
      userId,
      {
        type: "notification.created",
        notification: mappedNotification,
      },
      {sessionPublicId: targetSessionPublicId},
    );
    const pushDispatch = resolvedPushGateway.dispatchNotification(notification, {
      targetSessionPublicId,
    });
    if (awaitPush) {
      await pushDispatch;
    } else {
      Promise.resolve(pushDispatch).catch((error) =>
        console.error("[push] background dispatch failed", error),
      );
    }

    return mappedNotification;
  }

  return {
    resolveSharedTreeIdsForUsers,
    buildProfileViewerContext,
    buildPersonDossierPayload,
    createAndDispatchNotification,
  };
}

module.exports = {
  createAppOrchestrators,
};
