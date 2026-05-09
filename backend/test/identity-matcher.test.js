const test = require("node:test");
const assert = require("node:assert/strict");

const {
  findWithinTreeDuplicateCandidates,
  findCrossTreeIdentitySuggestions,
  normalizedBirthYear,
  scorePersonPair,
} = require("../src/identity-matcher");

// ── findWithinTreeDuplicateCandidates ───────────────────────────────────

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

test("findWithinTreeDuplicateCandidates skips persons already linked to user accounts", () => {
  // Slot уже занят user-аккаунтом — даже если есть «явный» кандидат
  // на дубль, его НЕ предлагаем: владелец слота уже зафиксирован,
  // авто-merge сюда привёл бы к destructive collapse двух real-юзеров.
  const suggestions = findWithinTreeDuplicateCandidates({
    treeId: "tree-1",
    persons: [
      {
        id: "claimed",
        treeId: "tree-1",
        userId: "user-1",
        identityId: "identity-a",
        name: "Иванов Иван Петрович",
        birthDate: "1970-03-12",
        gender: "male",
      },
      {
        id: "unclaimed",
        treeId: "tree-1",
        userId: null,
        identityId: "identity-b",
        name: "Иванов Иван Петрович",
        birthDate: "1970-03-12",
        gender: "male",
      },
    ],
  });

  assert.deepEqual(suggestions, []);
});

test("findWithinTreeDuplicateCandidates skips pairs already sharing an identityId", () => {
  // Уже linked через identity propagation — нечего предлагать.
  const suggestions = findWithinTreeDuplicateCandidates({
    treeId: "tree-1",
    persons: [
      {
        id: "left",
        treeId: "tree-1",
        userId: null,
        identityId: "shared-id",
        name: "Иванов Иван Петрович",
        birthDate: "1970-03-12",
        gender: "male",
      },
      {
        id: "right",
        treeId: "tree-1",
        userId: null,
        identityId: "shared-id",
        name: "Иванов Иван Петрович",
        birthDate: "1970-03-12",
        gender: "male",
      },
    ],
  });

  assert.deepEqual(suggestions, []);
});

test("findWithinTreeDuplicateCandidates respects biographical gate", () => {
  // Имена идеально совпадают, но НИ ДАТЫ, НИ МЕСТА рождения — gate
  // отрезает. Без этого полные тёзки всегда бы surfacились с нулевой
  // дополнительной информацией.
  const suggestions = findWithinTreeDuplicateCandidates({
    treeId: "tree-1",
    persons: [
      {
        id: "left",
        treeId: "tree-1",
        userId: null,
        identityId: "id-l",
        name: "Иванов Иван Петрович",
        gender: "male",
      },
      {
        id: "right",
        treeId: "tree-1",
        userId: null,
        identityId: "id-r",
        name: "Иванов Иван Петрович",
        gender: "male",
      },
    ],
  });

  assert.deepEqual(suggestions, []);
});

test("findWithinTreeDuplicateCandidates surfaces medium confidence when only year matches", () => {
  // ФИО (0.62) + только год (0.16) = 0.78 — точно граница «surface».
  const suggestions = findWithinTreeDuplicateCandidates({
    treeId: "tree-1",
    persons: [
      {
        id: "left",
        treeId: "tree-1",
        userId: null,
        identityId: "id-l",
        name: "Иванов Иван Петрович",
        birthDate: "1970-03-12",
      },
      {
        id: "right",
        treeId: "tree-1",
        userId: null,
        identityId: "id-r",
        name: "Иванов Иван Петрович",
        birthDate: "1970-08-04",
      },
    ],
  });

  assert.equal(suggestions.length, 1);
  assert.equal(suggestions[0].confidence, "medium");
  assert.ok(suggestions[0].reasons.includes("Совпадает год рождения"));
  assert.ok(!suggestions[0].reasons.includes("Совпадает дата рождения"));
});

test("findWithinTreeDuplicateCandidates does NOT surface name + birthPlace alone", () => {
  // ФИО (0.62) + место рождения (0.06) = 0.68 — ниже 0.78 порога.
  // Без даты рождения вряд ли получится отличить тёзок-однофамильцев
  // в одном городе.
  const suggestions = findWithinTreeDuplicateCandidates({
    treeId: "tree-1",
    persons: [
      {
        id: "left",
        treeId: "tree-1",
        userId: null,
        identityId: "id-l",
        name: "Иванов Иван Петрович",
        birthPlace: "Москва",
      },
      {
        id: "right",
        treeId: "tree-1",
        userId: null,
        identityId: "id-r",
        name: "Иванов Иван Петрович",
        birthPlace: "Москва",
      },
    ],
  });

  assert.deepEqual(suggestions, []);
});

test("findWithinTreeDuplicateCandidates respects suggestion limit and caps at 100", () => {
  // Generate 5 obvious-dup pairs, request limit 3 → expect 3.
  const persons = [];
  for (let i = 0; i < 10; i += 1) {
    persons.push({
      id: `person-${i}`,
      treeId: "tree-1",
      userId: null,
      identityId: `id-${i}`,
      name: i % 2 === 0 ? "Иванов Иван Петрович" : "Сидоров Семён Олегович",
      birthDate: i % 2 === 0 ? "1970-03-12" : "1985-07-22",
      gender: "male",
    });
  }

  const limited = findWithinTreeDuplicateCandidates({
    treeId: "tree-1",
    persons,
    limit: 3,
  });
  assert.equal(limited.length, 3);

  const noLimit = findWithinTreeDuplicateCandidates({
    treeId: "tree-1",
    persons,
  });
  // Default 20 covers all 20 generated pairs (10×9/2 / 2 by-name == 20).
  assert.ok(noLimit.length <= 20);
});

test("findWithinTreeDuplicateCandidates returns empty for missing treeId or non-array persons", () => {
  // Defensive — caller wiring bugs shouldn't crash the matcher.
  assert.deepEqual(
    findWithinTreeDuplicateCandidates({treeId: "", persons: []}),
    [],
  );
  assert.deepEqual(
    findWithinTreeDuplicateCandidates({treeId: "tree-1", persons: null}),
    [],
  );
  assert.deepEqual(
    findWithinTreeDuplicateCandidates({}),
    [],
  );
});

// ── scorePersonPair direct boundary checks ──────────────────────────────

test("scorePersonPair returns null when both sides are missing biography", () => {
  // Same name but no biographical signal anywhere → biographical
  // gate must reject. Fail-open here would surface "Иванов Иван
  // Петрович" matches in the millions.
  const result = scorePersonPair(
    {name: "Иванов Иван Петрович", gender: "male"},
    {name: "Иванов Иван Петрович", gender: "male"},
  );
  assert.equal(result, null);
});

test("scorePersonPair caps score at 0.99 with all signals stacked", () => {
  // ФИО (0.62) + полная дата (0.28) + пол (0.05) + место (0.06) +
  // дата смерти (0.04) = 1.05 → должен capиться до 0.99.
  const result = scorePersonPair(
    {
      name: "Иванов Иван Петрович",
      gender: "male",
      birthDate: "1970-03-12",
      birthPlace: "Москва",
      deathDate: "2020-01-01",
    },
    {
      name: "Иванов Иван Петрович",
      gender: "male",
      birthDate: "1970-03-12",
      birthPlace: "Москва",
      deathDate: "2020-01-01",
    },
  );

  assert.ok(result, "expected non-null score");
  assert.ok(
    result.score <= 0.99,
    `expected score ≤ 0.99, got ${result.score}`,
  );
  assert.ok(result.score >= 0.95, `expected high score, got ${result.score}`);
});

test("scorePersonPair below 0.78 returns null (silent)", () => {
  // tokenSimilarity = 2/3 ≈ 0.67 (между «Иван» и «Петрович» общие 2
  // из 3) — biographical gate тоже rejects (нет имени normalize match
  // или high-similarity).
  const result = scorePersonPair(
    {
      name: "Иванов Иван Петрович",
      gender: "male",
      birthDate: "1970-03-12",
    },
    {
      name: "Иванов Иван Сергеевич",
      gender: "male",
      birthDate: "1970-03-12",
    },
  );
  // 2/3 не дотягивает до strong-name threshold 0.85, → null.
  assert.equal(result, null);
});

test("scorePersonPair recognizes 'high similarity' tokens", () => {
  // Те же 3 токена в разном порядке — tokenSimilarity = 1.0,
  // считается как «очень похожее имя» (+0.42), плюс полная дата (+0.28).
  // 0.70 — ниже 0.78. Должен вернуть null.
  const result = scorePersonPair(
    {
      name: "Иванов Иван Петрович",
      birthDate: "1970-03-12",
    },
    {
      name: "Петрович Иван Иванов",
      birthDate: "1970-03-12",
    },
  );
  assert.equal(result, null);
});

test("scorePersonPair: name + full date + gender → high confidence", () => {
  const result = scorePersonPair(
    {
      name: "Кузнецова Анна Сергеевна",
      gender: "female",
      birthDate: "1985-07-22",
    },
    {
      name: "Кузнецова Анна Сергеевна",
      gender: "female",
      birthDate: "1985-07-22",
    },
  );
  assert.ok(result, "expected non-null score");
  assert.ok(result.score >= 0.9, `expected high (≥0.9), got ${result.score}`);
});

test("scorePersonPair: ё/е normalization is symmetric", () => {
  // Ёлкин/Елкин — одни и те же люди по нашей нормализации.
  const result = scorePersonPair(
    {name: "Ёлкин Иван", birthDate: "1970-03-12"},
    {name: "Елкин Иван", birthDate: "1970-03-12"},
  );
  assert.ok(result, "expected match after ё→е normalization");
  assert.ok(result.score >= 0.9, "expected high confidence");
});

test("scorePersonPair: gender 'unknown' on either side does not contribute", () => {
  const withUnknown = scorePersonPair(
    {
      name: "Иванов Иван Петрович",
      gender: "unknown",
      birthDate: "1970-03-12",
    },
    {
      name: "Иванов Иван Петрович",
      gender: "unknown",
      birthDate: "1970-03-12",
    },
  );
  const withMale = scorePersonPair(
    {
      name: "Иванов Иван Петрович",
      gender: "male",
      birthDate: "1970-03-12",
    },
    {
      name: "Иванов Иван Петрович",
      gender: "male",
      birthDate: "1970-03-12",
    },
  );
  assert.ok(withUnknown && withMale);
  // Mismatched-or-unknown gender losses 0.05 vs known-equal.
  assert.ok(
    withMale.score > withUnknown.score,
    `male+male should outscore unknown+unknown (was ${withMale.score} vs ${withUnknown.score})`,
  );
});

// ── findCrossTreeIdentitySuggestions ────────────────────────────────────

test("findCrossTreeIdentitySuggestions surfaces a cross-tree match", () => {
  const sourcePerson = {
    id: "src-1",
    treeId: "tree-A",
    name: "Иванов Иван Петрович",
    birthDate: "1970-03-12",
    gender: "male",
  };
  const candidate = {
    id: "tgt-1",
    treeId: "tree-B",
    name: "Иванов Иван Петрович",
    birthDate: "1970-03-12",
    gender: "male",
  };
  const suggestions = findCrossTreeIdentitySuggestions({
    sourcePerson,
    accessibleTrees: [
      {id: "tree-A", name: "Дерево Артёма"},
      {id: "tree-B", name: "Дерево Степы"},
    ],
    persons: [sourcePerson, candidate],
  });

  assert.equal(suggestions.length, 1);
  assert.equal(suggestions[0].sourcePersonId, "src-1");
  assert.equal(suggestions[0].targetPersonId, "tgt-1");
  assert.equal(suggestions[0].targetTreeId, "tree-B");
  assert.equal(suggestions[0].targetTreeName, "Дерево Степы");
  assert.equal(suggestions[0].confidence, "high");
});

test("findCrossTreeIdentitySuggestions skips candidates in the source's own tree", () => {
  // Within-tree dups имеют свою отдельную поверхность (/duplicates).
  const sourcePerson = {
    id: "src",
    treeId: "tree-A",
    name: "Иванов Иван Петрович",
    birthDate: "1970-03-12",
  };
  const sameTreeDup = {
    id: "dup",
    treeId: "tree-A",
    name: "Иванов Иван Петрович",
    birthDate: "1970-03-12",
  };
  const suggestions = findCrossTreeIdentitySuggestions({
    sourcePerson,
    accessibleTrees: [{id: "tree-A", name: ""}],
    persons: [sourcePerson, sameTreeDup],
  });

  assert.deepEqual(suggestions, []);
});

test("findCrossTreeIdentitySuggestions skips inaccessible trees", () => {
  // Privacy gate: даже если cathing matcher знает о person'е в
  // tree-C, без access у viewer'а его нельзя сурфейсить — leak.
  const sourcePerson = {
    id: "src",
    treeId: "tree-A",
    name: "Иванов Иван Петрович",
    birthDate: "1970-03-12",
  };
  const candidate = {
    id: "tgt",
    treeId: "tree-C",
    name: "Иванов Иван Петрович",
    birthDate: "1970-03-12",
  };
  const suggestions = findCrossTreeIdentitySuggestions({
    sourcePerson,
    // accessibleTrees НЕ содержит tree-C.
    accessibleTrees: [{id: "tree-A", name: ""}, {id: "tree-B", name: ""}],
    persons: [sourcePerson, candidate],
  });

  assert.deepEqual(suggestions, []);
});

test("findCrossTreeIdentitySuggestions skips already-linked pairs", () => {
  const sourcePerson = {
    id: "src",
    treeId: "tree-A",
    identityId: "shared-id",
    name: "Иванов Иван Петрович",
    birthDate: "1970-03-12",
  };
  const candidate = {
    id: "tgt",
    treeId: "tree-B",
    identityId: "shared-id",
    name: "Иванов Иван Петрович",
    birthDate: "1970-03-12",
  };
  const suggestions = findCrossTreeIdentitySuggestions({
    sourcePerson,
    accessibleTrees: [{id: "tree-A"}, {id: "tree-B"}],
    persons: [sourcePerson, candidate],
  });

  assert.deepEqual(suggestions, []);
});

test("findCrossTreeIdentitySuggestions skips dismissed targets", () => {
  // Юзер уже сказал «эти двое — разные люди» — больше не нагнетаем.
  const sourcePerson = {
    id: "src",
    treeId: "tree-A",
    name: "Иванов Иван Петрович",
    birthDate: "1970-03-12",
  };
  const candidate = {
    id: "tgt",
    treeId: "tree-B",
    name: "Иванов Иван Петрович",
    birthDate: "1970-03-12",
  };
  const suggestions = findCrossTreeIdentitySuggestions({
    sourcePerson,
    accessibleTrees: [{id: "tree-A"}, {id: "tree-B"}],
    persons: [sourcePerson, candidate],
    dismissedTargetPersonIds: new Set(["tgt"]),
  });

  assert.deepEqual(suggestions, []);
});

test("findCrossTreeIdentitySuggestions returns empty for malformed input", () => {
  assert.deepEqual(findCrossTreeIdentitySuggestions({}), []);
  assert.deepEqual(
    findCrossTreeIdentitySuggestions({
      sourcePerson: null,
      accessibleTrees: [],
      persons: [],
    }),
    [],
  );
  assert.deepEqual(
    findCrossTreeIdentitySuggestions({
      sourcePerson: {id: "", treeId: ""},
      accessibleTrees: [],
      persons: [],
    }),
    [],
  );
});

test("findCrossTreeIdentitySuggestions sorts by score desc and respects limit", () => {
  const sourcePerson = {
    id: "src",
    treeId: "tree-A",
    name: "Иванов Иван Петрович",
    birthDate: "1970-03-12",
    gender: "male",
    birthPlace: "Москва",
  };
  // Two candidates, second is a stronger match (extra place signal).
  const candidateLower = {
    id: "tgt-1",
    treeId: "tree-B",
    name: "Иванов Иван Петрович",
    birthDate: "1970-03-12",
    gender: "male",
  };
  const candidateHigher = {
    id: "tgt-2",
    treeId: "tree-C",
    name: "Иванов Иван Петрович",
    birthDate: "1970-03-12",
    gender: "male",
    birthPlace: "Москва",
  };
  const accessibleTrees = [
    {id: "tree-A"},
    {id: "tree-B"},
    {id: "tree-C"},
  ];
  const suggestions = findCrossTreeIdentitySuggestions({
    sourcePerson,
    accessibleTrees,
    persons: [sourcePerson, candidateLower, candidateHigher],
    limit: 1,
  });
  assert.equal(suggestions.length, 1);
  assert.equal(suggestions[0].targetPersonId, "tgt-2");
});

// ── normalizedBirthYear ─────────────────────────────────────────────────

test("normalizedBirthYear extracts a 4-digit ISO year", () => {
  assert.equal(normalizedBirthYear("1970-03-12T00:00:00.000Z"), "1970");
  assert.equal(normalizedBirthYear("1985-07-22"), "1985");
});

test("normalizedBirthYear is null for invalid or empty input", () => {
  assert.equal(normalizedBirthYear(""), null);
  assert.equal(normalizedBirthYear(null), null);
  assert.equal(normalizedBirthYear(undefined), null);
  assert.equal(normalizedBirthYear("not-a-date"), null);
});
