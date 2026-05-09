const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");

const {
  backfillPersonIdentities,
  collectLocalMediaObjects,
  hashSnapshot,
  inferMediaContentType,
  migrateTreesToGraphAndBranches,
  summarizeSnapshot,
} = require("../src/migration-utils");

test("summarizeSnapshot counts known collections and hash is stable", () => {
  const snapshot = {
    users: [{id: "u-1"}],
    personIdentities: [{id: "identity-1"}],
    chats: [{id: "c-1"}, {id: "c-2"}],
    messages: [{id: "m-1"}],
  };

  const summary = summarizeSnapshot(snapshot);
  assert.equal(summary.users, 1);
  assert.equal(summary.personIdentities, 1);
  assert.equal(summary.chats, 2);
  assert.equal(summary.messages, 1);
  assert.equal(summary.notifications, 0);
  assert.equal(hashSnapshot(snapshot), hashSnapshot({...snapshot}));
});

test("backfillPersonIdentities creates stable identities for legacy persons", () => {
  const ids = ["identity-a", "identity-b"];
  const snapshot = {
    persons: [
      {id: "person-1", treeId: "tree-1", identityId: null},
      {id: "person-2", treeId: "tree-1"},
    ],
    personIdentities: [],
  };

  const migration = backfillPersonIdentities(snapshot, {
    idFactory: () => ids.shift(),
    now: () => "2026-04-29T00:00:00.000Z",
  });

  assert.equal(migration.changed, true);
  assert.deepEqual(
    snapshot.persons.map((person) => person.identityId),
    ["identity-a", "identity-b"],
  );
  assert.deepEqual(snapshot.personIdentities, [
    {
      id: "identity-a",
      userId: null,
      personIds: ["person-1"],
      createdAt: "2026-04-29T00:00:00.000Z",
      updatedAt: "2026-04-29T00:00:00.000Z",
    },
    {
      id: "identity-b",
      userId: null,
      personIds: ["person-2"],
      createdAt: "2026-04-29T00:00:00.000Z",
      updatedAt: "2026-04-29T00:00:00.000Z",
    },
  ]);

  const secondRun = backfillPersonIdentities(snapshot, {
    idFactory: () => {
      throw new Error("idFactory should not be called");
    },
    now: () => "2026-04-29T01:00:00.000Z",
  });
  assert.equal(secondRun.changed, false);
  assert.equal(snapshot.personIdentities.length, 2);
});

test("backfillPersonIdentities preserves existing identity ids", () => {
  const snapshot = {
    persons: [{id: "person-1", treeId: "tree-1", identityId: "identity-existing"}],
    personIdentities: [],
  };

  const migration = backfillPersonIdentities(snapshot, {
    idFactory: () => "identity-new",
    now: () => "2026-04-29T00:00:00.000Z",
  });

  assert.equal(migration.changed, true);
  assert.equal(snapshot.persons[0].identityId, "identity-existing");
  assert.deepEqual(snapshot.personIdentities[0], {
    id: "identity-existing",
    userId: null,
    personIds: ["person-1"],
    createdAt: "2026-04-29T00:00:00.000Z",
    updatedAt: "2026-04-29T00:00:00.000Z",
  });
});

test("inferMediaContentType covers common media extensions", () => {
  assert.equal(inferMediaContentType("photo.JPG"), "image/jpeg");
  assert.equal(inferMediaContentType("clip.mp4"), "video/mp4");
  assert.equal(inferMediaContentType("voice.ogg"), "audio/ogg");
  assert.equal(inferMediaContentType("unknown.bin"), "application/octet-stream");
});

// ── Phase 3.1 trees → graph + branches migration tests ──────────────

// Helper used by the first migrate test to look up the orphan
// graphPerson id without depending on uuid output. Hoisted up
// here so all test() registrations stay in a contiguous block —
// node:test had a regression where helper declarations between
// test() calls interfered with discovery in some setups.
function expectedOrphanGraphId(snapshot) {
  const orphan = snapshot.graphPersons.find(
    (g) => g.id !== "identity-mom",
  );
  return orphan ? orphan.id : null;
}

test(
  "migrateTreesToGraphAndBranches collapses identity-linked persons to one graphPerson and trees to branches",
  () => {
    const ids = [
      "branch-view-1",
      "branch-view-2",
      "branch-view-3",
      "branch-view-4",
    ];
    const snapshot = {
      personIdentities: [
        {
          id: "identity-mom",
          userId: null,
          personIds: ["person-mom-tree-a", "person-mom-tree-b"],
        },
      ],
      // Two persons sharing the same identity — same human entered
      // on two different trees via the Phase 0 cross-tree picker.
      persons: [
        {
          id: "person-mom-tree-a",
          treeId: "tree-a",
          identityId: "identity-mom",
          name: "Мать Иванова",
          birthDate: "1965-03-12",
          birthPlace: "Тула",
          familySummary: "Глава семьи",
          notes: "Любит сад",
          visibility: "tree",
          isAlive: true,
          createdAt: "2026-04-01T00:00:00.000Z",
          updatedAt: "2026-04-15T00:00:00.000Z",
          creatorId: "user-1",
          userId: null,
        },
        {
          id: "person-mom-tree-b",
          treeId: "tree-b",
          identityId: "identity-mom",
          name: "Мать Иванова",
          birthDate: "1965-03-12",
          birthPlace: "Тула",
          // Tree-B's editor's note must end up in branchPersonViews,
          // NOT on the canonical graph row.
          familySummary: "Бабушкина дочь",
          notes: "Тётины истории про маму",
          visibility: "tree",
          isAlive: true,
          createdAt: "2026-04-02T00:00:00.000Z",
          updatedAt: "2026-04-10T00:00:00.000Z",
          creatorId: "user-1",
          userId: null,
        },
        // Person without an identity row at all — should still
        // produce a graphPerson 1:1.
        {
          id: "person-orphan",
          treeId: "tree-a",
          identityId: null,
          name: "Сирота",
          isAlive: true,
          createdAt: "2026-04-03T00:00:00.000Z",
          updatedAt: "2026-04-03T00:00:00.000Z",
          creatorId: "user-1",
        },
      ],
      relations: [
        // Same human pair appears on both trees — must dedup.
        {
          id: "rel-tree-a",
          treeId: "tree-a",
          person1Id: "person-mom-tree-a",
          person2Id: "person-orphan",
          relation1to2: "parent",
          relation2to1: "child",
          isConfirmed: true,
          createdBy: "user-1",
          createdAt: "2026-04-04T00:00:00.000Z",
          updatedAt: "2026-04-04T00:00:00.000Z",
        },
        // Hypothetical second copy on a third tree — wouldn't
        // exist for "person-orphan" (only on tree-a), so skip.
      ],
      trees: [
        {
          id: "tree-a",
          creatorId: "user-1",
          name: "Семья (моя)",
          isPrivate: true,
          memberIds: ["user-1"],
          createdAt: "2026-04-01T00:00:00.000Z",
          updatedAt: "2026-04-15T00:00:00.000Z",
        },
        {
          id: "tree-b",
          creatorId: "user-1",
          name: "Родня (мамина)",
          isPrivate: true,
          memberIds: ["user-1"],
          createdAt: "2026-04-02T00:00:00.000Z",
          updatedAt: "2026-04-10T00:00:00.000Z",
        },
      ],
      posts: [
        {
          id: "post-1",
          treeId: "tree-a",
          authorId: "user-1",
          content: "Семейный пост",
          createdAt: "2026-04-05T00:00:00.000Z",
        },
      ],
    };

    const result = migrateTreesToGraphAndBranches(snapshot, {
      idFactory: () => ids.shift(),
      now: () => "2026-05-07T00:00:00.000Z",
    });

    assert.equal(result.changed, true);
    assert.deepEqual(result.summary, {
      legacyPersonCount: 3,
      graphPersonCount: 2, // mom (merged) + orphan
      legacyRelationCount: 1,
      graphRelationCount: 1,
      branchCount: 2,
      branchPersonViewCount: 3, // 2 mom-views (one per tree) + 1 orphan-view
    });

    // graphPerson reuses the identityId so existing references stay valid.
    const momGraph = snapshot.graphPersons.find((g) => g.id === "identity-mom");
    assert.ok(momGraph, "mom graphPerson keyed on identityId");
    assert.equal(momGraph.name, "Мать Иванова");
    assert.equal(momGraph.birthDate, "1965-03-12");
    assert.equal(momGraph.birthPlace, "Тула");
    // Editorial fields must NOT leak onto the canonical graph row.
    assert.equal(momGraph.familySummary, undefined);
    assert.equal(momGraph.notes, undefined);
    // Back-trace to all legacy persons that fed into this row.
    assert.deepEqual(
      [...momGraph.legacyPersonIds].sort(),
      ["person-mom-tree-a", "person-mom-tree-b"].sort(),
    );
    // Versioning hook for Phase 3.3 owner-model.
    assert.equal(momGraph.version, 0);
    assert.equal(momGraph.deletedAt, null);
    assert.equal(momGraph.contactPrivacy, "owner-only");

    // Branches reuse legacy treeIds → /v1/trees/:treeId routes
    // can still resolve via id lookup in 3.1c.
    const branchA = snapshot.branches.find((b) => b.id === "tree-a");
    assert.ok(branchA);
    assert.equal(branchA.legacyTreeId, "tree-a");
    assert.equal(branchA.includeRules.type, "manual");
    // Both mom and orphan are on tree-a → both in branch-a's manual rule.
    assert.deepEqual(
      [...branchA.includeRules.manualPersonIds].sort(),
      ["identity-mom", expectedOrphanGraphId(snapshot)].sort(),
    );

    // Relations dedup: same canonical pair (mom + orphan) appears
    // once even if multiple trees contained the legacy edge.
    const dedupRelation = snapshot.graphRelations[0];
    assert.equal(dedupRelation.legacyRelationIds.length, 1);
    assert.equal(dedupRelation.legacyTreeIds[0], "tree-a");
    assert.equal(dedupRelation.person1Id, "identity-mom");
    assert.equal(
      dedupRelation.person2Id,
      expectedOrphanGraphId(snapshot),
    );

    // branchPersonViews carry the per-tree editorial annotations.
    const momViewOnB = snapshot.branchPersonViews.find(
      (v) => v.legacyPersonId === "person-mom-tree-b",
    );
    assert.ok(momViewOnB);
    assert.equal(momViewOnB.familySummary, "Бабушкина дочь");
    assert.equal(momViewOnB.notes, "Тётины истории про маму");
    assert.equal(momViewOnB.personId, "identity-mom");
    assert.equal(momViewOnB.branchId, "tree-b");

    // Post got back-compat branchIds stamp pointing at the matching
    // branch (= legacy tree id, since we reuse it).
    assert.deepEqual(snapshot.posts[0].branchIds, ["tree-a"]);

    // Migration ledger so the next read won't redo the work.
    assert.equal(snapshot.migrationStatus.treesToGraph, "complete");
    assert.equal(
      snapshot.migrationStatus.treesToGraphAt,
      "2026-05-07T00:00:00.000Z",
    );

    // ── Idempotency: second run is a no-op. ──
    const secondRun = migrateTreesToGraphAndBranches(snapshot, {
      idFactory: () => {
        throw new Error("idFactory must NOT be called on a re-run");
      },
      now: () => {
        throw new Error("now must NOT be called on a re-run");
      },
    });
    assert.equal(secondRun.changed, false);
    assert.equal(secondRun.summary, null);
    assert.equal(snapshot.graphPersons.length, 2);
    assert.equal(snapshot.branches.length, 2);
  },
);

test(
  "migrateTreesToGraphAndBranches dedups relations across trees that share a canonical pair",
  () => {
    const snapshot = {
      personIdentities: [
        {id: "id-mom", userId: null, personIds: ["mom-a", "mom-b"]},
        {id: "id-kid", userId: null, personIds: ["kid-a", "kid-b"]},
      ],
      persons: [
        {id: "mom-a", treeId: "t1", identityId: "id-mom", name: "Mom"},
        {id: "mom-b", treeId: "t2", identityId: "id-mom", name: "Mom"},
        {id: "kid-a", treeId: "t1", identityId: "id-kid", name: "Kid"},
        {id: "kid-b", treeId: "t2", identityId: "id-kid", name: "Kid"},
      ],
      relations: [
        // Same canonical pair (mom, kid) on tree-1 AND tree-2.
        // Must collapse to a single graphRelation with both legacy
        // ids and treeIds in the back-references.
        {
          id: "rel-1",
          treeId: "t1",
          person1Id: "mom-a",
          person2Id: "kid-a",
          relation1to2: "parent",
          relation2to1: "child",
        },
        {
          id: "rel-2",
          treeId: "t2",
          person1Id: "mom-b",
          person2Id: "kid-b",
          relation1to2: "parent",
          relation2to1: "child",
        },
      ],
      trees: [
        {id: "t1", creatorId: "u1", name: "T1"},
        {id: "t2", creatorId: "u1", name: "T2"},
      ],
    };

    const result = migrateTreesToGraphAndBranches(snapshot);
    assert.equal(result.changed, true);
    assert.equal(snapshot.graphRelations.length, 1);
    assert.deepEqual(
      [...snapshot.graphRelations[0].legacyRelationIds].sort(),
      ["rel-1", "rel-2"].sort(),
    );
    assert.deepEqual(
      [...snapshot.graphRelations[0].legacyTreeIds].sort(),
      ["t1", "t2"].sort(),
    );
  },
);

test(
  "migrateTreesToGraphAndBranches drops orphan relations whose persons are gone",
  () => {
    const snapshot = {
      personIdentities: [],
      persons: [
        {id: "p1", treeId: "t1", identityId: null, name: "A"},
      ],
      relations: [
        // p2 doesn't exist — orphan edge must be dropped silently.
        {
          id: "rel-orphan",
          treeId: "t1",
          person1Id: "p1",
          person2Id: "p-missing",
          relation1to2: "parent",
          relation2to1: "child",
        },
      ],
      trees: [{id: "t1", creatorId: "u1", name: "T1"}],
    };

    migrateTreesToGraphAndBranches(snapshot);
    assert.equal(snapshot.graphRelations.length, 0);
    assert.equal(snapshot.graphPersons.length, 1);
  },
);

test(
  "migrateTreesToGraphAndBranches preserves existing branchIds on posts",
  () => {
    const snapshot = {
      personIdentities: [],
      persons: [],
      relations: [],
      trees: [{id: "t1", creatorId: "u1", name: "T1"}],
      posts: [
        {id: "p-existing", branchIds: ["custom-branch"], treeId: "t1"},
        {id: "p-fresh", treeId: "t1"},
      ],
    };

    migrateTreesToGraphAndBranches(snapshot);
    // Existing branchIds untouched — we never overwrite a deliberate
    // assignment from a future write path.
    assert.deepEqual(snapshot.posts[0].branchIds, ["custom-branch"]);
    // Posts that came from the legacy treeId-only path get the
    // back-compat stamp pointing at the matching branch.
    assert.deepEqual(snapshot.posts[1].branchIds, ["t1"]);
  },
);

test(
  "migrateTreesToGraphAndBranches renames tree.creatorId → branch.ownerId",
  () => {
    // Phase 5 RFC ритуал: «creatorId» — устаревший термин, branches
    // должны открываться полем «ownerId». Проверка явная — потому
    // что rename легко потерять при одном неудачном merge.
    const snapshot = {
      personIdentities: [],
      persons: [],
      relations: [],
      trees: [{id: "t1", creatorId: "user-owner", name: "Семья"}],
    };
    migrateTreesToGraphAndBranches(snapshot);
    assert.equal(snapshot.branches[0].ownerId, "user-owner");
    assert.equal(snapshot.branches[0].legacyTreeId, "t1");
  },
);

test(
  "migrateTreesToGraphAndBranches mirrors tree.memberIds onto branch.memberIds",
  () => {
    const snapshot = {
      personIdentities: [],
      persons: [],
      relations: [],
      trees: [
        {
          id: "t1",
          creatorId: "u1",
          name: "T1",
          memberIds: ["u1", "u2", "u3"],
        },
      ],
    };
    migrateTreesToGraphAndBranches(snapshot);
    assert.deepEqual(snapshot.branches[0].memberIds, ["u1", "u2", "u3"]);
  },
);

test(
  "migrateTreesToGraphAndBranches falls back from missing memberIds to legacy 'members' alias",
  () => {
    // Очень старые snapshot'ы держали `members` (без Ids суффикса) —
    // back-compat fallback нужно явно зафиксировать тестом, чтобы
    // случайный refactor его не сломал.
    const snapshot = {
      personIdentities: [],
      persons: [],
      relations: [],
      trees: [
        {id: "t1", creatorId: "u1", name: "T1", members: ["u1", "u2"]},
      ],
    };
    migrateTreesToGraphAndBranches(snapshot);
    assert.deepEqual(snapshot.branches[0].memberIds, ["u1", "u2"]);
  },
);

test(
  "migrateTreesToGraphAndBranches preserves publicSlug, isCertified, certificationNote",
  () => {
    const snapshot = {
      personIdentities: [],
      persons: [],
      relations: [],
      trees: [
        {
          id: "t1",
          creatorId: "u1",
          name: "T1",
          publicSlug: "my-public-tree",
          isCertified: true,
          certificationNote: "Verified by archive",
          isPrivate: false,
          kind: "family",
          description: "Описание",
        },
      ],
    };
    migrateTreesToGraphAndBranches(snapshot);
    const branch = snapshot.branches[0];
    assert.equal(branch.publicSlug, "my-public-tree");
    assert.equal(branch.isCertified, true);
    assert.equal(branch.certificationNote, "Verified by archive");
    assert.equal(branch.isPrivate, false);
    assert.equal(branch.kind, "family");
    assert.equal(branch.description, "Описание");
  },
);

test(
  "migrateTreesToGraphAndBranches picks the user-claimed person as canonical",
  () => {
    // Identity ↔ user — это «настоящий человек» владеет этим
    // graphPerson'ом. Если оба linked-person'а на разных деревьях, но
    // один из них = user, в graphPerson едут поля user-record'а.
    const snapshot = {
      personIdentities: [
        {
          id: "id-self",
          userId: "u-self",
          personIds: ["self-tree-a", "self-tree-b"],
        },
      ],
      persons: [
        {
          id: "self-tree-a",
          treeId: "tree-a",
          identityId: "id-self",
          userId: "u-self",
          name: "Я (canonical)",
          birthDate: "1990-01-01",
          createdAt: "2026-04-01T00:00:00.000Z",
          updatedAt: "2026-04-15T00:00:00.000Z",
        },
        {
          id: "self-tree-b",
          treeId: "tree-b",
          identityId: "id-self",
          userId: null,
          name: "Я (чужие глазами)",
          birthDate: "1990-01-01",
          // Note: more recently updated than self-tree-a, but should
          // NOT win — claimed user record always beats updatedAt.
          createdAt: "2026-04-02T00:00:00.000Z",
          updatedAt: "2026-04-30T00:00:00.000Z",
        },
      ],
      relations: [],
      trees: [
        {id: "tree-a", creatorId: "u-self", name: "A"},
        {id: "tree-b", creatorId: "u-self", name: "B"},
      ],
    };
    migrateTreesToGraphAndBranches(snapshot);
    const graphPerson = snapshot.graphPersons.find(
      (g) => g.id === "id-self",
    );
    assert.equal(graphPerson.name, "Я (canonical)");
    assert.equal(graphPerson.userId, "u-self");
  },
);

test(
  "migrateTreesToGraphAndBranches falls back to most-recently-updated person without claim",
  () => {
    const snapshot = {
      personIdentities: [
        {
          id: "id-mom",
          userId: null,
          personIds: ["mom-tree-a", "mom-tree-b"],
        },
      ],
      persons: [
        {
          id: "mom-tree-a",
          treeId: "tree-a",
          identityId: "id-mom",
          name: "Мама (старая запись)",
          updatedAt: "2026-04-15T00:00:00.000Z",
        },
        {
          id: "mom-tree-b",
          treeId: "tree-b",
          identityId: "id-mom",
          name: "Мама (свежая запись)",
          updatedAt: "2026-04-30T00:00:00.000Z",
        },
      ],
      relations: [],
      trees: [
        {id: "tree-a", creatorId: "u1", name: "A"},
        {id: "tree-b", creatorId: "u1", name: "B"},
      ],
    };
    migrateTreesToGraphAndBranches(snapshot);
    const momGraph = snapshot.graphPersons.find((g) => g.id === "id-mom");
    assert.equal(momGraph.name, "Мама (свежая запись)");
  },
);

test(
  "migrateTreesToGraphAndBranches handles an empty snapshot without crashing",
  () => {
    const snapshot = {};
    const result = migrateTreesToGraphAndBranches(snapshot, {
      now: () => "2026-05-09T00:00:00.000Z",
    });
    assert.equal(result.changed, true);
    assert.deepEqual(snapshot.graphPersons, []);
    assert.deepEqual(snapshot.graphRelations, []);
    assert.deepEqual(snapshot.branches, []);
    assert.deepEqual(snapshot.branchPersonViews, []);
    assert.equal(snapshot.migrationStatus.treesToGraph, "complete");
  },
);

test(
  "migrateTreesToGraphAndBranches treats non-snapshot input safely",
  () => {
    // Defensive: null/undefined/scalar must not crash; should
    // return a minimally-populated snapshot.
    const result = migrateTreesToGraphAndBranches(null);
    assert.equal(result.changed, true);
    assert.deepEqual(result.snapshot.graphPersons, []);
    assert.equal(result.snapshot.migrationStatus.treesToGraph, "complete");
  },
);

test(
  "migrateTreesToGraphAndBranches preserves graphPerson canonical fields after sync",
  () => {
    const snapshot = {
      personIdentities: [
        {id: "id-x", personIds: ["px"]},
      ],
      persons: [
        {
          id: "px",
          treeId: "t1",
          identityId: "id-x",
          name: "X",
          birthDate: "1980-01-01",
          deathDate: "2050-12-31",
          isAlive: false,
          birthPlace: "СПб",
          deathPlace: "Москва",
          photoUrl: "https://example.com/x.jpg",
          primaryPhotoUrl: "https://example.com/x-primary.jpg",
          photoGallery: [
            {url: "https://example.com/g1.jpg"},
            {url: "https://example.com/g2.jpg"},
          ],
          maidenName: "Y",
          gender: "female",
          // Editorial — not on graph, должны попасть в branchPersonView.
          notes: "редкая запись",
          familySummary: "семейная сводка",
          bio: "биография",
          visibility: "tree",
        },
      ],
      relations: [],
      trees: [{id: "t1", creatorId: "u1", name: "T1"}],
    };
    migrateTreesToGraphAndBranches(snapshot);
    const graph = snapshot.graphPersons.find((g) => g.id === "id-x");
    assert.equal(graph.name, "X");
    assert.equal(graph.birthDate, "1980-01-01");
    assert.equal(graph.deathDate, "2050-12-31");
    assert.equal(graph.isAlive, false);
    assert.equal(graph.birthPlace, "СПб");
    assert.equal(graph.deathPlace, "Москва");
    assert.equal(graph.photoUrl, "https://example.com/x.jpg");
    assert.equal(graph.primaryPhotoUrl, "https://example.com/x-primary.jpg");
    assert.equal(graph.maidenName, "Y");
    assert.equal(graph.gender, "female");
    assert.deepEqual(graph.photoGallery, [
      {url: "https://example.com/g1.jpg"},
      {url: "https://example.com/g2.jpg"},
    ]);
    // Editorial fields — НЕ на graphPerson row, а на branchPersonView.
    assert.equal(graph.notes, undefined);
    assert.equal(graph.familySummary, undefined);
    assert.equal(graph.bio, undefined);
    assert.equal(graph.visibility, undefined);

    const view = snapshot.branchPersonViews.find(
      (v) => v.legacyPersonId === "px",
    );
    assert.equal(view.notes, "редкая запись");
    assert.equal(view.familySummary, "семейная сводка");
    assert.equal(view.bio, "биография");
    assert.equal(view.visibility, "tree");
  },
);

test("collectLocalMediaObjects maps bucket-relative media layout", async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-media-"));
  const imagePath = path.join(tempDir, "chat", "2026", "photo.jpg");
  const audioPath = path.join(tempDir, "voice", "note.ogg");

  await fs.mkdir(path.dirname(imagePath), {recursive: true});
  await fs.mkdir(path.dirname(audioPath), {recursive: true});
  await fs.writeFile(imagePath, Buffer.from("jpeg"));
  await fs.writeFile(audioPath, Buffer.from("ogg"));

  const result = await collectLocalMediaObjects(tempDir);
  const normalized = result
    .map((entry) => `${entry.bucket}/${entry.relativePath}`)
    .sort((left, right) => left.localeCompare(right));

  assert.deepEqual(normalized, ["chat/2026/photo.jpg", "voice/note.ogg"]);
});
