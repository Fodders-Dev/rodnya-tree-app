const {OAuth2Client} = require("google-auth-library");

function normalizeClientIds(value) {
  if (Array.isArray(value)) {
    return value
      .map((entry) => String(entry || "").trim())
      .filter(Boolean);
  }

  return String(value || "")
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function createGoogleTokenVerifier(config = {}) {
  const acceptedClientIds = Array.from(
    new Set([
      ...normalizeClientIds(config.googleWebClientId),
      ...normalizeClientIds(config.googleAllowedClientIds),
    ]),
  );
  const oauthClient = new OAuth2Client();

  return {
    isEnabled: acceptedClientIds.length > 0,
    acceptedClientIds,
    async verifyIdToken(idToken) {
      const normalizedIdToken = String(idToken || "").trim();
      if (!normalizedIdToken) {
        throw new Error("GOOGLE_ID_TOKEN_REQUIRED");
      }
      if (acceptedClientIds.length === 0) {
        throw new Error("GOOGLE_AUTH_NOT_CONFIGURED");
      }

      const ticket = await oauthClient.verifyIdToken({
        idToken: normalizedIdToken,
        audience: acceptedClientIds,
      });
      const payload = ticket?.getPayload?.();
      if (!payload?.sub) {
        throw new Error("GOOGLE_ID_TOKEN_INVALID");
      }

      return payload;
    },
  };
}

module.exports = {
  createGoogleTokenVerifier,
};
