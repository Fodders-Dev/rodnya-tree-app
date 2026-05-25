// Phase B Week 3 Ship 6: pull-selectively endpoint.
//
// POST /v1/semya/:targetSemyaId/pull-person
//   Body: {sourceSemyaId, sourcePersonId}
//   Auth:
//     - Target: editor+ membership (requireSemyaAccess editor)
//     - Source: any-role membership (route-inline findMembership check)
//     - Browse-token-based source access defers Ship 7
//   Effect:
//     - Wraps existing bulkImportPersonsToTree (store.js:10379) c
//       single-element source array. Bulk import handles identity
//       deduplication: если identityId already в target tree → returns
//       existing twin person id (idempotency).
//     - Appends tree change record «person.pulled-from-semya» к target
//       tree audit log (mirror existing «person.imported» pattern в
//       tree-routes /import endpoint).
//     - Fires tree_mutated notification к target tree audience (current
//       broadcast scope; Ship 9 extends к семья members proper).
//
// Idempotency: re-pull same person = no-op return (existing twin
// returned, no duplicate row, no duplicate notification).
//
// Ship 6 не включает:
//   * Browse-token source access — Ship 7 (browse mode endpoints)
//   * Cross-семья broadcast scope — Ship 9 (audience extension)
//   * Conflict-resolution UI hooks — Ship 9+ либо frontend Week 5-6
//   * Bulk pull (multiple persons) — на Day 1 single-person sufficient,
//     bulk via repeated calls. Future endpoint POST /pull-persons[]
//     if user feedback requires.

function registerSemyaPullRoutes(
  app,
  {store, requireAuth, requireSemyaAccess, createAndDispatchNotification},
) {
  app.post(
    "/v1/semya/:targetSemyaId/pull-person",
    requireAuth,
    async (req, res) => {
      // Target gate — editor+ required (pull mutates target tree).
      const targetAccess = await requireSemyaAccess(
        req,
        res,
        req.params.targetSemyaId,
        {requiredRole: "editor"},
      );
      if (!targetAccess) return;

      const sourceSemyaId = String(req.body?.sourceSemyaId || "").trim();
      const sourcePersonId = String(req.body?.sourcePersonId || "").trim();
      if (!sourceSemyaId || !sourcePersonId) {
        res.status(400).json({
          message: "Нужны sourceSemyaId и sourcePersonId",
        });
        return;
      }
      if (sourceSemyaId === req.params.targetSemyaId) {
        res.status(400).json({
          message: "Источник и цель не могут быть одной семьёй",
        });
        return;
      }

      // Source gate — any-role membership. Browse-token alternative
      // defers Ship 7.
      const sourceSemya = await store.findSemyaById(sourceSemyaId);
      if (!sourceSemya || sourceSemya.deletedAt) {
        res.status(404).json({message: "Источник не найден"});
        return;
      }
      const sourceMembership = await store.findMembership(
        sourceSemyaId,
        req.auth.user.id,
      );
      if (!sourceMembership) {
        res.status(403).json({
          message: "Нет доступа к семье-источнику",
        });
        return;
      }

      // Resolve trees через семья.treeId.
      const sourceTree = await store.findTree(sourceSemya.treeId);
      const targetTree = await store.findTree(targetAccess.semya.treeId);
      if (!sourceTree || !targetTree) {
        res.status(500).json({message: "Дерево семьи не найдено"});
        return;
      }

      // Verify source person belongs к source tree (avoid pulling
      // arbitrary person ids across trees as side-channel).
      const sourcePerson = await store.findPerson(
        sourceTree.id,
        sourcePersonId,
      );
      if (!sourcePerson) {
        res.status(404).json({
          message: "Человек не найден в исходной семье",
        });
        return;
      }

      // Bulk-import single person. Existing helper handles identity
      // dedup + twin creation + relation bridging.
      const result = await store.bulkImportPersonsToTree({
        sourceTreeId: sourceTree.id,
        sourcePersonIds: [sourcePersonId],
        targetTreeId: targetTree.id,
        actorId: req.auth.user.id,
      });

      if (!result) {
        // bulkImport returns null when actor lacks legacy
        // tree.memberIds access. С dual-write от Ship 5 это shouldn't
        // happen для семья members, но defensively guard.
        res.status(403).json({
          message: "Импорт отклонён — нет доступа к деревьям",
        });
        return;
      }

      const importedPerson = (result.persons || [])[0] || null;

      // Audit log change record (mirror existing tree mutation
      // pattern). Phase B новый change type «person.pulled-from-semya»
      // дифференцирует от обычного import (user-driven bulk) и
      // создания на месте.
      if (importedPerson) {
        try {
          await store.appendTreeChangeRecord({
            treeId: targetTree.id,
            actorId: req.auth.user.id,
            type: "person.pulled-from-semya",
            personId: importedPerson.id,
            details: {
              sourceSemyaId,
              sourcePersonId,
              sourcePersonName:
                sourcePerson.firstName || sourcePerson.name || null,
            },
          });
        } catch (auditErr) {
          // Audit failure не должна ломать pull — log + continue.
          // eslint-disable-next-line no-console
          console.error(
            "[semya-pull] audit log append failed",
            auditErr?.message || auditErr,
          );
        }
      }

      // Broadcast tree_mutated к target tree audience. Current
      // dispatch использует tree.memberIds (через
      // resolveTreeAudienceUserIds); Ship 9 extends к семья members
      // explicit. Pour Ship 6 — fire с existing audience, dual-write
      // от Ship 5 keeps семья members included.
      if (typeof createAndDispatchNotification === "function") {
        try {
          const audience = await store.resolveTreeAudienceUserIds(
            targetTree.id,
            {excludeUserId: req.auth.user.id},
          );
          for (const recipientId of audience) {
            await createAndDispatchNotification({
              userId: recipientId,
              type: "tree_mutated",
              title: "Дерево обновлено",
              body: "",
              data: {
                treeId: targetTree.id,
                kind: "person.pulled-from-semya",
                actorUserId: req.auth.user.id,
              },
              silent: true,
            });
          }
        } catch (notifyErr) {
          // eslint-disable-next-line no-console
          console.error(
            "[semya-pull] tree_mutated dispatch failed",
            notifyErr?.message || notifyErr,
          );
        }
      }

      res.json({
        person: importedPerson,
        relations: result.relations || [],
        sourceSemyaId,
        sourcePersonId,
        targetSemyaId: req.params.targetSemyaId,
      });
    },
  );
}

module.exports = {registerSemyaPullRoutes};
