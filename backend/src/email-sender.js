"use strict";

// Pluggable email sender used by the password-reset flow.
//
// Why a thin facade and not "just use nodemailer everywhere":
//   * Dev / test paths shouldn't blow up because SMTP isn't configured —
//     they fall back to a console-logger that prints the would-be
//     payload, so a developer can copy the reset link out of stdout.
//   * Switching providers (UniSender Go → Mailopost → SES → whatever)
//     stays a 1-line change in env, not a code refactor.
//   * Tests can swap the whole sender with a recording fake without
//     monkey-patching nodemailer internals.
//
// Public surface kept deliberately small. Add new template methods
// alongside `sendPasswordResetEmail` if/when other transactional
// flows show up (email verification, login alerts, etc.) — never
// expose the raw transport.

const FROM_DEFAULT_NAME = "Родня";
const PASSWORD_RESET_SUBJECT = "Сброс пароля — Родня";
const PASSWORD_RESET_TTL_HOURS = 24;

// Envelope-injection defense. RFC 5322 forbids CR/LF in header
// values; if we let user-controlled bytes through verbatim a
// crafted display name like "Артём\r\nBcc: attacker@evil.com"
// would graft a Bcc header onto the outgoing email and exfiltrate
// the reset link. nodemailer itself defends against this on most
// fields, but defense in depth is cheap.
function stripHeaderUnsafeChars(value) {
  return String(value || "").replace(/[\r\n\t\v\f]+/g, " ").trim();
}

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function buildPasswordResetBody({displayName, resetUrl, ttlHours}) {
  const safeName = stripHeaderUnsafeChars(displayName || "");
  const greeting = safeName ? `Здравствуйте, ${safeName}!` : "Здравствуйте!";

  const text = [
    greeting,
    "",
    "Мы получили запрос на сброс пароля для вашего аккаунта в Родне.",
    "Чтобы установить новый пароль, перейдите по ссылке ниже:",
    "",
    resetUrl,
    "",
    `Ссылка действительна в течение ${ttlHours} ч.`,
    "Если вы не запрашивали сброс пароля — просто проигнорируйте это письмо,",
    "ваш текущий пароль останется без изменений.",
    "",
    "С уважением,",
    "Команда Родни",
    "https://rodnya-tree.ru",
  ].join("\n");

  // HTML version is bare-bones on purpose — fancy CSS gets stripped
  // by Gmail / Yandex / Mail.ru anyway, and inline-styled marketing
  // emails trip more spam filters than plain text does.
  const html = `<!DOCTYPE html>
<html lang="ru">
<head><meta charset="utf-8"><title>${escapeHtml(PASSWORD_RESET_SUBJECT)}</title></head>
<body style="font-family:Arial,Helvetica,sans-serif;color:#222;line-height:1.5;">
  <p>${escapeHtml(greeting)}</p>
  <p>Мы получили запрос на сброс пароля для вашего аккаунта в Родне.<br>
     Чтобы установить новый пароль, нажмите на кнопку ниже:</p>
  <p style="margin:24px 0;">
    <a href="${escapeHtml(resetUrl)}"
       style="display:inline-block;padding:12px 20px;background:#8b5cf6;
              color:#ffffff;text-decoration:none;border-radius:8px;
              font-weight:600;">Сбросить пароль</a>
  </p>
  <p>Если кнопка не работает, скопируйте ссылку в браузер:<br>
     <a href="${escapeHtml(resetUrl)}">${escapeHtml(resetUrl)}</a></p>
  <p style="color:#666;font-size:13px;">
    Ссылка действительна в течение ${ttlHours} ч.<br>
    Если вы не запрашивали сброс пароля — просто проигнорируйте это
    письмо, ваш текущий пароль останется без изменений.
  </p>
  <hr style="border:none;border-top:1px solid #eee;margin:24px 0;">
  <p style="color:#888;font-size:12px;">
    С уважением,<br>Команда Родни<br>
    <a href="https://rodnya-tree.ru">rodnya-tree.ru</a>
  </p>
</body>
</html>`;

  return {text, html};
}

// Lazy nodemailer require — keeps the module loadable on dev boxes /
// CI runners where nodemailer wouldn't be installed yet, and avoids
// pulling its (modest) dependency tree into hot paths that don't
// actually send mail.
let _cachedNodemailer = null;
function loadNodemailer() {
  if (_cachedNodemailer) return _cachedNodemailer;
  // eslint-disable-next-line global-require
  _cachedNodemailer = require("nodemailer");
  return _cachedNodemailer;
}

function buildSmtpTransport({host, port, user, password, secure}) {
  const nodemailer = loadNodemailer();
  return nodemailer.createTransport({
    host,
    port,
    secure: Boolean(secure),
    auth: {user, pass: password},
    // Time out aggressively. UniSender Go's SMTP usually answers in
    // <500 ms; if we hit 10 s we'd rather fail the request than tie
    // up a libuv slot for the default 60 s.
    connectionTimeout: 10_000,
    greetingTimeout: 10_000,
    socketTimeout: 15_000,
  });
}

// Parse RFC 5322 "Display Name <email@addr>" into name + email
// pair, or fall back to the bare email when no display name is
// present. The HTTPS API needs them as separate JSON fields, while
// nodemailer takes the combined string.
function parseFromAddress(combined) {
  const value = String(combined || "").trim();
  // Match `"Name" <email>` or `Name <email>` or just `email`.
  const angled = value.match(/^"?([^"<]+?)"?\s*<\s*([^>]+)\s*>\s*$/);
  if (angled) {
    return {name: angled[1].trim(), email: angled[2].trim()};
  }
  return {name: "", email: value};
}

// HTTPS-API transport. Used when the host is on a VPS that blocks
// outbound SMTP (common — many providers block 25/465/587 by
// default). UniSender Go exposes the same send capability over
// HTTPS so we get reliable delivery via port 443 which is always
// open. Same API key as SMTP (re-used as-is).
function buildHttpsApiTransport({apiKey, baseUrl, logger}) {
  const sink = logger || console;
  const trimmedBase = String(baseUrl || "")
    .trim()
    .replace(/\/+$/u, "");
  if (!trimmedBase) {
    throw new Error("UniSender HTTPS API: base URL is required");
  }
  if (!apiKey) {
    throw new Error("UniSender HTTPS API: api key is required");
  }
  const sendUrl = `${trimmedBase}/email/send.json`;
  return {
    isHttpsApi: true,
    async sendMail(payload) {
      const fromParsed = parseFromAddress(payload.from);
      const body = {
        message: {
          recipients: [{email: payload.to}],
          subject: payload.subject,
          from_email: fromParsed.email,
          from_name: fromParsed.name || undefined,
          body: {
            ...(payload.text ? {plaintext: payload.text} : {}),
            ...(payload.html ? {html: payload.html} : {}),
          },
        },
      };
      // 10-second wall clock — UniSender Go normally answers in <500 ms
      // when the path is healthy. Anything past that we'd rather fail
      // the request than hold a libuv slot.
      let response;
      try {
        response = await fetch(sendUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-API-KEY": apiKey,
          },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(10_000),
        });
      } catch (error) {
        // Network-level failure — DNS, refused, timeout, TLS. Same
        // shape as nodemailer would give us back so the calling
        // route's error log stays consistent.
        const wrapped = new Error(
          `UniSender API network error: ${error?.message || String(error)}`,
        );
        wrapped.cause = error;
        throw wrapped;
      }
      const responseText = await response.text();
      let parsed = null;
      try {
        parsed = responseText ? JSON.parse(responseText) : null;
      } catch (_) {
        parsed = null;
      }
      if (!response.ok || parsed?.status !== "success") {
        // Don't shovel the entire response body into the error
        // message — could contain html error pages. Pull just the
        // structured `message` if present, else status code.
        const detail =
          parsed?.message ||
          `HTTP ${response.status} ${response.statusText || ""}`.trim();
        const code = parsed?.code != null ? ` (code ${parsed.code})` : "";
        sink.error(
          "[email-sender] UniSender HTTPS API non-success",
          JSON.stringify({
            status: response.status,
            apiStatus: parsed?.status || null,
            apiCode: parsed?.code || null,
            apiMessage: parsed?.message || null,
            // First 200 chars of the response in case JSON parse failed.
            rawHead: responseText.slice(0, 200),
          }),
        );
        const error = new Error(`UniSender API: ${detail}${code}`);
        error.statusCode = response.status;
        throw error;
      }
      return {
        messageId: parsed.job_id || null,
        accepted: Array.isArray(parsed.emails) ? parsed.emails : [payload.to],
      };
    },
  };
}

function buildLoggerTransport(logger) {
  // Dev / test fallback. We DON'T want a real transport here — when
  // SMTP isn't configured the right behavior is to make the password
  // reset link visible in the server log so a developer can grab it
  // out of stdout. Returning `{ok: true}` keeps the calling route
  // looking like a successful 202 to its caller.
  return {
    isLogger: true,
    async sendMail(payload) {
      const sink = logger || console;
      sink.info(
        "[email-sender] SMTP not configured — dumping payload to log",
        JSON.stringify(
          {
            to: payload.to,
            from: payload.from,
            subject: payload.subject,
            text: payload.text,
          },
          null,
          2,
        ),
      );
      return {messageId: "dev-logger-no-smtp", accepted: [payload.to]};
    },
  };
}

function createEmailSender({config = {}, logger = console} = {}) {
  const host = String(config.smtpHost || "").trim();
  const port = Number(config.smtpPort || 0);
  const user = String(config.smtpUser || "").trim();
  const password = String(config.smtpPassword || "");
  const fromAddress = stripHeaderUnsafeChars(
    config.mailFrom || "no-reply@rodnya-tree.ru",
  );
  const fromName = stripHeaderUnsafeChars(
    config.mailFromName || FROM_DEFAULT_NAME,
  );
  const secure = String(config.smtpSecure || "false")
    .toString()
    .toLowerCase() === "true";

  // Transport selection (in priority order):
  //   1. UniSender HTTPS API — when the API key is set. Preferred
  //      in production because (a) port 443 is universally open
  //      where outbound SMTP often isn't, and (b) structured JSON
  //      errors beat opaque SMTP 5xx codes for debugging.
  //   2. Plain SMTP (nodemailer) — when SMTP_* are set. Kept as
  //      a fallback for hosts where the HTTPS API is unavailable
  //      or for self-hosted SMTP relays.
  //   3. Console logger — when neither is configured. Dev / CI
  //      paths print what they would have sent; password reset
  //      links land in stdout for the developer to copy.
  const unisenderApiKey = String(config.unisenderApiKey || "").trim();
  const unisenderBaseUrl = String(
    config.unisenderApiBaseUrl ||
      "https://go2.unisender.ru/ru/transactional/api/v1",
  ).trim();

  let transport;
  if (unisenderApiKey) {
    transport = buildHttpsApiTransport({
      apiKey: unisenderApiKey,
      baseUrl: unisenderBaseUrl,
      logger,
    });
  } else if (host && port && user && password) {
    transport = buildSmtpTransport({host, port, user, password, secure});
  } else {
    transport = buildLoggerTransport(logger);
  }

  function formatFrom() {
    return fromName ? `"${fromName}" <${fromAddress}>` : fromAddress;
  }

  async function sendPasswordResetEmail({to, resetUrl, displayName = ""}) {
    const safeTo = stripHeaderUnsafeChars(to);
    const safeUrl = String(resetUrl || "").trim();
    if (!safeTo || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(safeTo)) {
      throw new Error("INVALID_EMAIL_RECIPIENT");
    }
    if (!/^https?:\/\//i.test(safeUrl)) {
      // Reset URL must be absolute https — otherwise a misconfigured
      // backend could email a relative path and the user clicks a
      // link that resolves against their MUA's base URL.
      throw new Error("INVALID_RESET_URL");
    }

    const {text, html} = buildPasswordResetBody({
      displayName,
      resetUrl: safeUrl,
      ttlHours: PASSWORD_RESET_TTL_HOURS,
    });

    try {
      const info = await transport.sendMail({
        from: formatFrom(),
        to: safeTo,
        subject: PASSWORD_RESET_SUBJECT,
        text,
        html,
      });
      return {
        ok: true,
        messageId: info?.messageId || null,
        usingLogger: Boolean(transport.isLogger),
      };
    } catch (error) {
      // Don't leak SMTP-server detail to the calling route — log the
      // raw error here, return a generic envelope.
      logger.error(
        "[email-sender] failed to send password reset email",
        JSON.stringify({
          to: safeTo,
          host,
          message: error?.message || String(error),
        }),
      );
      return {ok: false, error: "SEND_FAILED"};
    }
  }

  return {
    sendPasswordResetEmail,
    isUsingLogger: () => Boolean(transport.isLogger),
    /// Diagnostic — which delivery path is in use. Useful in
    /// boot-time logs to make sure ops actually wired what they
    /// thought they did. Values: "https-api" | "smtp" | "logger".
    activeTransport: () => {
      if (transport.isHttpsApi) return "https-api";
      if (transport.isLogger) return "logger";
      return "smtp";
    },
  };
}

module.exports = {
  createEmailSender,
  // Exported for tests so they can call the body builder directly
  // and assert on the rendered text without spinning up a transport.
  __test_buildPasswordResetBody: buildPasswordResetBody,
  __test_stripHeaderUnsafeChars: stripHeaderUnsafeChars,
  __test_parseFromAddress: parseFromAddress,
  __test_buildHttpsApiTransport: buildHttpsApiTransport,
  PASSWORD_RESET_TTL_HOURS,
  PASSWORD_RESET_SUBJECT,
};
