function registerRelationRequestRoutes(
  app,
  {
    store,
    requireAuth,
    requireTreeAccess,
    createAndDispatchNotification,
    mapPerson,
    mapRelation,
    mapRelationRequest,
  },
) {
  app.get(
    "/v1/trees/:treeId/relation-requests",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const requests = await store.listRelationRequests({
        treeId: tree.id,
        senderId: req.query.senderId ? String(req.query.senderId) : null,
        recipientId: req.query.recipientId ? String(req.query.recipientId) : null,
        status: req.query.status ? String(req.query.status) : null,
      });

      res.json({
        requests: requests.map(mapRelationRequest),
      });
    },
  );

  app.get("/v1/relation-requests/pending", requireAuth, async (req, res) => {
    const treeId = req.query.treeId ? String(req.query.treeId) : null;
    const direction = String(req.query.direction || "incoming")
      .trim()
      .toLowerCase();
    let requests;
    if (direction === "outgoing") {
      requests = await store.listRelationRequests({
        treeId,
        senderId: req.auth.user.id,
        status: "pending",
      });
    } else if (direction === "all") {
      const [incoming, outgoing] = await Promise.all([
        store.listRelationRequests({
          treeId,
          recipientId: req.auth.user.id,
          status: "pending",
        }),
        store.listRelationRequests({
          treeId,
          senderId: req.auth.user.id,
          status: "pending",
        }),
      ]);
      const byId = new Map();
      for (const item of [...incoming, ...outgoing]) {
        byId.set(item.id, item);
      }
      requests = Array.from(byId.values()).sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      );
    } else {
      requests = await store.listRelationRequests({
        treeId,
        recipientId: req.auth.user.id,
        status: "pending",
      });
    }

    res.json({
      requests: requests.map(mapRelationRequest),
    });
  });

  app.post(
    "/v1/trees/:treeId/relation-requests",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const recipientId = String(req.body?.recipientId || "").trim();
      const senderToRecipient = String(
        req.body?.senderToRecipient || req.body?.relationType || "other",
      ).trim();
      const targetPersonId = String(
        req.body?.targetPersonId || req.body?.offlineRelativeId || "",
      ).trim();
      const message = req.body?.message;

      if (!recipientId) {
        res.status(400).json({message: "Нужен recipientId"});
        return;
      }

      const request = await store.createRelationRequest({
        treeId: tree.id,
        senderId: req.auth.user.id,
        recipientId,
        senderToRecipient,
        targetPersonId: targetPersonId || null,
        message,
      });

      if (request === null) {
        res.status(404).json({message: "Семейное дерево не найдено"});
        return;
      }
      if (request === undefined) {
        res.status(404).json({message: "Отправитель или получатель не найден"});
        return;
      }
      if (request === false) {
        res.status(400).json({message: "Нельзя отправить запрос самому себе"});
        return;
      }
      if (request === "TARGET_PERSON_NOT_FOUND") {
        res.status(404).json({message: "Офлайн-профиль для приглашения не найден"});
        return;
      }
      if (request === "DUPLICATE") {
        res.status(409).json({message: "Похожий запрос уже ожидает ответа"});
        return;
      }

      await createAndDispatchNotification({
        userId: recipientId,
        type: "relation_request",
        title: "Новый запрос на родство",
        body: "Вам отправили запрос на подтверждение родственной связи",
        data: {
          requestId: request.id,
          treeId: request.treeId,
          senderId: request.senderId,
          relationType: request.senderToRecipient,
        },
      });

      res.status(201).json({request: mapRelationRequest(request)});
    },
  );

  async function handleCancelRelationRequest(request, req, res) {
    if (request.senderId !== req.auth.user.id) {
      res.status(403).json({message: "Отменить запрос может только отправитель"});
      return;
    }
    if (request.status !== "pending") {
      res.status(409).json({message: "Этот запрос уже обработан"});
      return;
    }

    const result = await store.respondToRelationRequest(request.id, "canceled");
    if (!result) {
      res.status(404).json({message: "Запрос не найден"});
      return;
    }
    if (result.conflict) {
      res.status(409).json({message: "Этот запрос уже обработан"});
      return;
    }

    await createAndDispatchNotification({
      userId: request.recipientId,
      type: "relation_request_canceled",
      title: "Запрос на родство отменён",
      body: "Отправитель отменил запрос на подтверждение родственной связи",
      data: {
        requestId: request.id,
        treeId: request.treeId,
        senderId: request.senderId,
        recipientId: request.recipientId,
        status: "canceled",
      },
    });

    res.json({
      ok: true,
      request: mapRelationRequest(result.request),
      person: null,
      relation: null,
    });
  }

  app.delete("/v1/relation-requests/:requestId", requireAuth, async (req, res) => {
    const request = await store.findRelationRequest(req.params.requestId);
    if (!request) {
      res.status(404).json({message: "Запрос не найден"});
      return;
    }
    await handleCancelRelationRequest(request, req, res);
  });

  app.post(
    "/v1/relation-requests/:requestId/respond",
    requireAuth,
    async (req, res) => {
      const responseStatus = String(req.body?.response || "").trim();
      if (!responseStatus) {
        res.status(400).json({message: "Нужен response"});
        return;
      }

      if (!["accepted", "rejected", "canceled"].includes(responseStatus)) {
        res.status(400).json({message: "Недопустимый статус ответа"});
        return;
      }

      const request = await store.findRelationRequest(req.params.requestId);
      if (!request) {
        res.status(404).json({message: "Запрос не найден"});
        return;
      }

      if (responseStatus === "canceled") {
        await handleCancelRelationRequest(request, req, res);
        return;
      }

      if (request.recipientId !== req.auth.user.id) {
        res.status(403).json({message: "Нельзя отвечать на чужой запрос"});
        return;
      }

      if (request.status !== "pending") {
        res.status(409).json({message: "Этот запрос уже обработан"});
        return;
      }

      let recipientPerson = null;
      let senderPerson = null;
      let relation = null;

      if (responseStatus === "accepted") {
        if (request.targetPersonId) {
          const linkedPerson = await store.linkPersonToUser({
            treeId: request.treeId,
            personId: request.targetPersonId,
            userId: req.auth.user.id,
            bypassClaimToken: true,
          });

          if (linkedPerson === null || linkedPerson === undefined) {
            res.status(404).json({message: "Профиль для привязки не найден"});
            return;
          }
          if (linkedPerson === false) {
            res.status(409).json({
              message: "Этот профиль уже связан с другим пользователем",
            });
            return;
          }

          recipientPerson = linkedPerson;
        } else {
          recipientPerson = await store.ensureUserPersonInTree({
            treeId: request.treeId,
            userId: req.auth.user.id,
          });
        }

        senderPerson = await store.ensureUserPersonInTree({
          treeId: request.treeId,
          userId: request.senderId,
          creatorId: request.senderId,
        });

        if (!recipientPerson || !senderPerson) {
          res.status(404).json({
            message: "Не удалось подготовить участников родственной связи",
          });
          return;
        }

        relation = await store.upsertRelation({
          treeId: request.treeId,
          person1Id: senderPerson.id,
          person2Id: recipientPerson.id,
          relation1to2: request.senderToRecipient,
          isConfirmed: true,
          createdBy: request.senderId,
        });
      }

      const result = await store.respondToRelationRequest(
        request.id,
        responseStatus,
      );
      if (!result) {
        res.status(404).json({message: "Запрос не найден"});
        return;
      }
      if (result.conflict) {
        res.status(409).json({message: "Этот запрос уже обработан"});
        return;
      }
      const updatedRequest = result.request;

      await createAndDispatchNotification({
        userId: request.senderId,
        type:
          responseStatus === "accepted"
            ? "relation_request_accepted"
            : "relation_request_updated",
        title:
          responseStatus === "accepted"
            ? "Запрос на родство принят"
            : "Запрос на родство обновлён",
        body:
          responseStatus === "accepted"
            ? "Ваш запрос на родство был принят"
            : "Получатель обработал ваш запрос на родство",
        data: {
          requestId: request.id,
          treeId: request.treeId,
          recipientId: request.recipientId,
          status: responseStatus,
        },
      });

      res.json({
        request: mapRelationRequest(updatedRequest),
        person: recipientPerson ? mapPerson(recipientPerson) : null,
        relation: relation ? mapRelation(relation) : null,
      });
    },
  );
}

module.exports = {
  registerRelationRequestRoutes,
};
