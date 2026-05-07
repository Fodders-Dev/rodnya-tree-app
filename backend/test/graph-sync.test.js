const test = require("node:test");
const assert = require("node:assert/strict");

const {FileStore, EMPTY_DB} = require("../src/store");

// The sync helpers don't touch the filesystem — they're pure
// functions over the in-memory db object — so we exercise them
// against a stub FileStore instance built from the prototype.
// `_syncGraphFromLegacy` is the aggregator we ultimately wire
// into `_read` and `_write`; calling it directly here lets us
// assert graph-side invariants without spinning up a server.
function makeStoreStub() {
  return Object.create(FileStore.prototype);
}

function freshDb() {
  return structuredClone(EMPTY_DB);
}

test(
  "_syncGraphFromLegacy creates graphPersons + branchPersonViews + branch include rule from a fresh tree",
  () => {
    const store = makeStoreStub();
    const db = freshDb();

    db.trees = [
      {
        id: "tree-a",
        creatorId: "user-1",
        name: "Семья",
        isPrivate: true,
        memberIds: ["user-1"],
        createdAt: "2026-04-01T00:00:00.000Z",
        updatedAt: "2026-04-01T00:00:00.000Z",
      },
    ];
    db.persons = [
      {
        id: "person-mom",
        treeId: "tree-a",
        identityId: "identity-mom",
        name: "Мама Иванова",
        birthDate: "1965-03-12",
        notes: "Хранитель семейных рецептов",
        familySummary: "Глава семьи",
        visibility: "tree",
        creatorId: "user-1",
        createdAt: "2026-04-01T00:00:00.000Z",
        updatedAt: "2026-04-01T00:00:00.000Z",
      },
    ];
    db.personIdentities = [
      {id: "identity-mom", userId: null, personIds: ["person-mom"]},
    ];

    store._syncGraphFromLegacy(db);

    assert.equal(db.branches.length, 1);
    const [branch] = db.branches;
    assert.equal(branch.id, "tree-a");
    assert.equal(branch.legacyTreeId, "tree-a");
    assert.equal(branch.includeRules.type, "manual");
    assert.deepEqual(branch.includeRules.manualPersonIds, ["identity-mom"]);

    assert.equal(db.graphPersons.length, 1);
    const [graphPerson] = db.graphPersons;
    assert.equal(graphPerson.id, "identity-mom");
    assert.equal(graphPerson.name, "Мама Иванова");
    assert.equal(graphPerson.birthDate, "1965-03-12");
    // Editorial fields stay on the per-(branch, person) view —
    // canonical row is "what is this human", not "how does this
    // branch describe them".
    assert.equal(graphPerson.notes, undefined);
    assert.equal(graphPerson.familySummary, undefined);
    assert.deepEqual(graphPerson.legacyPersonIds, ["person-mom"]);
    assert.equal(graphPerson.deletedAt, null);
    assert.equal(graphPerson.contactPrivacy, "owner-only");

    assert.equal(db.branchPersonViews.length, 1);
    const [view] = db.branchPersonViews;
    assert.equal(view.branchId, "tree-a");
    assert.equal(view.personId, "identity-mom");
    assert.equal(view.legacyPersonId, "person-mom");
    assert.equal(view.notes, "Хранитель семейных рецептов");
    assert.equal(view.familySummary, "Глава семьи");
  },
);

test(
  "_syncGraphFromLegacy is idempotent — re-running yields the same graph rows (stable IDs)",
  () => {
    const store = makeStoreStub();
    const db = freshDb();
    db.trees = [{id: "t1", creatorId: "u1", name: "T1"}];
    db.persons = [
      {
        id: "p1",
        treeId: "t1",
        identityId: "i1",
        name: "Тест",
        creatorId: "u1",
      },
    ];
    db.personIdentities = [{id: "i1", personIds: ["p1"]}];

    store._syncGraphFromLegacy(db);
    const firstViewId = db.branchPersonViews[0].id;
    const firstGraphId = db.graphPersons[0].id;

    store._syncGraphFromLegacy(db);
    store._syncGraphFromLegacy(db);

    assert.equal(db.graphPersons.length, 1);
    assert.equal(db.branchPersonViews.length, 1);
    assert.equal(db.branches.length, 1);
    // Stable IDs — re-runs MUST NOT replace rows. Anything else
    // would invalidate references held by other collections.
    assert.equal(db.branchPersonViews[0].id, firstViewId);
    assert.equal(db.graphPersons[0].id, firstGraphId);
  },
);

test(
  "_syncGraphFromLegacy mirrors a canonical-field update from legacy onto the graphPerson",
  () => {
    const store = makeStoreStub();
    const db = freshDb();
    db.trees = [{id: "t1", creatorId: "u1", name: "T1"}];
    db.persons = [
      {
        id: "p1",
        treeId: "t1",
        identityId: "i1",
        name: "Иван Иванов",
        birthPlace: null,
        creatorId: "u1",
      },
    ];
    db.personIdentities = [{id: "i1", personIds: ["p1"]}];

    store._syncGraphFromLegacy(db);
    assert.equal(db.graphPersons[0].name, "Иван Иванов");
    assert.equal(db.graphPersons[0].birthPlace, null);
    assert.equal(db.graphPersons[0].version, 0);

    // Legacy edit — simulate updatePerson rewriting the person.
    db.persons[0].birthPlace = "Тула";
    db.persons[0].name = "Иван Иванович Иванов";
    db.persons[0].updatedAt = "2026-05-01T00:00:00.000Z";

    store._syncGraphFromLegacy(db);

    assert.equal(db.graphPersons[0].name, "Иван Иванович Иванов");
    assert.equal(db.graphPersons[0].birthPlace, "Тула");
    // Version bumps on each canonical-field change so optimistic
    // concurrency in Phase 3.3 has a stable monotonic counter.
    assert.equal(db.graphPersons[0].version, 1);
    assert.equal(db.graphPersons[0].updatedAt, "2026-05-01T00:00:00.000Z");
  },
);

test(
  "_syncGraphFromLegacy mirrors editorial-field updates onto the branchPersonView",
  () => {
    const store = makeStoreStub();
    const db = freshDb();
    db.trees = [{id: "t1", creatorId: "u1", name: "T1"}];
    db.persons = [
      {
        id: "p1",
        treeId: "t1",
        identityId: "i1",
        name: "Иван",
        notes: "Старая заметка",
        creatorId: "u1",
      },
    ];
    db.personIdentities = [{id: "i1", personIds: ["p1"]}];

    store._syncGraphFromLegacy(db);
    assert.equal(db.branchPersonViews[0].notes, "Старая заметка");

    db.persons[0].notes = "Новая заметка";
    db.persons[0].familySummary = "Глава семьи";

    store._syncGraphFromLegacy(db);

    assert.equal(db.branchPersonViews[0].notes, "Новая заметка");
    assert.equal(db.branchPersonViews[0].familySummary, "Глава семьи");
    // Editorial changes do NOT bump graphPerson.version — only
    // canonical fields move the canonical row.
    assert.equal(db.graphPersons[0].version, 0);
  },
);

test(
  "_syncGraphFromLegacy soft-deletes the graphPerson + drops the view + trims branch when the legacy person disappears",
  () => {
    const store = makeStoreStub();
    const db = freshDb();
    db.trees = [{id: "t1", creatorId: "u1", name: "T1"}];
    db.persons = [
      {
        id: "p1",
        treeId: "t1",
        identityId: "i1",
        name: "Test",
        creatorId: "u1",
      },
    ];
    db.personIdentities = [{id: "i1", personIds: ["p1"]}];

    store._syncGraphFromLegacy(db);
    assert.equal(db.graphPersons.length, 1);
    assert.equal(db.graphPersons[0].deletedAt, null);
    assert.deepEqual(
      db.branches[0].includeRules.manualPersonIds,
      ["i1"],
    );

    // Legacy delete — caller has just dropped p1 from db.persons
    // (deletePerson does this). The next sync should soft-delete
    // the graph row + drop the view + trim the branch's rule.
    db.persons = [];
    db.personIdentities = [];

    store._syncGraphFromLegacy(db);

    assert.equal(db.graphPersons.length, 1);
    assert.notEqual(db.graphPersons[0].deletedAt, null);
    assert.equal(db.branchPersonViews.length, 0);
    assert.deepEqual(db.branches[0].includeRules.manualPersonIds, []);
  },
);

test(
  "_syncGraphFromLegacy resurrects a soft-deleted graphPerson when the legacy person comes back",
  () => {
    const store = makeStoreStub();
    const db = freshDb();
    db.trees = [{id: "t1", creatorId: "u1", name: "T1"}];
    db.persons = [
      {id: "p1", treeId: "t1", identityId: "i1", name: "T", creatorId: "u1"},
    ];
    db.personIdentities = [{id: "i1", personIds: ["p1"]}];

    store._syncGraphFromLegacy(db);
    db.persons = [];
    store._syncGraphFromLegacy(db);
    assert.notEqual(db.graphPersons[0].deletedAt, null);

    // Restore — undo of the soft-delete in the 30-day window.
    db.persons = [
      {id: "p1", treeId: "t1", identityId: "i1", name: "T", creatorId: "u1"},
    ];
    db.personIdentities = [{id: "i1", personIds: ["p1"]}];

    store._syncGraphFromLegacy(db);

    assert.equal(db.graphPersons[0].deletedAt, null);
    assert.deepEqual(
      db.branches[0].includeRules.manualPersonIds,
      ["i1"],
    );
  },
);

test(
  "_syncGraphFromLegacy collapses identity-linked legacy persons across two trees onto one graphPerson with both views",
  () => {
    const store = makeStoreStub();
    const db = freshDb();
    db.trees = [
      {id: "t1", creatorId: "u1", name: "T1"},
      {id: "t2", creatorId: "u1", name: "T2"},
    ];
    db.persons = [
      {
        id: "p-mom-on-t1",
        treeId: "t1",
        identityId: "id-mom",
        name: "Мама",
        notes: "Из дерева T1",
        creatorId: "u1",
      },
      {
        id: "p-mom-on-t2",
        treeId: "t2",
        identityId: "id-mom",
        name: "Мама",
        notes: "Из дерева T2",
        creatorId: "u1",
      },
    ];
    db.personIdentities = [
      {id: "id-mom", personIds: ["p-mom-on-t1", "p-mom-on-t2"]},
    ];

    store._syncGraphFromLegacy(db);

    // One canonical row; both legacy ids tracked.
    assert.equal(db.graphPersons.length, 1);
    assert.equal(db.graphPersons[0].id, "id-mom");
    assert.deepEqual(
      [...db.graphPersons[0].legacyPersonIds].sort(),
      ["p-mom-on-t1", "p-mom-on-t2"].sort(),
    );

    // Two views — one per branch — keeping their per-branch
    // editorial annotation isolated.
    assert.equal(db.branchPersonViews.length, 2);
    const viewT1 = db.branchPersonViews.find((v) => v.branchId === "t1");
    const viewT2 = db.branchPersonViews.find((v) => v.branchId === "t2");
    assert.equal(viewT1.notes, "Из дерева T1");
    assert.equal(viewT2.notes, "Из дерева T2");

    // Both branches include the canonical id.
    const branchT1 = db.branches.find((b) => b.id === "t1");
    const branchT2 = db.branches.find((b) => b.id === "t2");
    assert.deepEqual(branchT1.includeRules.manualPersonIds, ["id-mom"]);
    assert.deepEqual(branchT2.includeRules.manualPersonIds, ["id-mom"]);
  },
);

test(
  "_syncGraphFromLegacy dedups relations across trees + soft-deletes when the last legacy edge disappears",
  () => {
    const store = makeStoreStub();
    const db = freshDb();
    db.trees = [
      {id: "t1", creatorId: "u1", name: "T1"},
      {id: "t2", creatorId: "u1", name: "T2"},
    ];
    db.persons = [
      {id: "mom-t1", treeId: "t1", identityId: "id-mom", name: "Мама", creatorId: "u1"},
      {id: "mom-t2", treeId: "t2", identityId: "id-mom", name: "Мама", creatorId: "u1"},
      {id: "kid-t1", treeId: "t1", identityId: "id-kid", name: "Сын", creatorId: "u1"},
      {id: "kid-t2", treeId: "t2", identityId: "id-kid", name: "Сын", creatorId: "u1"},
    ];
    db.personIdentities = [
      {id: "id-mom", personIds: ["mom-t1", "mom-t2"]},
      {id: "id-kid", personIds: ["kid-t1", "kid-t2"]},
    ];
    db.relations = [
      {
        id: "rel-t1",
        treeId: "t1",
        person1Id: "mom-t1",
        person2Id: "kid-t1",
        relation1to2: "parent",
        relation2to1: "child",
      },
      {
        id: "rel-t2",
        treeId: "t2",
        person1Id: "mom-t2",
        person2Id: "kid-t2",
        relation1to2: "parent",
        relation2to1: "child",
      },
    ];

    store._syncGraphFromLegacy(db);

    // Both legacy edges share the same canonical pair → one
    // graphRelation with both rel ids and tree ids tracked.
    assert.equal(db.graphRelations.length, 1);
    const [graphRelation] = db.graphRelations;
    assert.equal(graphRelation.deletedAt, null);
    assert.deepEqual(
      [...graphRelation.legacyRelationIds].sort(),
      ["rel-t1", "rel-t2"].sort(),
    );
    assert.deepEqual(
      [...graphRelation.legacyTreeIds].sort(),
      ["t1", "t2"].sort(),
    );

    // Drop one legacy edge — graphRelation stays alive, only the
    // back-refs shrink.
    db.relations = db.relations.filter((r) => r.id !== "rel-t1");
    store._syncGraphFromLegacy(db);
    assert.equal(db.graphRelations.length, 1);
    assert.equal(db.graphRelations[0].deletedAt, null);
    assert.deepEqual(
      db.graphRelations[0].legacyRelationIds,
      ["rel-t2"],
    );

    // Drop the last legacy edge — graph row gets soft-deleted.
    db.relations = [];
    store._syncGraphFromLegacy(db);
    assert.notEqual(db.graphRelations[0].deletedAt, null);
  },
);

test(
  "_syncGraphFromLegacy is a no-op when called on EMPTY_DB (cold start safety)",
  () => {
    const store = makeStoreStub();
    const db = freshDb();
    store._syncGraphFromLegacy(db);
    assert.equal(db.graphPersons.length, 0);
    assert.equal(db.graphRelations.length, 0);
    assert.equal(db.branches.length, 0);
    assert.equal(db.branchPersonViews.length, 0);
  },
);

// ── Phase 3.1d: graph-first read helper ────────────────────────────

test(
  "_buildPersonViewFromGraph returns a legacy-shape record sourced from graphPerson + branchPersonView",
  () => {
    const store = makeStoreStub();
    const db = freshDb();
    db.trees = [{id: "t1", creatorId: "u1", name: "T1"}];
    db.persons = [
      {
        id: "p1",
        treeId: "t1",
        identityId: "i1",
        firstName: "Иван",
        middleName: "Иванович",
        lastName: "Иванов",
        name: "Иванов Иван Иванович",
        birthDate: "1990-01-01",
        notes: "Старая заметка",
        creatorId: "u1",
      },
    ];
    db.personIdentities = [{id: "i1", personIds: ["p1"]}];
    store._syncGraphFromLegacy(db);

    const view = store._buildPersonViewFromGraph(db, "t1", "p1");
    assert.equal(view.id, "p1");
    assert.equal(view.treeId, "t1");
    assert.equal(view.identityId, "i1");
    assert.equal(view.name, "Иванов Иван Иванович");
    assert.equal(view.birthDate, "1990-01-01");
    // Legacy-only fields stay accessible — needed by writes that
    // recompose `name` from firstName/lastName/middleName.
    assert.equal(view.firstName, "Иван");
    assert.equal(view.lastName, "Иванов");
    // Editorial fields come from branchPersonView.
    assert.equal(view.notes, "Старая заметка");
  },
);

test(
  "_buildPersonViewFromGraph prefers graphPerson canonical fields over the legacy record (graph is source of truth)",
  () => {
    const store = makeStoreStub();
    const db = freshDb();
    db.trees = [{id: "t1", creatorId: "u1", name: "T1"}];
    db.persons = [
      {
        id: "p1",
        treeId: "t1",
        identityId: "i1",
        name: "Старое имя",
        birthDate: "1990-01-01",
        creatorId: "u1",
      },
    ];
    db.personIdentities = [{id: "i1", personIds: ["p1"]}];
    store._syncGraphFromLegacy(db);

    // Simulate graph drift — graphPerson holds a newer canonical
    // value than the legacy record. The helper should return the
    // graph value (the unified-graph migration gives the graph
    // side authority over canonical fields).
    db.graphPersons[0].name = "Новое имя";
    db.graphPersons[0].birthDate = "1995-06-15";

    const view = store._buildPersonViewFromGraph(db, "t1", "p1");
    assert.equal(view.name, "Новое имя");
    assert.equal(view.birthDate, "1995-06-15");
  },
);

test(
  "_buildPersonViewFromGraph prefers branchPersonView editorial fields over the legacy record",
  () => {
    const store = makeStoreStub();
    const db = freshDb();
    db.trees = [{id: "t1", creatorId: "u1", name: "T1"}];
    db.persons = [
      {
        id: "p1",
        treeId: "t1",
        identityId: "i1",
        name: "X",
        notes: "Старая заметка",
        familySummary: "Старое описание",
        creatorId: "u1",
      },
    ];
    db.personIdentities = [{id: "i1", personIds: ["p1"]}];
    store._syncGraphFromLegacy(db);

    // Simulate per-branch editorial drift.
    const view = db.branchPersonViews[0];
    view.notes = "Новая заметка";
    view.familySummary = "Новое описание";

    const result = store._buildPersonViewFromGraph(db, "t1", "p1");
    assert.equal(result.notes, "Новая заметка");
    assert.equal(result.familySummary, "Новое описание");
  },
);

test(
  "_buildPersonViewFromGraph falls back to the legacy record when graph data is missing",
  () => {
    const store = makeStoreStub();
    const db = freshDb();
    db.trees = [{id: "t1", creatorId: "u1", name: "T1"}];
    db.persons = [
      {
        id: "p1",
        treeId: "t1",
        identityId: "i1",
        name: "Иван",
        birthDate: "1990-01-01",
        notes: "Заметка",
        creatorId: "u1",
      },
    ];
    db.personIdentities = [{id: "i1", personIds: ["p1"]}];
    // Deliberately skip the sync — graphPersons / branchPersonViews
    // stay empty. Helper must fall through to the legacy record so
    // existing API behavior survives until the migration ran on a
    // production snapshot.

    const result = store._buildPersonViewFromGraph(db, "t1", "p1");
    assert.equal(result.name, "Иван");
    assert.equal(result.birthDate, "1990-01-01");
    assert.equal(result.notes, "Заметка");
  },
);

test(
  "_buildPersonViewFromGraph returns null when the legacy person isn't on this branch",
  () => {
    const store = makeStoreStub();
    const db = freshDb();
    db.trees = [{id: "t1", creatorId: "u1", name: "T1"}];
    db.persons = [];
    store._syncGraphFromLegacy(db);

    assert.equal(
      store._buildPersonViewFromGraph(db, "t1", "p-missing"),
      null,
    );
  },
);

test(
  "_buildPersonViewFromGraph filters out a soft-deleted graphPerson and falls back to legacy",
  () => {
    const store = makeStoreStub();
    const db = freshDb();
    db.trees = [{id: "t1", creatorId: "u1", name: "T1"}];
    db.persons = [
      {
        id: "p1",
        treeId: "t1",
        identityId: "i1",
        name: "Иван",
        creatorId: "u1",
      },
    ];
    db.personIdentities = [{id: "i1", personIds: ["p1"]}];
    store._syncGraphFromLegacy(db);

    // Soft-delete the graph row. Legacy record is still alive
    // (real deletion would have removed it from db.persons too) —
    // helper must ignore the tombstoned graph row and use legacy.
    db.graphPersons[0].deletedAt = new Date().toISOString();

    const result = store._buildPersonViewFromGraph(db, "t1", "p1");
    assert.equal(result.name, "Иван");
  },
);
