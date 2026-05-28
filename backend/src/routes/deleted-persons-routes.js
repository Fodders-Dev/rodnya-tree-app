// Ship Q4a (2026-05-28): deleted-persons «корзина» HTTP endpoints.
//
// Per PHASE-Q4A-SOFT-DELETE-DESIGN (ec12804) + 8 decisions locked
// 2026-05-28. Path 2 architecture — persons go to db.deletedPersons
// snapshot collection on delete, recoverable for 30d.
//
// Endpoints:
//   GET    /v1/me/deleted-persons                  — caller's view (cross-семья)
//   GET    /v1/semya/:semyaId/deleted-persons      — семя-scoped (member required)
//   POST   /v1/deleted-persons/:id/restore         — restore (member либо original actor)
//   DELETE /v1/deleted-persons/:id                 — hard-purge (3h floor protection)
//
// Permission summary:
//   • GET cross-семья — caller sees deleted persons они либо в их semиях
//   • GET семя-scoped — viewer+ membership required
//   • POST restore — original actor либо семя member; rejects если
//     hardDeleteScheduledAt elapsed либо seem semя soft-deleted
//   • DELETE hard-purge — original actor либо семя member; rejects
//     если earliestHardDelete не пройден (3h floor)

function registerDeletedPersonsRoutes(
  app,
  {store, requireAuth},
) {
  function mapDeletedPerson(row) {
    if (!row) return null;
    return {
      id: row.id,
      originalPersonId: row.originalPersonId,
      treeId: row.treeId,
      semyaId: row.semyaId ?? null,
      snapshot: row.snapshot,
      relationsSnapshot: row.relationsSnapshot ?? [],
      deletedAt: row.deletedAt,
      deletedByUserId: row.deletedByUserId ?? null,
      hardDeleteScheduledAt: row.hardDeleteScheduledAt,
      earliestHardDelete: row.earliestHardDelete,
      restoredAt: row.restoredAt ?? null,
      restoredByUserId: row.restoredByUserId ?? null,
    };
  }

  // GET /v1/me/deleted-persons — caller's soft-deleted persons
  // (cross-семья). Returns rows where caller is either deleter либо
  // member of bound семя.
  app.get("/v1/me/deleted-persons", requireAuth, async (req, res) => {
    const rows = await store.listDeletedPersonsForUser({
      userId: req.auth.user.id,
    });
    res.json({deletedPersons: rows.map(mapDeletedPerson)});
  });

  // GET /v1/semya/:semyaId/deleted-persons — семя-scoped list.
  // Member-only (any role). Store throws NOT_MEMBER → 403.
  app.get(
    "/v1/semya/:semyaId/deleted-persons",
    requireAuth,
    async (req, res) => {
      try {
        const rows = await store.listDeletedPersonsForSemya({
          semyaId: req.params.semyaId,
          userId: req.auth.user.id,
        });
        res.json({deletedPersons: rows.map(mapDeletedPerson)});
      } catch (error) {
        const code = error?.message;
        if (code === "NOT_MEMBER") {
          res.status(403).json({message: "Доступ только для участников семьи"});
          return;
        }
        throw error;
      }
    },
  );

  // POST /v1/deleted-persons/:id/restore — restore из snapshot.
  app.post(
    "/v1/deleted-persons/:id/restore",
    requireAuth,
    async (req, res) => {
      try {
        const restored = await store.restorePerson({
          deletedPersonId: req.params.id,
          actorUserId: req.auth.user.id,
        });
        res.json({restored: mapDeletedPerson(restored)});
      } catch (error) {
        const code = error?.message;
        if (code === "DELETED_PERSON_NOT_FOUND") {
          res.status(404).json({message: "Удалённая карточка не найдена"});
          return;
        }
        if (code === "ALREADY_RESTORED") {
          res.status(409).json({message: "Уже восстановлена"});
          return;
        }
        if (code === "HARD_DELETE_ELAPSED") {
          res.status(410).json({
            message: "Срок восстановления истёк — карточка удалена навсегда",
          });
          return;
        }
        if (code === "SEMYA_DELETED") {
          res.status(410).json({
            message: "Семья удалена — карточку нельзя восстановить",
          });
          return;
        }
        if (code === "FORBIDDEN") {
          res.status(403).json({
            message: "Восстановить может только участник семьи",
          });
          return;
        }
        if (
          code === "INVALID_INPUT" ||
          code === "INVALID_ACTOR"
        ) {
          res.status(400).json({message: "Некорректные параметры"});
          return;
        }
        throw error;
      }
    },
  );

  // DELETE /v1/deleted-persons/:id — manual hard-purge (skip 30d wait).
  app.delete(
    "/v1/deleted-persons/:id",
    requireAuth,
    async (req, res) => {
      try {
        const result = await store.hardDeletePerson({
          deletedPersonId: req.params.id,
          actorUserId: req.auth.user.id,
        });
        res.json(result);
      } catch (error) {
        const code = error?.message;
        if (code === "DELETED_PERSON_NOT_FOUND") {
          res.status(404).json({message: "Удалённая карточка не найдена"});
          return;
        }
        if (code === "ALREADY_RESTORED") {
          res.status(409).json({
            message: "Карточка восстановлена — удалить нельзя",
          });
          return;
        }
        if (code === "FLOOR_NOT_MET") {
          res.status(409).json({
            message:
              "Подождите немного перед окончательным удалением (защита от случайного нажатия)",
          });
          return;
        }
        if (code === "FORBIDDEN") {
          res.status(403).json({
            message: "Удалить навсегда может только участник семьи",
          });
          return;
        }
        if (
          code === "INVALID_INPUT" ||
          code === "INVALID_ACTOR"
        ) {
          res.status(400).json({message: "Некорректные параметры"});
          return;
        }
        throw error;
      }
    },
  );
}

module.exports = {registerDeletedPersonsRoutes};
