"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  createEmailSender,
  __test_parseFromAddress,
  __test_buildHttpsApiTransport,
  __test_stripHeaderUnsafeChars,
} = require("../src/email-sender");

// ── parseFromAddress ─────────────────────────────────────────────────

test("parseFromAddress splits 'Name <email>' format", () => {
  assert.deepEqual(__test_parseFromAddress('"Родня" <no-reply@rodnya-tree.ru>'), {
    name: "Родня",
    email: "no-reply@rodnya-tree.ru",
  });
  assert.deepEqual(
    __test_parseFromAddress("Родня <no-reply@rodnya-tree.ru>"),
    {name: "Родня", email: "no-reply@rodnya-tree.ru"},
  );
});

test("parseFromAddress handles bare email without display name", () => {
  assert.deepEqual(__test_parseFromAddress("no-reply@rodnya-tree.ru"), {
    name: "",
    email: "no-reply@rodnya-tree.ru",
  });
});

// ── stripHeaderUnsafeChars ───────────────────────────────────────────

test("stripHeaderUnsafeChars drops CR/LF/tab so a crafted display name can't graft a Bcc header", () => {
  const malicious = "Артём\r\nBcc: attacker@evil.com";
  assert.equal(
    __test_stripHeaderUnsafeChars(malicious),
    "Артём Bcc: attacker@evil.com",
  );
  assert.equal(__test_stripHeaderUnsafeChars("clean\tname"), "clean name");
  assert.equal(__test_stripHeaderUnsafeChars(null), "");
});

// ── HTTPS API transport ──────────────────────────────────────────────

// Replace the global fetch for the duration of one test. Returns a
// recording fake we can assert on plus a cleanup function.
function withFakeFetch(handler) {
  const calls = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    calls.push({url, options});
    return handler(url, options);
  };
  return {
    calls,
    restore() {
      globalThis.fetch = originalFetch;
    },
  };
}

test("HTTPS API transport posts a UniSender Go message envelope and returns the job id", async () => {
  const fake = withFakeFetch(async () => {
    return new Response(
      JSON.stringify({
        status: "success",
        job_id: "job-123",
        emails: ["alice@example.com"],
        failed_emails: {},
      }),
      {status: 200, headers: {"content-type": "application/json"}},
    );
  });
  try {
    const transport = __test_buildHttpsApiTransport({
      apiKey: "test-key-9999",
      baseUrl: "https://go2.unisender.ru/ru/transactional/api/v1/",
    });
    const result = await transport.sendMail({
      from: '"Родня" <no-reply@rodnya-tree.ru>',
      to: "alice@example.com",
      subject: "Сброс пароля",
      text: "plain version",
      html: "<p>html version</p>",
    });

    assert.equal(fake.calls.length, 1);
    const sent = fake.calls[0];
    assert.equal(
      sent.url,
      "https://go2.unisender.ru/ru/transactional/api/v1/email/send.json",
    );
    assert.equal(sent.options.method, "POST");
    assert.equal(sent.options.headers["X-API-KEY"], "test-key-9999");
    assert.equal(
      sent.options.headers["Content-Type"],
      "application/json",
    );
    const body = JSON.parse(sent.options.body);
    assert.deepEqual(body.message.recipients, [{email: "alice@example.com"}]);
    assert.equal(body.message.subject, "Сброс пароля");
    assert.equal(body.message.from_email, "no-reply@rodnya-tree.ru");
    assert.equal(body.message.from_name, "Родня");
    assert.equal(body.message.body.plaintext, "plain version");
    assert.equal(body.message.body.html, "<p>html version</p>");

    assert.equal(result.messageId, "job-123");
    assert.deepEqual(result.accepted, ["alice@example.com"]);
  } finally {
    fake.restore();
  }
});

test("HTTPS API transport surfaces a structured error on non-success response", async () => {
  const fake = withFakeFetch(async () => {
    return new Response(
      JSON.stringify({
        status: "error",
        message: "invalid api key",
        code: 401,
      }),
      {status: 401, headers: {"content-type": "application/json"}},
    );
  });
  try {
    const transport = __test_buildHttpsApiTransport({
      apiKey: "bogus",
      baseUrl: "https://go2.unisender.ru/ru/transactional/api/v1",
    });
    await assert.rejects(
      () =>
        transport.sendMail({
          from: "no-reply@rodnya-tree.ru",
          to: "alice@example.com",
          subject: "x",
          text: "x",
          html: "<p>x</p>",
        }),
      (err) =>
        /invalid api key/i.test(err.message) &&
        err.statusCode === 401,
    );
  } finally {
    fake.restore();
  }
});

test("HTTPS API transport wraps network-level failures with a clear message", async () => {
  const fake = withFakeFetch(async () => {
    throw new Error("ECONNREFUSED");
  });
  try {
    const transport = __test_buildHttpsApiTransport({
      apiKey: "k",
      baseUrl: "https://go2.unisender.ru/ru/transactional/api/v1",
    });
    await assert.rejects(
      () =>
        transport.sendMail({
          from: "no-reply@rodnya-tree.ru",
          to: "alice@example.com",
          subject: "x",
          text: "x",
        }),
      /UniSender API network error.*ECONNREFUSED/,
    );
  } finally {
    fake.restore();
  }
});

// ── createEmailSender transport selection ────────────────────────────

test("createEmailSender prefers HTTPS API when unisenderApiKey is set, even if SMTP_* are also set", () => {
  const sender = createEmailSender({
    config: {
      unisenderApiKey: "key",
      // SMTP also configured — proves we pick HTTPS over SMTP.
      smtpHost: "smtp.example.com",
      smtpPort: 587,
      smtpUser: "u",
      smtpPassword: "p",
    },
  });
  assert.equal(sender.activeTransport(), "https-api");
  assert.equal(sender.isUsingLogger(), false);
});

test("createEmailSender falls back to SMTP when only SMTP is configured", () => {
  const sender = createEmailSender({
    config: {
      smtpHost: "smtp.example.com",
      smtpPort: 587,
      smtpUser: "u",
      smtpPassword: "p",
    },
  });
  assert.equal(sender.activeTransport(), "smtp");
});

test("createEmailSender falls back to console logger when neither transport is configured", () => {
  const sender = createEmailSender({config: {}});
  assert.equal(sender.activeTransport(), "logger");
  assert.equal(sender.isUsingLogger(), true);
});

test("createEmailSender via HTTPS API → sendPasswordResetEmail builds the right envelope and shape", async () => {
  const fake = withFakeFetch(async () => {
    return new Response(
      JSON.stringify({
        status: "success",
        job_id: "job-abc",
        emails: ["user@rodnya.app"],
        failed_emails: {},
      }),
      {status: 200, headers: {"content-type": "application/json"}},
    );
  });
  try {
    const sender = createEmailSender({
      config: {
        unisenderApiKey: "k",
        unisenderApiBaseUrl: "https://go2.unisender.ru/ru/transactional/api/v1",
        mailFrom: "no-reply@rodnya-tree.ru",
        mailFromName: "Родня",
      },
    });
    const result = await sender.sendPasswordResetEmail({
      to: "user@rodnya.app",
      resetUrl: "https://rodnya-tree.ru/reset-password?token=abc",
      displayName: "Артём",
    });
    assert.equal(result.ok, true);
    assert.equal(result.messageId, "job-abc");
    assert.equal(fake.calls.length, 1);
    const body = JSON.parse(fake.calls[0].options.body);
    assert.equal(body.message.from_name, "Родня");
    // The bottom-up "Здравствуйте, Артём!" greeting from the
    // template builder must thread through to the wire payload.
    assert.match(body.message.body.plaintext, /Здравствуйте, Артём!/);
    assert.match(
      body.message.body.html,
      /Сбросить пароль/,
    );
    // URL must NOT be substituted with anything unsafe.
    assert.match(
      body.message.body.plaintext,
      /https:\/\/rodnya-tree\.ru\/reset-password\?token=abc/,
    );
  } finally {
    fake.restore();
  }
});

test("createEmailSender via HTTPS API → SMTP failure does NOT leak detail to caller (returns generic envelope)", async () => {
  const fake = withFakeFetch(async () => {
    return new Response("server boom", {status: 500});
  });
  try {
    const sender = createEmailSender({
      config: {
        unisenderApiKey: "k",
        unisenderApiBaseUrl: "https://go2.unisender.ru/ru/transactional/api/v1",
      },
    });
    const result = await sender.sendPasswordResetEmail({
      to: "user@rodnya.app",
      resetUrl: "https://rodnya-tree.ru/reset-password?token=abc",
    });
    assert.equal(result.ok, false);
    assert.equal(result.error, "SEND_FAILED");
  } finally {
    fake.restore();
  }
});

test("sendPasswordResetEmail rejects relative reset URLs (defense against route misconfiguration)", async () => {
  const sender = createEmailSender({config: {}}); // logger transport
  await assert.rejects(
    () =>
      sender.sendPasswordResetEmail({
        to: "user@rodnya.app",
        resetUrl: "/reset-password?token=abc",
      }),
    /INVALID_RESET_URL/,
  );
});

test("sendPasswordResetEmail rejects malformed recipient addresses", async () => {
  const sender = createEmailSender({config: {}});
  await assert.rejects(
    () =>
      sender.sendPasswordResetEmail({
        to: "not-an-email",
        resetUrl: "https://rodnya-tree.ru/reset-password?token=abc",
      }),
    /INVALID_EMAIL_RECIPIENT/,
  );
});
