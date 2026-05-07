const {
  findWithinTreeDuplicateCandidates,
} = require("../identity-matcher");

function registerTreeRoutes(
  app,
  {
    store,
    requireAuth,
    requireTreeAccess,
    requirePublicTree,
    mapTree,
    mapPerson,
    mapRelation,
    mapProfileContribution,
    mapTreeChangeRecord,
    mapTreeGraphSnapshot,
    buildPersonDossierPayload,
  },
) {
  app.post("/v1/trees", requireAuth, async (req, res) => {
    const {name, description, isPrivate, kind} = req.body || {};
    if (!String(name || "").trim()) {
      res.status(400).json({message: "Нужно название дерева"});
      return;
    }

    const tree = await store.createTree({
      creatorId: req.auth.user.id,
      name,
      description,
      isPrivate,
      kind,
    });

    res.status(201).json({tree: mapTree(tree)});
  });

  app.get("/v1/trees", requireAuth, async (req, res) => {
    const trees = await store.listUserTrees(req.auth.user.id);
    res.json({
      trees: trees.map(mapTree),
    });
  });

  app.delete("/v1/trees/:treeId", requireAuth, async (req, res) => {
    const tree = await store.findTree(req.params.treeId);
    if (!tree) {
      res.status(404).json({message: "Дерево не найдено"});
      return;
    }

    const memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
    const members = Array.isArray(tree.members) ? tree.members : [];
    const hasAccess =
      tree.creatorId === req.auth.user.id ||
      memberIds.includes(req.auth.user.id) ||
      members.includes(req.auth.user.id);
    if (!hasAccess) {
      res.status(403).json({message: "Доступ к дереву запрещён"});
      return;
    }

    const result = await store.removeTreeForUser({
      treeId: req.params.treeId,
      userId: req.auth.user.id,
    });
    if (result === null) {
      res.status(404).json({message: "Дерево не найдено"});
      return;
    }
    if (result === false) {
      res.status(403).json({message: "Доступ к дереву запрещён"});
      return;
    }

    res.json({
      action: result.action,
      tree: mapTree(result.tree),
    });
  });

  app.get("/v1/public/trees/:publicTreeId", async (req, res) => {
    const tree = await requirePublicTree(req, res, req.params.publicTreeId);
    if (!tree) {
      return;
    }

    const [persons, relations] = await Promise.all([
      store.listPersons(tree.id),
      store.listRelations(tree.id),
    ]);

    res.json({
      tree: mapTree(tree),
      stats: {
        peopleCount: persons.length,
        relationsCount: relations.length,
      },
    });
  });

  app.get("/v1/public/trees/:publicTreeId/persons", async (req, res) => {
    const tree = await requirePublicTree(req, res, req.params.publicTreeId);
    if (!tree) {
      return;
    }

    const persons = await store.listPersons(tree.id);
    res.json({
      tree: mapTree(tree),
      persons: persons.map(mapPerson),
    });
  });

  app.get("/v1/public/trees/:publicTreeId/relations", async (req, res) => {
    const tree = await requirePublicTree(req, res, req.params.publicTreeId);
    if (!tree) {
      return;
    }

    const relations = await store.listRelations(tree.id);
    res.json({
      tree: mapTree(tree),
      relations: relations.map(mapRelation),
    });
  });

  app.get("/v1/trees/selectable", requireAuth, async (req, res) => {
    const trees = await store.listUserTrees(req.auth.user.id);
    res.json({
      trees: trees.map((tree) => ({
        id: tree.id,
        name: tree.name,
        createdAt: tree.createdAt,
      })),
    });
  });

  // Phase 0 of unified-graph migration: cross-tree person search.
  // The Flutter add-relative screen calls this from a debounced
  // textfield as the user types — surfaces relatives they ALREADY
  // entered on any of their other trees so they don't have to
  // re-key the same human. Picking a result on the client side
  // pre-fills the form, stamps `sourcePersonId` into the create
  // payload, and the server then shares an identityId between the
  // two records (Phase 1 turns this into full edit propagation).
  //
  // Strict per-user scope: only walks the caller's accessible
  // trees (creator + member), never anyone else's. Future Phase 4
  // adds a separate opt-in social-discovery endpoint with explicit
  // consent — that's a different problem and a different route.
  app.get("/v1/persons/search", requireAuth, async (req, res) => {
    const rawQuery = req.query?.q;
    const query = typeof rawQuery === "string" ? rawQuery : "";
    if (query.length > 200) {
      // Defense in depth — `searchPersonsForUser` already does a
      // bounded substring scan, but pathological queries deserve
      // an early reject so we don't tie up the libuv thread on a
      // 1MB needle. Real names don't get this long.
      res.status(400).json({message: "Слишком длинный запрос"});
      return;
    }

    const excludeTreeId = req.query?.excludeTreeId;
    const limitRaw = Number(req.query?.limit);
    const limit = Number.isFinite(limitRaw) && limitRaw > 0
      ? Math.min(limitRaw, 50)
      : 20;

    const persons = await store.searchPersonsForUser({
      userId: req.auth.user.id,
      query,
      excludeTreeId:
        typeof excludeTreeId === "string" ? excludeTreeId : null,
      limit,
    });

    res.json({
      // Trim to the lightweight summary shape — the picker only
      // needs name + photo + tree name to render. Full Person
      // payload is fetched on demand via /v1/trees/:id/persons/:id
      // when the user actually picks. Keeps this hot path tiny
      // even for users with many trees / hundreds of persons.
      persons: persons.map((person) => ({
        id: person.id,
        treeId: person.treeId,
        treeName: person.treeName || "",
        displayName: person.name || "",
        photoUrl: person.primaryPhotoUrl || person.photoUrl || null,
        birthDate: person.birthDate || null,
        gender: person.gender || "unknown",
      })),
    });
  });

  app.get("/v1/trees/:treeId/persons", requireAuth, async (req, res) => {
    const tree = await requireTreeAccess(req, res, req.params.treeId);
    if (!tree) {
      return;
    }

    const persons = await store.listPersons(tree.id);
    res.json({
      persons: persons.map(mapPerson),
    });
  });

  app.get("/v1/trees/:treeId/duplicates", requireAuth, async (req, res) => {
    const tree = await requireTreeAccess(req, res, req.params.treeId);
    if (!tree) {
      return;
    }

    const requestedLimit = Number(req.query.limit || 20);
    const persons = await store.listPersons(tree.id);
    const suggestions = findWithinTreeDuplicateCandidates({
      treeId: tree.id,
      persons,
      limit: Number.isFinite(requestedLimit) ? requestedLimit : 20,
    });

    res.json({
      suggestions: suggestions.map((suggestion) => ({
        id: suggestion.id,
        treeId: suggestion.treeId,
        score: suggestion.score,
        confidence: suggestion.confidence,
        reasons: suggestion.reasons,
        personA: mapPerson(suggestion.personA),
        personB: mapPerson(suggestion.personB),
      })),
    });
  });

  // ── Phase 1.2: voltage-indicator matcher ────────────────────────────
  // For one specific person, surface medium+high confidence cross-
  // tree matches the user hasn't linked or dismissed. Drives the
  // 💡 indicator on each card. The Flutter client batches calls
  // (one per visible person) and renders the dot when length > 0.
  app.get(
    "/v1/trees/:treeId/persons/:personId/identity-suggestions",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) return;
      const requestedLimit = Number(req.query.limit || 10);
      const limit = Number.isFinite(requestedLimit) && requestedLimit > 0
        ? Math.min(requestedLimit, 50)
        : 10;
      const suggestions = await store.findCrossTreeSuggestionsForPerson({
        userId: req.auth.user.id,
        treeId: tree.id,
        personId: req.params.personId,
        limit,
      });
      res.json({
        suggestions: suggestions.map((suggestion) => ({
          sourcePersonId: suggestion.sourcePersonId,
          sourceTreeId: suggestion.sourceTreeId,
          targetPersonId: suggestion.targetPersonId,
          targetTreeId: suggestion.targetTreeId,
          targetTreeName: suggestion.targetTreeName,
          targetPerson: mapPerson(suggestion.targetPerson),
          score: suggestion.score,
          confidence: suggestion.confidence,
          reasons: suggestion.reasons,
        })),
      });
    },
  );

  // Confirm a 💡-suggested match: link both persons under one
  // PersonIdentity. From this point on, identity propagation
  // (Phase 1.1) keeps the canonical fields in sync. Caller passes
  // the target via {targetTreeId, targetPersonId} on the body —
  // we verify they have access to the target tree before linking
  // (otherwise an attacker could probe for IDs).
  app.post(
    "/v1/trees/:treeId/persons/:personId/link-identity",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) return;
      const targetTreeIdRaw = req.body?.targetTreeId;
      const targetPersonIdRaw = req.body?.targetPersonId;
      const targetTreeId =
        typeof targetTreeIdRaw === "string" ? targetTreeIdRaw.trim() : "";
      const targetPersonId =
        typeof targetPersonIdRaw === "string" ? targetPersonIdRaw.trim() : "";
      if (!targetTreeId || !targetPersonId) {
        res.status(400).json({
          message: "Нужны targetTreeId и targetPersonId",
        });
        return;
      }
      // Auth: verify the user can access the target tree too.
      const targetTree = await requireTreeAccess(req, res, targetTreeId);
      if (!targetTree) return;

      try {
        const result = await store.linkPersonsByIdentity({
          sourceTreeId: tree.id,
          sourcePersonId: req.params.personId,
          targetTreeId: targetTree.id,
          targetPersonId,
          actorId: req.auth.user.id,
        });
        if (!result) {
          res.status(404).json({message: "Карточки не найдены"});
          return;
        }
        res.json({
          identityId: result.identityId,
          source: mapPerson(result.sourcePerson),
          target: mapPerson(result.targetPerson),
        });
      } catch (error) {
        if (error?.message === "CONFLICTING_IDENTITIES") {
          res.status(409).json({
            message:
              "Эти карточки уже связаны с разными identityId — сначала объедините их через merge.",
          });
          return;
        }
        throw error;
      }
    },
  );

  // Dismiss a 💡 suggestion — the user said "these are different
  // people". We record the per-user dismissal so the same
  // suggestion doesn't keep surfacing.
  app.post(
    "/v1/trees/:treeId/persons/:personId/dismiss-suggestion",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) return;
      const targetPersonIdRaw = req.body?.targetPersonId;
      const targetPersonId =
        typeof targetPersonIdRaw === "string" ? targetPersonIdRaw.trim() : "";
      if (!targetPersonId) {
        res.status(400).json({message: "Нужен targetPersonId"});
        return;
      }
      await store.dismissIdentitySuggestion({
        userId: req.auth.user.id,
        sourcePersonId: req.params.personId,
        dismissedTargetPersonId: targetPersonId,
      });
      res.status(204).send();
    },
  );

  app.post("/v1/trees/:treeId/persons", requireAuth, async (req, res) => {
    const tree = await requireTreeAccess(req, res, req.params.treeId);
    if (!tree) {
      return;
    }

    const requestedUserId = req.body?.userId;
    if (requestedUserId && requestedUserId !== req.auth.user.id) {
      res.status(403).json({
        message: "Нельзя привязать к профилю другого пользователя",
      });
      return;
    }

    // Phase 0 cross-tree picker: optional `sourcePersonId` on the
    // body lets the client say "this is the same human as person
    // X on one of my other trees". The store enforces access (the
    // source must live in a tree the caller can reach), so a
    // forged ID can't leak data — it's just dropped. We pass the
    // raw value through; the store does the access check.
    const sourcePersonIdRaw = req.body?.sourcePersonId;
    const sourcePersonId =
      typeof sourcePersonIdRaw === "string" && sourcePersonIdRaw.trim()
        ? sourcePersonIdRaw.trim()
        : null;

    const person = await store.createPerson({
      treeId: tree.id,
      creatorId: req.auth.user.id,
      userId: requestedUserId || null,
      personData: req.body || {},
      sourcePersonId,
    });

    if (!person) {
      res.status(404).json({message: "Семейное дерево не найдено"});
      return;
    }

    res.status(201).json({person: mapPerson(person)});
  });

  app.get(
    "/v1/trees/:treeId/persons/:personId",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const person = await store.findPerson(tree.id, req.params.personId);
      if (!person) {
        res.status(404).json({message: "Человек не найден"});
        return;
      }

      res.json({person: mapPerson(person)});
    },
  );

  app.get(
    "/v1/trees/:treeId/persons/:personId/dossier",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const dossier = await buildPersonDossierPayload({
        treeId: tree.id,
        personId: req.params.personId,
        viewerUserId: req.auth.user.id,
      });
      if (!dossier) {
        res.status(404).json({message: "Человек не найден"});
        return;
      }

      res.json({dossier});
    },
  );

  app.patch(
    "/v1/trees/:treeId/persons/:personId",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const person = await store.updatePerson(
        tree.id,
        req.params.personId,
        req.body || {},
        req.auth.user.id,
      );
      if (!person) {
        res.status(404).json({message: "Человек не найден"});
        return;
      }

      // Phase 1.1 identity propagation: if the update fanned out to
      // other person records that share the same identityId
      // (typically: the same human entered into a different tree
      // by the same user via the cross-tree picker), the store
      // attaches a `_propagatedTo: [{treeId, personId}, ...]`
      // hint. We surface it in the response so the Flutter client
      // can invalidate the affected trees' caches without
      // refetching everything.
      const propagatedTo = Array.isArray(person._propagatedTo)
        ? person._propagatedTo
        : [];

      const responsePayload = {
        person: mapPerson(person),
      };
      if (propagatedTo.length > 0) {
        responsePayload.identityPropagation = {affected: propagatedTo};
      }
      res.json(responsePayload);
    },
  );

  app.post(
    "/v1/trees/:treeId/persons/:personId/profile-contributions",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const contribution = await store.createProfileContribution({
        treeId: tree.id,
        personId: req.params.personId,
        authorUserId: req.auth.user.id,
        message: req.body?.message,
        fields: req.body?.fields,
      });
      if (contribution === null) {
        res.status(404).json({message: "Человек не найден"});
        return;
      }
      if (contribution === false) {
        res.status(403).json({
          message: "Пользователь не принимает предложения по профилю.",
        });
        return;
      }
      if (contribution === undefined) {
        res.status(400).json({message: "Нет данных для предложения правки"});
        return;
      }

      const author = await store.findUserById(req.auth.user.id);
      res.status(201).json({
        contribution: mapProfileContribution({
          ...contribution,
          authorDisplayName:
            author?.profile?.displayName || author?.email || "Пользователь",
          authorPhotoUrl: author?.profile?.photoUrl || null,
        }),
      });
    },
  );

  app.delete(
    "/v1/trees/:treeId/persons/:personId",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const deleted = await store.deletePerson(
        tree.id,
        req.params.personId,
        req.auth.user.id,
      );
      if (!deleted) {
        res.status(404).json({message: "Человек не найден"});
        return;
      }

      res.status(204).send();
    },
  );

  app.post(
    "/v1/trees/:treeId/persons/:personId/media",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const url =
        req.body?.url || req.body?.mediaUrl || req.body?.photoUrl || null;
      if (!url) {
        res.status(400).json({message: "Нужен url media-файла"});
        return;
      }

      const result = await store.addPersonMedia({
        treeId: tree.id,
        personId: req.params.personId,
        actorId: req.auth.user.id,
        media: req.body || {},
      });
      if (!result) {
        res.status(404).json({message: "Человек не найден"});
        return;
      }

      res.status(201).json({
        person: mapPerson(result.person),
        media: result.media,
        // Phase 1.1 photo propagation: list of {treeId, personId}
        // pairs the change fanned out to. Flutter client uses
        // this to invalidate graph snapshots on the affected
        // trees so the UI doesn't stay stale.
        propagatedTo: result.propagatedTo || [],
      });
    },
  );

  app.patch(
    "/v1/trees/:treeId/persons/:personId/media/:mediaId",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const result = await store.updatePersonMedia({
        treeId: tree.id,
        personId: req.params.personId,
        mediaId: req.params.mediaId,
        actorId: req.auth.user.id,
        updates: req.body || {},
      });
      if (result === null) {
        res.status(404).json({message: "Человек не найден"});
        return;
      }
      if (result === false) {
        res.status(404).json({message: "Media элемент не найден"});
        return;
      }

      res.json({
        person: mapPerson(result.person),
        media: result.media,
        propagatedTo: result.propagatedTo || [],
      });
    },
  );

  app.delete(
    "/v1/trees/:treeId/persons/:personId/media/:mediaId",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      // Clients that cached person data before real UUIDs were added may send
      // a synthetic ID like "photo-1". Fall back to URL-based lookup in that case.
      const fallbackUrl = String(req.body?.url || req.query?.url || "").trim();
      const result = await store.deletePersonMedia({
        treeId: tree.id,
        personId: req.params.personId,
        mediaId: req.params.mediaId,
        fallbackUrl: fallbackUrl || null,
        actorId: req.auth.user.id,
      });
      if (result === null) {
        res.status(404).json({message: "Человек не найден"});
        return;
      }
      if (result === false) {
        res.status(404).json({message: "Media элемент не найден"});
        return;
      }

      res.json({
        person: mapPerson(result.person),
        deletedMediaId: result.deletedMedia?.id || req.params.mediaId,
        propagatedTo: result.propagatedTo || [],
      });
    },
  );

  app.get("/v1/trees/:treeId/history", requireAuth, async (req, res) => {
    const tree = await requireTreeAccess(req, res, req.params.treeId);
    if (!tree) {
      return;
    }

    const personId = String(req.query.personId || "").trim() || null;
    const type = String(req.query.type || "").trim() || null;
    const actorId = String(req.query.actorId || "").trim() || null;
    const records = await store.listTreeChangeRecords(tree.id, {
      personId,
      type,
      actorId,
    });

    res.json({
      records: records.map(mapTreeChangeRecord),
    });
  });

  app.get("/v1/trees/:treeId/relations", requireAuth, async (req, res) => {
    const tree = await requireTreeAccess(req, res, req.params.treeId);
    if (!tree) {
      return;
    }

    const relations = await store.listRelations(tree.id);
    res.json({
      relations: relations.map(mapRelation),
    });
  });

  app.get("/v1/trees/:treeId/graph", requireAuth, async (req, res) => {
    const tree = await requireTreeAccess(req, res, req.params.treeId);
    if (!tree) {
      return;
    }

    const snapshot = await store.getTreeGraphSnapshot(tree.id, {
      viewerUserId: req.auth.user.id,
    });
    if (!snapshot) {
      res.status(404).json({message: "Дерево не найдено"});
      return;
    }

    res.json({
      snapshot: mapTreeGraphSnapshot(snapshot),
    });
  });

  app.post("/v1/trees/:treeId/relations", requireAuth, async (req, res) => {
    const tree = await requireTreeAccess(req, res, req.params.treeId);
    if (!tree) {
      return;
    }

    const {
      person1Id,
      person2Id,
      relation1to2,
      relation2to1,
      customRelationLabel1to2,
      customRelationLabel2to1,
      isConfirmed,
      marriageDate,
      divorceDate,
      parentSetId,
      parentSetType,
      isPrimaryParentSet,
      unionId,
      unionType,
      unionStatus,
    } =
      req.body || {};
    if (!person1Id || !person2Id || !relation1to2) {
      res.status(400).json({
        message: "Нужны person1Id, person2Id и relation1to2",
      });
      return;
    }

    const relation = await store.upsertRelation({
      treeId: tree.id,
      person1Id: String(person1Id),
      person2Id: String(person2Id),
      relation1to2: String(relation1to2),
      relation2to1: relation2to1 ? String(relation2to1) : undefined,
      customRelationLabel1to2:
        customRelationLabel1to2 === undefined || customRelationLabel1to2 === null
          ? customRelationLabel1to2
          : String(customRelationLabel1to2),
      customRelationLabel2to1:
        customRelationLabel2to1 === undefined || customRelationLabel2to1 === null
          ? customRelationLabel2to1
          : String(customRelationLabel2to1),
      isConfirmed: isConfirmed !== false,
      marriageDate:
        marriageDate === undefined || marriageDate === null
          ? marriageDate
          : String(marriageDate),
      divorceDate:
        divorceDate === undefined || divorceDate === null
          ? divorceDate
          : String(divorceDate),
      parentSetId:
        parentSetId === undefined || parentSetId === null
          ? parentSetId
          : String(parentSetId),
      parentSetType:
        parentSetType === undefined || parentSetType === null
          ? parentSetType
          : String(parentSetType),
      isPrimaryParentSet,
      unionId:
        unionId === undefined || unionId === null ? unionId : String(unionId),
      unionType:
        unionType === undefined || unionType === null
          ? unionType
          : String(unionType),
      unionStatus:
        unionStatus === undefined || unionStatus === null
          ? unionStatus
          : String(unionStatus),
      createdBy: req.auth.user.id,
    });

    if (!relation) {
      res.status(404).json({
        message: "Один или оба человека не найдены в дереве",
      });
      return;
    }

    res.status(201).json({relation: mapRelation(relation)});
  });

  app.delete(
    "/v1/trees/:treeId/relations/:relationId",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const deletedRelation = await store.deleteRelation(
        tree.id,
        req.params.relationId,
        req.auth.user.id,
      );
      if (!deletedRelation) {
        res.status(404).json({message: "Связь не найдена"});
        return;
      }

      res.status(204).send();
    },
  );
}

module.exports = {
  registerTreeRoutes,
};
