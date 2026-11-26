const path = require("node:path");

function nowIso() {
  return new Date().toISOString();
}

// Compare two values for one of the identity-propagation fields.
// `photoGallery` is an array — JSON-snapshot equality matches the
// existing propagation skip-rule (see `_propagateIdentityFields`)
// so reordering with the same content doesn't count as a change.
// Other fields are scalars; reference/value equality is enough.
function valuesEqualForPropagation(field, a, b) {
  if (field === "photoGallery") {
    return JSON.stringify(a || []) === JSON.stringify(b || []);
  }
  return a === b;
}

// Phase 6.3: parse a date-string (YYYY-MM-DD or full ISO) and
// return the next anniversary inside the next [now, now+horizonDays]
// window, or null when the date is invalid / the anniversary is
// outside the window. Birthday for living people, death anniversary
// for memorials — same logic, different fields.
function computeUpcomingAnniversary(rawDate, now, horizonDays) {
  if (!rawDate) return null;
  const parsed = new Date(rawDate);
  if (Number.isNaN(parsed.getTime())) return null;
  // Take month + day from the original date but anchor to the
  // current year. If that anniversary is already in the past for
  // this calendar year, push to next year.
  const month = parsed.getUTCMonth();
  const day = parsed.getUTCDate();
  const todayUtc = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
  );
  let anniversary = new Date(
    Date.UTC(now.getUTCFullYear(), month, day),
  );
  if (anniversary.getTime() < todayUtc.getTime()) {
    anniversary = new Date(
      Date.UTC(now.getUTCFullYear() + 1, month, day),
    );
  }
  const daysUntil = Math.round(
    (anniversary.getTime() - todayUtc.getTime()) / 86400_000,
  );
  if (daysUntil > horizonDays) return null;
  const yearsSince =
    anniversary.getUTCFullYear() - parsed.getUTCFullYear();
  return {
    date: anniversary,
    daysUntil,
    yearsSince,
  };
}

function normalizeOptionalIsoTimestamp(value) {
  const rawValue = String(value || "").trim();
  if (!rawValue) {
    return null;
  }

  const parsedDate = new Date(rawValue);
  if (Number.isNaN(parsedDate.getTime())) {
    return null;
  }

  return parsedDate.toISOString();
}

function isExpiredAt(value, referenceTimeMs = Date.now()) {
  const normalizedValue = normalizeOptionalIsoTimestamp(value);
  if (!normalizedValue) {
    return false;
  }
  return new Date(normalizedValue).getTime() <= referenceTimeMs;
}

function normalizeParticipantIds(participantIds) {
  return Array.from(
    new Set(
      (Array.isArray(participantIds) ? participantIds : [])
        .map((value) => String(value || "").trim())
        .filter(Boolean),
    ),
  ).sort((left, right) => left.localeCompare(right));
}

function normalizeOptionalString(value, maxLength = 80) {
  const normalized = String(value ?? "").trim();
  if (!normalized) {
    return null;
  }
  if (Number.isFinite(maxLength) && maxLength > 0 && normalized.length > maxLength) {
    return normalized.slice(0, maxLength);
  }
  return normalized;
}

function normalizeNullableString(value) {
  const normalized = String(value || "").trim();
  return normalized ? normalized : null;
}

// SPEED-11: recursively Object.freeze()s a plain JSON-shaped value (arrays/
// objects/primitives — exactly what a normalized db snapshot is; no class
// instances, no functions, no cycles by construction since it round-trips
// through Postgres jsonb / JSON.parse). Used to freeze a cache-fill snapshot
// EXACTLY ONCE, so readSharedSnapshot() can hand the same object out to every
// concurrent GET without a structuredClone per hit. `seen` guards against a
// cycle anyway (cheap insurance, not expected to ever trigger on this data).
//
// Early-returns on a value that's ALREADY frozen instead of walking into it:
// this function is the ONLY thing that ever freezes state data (verified —
// no other bare `Object.freeze()` touches a db snapshot), and it always
// freezes top-down before recursing, so "already frozen" can only mean "this
// exact subtree was already fully processed by a prior call". That makes
// re-freezing an already-shared snapshot O(1) instead of O(size) — load-
// bearing for readSharedSnapshot() calling this defensively on every cache
// hit (see PostgresStore.readSharedSnapshot) and for the miss path being
// safe if a concurrent single-flight ever raced two full freezes.
function deepFreezeState(value, seen) {
  if (value === null || typeof value !== "object") {
    return value;
  }
  if (Object.isFrozen(value)) {
    return value;
  }
  const visited = seen || new WeakSet();
  if (visited.has(value)) {
    return value;
  }
  visited.add(value);
  Object.freeze(value);
  if (Array.isArray(value)) {
    for (const item of value) {
      deepFreezeState(item, visited);
    }
  } else {
    for (const key of Object.keys(value)) {
      deepFreezeState(value[key], visited);
    }
  }
  return value;
}

module.exports = {
  nowIso,
  valuesEqualForPropagation,
  computeUpcomingAnniversary,
  normalizeOptionalIsoTimestamp,
  isExpiredAt,
  normalizeParticipantIds,
  normalizeOptionalString,
  normalizeNullableString,
  deepFreezeState,
};
