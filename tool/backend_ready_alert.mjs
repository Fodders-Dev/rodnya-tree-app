#!/usr/bin/env node

import process from "node:process";
import {fetchWithHttpFallback} from "./http_request_with_fallback.mjs";

function parseArgs(argv) {
  const options = {
    url: process.env.RODNYA_READY_URL || "https://api.rodnya-tree.ru/ready",
    failOnWarnings:
      String(process.env.RODNYA_READY_FAIL_ON_WARNINGS || "").trim() === "1",
    webhookUrl: process.env.RODNYA_READY_ALERT_WEBHOOK_URL || "",
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    const nextValue = argv[index + 1];
    switch (token) {
      case "--url":
        options.url = nextValue || options.url;
        index += 1;
        break;
      case "--fail-on-warnings":
        options.failOnWarnings = true;
        break;
      case "--webhook-url":
        options.webhookUrl = nextValue || options.webhookUrl;
        index += 1;
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
      `Alert webhook failed with ${response.status}: ${await response.text()}`,
    );
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const response = await fetchWithHttpFallback(options.url, {
    headers: {accept: "application/json"},
  });
  const payload = await response.json().catch(() => ({}));
  const warnings = Array.isArray(payload?.warnings) ? payload.warnings : [];
  const isReady = response.ok && payload?.ready !== false && payload?.status === "ready";

  console.log(
    JSON.stringify(
      {
        url: options.url,
        httpStatus: response.status,
        ready: isReady,
        status: payload?.status || null,
        releaseLabel: payload?.runtime?.releaseLabel || null,
        warnings,
      },
      null,
      2,
    ),
  );

  const shouldAlert =
    !isReady || (options.failOnWarnings && warnings.length > 0);
  if (shouldAlert) {
    await notifyWebhook(options.webhookUrl, {
      source: "rodnya-ready-alert",
      url: options.url,
      httpStatus: response.status,
      ready: isReady,
      status: payload?.status || null,
      releaseLabel: payload?.runtime?.releaseLabel || null,
      warnings,
      generatedAt: new Date().toISOString(),
    });
  }

  if (!isReady) {
    process.exitCode = 1;
    return;
  }
  if (options.failOnWarnings && warnings.length > 0) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(`[backend-ready-alert] ${error?.stack || error}`);
  process.exitCode = 1;
});
