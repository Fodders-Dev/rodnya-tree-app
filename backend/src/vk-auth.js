const crypto = require("node:crypto");

const VK_ID_DOMAIN = "id.vk.ru";
const VK_AUTH_SCOPE = "phone email";

function toBase64Url(value) {
  return Buffer.from(value)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function createVkPkcePair() {
  const codeVerifier = toBase64Url(crypto.randomBytes(32));
  const codeChallenge = toBase64Url(
    crypto.createHash("sha256").update(codeVerifier, "utf8").digest(),
  );

  return {
    codeVerifier,
    codeChallenge,
  };
}

function buildVkAuthorizeUrl({
  appId,
  redirectUri,
  state,
  codeChallenge,
  scope = VK_AUTH_SCOPE,
}) {
  const params = new URLSearchParams({
    client_id: String(appId || "").trim(),
    redirect_uri: String(redirectUri || "").trim(),
    response_type: "code",
    state: String(state || "").trim(),
    code_challenge: String(codeChallenge || "").trim(),
    code_challenge_method: "s256",
    scope: String(scope || VK_AUTH_SCOPE).trim() || VK_AUTH_SCOPE,
  });

  return `https://${VK_ID_DOMAIN}/authorize?${params.toString()}`;
}

async function parseVkResponse(response, fallbackCode) {
  const bodyText = await response.text();
  let parsedBody = {};

  if (bodyText.trim()) {
    try {
      parsedBody = JSON.parse(bodyText);
    } catch {
      throw new Error(fallbackCode);
    }
  }

  if (!response.ok || parsedBody?.error) {
    const error = new Error(
      String(parsedBody?.error || parsedBody?.error_description || fallbackCode),
    );
    error.code = String(parsedBody?.error || fallbackCode);
    error.description = parsedBody?.error_description || null;
    error.statusCode = response.status;
    error.payload = parsedBody;
    throw error;
  }

  return parsedBody;
}

function createVkAuthClient(config = {}) {
  const webAppId = String(config.vkWebAppId || "").trim();
  const webProtectedKey = String(config.vkWebProtectedKey || "").trim();

  return {
    isEnabled: Boolean(webAppId),
    webAppId,
    webProtectedKey,
    async exchangeCode({
      code,
      deviceId,
      state,
      codeVerifier,
      redirectUri,
    }) {
      if (!webAppId) {
        throw new Error("VK_AUTH_NOT_CONFIGURED");
      }

      const normalizedCode = String(code || "").trim();
      const normalizedDeviceId = String(deviceId || "").trim();
      const normalizedState = String(state || "").trim();
      const normalizedCodeVerifier = String(codeVerifier || "").trim();
      const normalizedRedirectUri = String(redirectUri || "").trim();

      if (
        !normalizedCode ||
        !normalizedDeviceId ||
        !normalizedState ||
        !normalizedCodeVerifier ||
        !normalizedRedirectUri
      ) {
        throw new Error("VK_AUTH_CODE_REQUIRED");
      }

      const queryParams = new URLSearchParams({
        grant_type: "authorization_code",
        client_id: webAppId,
        redirect_uri: normalizedRedirectUri,
        state: normalizedState,
        device_id: normalizedDeviceId,
        code_verifier: normalizedCodeVerifier,
      });
      const response = await fetch(
        `https://${VK_ID_DOMAIN}/oauth2/auth?${queryParams.toString()}`,
        {
          method: "POST",
          headers: {
            "content-type": "application/x-www-form-urlencoded;charset=UTF-8",
            accept: "application/json",
          },
          body: new URLSearchParams({
            code: normalizedCode,
          }),
        },
      );

      return parseVkResponse(response, "VK_AUTH_EXCHANGE_FAILED");
    },
    async fetchUserInfo(accessToken) {
      if (!webAppId) {
        throw new Error("VK_AUTH_NOT_CONFIGURED");
      }

      const normalizedAccessToken = String(accessToken || "").trim();
      if (!normalizedAccessToken) {
        throw new Error("VK_ACCESS_TOKEN_REQUIRED");
      }

      const queryParams = new URLSearchParams({
        client_id: webAppId,
      });
      const response = await fetch(
        `https://${VK_ID_DOMAIN}/oauth2/user_info?${queryParams.toString()}`,
        {
          method: "POST",
          headers: {
            "content-type": "application/x-www-form-urlencoded;charset=UTF-8",
            accept: "application/json",
          },
          body: new URLSearchParams({
            access_token: normalizedAccessToken,
          }),
        },
      );

      return parseVkResponse(response, "VK_USER_INFO_FAILED");
    },
  };
}

module.exports = {
  VK_AUTH_SCOPE,
  buildVkAuthorizeUrl,
  createVkAuthClient,
  createVkPkcePair,
};
