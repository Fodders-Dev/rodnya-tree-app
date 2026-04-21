const HTTPS_ONLY_PUBLIC_HOSTS = new Set([
  "api.rodnya-tree.ru",
  "rodnya-tree.ru",
  "api.fodder-development.ru",
]);

const PROFILE_VISIBILITY_SCOPES = new Set([
  "private",
  "shared_trees",
  "public",
  "specific_trees",
  "specific_branches",
  "specific_users",
]);

const PROFILE_CONTRIBUTION_POLICIES = new Set([
  "disabled",
  "suggestions",
]);

const TRUSTED_CHANNEL_PROVIDERS = new Set([
  "google",
  "telegram",
  "vk",
  "max",
]);

const DEFAULT_PROFILE_VISIBILITY = Object.freeze({
  contacts: Object.freeze({
    scope: "private",
    treeIds: [],
    branchRootPersonIds: [],
    userIds: [],
  }),
  about: Object.freeze({
    scope: "shared_trees",
    treeIds: [],
    branchRootPersonIds: [],
    userIds: [],
  }),
  background: Object.freeze({
    scope: "shared_trees",
    treeIds: [],
    branchRootPersonIds: [],
    userIds: [],
  }),
  worldview: Object.freeze({
    scope: "shared_trees",
    treeIds: [],
    branchRootPersonIds: [],
    userIds: [],
  }),
});

const PROFILE_SECTION_FIELDS = Object.freeze({
  contacts: ["email", "phoneNumber", "countryCode", "countryName", "city"],
  about: ["bio", "familyStatus", "aboutFamily"],
  background: [
    "gender",
    "birthDate",
    "birthPlace",
    "maidenName",
    "education",
    "work",
    "hometown",
    "languages",
  ],
  worldview: ["values", "religion", "interests"],
});

function computeProfileStatus(profile) {
  const missingFields = [];

  if (!profile.firstName || !String(profile.firstName).trim()) {
    missingFields.push("firstName");
  }
  if (!profile.lastName || !String(profile.lastName).trim()) {
    missingFields.push("lastName");
  }
  if (!profile.username || !String(profile.username).trim()) {
    missingFields.push("username");
  }

  return {
    isComplete: missingFields.length === 0,
    missingFields,
  };
}

function composeDisplayName(profile) {
  const parts = [
    profile.firstName,
    profile.middleName,
    profile.lastName,
  ]
    .map((value) => String(value || "").trim())
    .filter(Boolean);

  if (parts.length > 0) {
    return parts.join(" ");
  }

  return String(profile.displayName || "").trim();
}

function normalizePublicUrl(value) {
  const rawValue = String(value || "").trim();
  if (!rawValue) {
    return null;
  }

  try {
    const parsedUrl = new URL(rawValue);
    if (
      parsedUrl.protocol === "http:" &&
      HTTPS_ONLY_PUBLIC_HOSTS.has(parsedUrl.hostname.toLowerCase())
    ) {
      parsedUrl.protocol = "https:";
      return parsedUrl.toString();
    }
  } catch {
    return rawValue;
  }

  return rawValue;
}

function normalizePublicUrlList(values) {
  return Array.isArray(values)
    ? values.map((value) => normalizePublicUrl(value)).filter(Boolean)
    : [];
}

function normalizeString(value) {
  return String(value || "").trim();
}

function normalizeStringList(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return [...new Set(value.map((entry) => normalizeString(entry)).filter(Boolean))];
}

function normalizeProfileContributionPolicy(value) {
  const normalizedValue = normalizeString(value);
  return PROFILE_CONTRIBUTION_POLICIES.has(normalizedValue)
    ? normalizedValue
    : "suggestions";
}

function normalizePrimaryTrustedChannel(value) {
  const normalizedValue = normalizeString(value).toLowerCase();
  return TRUSTED_CHANNEL_PROVIDERS.has(normalizedValue)
    ? normalizedValue
    : null;
}

function normalizeProfileVisibilityEntry(rawEntry, fallbackEntry) {
  const fallbackScope = normalizeString(fallbackEntry?.scope) || "private";
  if (!rawEntry || typeof rawEntry !== "object" || Array.isArray(rawEntry)) {
    return {
      scope: fallbackScope,
      treeIds: normalizeStringList(fallbackEntry?.treeIds),
      branchRootPersonIds: normalizeStringList(
        fallbackEntry?.branchRootPersonIds,
      ),
      userIds: normalizeStringList(fallbackEntry?.userIds),
    };
  }

  const scope = normalizeString(rawEntry.scope);
  return {
    scope: PROFILE_VISIBILITY_SCOPES.has(scope) ? scope : fallbackScope,
    treeIds: normalizeStringList(rawEntry.treeIds),
    branchRootPersonIds: normalizeStringList(rawEntry.branchRootPersonIds),
    userIds: normalizeStringList(rawEntry.userIds),
  };
}

function normalizeProfileVisibility(profileVisibility = {}) {
  const normalized = {};
  for (const [sectionKey, defaultEntry] of Object.entries(
    DEFAULT_PROFILE_VISIBILITY,
  )) {
    normalized[sectionKey] = normalizeProfileVisibilityEntry(
      profileVisibility?.[sectionKey],
      defaultEntry,
    );
  }
  return normalized;
}

function normalizeProfileViewerContext(viewerContext = null) {
  if (!viewerContext || typeof viewerContext !== "object") {
    return {
      viewerUserId: null,
      targetUserId: null,
      sharedTreeIds: [],
      branchRootMatches: [],
    };
  }

  return {
    viewerUserId: normalizeString(viewerContext.viewerUserId),
    targetUserId: normalizeString(viewerContext.targetUserId),
    sharedTreeIds: normalizeStringList(viewerContext.sharedTreeIds),
    branchRootMatches: normalizeStringList(viewerContext.branchRootMatches),
  };
}

function canViewProfileSection(entry, viewerContext) {
  const scope = normalizeString(entry?.scope) || "private";
  const {viewerUserId, sharedTreeIds, branchRootMatches} = viewerContext;

  switch (scope) {
    case "public":
      return true;
    case "shared_trees":
      return sharedTreeIds.length > 0;
    case "specific_trees":
      return entry.treeIds.some((treeId) => sharedTreeIds.includes(treeId));
    case "specific_branches":
      return entry.branchRootPersonIds.some((personId) =>
        branchRootMatches.includes(personId),
      );
    case "specific_users":
      return Boolean(viewerUserId) && entry.userIds.includes(viewerUserId);
    case "private":
    default:
      return false;
  }
}

function sanitizeProfile(profile = {}, viewerContext = null) {
  const profileVisibility = normalizeProfileVisibility(profile.profileVisibility);
  const normalizedViewerContext = normalizeProfileViewerContext(viewerContext);
  const isSelfView =
    normalizedViewerContext.viewerUserId &&
    normalizedViewerContext.targetUserId &&
    normalizedViewerContext.viewerUserId === normalizedViewerContext.targetUserId;

  const sanitized = {
    id: normalizeString(profile.id),
    email: normalizeString(profile.email),
    firstName: normalizeString(profile.firstName),
    lastName: normalizeString(profile.lastName),
    middleName: normalizeString(profile.middleName),
    displayName: composeDisplayName(profile),
    username: normalizeString(profile.username),
    phoneNumber: normalizeString(profile.phoneNumber),
    countryCode:
      profile.countryCode === undefined || profile.countryCode === null
        ? null
        : String(profile.countryCode),
    countryName:
      profile.countryName === undefined || profile.countryName === null
        ? null
        : String(profile.countryName),
    city: normalizeString(profile.city),
    photoUrl: normalizePublicUrl(profile.photoUrl),
    gender: normalizeString(profile.gender || "unknown"),
    maidenName: normalizeString(profile.maidenName),
    birthDate:
      profile.birthDate === undefined || profile.birthDate === null
        ? null
        : String(profile.birthDate),
    birthPlace: normalizeString(profile.birthPlace),
    bio: normalizeString(profile.bio),
    familyStatus: normalizeString(profile.familyStatus),
    aboutFamily: normalizeString(profile.aboutFamily),
    education: normalizeString(profile.education),
    work: normalizeString(profile.work),
    hometown: normalizeString(profile.hometown),
    languages: normalizeString(profile.languages),
    values: normalizeString(profile.values),
    religion: normalizeString(profile.religion),
    interests: normalizeString(profile.interests),
    profileContributionPolicy: normalizeProfileContributionPolicy(
      profile.profileContributionPolicy,
    ),
    primaryTrustedChannel: normalizePrimaryTrustedChannel(
      profile.primaryTrustedChannel,
    ),
    hiddenProfileSections: [],
    createdAt:
      profile.createdAt === undefined || profile.createdAt === null
        ? null
        : String(profile.createdAt),
    updatedAt:
      profile.updatedAt === undefined || profile.updatedAt === null
        ? null
        : String(profile.updatedAt),
  };

  if (isSelfView || !normalizedViewerContext.viewerUserId) {
    sanitized.profileVisibility = profileVisibility;
    return sanitized;
  }

  const hiddenSections = [];
  for (const [sectionKey, fields] of Object.entries(PROFILE_SECTION_FIELDS)) {
    if (canViewProfileSection(profileVisibility[sectionKey], normalizedViewerContext)) {
      continue;
    }
    hiddenSections.push(sectionKey);
    for (const fieldName of fields) {
      sanitized[fieldName] = fieldName === "birthDate" ? null : "";
    }
    if (sectionKey === "contacts") {
      sanitized.countryCode = null;
      sanitized.countryName = null;
    }
  }

  sanitized.hiddenProfileSections = hiddenSections;
  sanitized.profileVisibility = Object.fromEntries(
    Object.entries(profileVisibility).map(([sectionKey, entry]) => [
      sectionKey,
      {scope: entry.scope},
    ]),
  );

  return sanitized;
}

function sanitizeUserProfilePreview(user) {
  const profile = user?.profile || {};
  return {
    id: normalizeString(user?.id || profile.id),
    firstName: normalizeString(profile.firstName),
    lastName: normalizeString(profile.lastName),
    middleName: normalizeString(profile.middleName),
    displayName: composeDisplayName(profile),
    username: normalizeString(profile.username),
    photoUrl: normalizePublicUrl(profile.photoUrl),
  };
}

module.exports = {
  DEFAULT_PROFILE_VISIBILITY,
  PROFILE_CONTRIBUTION_POLICIES,
  PROFILE_SECTION_FIELDS,
  PROFILE_VISIBILITY_SCOPES,
  computeProfileStatus,
  composeDisplayName,
  normalizeProfileContributionPolicy,
  normalizePrimaryTrustedChannel,
  normalizeProfileVisibility,
  normalizePublicUrl,
  normalizePublicUrlList,
  sanitizeProfile,
  sanitizeUserProfilePreview,
};
