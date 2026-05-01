const test = require("node:test");
const assert = require("node:assert/strict");

const {
  findWithinTreeDuplicateCandidates,
} = require("../src/identity-matcher");

test("findWithinTreeDuplicateCandidates suggests unclaimed duplicates", () => {
  const suggestions = findWithinTreeDuplicateCandidates({
    treeId: "tree-1",
    persons: [
      {
        id: "person-a",
        treeId: "tree-1",
        userId: null,
        identityId: "identity-a",
        name: "Иванов Иван Петрович",
        gender: "male",
        birthDate: "1970-03-12T00:00:00.000Z",
      },
      {
        id: "person-b",
        treeId: "tree-1",
        userId: null,
        identityId: "identity-b",
        name: "Иванов Иван Петрович",
        gender: "male",
        birthDate: "1970-03-12T00:00:00.000Z",
      },
      {
        id: "person-c",
        treeId: "tree-1",
        userId: "user-1",
        identityId: "identity-c",
        name: "Иванов Иван Петрович",
        gender: "male",
        birthDate: "1970-03-12T00:00:00.000Z",
      },
    ],
  });

  assert.equal(suggestions.length, 1);
  assert.equal(suggestions[0].id, "tree-1:person-a:person-b");
  assert.equal(suggestions[0].confidence, "high");
  assert.deepEqual(suggestions[0].reasons, [
    "Совпадает ФИО",
    "Совпадает дата рождения",
    "Совпадает пол",
  ]);
});

test("findWithinTreeDuplicateCandidates ignores weak name-only matches", () => {
  const suggestions = findWithinTreeDuplicateCandidates({
    treeId: "tree-1",
    persons: [
      {
        id: "person-a",
        treeId: "tree-1",
        userId: null,
        identityId: "identity-a",
        name: "Мария Иванова",
        gender: "female",
      },
      {
        id: "person-b",
        treeId: "tree-1",
        userId: null,
        identityId: "identity-b",
        name: "Мария Иванова",
        gender: "female",
      },
    ],
  });

  assert.deepEqual(suggestions, []);
});
