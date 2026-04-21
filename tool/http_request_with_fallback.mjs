import {execFile as execFileCallback} from "node:child_process";
import dns from "node:dns";
import process from "node:process";
import {setTimeout as delay} from "node:timers/promises";
import {promisify} from "node:util";

dns.setDefaultResultOrder("ipv4first");

const execFile = promisify(execFileCallback);
const FETCH_RETRY_LIMIT = 3;
const FETCH_RETRY_DELAY_MS = 1_000;
const CURL_MARKER = "__RODNYA_HTTP_STATUS__:";

class CurlFallbackResponse {
  constructor(status, bodyText) {
    this.status = status;
    this.ok = status >= 200 && status < 300;
    this._bodyText = bodyText;
  }

  async text() {
    return this._bodyText;
  }

  async json() {
    return JSON.parse(this._bodyText || "null");
  }
}

function normalizeHeaders(headers) {
  if (!headers) {
    return [];
  }
  if (headers instanceof Headers) {
    return Array.from(headers.entries());
  }
  if (Array.isArray(headers)) {
    return headers.map(([key, value]) => [String(key), String(value)]);
  }
  return Object.entries(headers).map(([key, value]) => [
    String(key),
    String(value),
  ]);
}

function isTransientFetchError(error) {
  if (!error) {
    return false;
  }

  const message = String(error.message || "").toLowerCase();
  const causeCode = String(error.cause?.code || "").toLowerCase();
  return (
    error.name === "TypeError" ||
    message.includes("fetch failed") ||
    message.includes("networkerror") ||
    message.includes("socket") ||
    message.includes("timed out") ||
    message.includes("econnreset") ||
    message.includes("econnrefused") ||
    causeCode.includes("timeout")
  );
}

async function curlRequest(input, init) {
  const curlExecutable = process.platform === "win32" ? "curl.exe" : "curl";
  const method = String(init?.method || "GET").toUpperCase();
  const body =
    init?.body == null
      ? null
      : typeof init.body === "string"
        ? init.body
        : JSON.stringify(init.body);
  const args = [
    "--silent",
    "--show-error",
    "--location",
    "--connect-timeout",
    "15",
    "--max-time",
    "45",
    "--request",
    method,
  ];

  for (const [key, value] of normalizeHeaders(init?.headers)) {
    args.push("--header", `${key}: ${value}`);
  }

  if (body != null) {
    args.push("--data-raw", body);
  }

  args.push(
    "--write-out",
    `\n${CURL_MARKER}%{http_code}`,
    String(input),
  );

  const {stdout, stderr} = await execFile(curlExecutable, args, {
    maxBuffer: 20 * 1024 * 1024,
  });
  const markerIndex = stdout.lastIndexOf(CURL_MARKER);
  if (markerIndex === -1) {
    throw new Error(
      `curl fallback did not return an HTTP status marker.${stderr ? ` stderr=${stderr}` : ""}`,
    );
  }

  const bodyText = stdout.slice(0, markerIndex).replace(/\r?\n$/, "");
  const statusText = stdout.slice(markerIndex + CURL_MARKER.length).trim();
  const status = Number.parseInt(statusText, 10);
  if (!Number.isFinite(status)) {
    throw new Error(`curl fallback returned invalid status: ${statusText}`);
  }

  return new CurlFallbackResponse(status, bodyText);
}

export async function fetchWithHttpFallback(
  input,
  init,
  {retries = FETCH_RETRY_LIMIT} = {},
) {
  let lastError = null;
  for (let attempt = 1; attempt <= retries; attempt += 1) {
    try {
      return await fetch(input, init);
    } catch (error) {
      lastError = error;
      if (attempt >= retries || !isTransientFetchError(error)) {
        break;
      }
      await delay(FETCH_RETRY_DELAY_MS * attempt);
    }
  }

  return curlRequest(input, init).catch((curlError) => {
    if (lastError) {
      curlError.cause = lastError;
    }
    throw curlError;
  });
}
