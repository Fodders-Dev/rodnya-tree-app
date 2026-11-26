const {
  computeProfileStatus,
  normalizePrimaryTrustedChannel,
  normalizePublicUrl,
  sanitizeProfile,
} = require("../profile-utils");

function maskEmailAddress(value) {
  const normalizedValue = String(value || "").trim().toLowerCase();
  const atIndex = normalizedValue.indexOf("@");
  if (atIndex <= 0) {
    return null;
  }

  const localPart = normalizedValue.slice(0, atIndex);
  const domainPart = normalizedValue.slice(atIndex + 1);
  if (!localPart || !domainPart) {
    return null;
  }

  const visibleLocal =
    localPart.length <= 2
      ? `${localPart[0]}*`
      : `${localPart.slice(0, 2)}***`;
  return `${visibleLocal}@${domainPart}`;
}

function maskPhoneNumber(value) {
  const normalizedValue = String(value || "").replace(/\D+/g, "");
  if (normalizedValue.length < 7) {
    return null;
  }

  return `+${normalizedValue.slice(0, 2)}***${normalizedValue.slice(-2)}`;
}

function secondsUntil(value) {
  const timestamp = new Date(String(value || "")).getTime();
  if (!Number.isFinite(timestamp)) {
    return 0;
  }
  return Math.max(0, Math.ceil((timestamp - Date.now()) / 1000));
}

function mapLinkedAuthIdentity(identity) {
  return {
    provider: identity.provider,
    linkedAt: identity.linkedAt,
    lastUsedAt: identity.lastUsedAt || null,
    emailMasked: maskEmailAddress(identity.email),
    phoneMasked: maskPhoneNumber(
      identity.normalizedPhoneNumber || identity.phoneNumber,
    ),
    displayName: identity.displayName || null,
  };
}


function createAuthPresenters({config}) {
  function resolvePublicAppUrl() {
    return String(config.publicAppUrl || "https://rodnya-tree.ru")
      .trim()
      .replace(/\/$/, "");
  }

  function trustedChannelLabel(provider) {
    switch (provider) {
      case "google":
        return "Google";
      case "telegram":
        return "Telegram";
      case "vk":
        return "VK ID";
      case "max":
        return "MAX";
      case "password":
      default:
        return "Email и пароль";
    }
  }

  function trustedChannelDescription(provider) {
    switch (provider) {
      case "google":
        return "Подтверждённый вход через Google-аккаунт.";
      case "telegram":
        return "Подтверждённая связь через Telegram.";
      case "vk":
        return "Подтверждённый профиль через VK ID.";
      case "max":
        return "Подтверждённая связь через MAX.";
      case "password":
      default:
        return "Резервный вход по email и паролю.";
    }
  }

  function trustedChannelVerificationLabel(provider) {
    switch (provider) {
      case "google":
        return "Аккаунт подтверждён через Google";
      case "telegram":
        return "Связь подтверждена через Telegram";
      case "vk":
        return "Аккаунт подтверждён через VK";
      case "max":
        return "Основной канал подтверждён через MAX";
      case "password":
      default:
        return "Доступ защищён email и паролем";
    }
  }

  function resolvePrimaryTrustedChannelProvider({
    linkedProviderIds = [],
    profile = {},
  } = {}) {
    const preferredProvider = normalizePrimaryTrustedChannel(
      profile?.primaryTrustedChannel,
    );
    if (
      preferredProvider &&
      Array.isArray(linkedProviderIds) &&
      linkedProviderIds.includes(preferredProvider)
    ) {
      return preferredProvider;
    }

    for (const provider of ["telegram", "vk", "max", "google"]) {
      if (linkedProviderIds.includes(provider)) {
        return provider;
      }
    }

    return null;
  }

  function buildTrustedChannels({
    linkedProviderIds = [],
    authIdentities = [],
    profile = {},
  } = {}) {
    const mappedIdentities = Array.isArray(authIdentities)
      ? authIdentities.map(mapLinkedAuthIdentity)
      : [];
    const identityByProvider = new Map();
    for (const identity of mappedIdentities) {
      if (identity?.provider && !identityByProvider.has(identity.provider)) {
        identityByProvider.set(identity.provider, identity);
      }
    }

    const primaryProvider = resolvePrimaryTrustedChannelProvider({
      linkedProviderIds,
      profile,
    });

    return ["password", "google", "telegram", "vk", "max"].map((provider) => {
      const identity = identityByProvider.get(provider) || null;
      const isLinked = linkedProviderIds.includes(provider);
      const isTrustedChannel = isLinked && provider !== "password";
      return {
        provider,
        label: trustedChannelLabel(provider),
        description: trustedChannelDescription(provider),
        verificationLabel: trustedChannelVerificationLabel(provider),
        isLinked,
        isTrustedChannel,
        isLoginMethod: isLinked,
        isPrimary: primaryProvider === provider,
        linkedAt: identity?.linkedAt || null,
        lastUsedAt: identity?.lastUsedAt || null,
        emailMasked: identity?.emailMasked || null,
        phoneMasked: identity?.phoneMasked || null,
        displayName: identity?.displayName || null,
      };
    });
  }

  function buildTrustedChannelSummary(trustedChannels = []) {
    const primaryChannel = trustedChannels.find(
      (entry) => entry.isPrimary === true && entry.isTrustedChannel === true,
    );
    if (primaryChannel) {
      return {
        title: primaryChannel.verificationLabel,
        detail: `Основной канал: ${primaryChannel.label}`,
      };
    }

    const firstTrustedChannel = trustedChannels.find(
      (entry) => entry.isTrustedChannel === true,
    );
    if (firstTrustedChannel) {
      return {
        title: firstTrustedChannel.verificationLabel,
        detail: "Можно выбрать этот канал основным в настройках профиля.",
      };
    }

    return {
      title: "Подтверждённый канал пока не выбран",
      detail:
        "Привяжите VK, Telegram, Google или MAX, чтобы подтвердить канал связи и входа.",
    };
  }

  // Phase 6 chunk 4a (PHASE-6-PROPOSAL.md §2.8 + DECISIONS 2026-05-14
  // «post-signup redirect Option A simplified»): auth response carries
  // optional `requiresOnboarding` flag — client redirects к `/setup`
  // wizard when true. Каждый auth endpoint решает свой flag value:
  //   • register / fresh Google/VK/Telegram/MAX signup → true
  //   • login / linking existing user → computed via
  //     store.hasIncompleteOnboarding (true только если user mid-wizard)
  //   • refresh → omit flag (no redirect on token refresh)
  function authResponse(user, sessionTokens, extra = {}) {
    const profile = sanitizeProfile(user.profile);
    const profileStatus = computeProfileStatus(user.profile);
    return {
      accessToken: sessionTokens.token,
      refreshToken: sessionTokens.refreshToken,
      user: {
        id: user.id,
        identityId: user.identityId || null,
        email: user.email,
        displayName: profile.displayName,
        photoUrl: profile.photoUrl,
        providerIds: user.providerIds || ["password"],
      },
      profileStatus,
      ...extra,
    };
  }

  function resolveGoogleDisplayName(payload) {
    const explicitName = String(payload?.name || "").trim();
    if (explicitName) {
      return explicitName;
    }

    return [
      String(payload?.given_name || "").trim(),
      String(payload?.family_name || "").trim(),
    ].filter(Boolean).join(" ");
  }

  function buildGoogleIdentityFromPayload(payload) {
    const providerUserId = String(payload?.sub || "").trim();
    if (!providerUserId) {
      throw new Error("GOOGLE_ID_TOKEN_INVALID");
    }

    const email = String(payload?.email || "").trim().toLowerCase() || null;
    const displayName = resolveGoogleDisplayName(payload);
    const picture = String(payload?.picture || "").trim() || null;
    const emailVerified =
      payload?.email_verified === true ||
      String(payload?.email_verified || "").trim().toLowerCase() === "true";

    return {
      provider: "google",
      providerUserId,
      email,
      displayName: displayName || null,
      metadata: {
        emailVerified,
        givenName: String(payload?.given_name || "").trim() || null,
        familyName: String(payload?.family_name || "").trim() || null,
        picture,
      },
    };
  }


  return {
    resolvePublicAppUrl,
    maskEmailAddress,
    maskPhoneNumber,
    secondsUntil,
    mapLinkedAuthIdentity,
    trustedChannelLabel,
    trustedChannelDescription,
    trustedChannelVerificationLabel,
    resolvePrimaryTrustedChannelProvider,
    buildTrustedChannels,
    buildTrustedChannelSummary,
    authResponse,
    resolveGoogleDisplayName,
    buildGoogleIdentityFromPayload,
  };
}

module.exports = {
  createAuthPresenters,
  maskEmailAddress,
  maskPhoneNumber,
  secondsUntil,
  mapLinkedAuthIdentity,
};
