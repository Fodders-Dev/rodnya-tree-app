const {GoogleAuth} = require("google-auth-library");

// FCM HTTP v1 send scope. A service-account access token with this scope is
// the Bearer credential for POST .../messages:send.
const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const DEFAULT_API_BASE_URL = "https://fcm.googleapis.com";

// Mints + caches an OAuth2 access token for FCM HTTP v1 sends from a Firebase
// service-account JSON.
//
// google-auth-library's GoogleAuth caches the access token internally and
// refreshes it shortly before expiry, so a SINGLE shared instance is correct
// under PushGateway's parallel `Promise.allSettled` fan-out — concurrent
// getAccessToken() calls dedupe onto one refresh instead of minting N tokens.
//
// Inert (isEnabled=false) until both a project id and a parseable service
// account (with client_email + private_key) are supplied, so this can ship
// dark and only activate once the backend env is set.
function createFcmSender(config = {}) {
  const projectId = String(config.fcmProjectId || "").trim();
  const apiBaseUrl = String(config.fcmApiBaseUrl || DEFAULT_API_BASE_URL).replace(
    /\/+$/,
    "",
  );
  const serviceAccount =
    config.fcmServiceAccount && typeof config.fcmServiceAccount === "object"
      ? config.fcmServiceAccount
      : null;

  const enabled = Boolean(
    projectId &&
      serviceAccount &&
      serviceAccount.client_email &&
      serviceAccount.private_key,
  );

  let auth = null;
  if (enabled) {
    auth = new GoogleAuth({
      credentials: serviceAccount,
      projectId,
      scopes: [FCM_SCOPE],
    });
  }

  return {
    isEnabled: enabled,
    projectId,
    apiBaseUrl,
    sendUrl: `${apiBaseUrl}/v1/projects/${encodeURIComponent(projectId)}/messages:send`,
    async getAccessToken() {
      if (!auth) {
        throw new Error("FCM_NOT_CONFIGURED");
      }
      const token = await auth.getAccessToken();
      const value = typeof token === "string" ? token : token?.token;
      if (!value) {
        throw new Error("FCM_ACCESS_TOKEN_UNAVAILABLE");
      }
      return value;
    },
  };
}

module.exports = {createFcmSender, FCM_SCOPE, DEFAULT_FCM_API_BASE_URL: DEFAULT_API_BASE_URL};
