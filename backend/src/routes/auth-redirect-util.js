"use strict";

// The mobile app's own registered custom URL scheme for OAuth deep-link
// callbacks — see android/app/src/main/AndroidManifest.xml (android:scheme).
// Auth callbacks use `rodnya://oauth/callback`. `rodnyabilling` is a separate
// billing scheme and is intentionally NOT a valid auth-redirect target.
const ALLOWED_CUSTOM_SCHEMES = new Set(["rodnya"]);

// Validate a client-supplied `finalRedirect` BEFORE the single-use social
// auth code is appended to it.
//
// Without this guard, a crafted link
//   /v1/auth/{vk,telegram}/start?finalRedirect=https://evil.example
// would make us 302 the victim's browser to the attacker host with the
// auth code in the query string. Because /v1/auth/{vk,telegram}/exchange
// returns the session tokens to anyone who presents that code (no device /
// PKCE / origin binding), the attacker could then exchange it and hijack
// the victim's account. So we allow ONLY:
//   - the app's own web origin (identical scheme+host+port to appUrl), or
//   - the app's registered mobile deep-link scheme(s) (rodnya://…), which
//     resolve to an on-device app, not a remote attacker server.
// Anything else returns null → callers fall back to the app's own /#/login.
function sanitizeFinalRedirect(raw, appUrl) {
  const value = typeof raw === "string" ? raw.trim() : "";
  if (!value) {
    return null;
  }
  let parsed;
  try {
    parsed = new URL(value);
  } catch (_error) {
    return null;
  }
  const scheme = parsed.protocol.replace(/:$/, "").toLowerCase();
  if (ALLOWED_CUSTOM_SCHEMES.has(scheme)) {
    return value;
  }
  if (scheme === "http" || scheme === "https") {
    let appOrigin = null;
    try {
      appOrigin = new URL(appUrl).origin;
    } catch (_error) {
      return null;
    }
    // origin = scheme://host:port — blocks off-host exfiltration,
    // suffix tricks (rodnya-tree.ru.evil.com), and scheme downgrades.
    if (parsed.origin === appOrigin) {
      return value;
    }
  }
  return null;
}

module.exports = {sanitizeFinalRedirect, ALLOWED_CUSTOM_SCHEMES};
