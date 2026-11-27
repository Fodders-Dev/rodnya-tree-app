const path = require("node:path");
const crypto = require("node:crypto");
const {
  backfillPersonIdentities,
} = require("../../migration-utils");
const {
  createCircleRecord,
  ensureAutoCirclesForTree,
  ensureCirclesForTree,
  ensureDefaultCirclesForTree,
  normalizeCircleMemberIdentityIds,
  normalizeNullableString,
  nowIso,
} = require("../helpers");

module.exports = {
  _circleMemberCount(db, circle) {
    if (!circle) {
      return 0;
    }
    if (circle.kind === "all_tree") {
      return (Array.isArray(db.persons) ? db.persons : []).filter(
        (person) => person.treeId === circle.treeId,
      ).length;
    }
    return (Array.isArray(db.circleMembers) ? db.circleMembers : []).filter(
      (entry) => entry.treeId === circle.treeId && entry.circleId === circle.id,
    ).length;
  },

  _mapCircleWithCount(db, circle) {
    return {
      ...circle,
      memberCount: this._circleMemberCount(db, circle),
    };
  },

  async listCircles(treeId) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (!tree) {
      return null;
    }

    const {changed} = ensureCirclesForTree(db, tree);
    if (changed) {
      await this._write(db);
    }

    return db.circles
      .filter((entry) => entry.treeId === treeId)
      .sort((left, right) => {
        const kindOrder = {
          all_tree: 0,
          favorites: 1,
          descendants_of: 2,
          ancestors_of: 3,
          pair: 4,
          custom: 5,
        };
        const leftOrder = kindOrder[left.kind] ?? 99;
        const rightOrder = kindOrder[right.kind] ?? 99;
        if (leftOrder !== rightOrder) {
          return leftOrder - rightOrder;
        }
        return String(left.name || "").localeCompare(String(right.name || ""));
      })
      .map((circle) => structuredClone(this._mapCircleWithCount(db, circle)));
  },

  async findCircle(treeId, circleId) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (!tree) {
      return null;
    }
    const {changed} = ensureCirclesForTree(db, tree);
    if (changed) {
      await this._write(db);
    }
    const circle = db.circles.find(
      (entry) => entry.treeId === treeId && entry.id === circleId,
    );
    return circle
      ? structuredClone(this._mapCircleWithCount(db, circle))
      : null;
  },

  async createCircle({treeId, name, description = null, createdBy = null}) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (!tree) {
      return null;
    }
    ensureCirclesForTree(db, tree);
    const circle = createCircleRecord({
      treeId,
      name,
      description,
      createdBy,
      kind: "custom",
    });
    db.circles.push(circle);
    await this._write(db);
    return structuredClone(this._mapCircleWithCount(db, circle));
  },

  _canManageCircle(db, treeId, circle, actorUserId) {
    if (!actorUserId) {
      return true;
    }
    const tree = (Array.isArray(db.trees) ? db.trees : []).find(
      (entry) => entry.id === treeId,
    );
    const isSemyaOwner =
      typeof this._isActiveSemyaOwnerForTree === "function" &&
      this._isActiveSemyaOwnerForTree(db, treeId, actorUserId);
    const isLegacyOwner = Boolean(
      tree && !tree.semyaId && tree.creatorId === actorUserId,
    );
    if (isSemyaOwner || isLegacyOwner) {
      return true;
    }
    const ownerId = normalizeNullableString(circle?.createdBy);
    return Boolean(ownerId && ownerId === actorUserId);
  },

  async updateCircle({
    treeId,
    circleId,
    name,
    description = undefined,
    actorUserId = null,
  }) {
    return this._mutate((db, skip) => {
      const circle = db.circles.find(
        (entry) => entry.treeId === treeId && entry.id === circleId,
      );
      if (!circle) {
        return skip(null);
      }
      if (circle.kind !== "custom" && circle.kind !== "favorites") {
        return skip({error: "SYSTEM_CIRCLE"});
      }
      if (!this._canManageCircle(db, treeId, circle, actorUserId)) {
        return skip({error: "FORBIDDEN"});
      }

      const normalizedName = String(name || "").trim();
      if (normalizedName) {
        circle.name = normalizedName;
      }
      if (description !== undefined) {
        circle.description = normalizeNullableString(description);
      }
      circle.updatedAt = nowIso();
      return structuredClone(this._mapCircleWithCount(db, circle));
    });
  },

  async deleteCircle({treeId, circleId, actorUserId = null}) {
    return this._mutate((db, skip) => {
      const circleIndex = db.circles.findIndex(
        (entry) => entry.treeId === treeId && entry.id === circleId,
      );
      if (circleIndex < 0) {
        return skip(null);
      }
      const circle = db.circles[circleIndex];
      if (circle.kind !== "custom") {
        return skip({error: "SYSTEM_CIRCLE"});
      }
      if (!this._canManageCircle(db, treeId, circle, actorUserId)) {
        return skip({error: "FORBIDDEN"});
      }

      db.circles.splice(circleIndex, 1);
      db.circleMembers = db.circleMembers.filter(
        (entry) => !(entry.treeId === treeId && entry.circleId === circleId),
      );
      const {allTreeCircle} = ensureDefaultCirclesForTree(db, treeId);
      const fallbackCircleId = allTreeCircle?.id || null;
      const timestamp = nowIso();

      for (const collection of [db.posts, db.stories, db.gatherings, db.polls]) {
        for (const item of Array.isArray(collection) ? collection : []) {
          if (item.treeId === treeId && item.circleId === circleId) {
            item.circleId = fallbackCircleId;
            item.updatedAt = timestamp;
          }
        }
      }
      for (const deletedRow of Array.isArray(db.deletedPosts)
        ? db.deletedPosts
        : []) {
        if (
          deletedRow.treeId === treeId &&
          deletedRow.snapshot?.circleId === circleId
        ) {
          deletedRow.snapshot.circleId = fallbackCircleId;
          deletedRow.snapshot.updatedAt = timestamp;
        }
      }
      return structuredClone(circle);
    });
  },

  async replaceCircleMembers({
    treeId,
    circleId,
    identityIds = [],
    personIds = [],
    actorUserId = null,
  }) {
    return this._mutate((db, skip) => {
      const tree = db.trees.find((entry) => entry.id === treeId);
      if (!tree) {
        return skip(null);
      }
      ensureCirclesForTree(db, tree);
      const circle = db.circles.find(
        (entry) => entry.treeId === treeId && entry.id === circleId,
      );
      if (!circle) {
        return skip(null);
      }
      if (circle.kind !== "custom" && circle.kind !== "favorites") {
        return skip({error: "SYSTEM_CIRCLE"});
      }
      if (!this._canManageCircle(db, treeId, circle, actorUserId)) {
        return skip({error: "FORBIDDEN"});
      }

      const identityIdsFromPersons = (Array.isArray(personIds) ? personIds : [])
        .map((personId) => {
          const normalizedPersonId = normalizeNullableString(personId);
          return db.persons.find(
            (person) =>
              person.treeId === treeId && person.id === normalizedPersonId,
          )?.identityId;
        })
        .filter(Boolean);
      const normalizedIdentityIds = normalizeCircleMemberIdentityIds(
        db,
        treeId,
        [...identityIds, ...identityIdsFromPersons],
      );
      const timestamp = nowIso();
      db.circleMembers = db.circleMembers.filter(
        (entry) => !(entry.treeId === treeId && entry.circleId === circleId),
      );
      for (const identityId of normalizedIdentityIds) {
        db.circleMembers.push({
          id: crypto.randomUUID(),
          treeId,
          circleId,
          identityId,
          createdAt: timestamp,
          updatedAt: timestamp,
        });
      }
      circle.updatedAt = timestamp;
      return structuredClone(this._mapCircleWithCount(db, circle));
    });
  },

  async listCircleMembers(treeId, circleId) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (!tree) {
      return null;
    }
    const {changed} = ensureCirclesForTree(db, tree);
    if (changed) {
      await this._write(db);
    }
    const circle = db.circles.find(
      (entry) => entry.treeId === treeId && entry.id === circleId,
    );
    if (!circle) {
      return null;
    }
    if (circle.kind === "all_tree") {
      return db.persons
        .filter((person) => person.treeId === treeId)
        .map((person) => ({
          treeId,
          circleId,
          identityId: normalizeNullableString(person.identityId),
          personId: person.id,
        }))
        .filter((entry) => entry.identityId)
        .map((entry) => structuredClone(entry));
    }
    return db.circleMembers
      .filter((entry) => entry.treeId === treeId && entry.circleId === circleId)
      .map((entry) => structuredClone(entry));
  },

  // SPEED-11: ensureCirclesForTree (called below) reconciles auto-circles
  // in-memory on EVERY call — SPEED-8c made that reconciliation intentionally
  // transient (never persisted from a read path), which was always safe
  // because `db` used to be a private structuredClone from _read(). Now that
  // readSharedSnapshot() can hand this method a FROZEN, cross-request-shared
  // `db` (SPEED-11), the same in-place `db.circles.push(...)` / `circle[key]
  // = value` writes would throw (Array mutators throw on a frozen array
  // regardless of strict mode) or silently no-op (plain property assignment
  // in sloppy-mode store.js) — either crashing the request or computing
  // visibility off half-reconciled circles. This builds a cheap, request-
  // scoped copy-on-write projection — ONLY `circles`/`persons` rows
  // belonging to `treeId` are cloned, everything else stays a shared
  // reference into the frozen snapshot — so ensureCirclesForTree can mutate
  // it freely without ever touching the shared cache. No-op (returns `db`
  // unchanged) when `db` isn't frozen, which covers every pre-existing
  // caller (createPost/createStory/listPosts/... always pass a private
  // _read() clone) with zero extra cost beyond one Object.isFrozen check.
  // Memoized per treeId in `cache` (same lifetime as cache.circles/
  // .identities — one JS object per listX() call, discarded after).
  _writableCirclesViewForTree(db, treeId, cache) {
    if (!db || !Object.isFrozen(db)) {
      return db;
    }
    if (cache) {
      if (!cache.circleViews) {
        cache.circleViews = new Map();
      }
      const existing = cache.circleViews.get(treeId);
      if (existing) {
        return existing;
      }
    }
    // ХОТФИКС (06.09): не {...db} — spread перечисляет геттер sessions
    // общего снимка (SPEED-11), а он бросает по контракту. Копируем ключи
    // явно, sessions пропускаем — кругам он не нужен.
    const overlay = {};
    for (const key of Object.keys(db)) {
      if (key === "sessions") continue;
      overlay[key] = db[key];
    }
    Object.defineProperty(overlay, "sessions", {
      enumerable: true,
      configurable: false,
      get() {
        throw new Error(
          "_writableCirclesViewForTree(): overlay has no sessions — use " +
            "findSession/findUserBySessionToken/store session methods instead of db.sessions (SPEED-11/12)",
        );
      },
    });
    overlay.circles = (Array.isArray(db.circles) ? db.circles : []).map(
      (entry) => (entry && entry.treeId === treeId ? {...entry} : entry),
    );
    // persons — needed because ensureAutoCirclesForTree calls
    // backfillPersonIdentities(db) when this tree still has a person
    // without identityId (legacy-data path, SPEED-8c) — that mutates
    // person.identityId IN PLACE. backfillPersonIdentities scans+mutates
    // ALL persons in `db.persons`, not just this tree's (it back-links
    // personIdentities globally), so cloning only THIS tree's rows would
    // leave persons of OTHER trees frozen — their in-place identityId
    // write would silently no-op (sloppy-mode assignment on a frozen
    // object) while the identity it built still lists them as linked,
    // an inconsistent (if currently unread — every caller here scopes
    // its own lookups by treeId) overlay. Cloning every person is the
    // robust fix, not "prove it's unreachable today": cheap regardless,
    // given this app's person counts (low hundreds, not millions).
    overlay.persons = (Array.isArray(db.persons) ? db.persons : []).map(
      (entry) => (entry ? {...entry} : entry),
    );
    // Ревью SPEED-11: circleMembers и personIdentities сегодня переприсваиваются
    // перед push (filter → новый массив), но это свойство кода кругов, а не
    // инвариант. Мелкие копии массивов (ссылки на те же записи) закрывают
    // ветку «push в замороженный массив» на будущее — цена копии ничтожна.
    overlay.circleMembers = Array.isArray(db.circleMembers)
      ? [...db.circleMembers]
      : [];
    overlay.personIdentities = Array.isArray(db.personIdentities)
      ? [...db.personIdentities]
      : [];
    if (cache) {
      cache.circleViews.set(treeId, overlay);
    }
    return overlay;
  },

  // SPEED-10: см. _canUserViewCircleContent — `cache` опционален и
  // прокидывается в оба внутренних вызова один-в-один.
  _createCircleVisibilityCache() {
    return {circles: new Map(), identities: new Map()};
  },
};
