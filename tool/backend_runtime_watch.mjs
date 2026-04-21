#!/usr/bin/env node

import process from "node:process";
import {fetchWithHttpFallback} from "./http_request_with_fallback.mjs";

function parseArgs(argv) {
  const options = {
    apiUrl: process.env.RODNYA_RUNTIME_API_URL || "https://api.rodnya-tree.ru",
    email: process.env.RODNYA_RUNTIME_EMAIL || "",
    password: process.env.RODNYA_RUNTIME_PASSWORD || "",
    webhookUrl:
      process.env.RODNYA_RUNTIME_ALERT_WEBHOOK_URL ||
      process.env.RODNYA_READY_ALERT_WEBHOOK_URL ||
      "",
    failOnWarnings:
      String(process.env.RODNYA_RUNTIME_FAIL_ON_WARNINGS || "").trim() === "1",
    failOnRecentErrors:
      String(process.env.RODNYA_RUNTIME_FAIL_ON_RECENT_ERRORS || "1").trim() !==
      "0",
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    const nextValue = argv[index + 1];
    switch (token) {
      case "--api-url":
        options.apiUrl = nextValue || options.apiUrl;
        index += 1;
        break;
      case "--email":
        options.email = nextValue || options.email;
        index += 1;
        break;
      case "--password":
        options.password = nextValue || options.password;
        index += 1;
        break;
      case "--webhook-url":
        options.webhookUrl = nextValue || options.webhookUrl;
        index += 1;
        break;
      case "--fail-on-warnings":
        options.failOnWarnings = true;
        break;
      case "--allow-recent-errors":
        options.failOnRecentErrors = false;
        break;
      default:
        break;
    }
  }

  return options;
}

async function notifyWebhook(webhookUrl, payload) {
  const normalizedUrl = String(webhookUrl || "").trim();
  if (!normalizedUrl) {
    return;
  }

  const response = await fetchWithHttpFallback(normalizedUrl, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      accept: "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    throw new Error(
      `Runtime webhook failed with ${response.status}: ${await response.text()}`,
    );
  }
}

async function login({apiUrl, email, password}) {
  const response = await fetchWithHttpFallback(
    `${apiUrl.replace(/\/+$/, "")}/v1/auth/login`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        accept: "application/json",
      },
      body: JSON.stringify({email, password}),
    },
  );
  if (!response.ok) {
    throw new Error(
      `Runtime login failed with ${response.status}: ${await response.text()}`,
    );
  }
  const payload = await response.json();
  const accessToken = String(payload?.accessToken || "").trim();
  if (!accessToken) {
    throw new Error("Runtime login did not return accessToken.");
  }
  return accessToken;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (!options.email || !options.password) {
    console.log(
      JSON.stringify(
        {
          skipped: true,
          reason:
            "RODNYA_RUNTIME_EMAIL/RODNYA_RUNTIME_PASSWORD are not configured.",
        },
        null,
        2,
      ),
    );
    return;
  }

  const accessToken = await login(options);
  const response = await fetchWithHttpFallback(
    `${options.apiUrl.replace(/\/+$/, "")}/v1/admin/runtime`,
    {
      headers: {
        authorization: `Bearer ${accessToken}`,
        accept: "application/json",
      },
    },
  );

  if (!response.ok) {
    throw new Error(
      `Runtime endpoint failed with ${response.status}: ${await response.text()}`,
    );
  }

  const payload = await response.json();
  const warnings = Array.isArray(payload?.warnings) ? payload.warnings : [];
  const recentErrors = Array.isArray(payload?.runtime?.recentErrors)
    ? payload.runtime.recentErrors
    : [];
  const summary = {
    apiUrl: options.apiUrl,
    status: payload?.status || null,
    releaseLabel: payload?.runtime?.releaseLabel || null,
    warnings,
    recentErrors,
    recentErrorCount: recentErrors.length,
  };

  console.log(JSON.stringify(summary, null, 2));

  const shouldAlert =
    (options.failOnWarnings && warnings.length > 0) ||
    (options.failOnRecentErrors && recentErrors.length > 0);

  if (shouldAlert) {
    await notifyWebhook(options.webhookUrl, {
      source: "rodnya-runtime-watch",
      generatedAt: new Date().toISOString(),
      ...summary,
    });
  }

  if (options.failOnWarnings && warnings.length > 0) {
    process.exitCode = 1;
  }
  if (options.failOnRecentErrors && recentErrors.length > 0) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(`[backend-runtime-watch] ${error?.stack || error}`);
  process.exitCode = 1;
});
