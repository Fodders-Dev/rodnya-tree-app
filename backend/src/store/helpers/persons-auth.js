const path = require("node:path");
const crypto = require("node:crypto");
const {
  normalizedBirthYear,
} = require("../../identity-matcher");
const {
  PERSON_ATTRIBUTE_FIELDS,
  PERSON_VISIBILITIES,
  PROFILE_CONTRIBUTION_POLICIES,
  PROFILE_SUGGESTION_FIELDS,
  SUPPORTED_AUTH_PROVIDERS,
} = require("../constants");
const {
  normalizeNullableString,
  normalizeOptionalIsoTimestamp,
  normalizeParticipantIds,
  nowIso,
} = require("./utils");

function fullNameFromPersonInput(person = {}) {
  const parts = [person.lastName, person.firstName, person.middleName]
    .map((value) => String(value || "").trim())
    .filter(Boolean);

  if (parts.length > 0) {
    return parts.join(" ");
  }

  return String(person.name || "").trim();
}

function composeDisplayNameFromProfile(profile = {}) {
  return fullNameFromPersonInput({
    firstName: profile.firstName,
    lastName: profile.lastName,
    middleName: profile.middleName,
    name: profile.displayName,
  });
}

function defaultPersonVisibility({deathDate = null, isAlive = true} = {}) {
  if (normalizeNullableString(deathDate) || isAlive === false) {
    return "tree";
  }
  return "private";
}

function normalizePersonVisibility(value, fallback = "private") {
  const normalized = String(value || "").trim().toLowerCase();
  if (PERSON_VISIBILITIES.has(normalized)) {
    return normalized;
  }
  return PERSON_VISIBILITIES.has(fallback) ? fallback : "private";
}

function defaultAttributeVisibility(field, person = {}) {
  const personDefault = normalizePersonVisibility(
    person.visibility,
    defaultPersonVisibility(person),
  );
  if (field === "contacts") {
    return "private";
  }
  if (personDefault === "public" || personDefault === "cross-tree") {
    return field === "name" || field === "birthYear" || field === "relations"
      ? "cross-tree"
      : "tree";
  }
  return personDefault;
}

function extractBirthYear(value) {
  const normalized = normalizeIsoDate(value);
  return normalized ? normalized.slice(0, 4) : null;
}

function safeMergePersonPreview(person, {contextLabel = null, ownership = "other"} = {}) {
  return {
    name: String(person?.name || "Без имени").trim() || "Без имени",
    birthYear: normalizedBirthYear(person?.birthDate),
    contextLabel: normalizeNullableString(contextLabel),
    // A-copy: чья это карточка — для бейджа «Ваша / Общая / Карточка
    // <имя>», чтобы зритель видел, что ничего чужого не поглощается.
    ownership: ownership === "own" || ownership === "shared" ? ownership : "other",
  };
}

function personStewardUserIds(db, person) {
  const tree = db.trees.find((entry) => entry.id === person?.treeId);
  return normalizeParticipantIds([
    person?.userId,
    person?.creatorId,
    tree?.creatorId,
  ]);
}

function identityStewardUserIds(db, identity = {}) {
  const personIds = normalizeParticipantIds(identity.personIds);
  const stewards = [
    identity.claimedByUserId,
    identity.userId,
    ...(Array.isArray(identity.stewardUserIds) ? identity.stewardUserIds : []),
  ];
  for (const personId of personIds) {
    const person = db.persons.find((entry) => entry.id === personId);
    stewards.push(...personStewardUserIds(db, person));
  }
  return normalizeParticipantIds(stewards);
}

function normalizeProfileContributionPolicy(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return PROFILE_CONTRIBUTION_POLICIES.has(normalized)
    ? normalized
    : "suggestions";
}

function normalizePrimaryTrustedChannel(value) {
  const normalized = normalizeAuthProvider(value);
  if (
    normalized === "google" ||
    normalized === "telegram" ||
    normalized === "vk" ||
    normalized === "max"
  ) {
    return normalized;
  }
  return null;
}

function resolvePersonFamilySummary(person = {}) {
  return (
    normalizeNullableString(person.familySummary) ||
    normalizeNullableString(person.notes) ||
    normalizeNullableString(person.bio)
  );
}

function normalizeProfileContributionFields(fields = {}) {
  if (!fields || typeof fields !== "object" || Array.isArray(fields)) {
    return {};
  }

  const normalized = {};
  for (const fieldName of PROFILE_SUGGESTION_FIELDS) {
    if (!Object.prototype.hasOwnProperty.call(fields, fieldName)) {
      continue;
    }

    switch (fieldName) {
      case "birthDate":
        normalized[fieldName] = normalizeIsoDate(fields[fieldName]);
        break;
      case "photoUrl":
        normalized[fieldName] = normalizeNullableString(fields[fieldName]);
        break;
      default:
        normalized[fieldName] = normalizeNullableString(fields[fieldName]) || "";
        break;
    }
  }

  return normalized;
}

function normalizeCountryDialCode(value) {
  const digits = String(value || "").replace(/\D+/g, "");
  return digits ? `+${digits}` : null;
}

function normalizePhoneNumber(value, countryCode = null) {
  const rawValue = String(value || "").trim();
  if (!rawValue) {
    return null;
  }

  const hasLeadingPlus = rawValue.startsWith("+");
  let digits = rawValue.replace(/\D+/g, "");
  if (!digits) {
    return null;
  }

  const normalizedCountryCode = normalizeCountryDialCode(countryCode);
  const countryDigits = normalizedCountryCode
    ? normalizedCountryCode.replace(/\D+/g, "")
    : "";

  if (hasLeadingPlus) {
    return `+${digits}`;
  }

  if (digits.length === 11 && digits.startsWith("8")) {
    digits = `7${digits.slice(1)}`;
  }

  if (digits.length === 10 && countryDigits) {
    digits = `${countryDigits}${digits}`;
  }

  if (digits.length <= 6) {
    return null;
  }

  return `+${digits}`;
}

function normalizeAuthProvider(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return SUPPORTED_AUTH_PROVIDERS.has(normalized) ? normalized : null;
}

function createPasswordAuthIdentity(email, timestamp = nowIso()) {
  const normalizedEmail = normalizeNullableString(email)?.toLowerCase();
  if (!normalizedEmail) {
    return null;
  }

  return {
    provider: "password",
    providerUserId: normalizedEmail,
    linkedAt: timestamp,
    lastUsedAt: timestamp,
    email: normalizedEmail,
    phoneNumber: null,
    normalizedPhoneNumber: null,
    displayName: null,
    metadata: {},
  };
}

function createAuthHandoffRecord({
  type,
  payload = {},
  userId = null,
  expiresAt = null,
}) {
  const createdAt = nowIso();
  const normalizedExpiresAt =
    normalizeOptionalIsoTimestamp(expiresAt) ||
    new Date(Date.now() + 10 * 60 * 1000).toISOString();
  return {
    code: crypto.randomBytes(24).toString("hex"),
    type: normalizeNullableString(type),
    userId: normalizeNullableString(userId),
    payload:
      payload && typeof payload === "object" ? structuredClone(payload) : {},
    createdAt,
    expiresAt: normalizedExpiresAt,
  };
}

function normalizeAuthIdentityRecord(identity) {
  const provider = normalizeAuthProvider(identity?.provider);
  const rawProviderUserId = String(identity?.providerUserId || "").trim();
  if (!provider || !rawProviderUserId) {
    return null;
  }

  const normalizedEmail = normalizeNullableString(identity?.email)?.toLowerCase();
  const phoneNumber = normalizeNullableString(identity?.phoneNumber);
  const normalizedPhoneNumber = normalizePhoneNumber(
    identity?.normalizedPhoneNumber || phoneNumber,
  );
  const providerUserId =
    provider === "password" && normalizedEmail
      ? normalizedEmail
      : rawProviderUserId;

  return {
    provider,
    providerUserId,
    linkedAt: normalizeOptionalIsoTimestamp(identity?.linkedAt) || nowIso(),
    lastUsedAt: normalizeOptionalIsoTimestamp(identity?.lastUsedAt),
    email: normalizedEmail,
    phoneNumber,
    normalizedPhoneNumber,
    displayName: normalizeNullableString(identity?.displayName),
    metadata:
      identity?.metadata && typeof identity.metadata === "object"
        ? structuredClone(identity.metadata)
        : {},
  };
}

function listAuthIdentitiesForUser(user) {
  const identities = [];
  const seenKeys = new Set();

  const addIdentity = (identity) => {
    const normalizedIdentity = normalizeAuthIdentityRecord(identity);
    if (!normalizedIdentity) {
      return;
    }

    const identityKey =
      `${normalizedIdentity.provider}:${normalizedIdentity.providerUserId}`;
    if (seenKeys.has(identityKey)) {
      return;
    }

    seenKeys.add(identityKey);
    identities.push(normalizedIdentity);
  };

  if (Array.isArray(user?.authIdentities)) {
    for (const identity of user.authIdentities) {
      addIdentity(identity);
    }
  }

  if (user?.passwordHash && user?.email) {
    addIdentity(createPasswordAuthIdentity(user.email, user.createdAt || nowIso()));
  }

  return identities.sort((left, right) => {
    if (left.provider === "password" && right.provider !== "password") {
      return -1;
    }
    if (right.provider === "password" && left.provider !== "password") {
      return 1;
    }
    return String(left.linkedAt).localeCompare(String(right.linkedAt));
  });
}

function deriveProviderIdsForUser(user) {
  const providerIds = Array.isArray(user?.providerIds)
    ? user.providerIds
      .map((value) => normalizeAuthProvider(value))
      .filter(Boolean)
    : [];

  for (const identity of listAuthIdentitiesForUser(user)) {
    providerIds.push(identity.provider);
  }

  if (user?.passwordHash) {
    providerIds.push("password");
  }

  return Array.from(new Set(providerIds));
}

function cloneUserWithAuthState(user) {
  const clonedUser = structuredClone(user);
  clonedUser.authIdentities = listAuthIdentitiesForUser(clonedUser);
  clonedUser.providerIds = deriveProviderIdsForUser(clonedUser);
  return clonedUser;
}

function normalizeIsoDate(value) {
  if (!value) {
    return null;
  }

  const parsed = new Date(String(value));
  if (Number.isNaN(parsed.getTime())) {
    return null;
  }

  return parsed.toISOString();
}

// F5: точность даты — «знаю только год». Хранение остаётся ISO-датой
// (01.01.года), правда живёт во флаге; всё, кроме «yearOnly», схлопываем
// в дефолт «exact», чтобы мусор с клиента не плодил третьи состояния.
function normalizeDatePrecision(value) {
  return String(value || "").trim() === "yearOnly" ? "yearOnly" : "exact";
}

function createTreeInvitationRecord({
  treeId,
  userId,
  addedBy = null,
  relationToTree = null,
}) {
  const timestamp = nowIso();
  return {
    id: crypto.randomUUID(),
    treeId,
    userId,
    role: "pending",
    addedAt: timestamp,
    addedBy,
    acceptedAt: null,
    relationToTree: normalizeNullableString(relationToTree),
  };
}

function normalizePersonMediaType(type, contentType = null) {
  const normalizedType = String(type || "").trim().toLowerCase();
  if (normalizedType === "image" || normalizedType === "video") {
    return normalizedType;
  }

  const normalizedContentType = String(contentType || "")
    .trim()
    .toLowerCase();
  if (normalizedContentType.startsWith("video/")) {
    return "video";
  }

  return "image";
}

function normalizePersonPhotoGallery(photoGallery, {
  photoUrl = null,
  primaryPhotoUrl = null,
} = {}) {
  const entries = [];
  const seenIds = new Set();
  const seenUrls = new Set();

  const addEntry = (rawEntry) => {
    if (typeof rawEntry === "string") {
      rawEntry = {url: rawEntry};
    }

    if (!rawEntry || typeof rawEntry !== "object") {
      return;
    }

    const normalizedUrl = normalizeNullableString(rawEntry.url);
    if (!normalizedUrl || seenUrls.has(normalizedUrl)) {
      return;
    }

    let mediaId = normalizeNullableString(rawEntry.id);
    if (mediaId && seenIds.has(mediaId)) {
      mediaId = null;
    }
    if (!mediaId) {
      mediaId = crypto.randomUUID();
    }

    seenIds.add(mediaId);
    seenUrls.add(normalizedUrl);

    const createdAt =
      normalizeOptionalIsoTimestamp(rawEntry.createdAt) || nowIso();
    const updatedAt =
      normalizeOptionalIsoTimestamp(rawEntry.updatedAt) || createdAt;

    entries.push({
      id: mediaId,
      url: normalizedUrl,
      thumbnailUrl: normalizeNullableString(rawEntry.thumbnailUrl),
      type: normalizePersonMediaType(
        rawEntry.type || rawEntry.mediaType,
        rawEntry.contentType,
      ),
      contentType: normalizeNullableString(rawEntry.contentType),
      caption: normalizeNullableString(rawEntry.caption),
      createdAt,
      updatedAt,
      isPrimary: rawEntry.isPrimary === true,
    });
  };

  if (Array.isArray(photoGallery)) {
    for (const entry of photoGallery) {
      addEntry(entry);
    }
  }

  const requestedPrimary =
    normalizeNullableString(primaryPhotoUrl) ||
    normalizeNullableString(photoUrl) ||
    entries.find((entry) => entry.isPrimary === true)?.url ||
    null;

  if (requestedPrimary && !seenUrls.has(requestedPrimary)) {
    addEntry({url: requestedPrimary, isPrimary: true});
  }

  const resolvedPrimary =
    requestedPrimary && seenUrls.has(requestedPrimary)
      ? requestedPrimary
      : entries[0]?.url || null;

  if (resolvedPrimary) {
    const primaryIndex = entries.findIndex((entry) => entry.url === resolvedPrimary);
    if (primaryIndex > 0) {
      const [primaryEntry] = entries.splice(primaryIndex, 1);
      entries.unshift(primaryEntry);
    }
  }

  for (const entry of entries) {
    entry.isPrimary = resolvedPrimary !== null && entry.url === resolvedPrimary;
  }

  return {
    primaryPhotoUrl: resolvedPrimary,
    photoUrl: resolvedPrimary,
    photoGallery: entries,
  };
}

// SPEED-8b: общие для блоба и таблиц правила ретенции.
function stripTreeChangeRecordDetails(record, {cutoffTs, dryRun = false}) {
  if (!record || typeof record !== "object") return false;
  if (typeof record.type === "string" && record.type.startsWith("article.")) {
    return false;
  }
  const createdTs = record.createdAt ? Date.parse(record.createdAt) : NaN;
  if (!Number.isFinite(createdTs) || createdTs >= cutoffTs) return false;
  const details = record.details;
  if (!details || typeof details !== "object") return false;
  let stripped = false;
  for (const heavyKey of ["before", "after", "mergedFrom"]) {
    if (Object.prototype.hasOwnProperty.call(details, heavyKey)) {
      if (!dryRun) delete details[heavyKey];
      stripped = true;
    }
  }
  return stripped;
}

function isHardDeleteAuditEntryExpired(entry, cutoffTs) {
  const hardDeletedTs = entry?.hardDeletedAt
    ? Date.parse(entry.hardDeletedAt)
    : NaN;
  return Number.isFinite(hardDeletedTs) && hardDeletedTs < cutoffTs;
}

function createTreeChangeRecord({
  treeId,
  actorId = null,
  type,
  personId = null,
  personIds = [],
  relationId = null,
  mediaId = null,
  details = {},
}) {
  const normalizedPersonIds = Array.from(
    new Set(
      [
        personId,
        ...(Array.isArray(personIds) ? personIds : []),
      ]
        .map((value) => String(value || "").trim())
        .filter(Boolean),
    ),
  );

  return {
    id: crypto.randomUUID(),
    treeId,
    actorId: normalizeNullableString(actorId),
    type: String(type || "unknown").trim() || "unknown",
    personId: normalizeNullableString(personId) || normalizedPersonIds[0] || null,
    personIds: normalizedPersonIds,
    relationId: normalizeNullableString(relationId),
    mediaId: normalizeNullableString(mediaId),
    createdAt: nowIso(),
    details:
      details && typeof details === "object" ? structuredClone(details) : {},
  };
}

function buildPersonRecord({
  treeId,
  creatorId,
  userId = null,
  identityId = null,
  personData = {},
}) {
  const createdAt = nowIso();
  const birthDate = normalizeIsoDate(personData.birthDate);
  const deathDate = normalizeIsoDate(personData.deathDate);
  const familySummary = resolvePersonFamilySummary(personData);
  const photoState = normalizePersonPhotoGallery(personData.photoGallery, {
    photoUrl: personData.photoUrl,
    primaryPhotoUrl: personData.primaryPhotoUrl,
  });

  return {
    id: crypto.randomUUID(),
    treeId,
    userId,
    identityId: normalizeNullableString(identityId),
    name: fullNameFromPersonInput(personData),
    maidenName: normalizeNullableString(personData.maidenName),
    photoUrl: photoState.photoUrl,
    primaryPhotoUrl: photoState.primaryPhotoUrl,
    photoGallery: photoState.photoGallery,
    gender: String(personData.gender || "unknown"),
    birthDate,
    // F5: «знаю только год» — дата хранится как 01.01.года, точность
    // отдельным флагом.
    birthDatePrecision: normalizeDatePrecision(personData.birthDatePrecision),
    birthPlace: normalizeNullableString(personData.birthPlace),
    deathDate,
    deathDatePrecision: normalizeDatePrecision(personData.deathDatePrecision),
    deathPlace: normalizeNullableString(personData.deathPlace),
    familySummary,
    bio: normalizeNullableString(personData.bio),
    isAlive: deathDate === null,
    visibility: normalizePersonVisibility(
      personData.visibility,
      defaultPersonVisibility({deathDate, isAlive: deathDate === null}),
    ),
    creatorId,
    createdAt,
    updatedAt: createdAt,
    notes: normalizeNullableString(personData.notes),
  };
}

// Phase 0 cross-tree picker: when a user picks an existing relative
// from one of their other trees, the new person record on the
// target tree pre-fills any fields the caller didn't supply with
// values from the source. Caller-supplied fields always win — we
// only fill blanks. This is a CONSERVATIVE merge: we only forward
// fields that describe the human (name, birth, photos, gender),
// never tree-local stuff (visibility, notes), since those are a
// per-tree editorial decision.
function mergePersonDataFromSource(personData, sourcePerson) {
  if (!sourcePerson) {
    return personData;
  }
  const merged = {...personData};

  function fillIfBlank(field) {
    const supplied = merged[field];
    const isBlank =
      supplied === undefined ||
      supplied === null ||
      (typeof supplied === "string" && supplied.trim() === "");
    if (isBlank && sourcePerson[field] != null && sourcePerson[field] !== "") {
      merged[field] = sourcePerson[field];
    }
  }

  // Source persons store a composed `name` (no separate firstName /
  // lastName / middleName), so forwarding the composed name is the
  // correct fallback — fullNameFromPersonInput consumes either form.
  const callerProvidedAnyNamePart =
    Boolean(merged.firstName) ||
    Boolean(merged.lastName) ||
    Boolean(merged.middleName) ||
    Boolean(merged.name);
  if (!callerProvidedAnyNamePart && sourcePerson.name) {
    merged.name = sourcePerson.name;
  }

  fillIfBlank("maidenName");
  fillIfBlank("gender");
  fillIfBlank("birthDate");
  // F5: точность даты едет вместе с датой из карточки-источника.
  if (merged.birthDate === sourcePerson.birthDate) {
    fillIfBlank("birthDatePrecision");
  }
  fillIfBlank("birthPlace");
  fillIfBlank("deathDate");
  if (merged.deathDate === sourcePerson.deathDate) {
    fillIfBlank("deathDatePrecision");
  }
  fillIfBlank("deathPlace");
  fillIfBlank("photoUrl");
  fillIfBlank("primaryPhotoUrl");
  if (
    !merged.photoGallery &&
    Array.isArray(sourcePerson.photoGallery) &&
    sourcePerson.photoGallery.length > 0
  ) {
    merged.photoGallery = sourcePerson.photoGallery;
  }

  return merged;
}

function createPersonIdentityRecord({
  id = crypto.randomUUID(),
  userId = null,
  personIds = [],
} = {}) {
  const createdAt = nowIso();
  const normalizedUserId = normalizeNullableString(userId);
  return {
    id,
    userId: normalizedUserId,
    claimedByUserId: normalizedUserId,
    primaryPersonId: normalizeParticipantIds(personIds)[0] || null,
    personIds: normalizeParticipantIds(personIds),
    isLiving: true,
    isPublicDiscoverable: false,
    stewardUserIds: normalizedUserId ? [normalizedUserId] : [],
    mergedInto: null,
    createdAt,
    updatedAt: createdAt,
  };
}

function createPersonAttributeRecord({
  identityId,
  field,
  value = null,
  sourcePersonId = null,
  sourceUserId = null,
  visibility = "private",
  confidence = 1,
}) {
  const timestamp = nowIso();
  return {
    id: crypto.randomUUID(),
    identityId,
    field,
    value,
    sourcePersonId: normalizeNullableString(sourcePersonId),
    sourceUserId: normalizeNullableString(sourceUserId),
    confidence: Number.isFinite(Number(confidence)) ? Number(confidence) : 1,
    visibility: normalizePersonVisibility(visibility),
    status: "active",
    createdAt: timestamp,
    updatedAt: timestamp,
  };
}

function personAttributeValue(person, field) {
  switch (field) {
    case "name":
      return normalizeNullableString(person?.name);
    case "photo":
      return normalizeNullableString(person?.primaryPhotoUrl || person?.photoUrl);
    case "birthDate":
      return normalizeNullableString(person?.birthDate);
    case "birthYear":
      return extractBirthYear(person?.birthDate);
    case "places":
      return normalizeNullableString(
        [person?.birthPlace, person?.deathPlace].filter(Boolean).join(" · "),
      );
    case "contacts":
      return normalizeNullableString(person?.userId);
    case "notes":
      return normalizeNullableString(
        person?.familySummary || person?.notes || person?.bio,
      );
    case "relations":
      return normalizeNullableString(person?.treeId);
    default:
      return null;
  }
}

function upsertPersonAttributesForPerson(db, person, sourceUserId = null) {
  if (!person?.identityId) {
    return false;
  }
  db.personAttributes = Array.isArray(db.personAttributes)
    ? db.personAttributes
    : [];

  let changed = false;
  for (const field of PERSON_ATTRIBUTE_FIELDS) {
    const value = personAttributeValue(person, field);
    const existing = db.personAttributes.find(
      (entry) =>
        entry.identityId === person.identityId &&
        entry.sourcePersonId === person.id &&
        entry.field === field &&
        entry.status !== "archived",
    );
    if (!value && !existing) {
      continue;
    }

    const visibility = existing?.visibility || defaultAttributeVisibility(field, person);
    if (!existing) {
      db.personAttributes.push(
        createPersonAttributeRecord({
          identityId: person.identityId,
          field,
          value,
          sourcePersonId: person.id,
          sourceUserId: sourceUserId || person.creatorId || person.userId,
          visibility,
        }),
      );
      changed = true;
      continue;
    }

    if (existing.value !== value || existing.visibility !== visibility) {
      existing.value = value;
      existing.visibility = normalizePersonVisibility(visibility);
      existing.updatedAt = nowIso();
      changed = true;
    }
  }
  return changed;
}

function pickPersonValue(currentValue, fallbackValue) {
  if (currentValue === null || currentValue === undefined) {
    return fallbackValue ?? currentValue;
  }

  if (typeof currentValue === "string" && currentValue.trim().length === 0) {
    return fallbackValue ?? currentValue;
  }

  return currentValue;
}

function relationDedupKey(relation) {
  const leftId = String(relation.person1Id || "");
  const rightId = String(relation.person2Id || "");
  const leftToRight = String(relation.relation1to2 || "other");
  const rightToLeft = String(relation.relation2to1 || "other");

  if (leftId <= rightId) {
    return `${relation.treeId}:${leftId}:${rightId}:${leftToRight}:${rightToLeft}`;
  }

  return `${relation.treeId}:${rightId}:${leftId}:${rightToLeft}:${leftToRight}`;
}

// scrypt is memory-hard by design — that's why it's a good password
// KDF, but the synchronous variant blocks the Node event loop for
// 100-200 ms on commodity hardware. Under any concurrent login load
// `scryptSync` would queue every other request behind the hash. The
// async variant runs on Node's libuv thread pool and lets the loop
// keep handling other connections. Wrap it once so the rest of the
// auth path stays a clean async/await chain.
function hashPasswordAsync(
  password,
  salt = crypto.randomBytes(16).toString("hex"),
) {
  return new Promise((resolve, reject) => {
    crypto.scrypt(password, salt, 64, (err, derivedKey) => {
      if (err) {
        reject(err);
        return;
      }
      resolve({
        salt,
        passwordHash: derivedKey.toString("hex"),
      });
    });
  });
}

module.exports = {
  fullNameFromPersonInput,
  composeDisplayNameFromProfile,
  defaultPersonVisibility,
  normalizePersonVisibility,
  defaultAttributeVisibility,
  extractBirthYear,
  safeMergePersonPreview,
  personStewardUserIds,
  identityStewardUserIds,
  normalizeProfileContributionPolicy,
  normalizePrimaryTrustedChannel,
  resolvePersonFamilySummary,
  normalizeProfileContributionFields,
  normalizeCountryDialCode,
  normalizePhoneNumber,
  normalizeAuthProvider,
  createPasswordAuthIdentity,
  createAuthHandoffRecord,
  normalizeAuthIdentityRecord,
  listAuthIdentitiesForUser,
  deriveProviderIdsForUser,
  cloneUserWithAuthState,
  normalizeIsoDate,
  normalizeDatePrecision,
  createTreeInvitationRecord,
  normalizePersonMediaType,
  normalizePersonPhotoGallery,
  stripTreeChangeRecordDetails,
  isHardDeleteAuditEntryExpired,
  createTreeChangeRecord,
  buildPersonRecord,
  mergePersonDataFromSource,
  createPersonIdentityRecord,
  createPersonAttributeRecord,
  personAttributeValue,
  upsertPersonAttributesForPerson,
  pickPersonValue,
  relationDedupKey,
  hashPasswordAsync,
};
