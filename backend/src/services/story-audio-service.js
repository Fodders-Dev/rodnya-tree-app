const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const crypto = require("node:crypto");
const {execFile} = require("node:child_process");
const {promisify} = require("node:util");

const execFileAsync = promisify(execFile);

let cachedFfmpegAvailable = null;

async function isFfmpegAvailable() {
  if (cachedFfmpegAvailable !== null) {
    return cachedFfmpegAvailable;
  }
  try {
    await execFileAsync("ffmpeg", ["-version"], {timeout: 3000});
    cachedFfmpegAvailable = true;
  } catch (_) {
    cachedFfmpegAvailable = false;
  }
  return cachedFfmpegAvailable;
}

/**
 * Normalizes uploaded browser/device audio to universal m4a/AAC when ffmpeg
 * is present on the host so Chrome WebM recordings play reliably on iOS Safari.
 * Gracefully returns the original buffer if ffmpeg is absent or transcoding fails.
 */
async function normalizeStoryAudio({
  buffer,
  contentType,
  originalExt = "webm",
  ffmpegAvailable = null,
  runExecFile = execFileAsync,
} = {}) {
  const cleanType = String(contentType || "").split(";")[0].trim().toLowerCase();
  const cleanExt = String(originalExt || "webm").replace(/[^a-z0-9]/gi, "").toLowerCase() || "webm";
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) {
    return {buffer, contentType: cleanType || "audio/mp4", ext: cleanExt, transcoded: false};
  }
  if (cleanType === "audio/mp4" || cleanType === "audio/m4a" || cleanType === "audio/x-m4a" || cleanExt === "m4a") {
    return {buffer, contentType: "audio/mp4", ext: "m4a", transcoded: false};
  }

  const hasFfmpeg = ffmpegAvailable !== null ? Boolean(ffmpegAvailable) : await isFfmpegAvailable();
  if (!hasFfmpeg) {
    return {buffer, contentType: cleanType || "audio/webm", ext: cleanExt, transcoded: false};
  }

  const id = crypto.randomUUID();
  const inPath = path.join(os.tmpdir(), `rodnya-story-in-${id}.${cleanExt}`);
  const outPath = path.join(os.tmpdir(), `rodnya-story-out-${id}.m4a`);
  try {
    await fs.writeFile(inPath, buffer);
    await runExecFile(
      "ffmpeg",
      ["-y", "-i", inPath, "-vn", "-c:a", "aac", "-b:a", "64k", "-movflags", "+faststart", outPath],
      {timeout: 30_000},
    );
    const outBuffer = await fs.readFile(outPath);
    if (!outBuffer || outBuffer.length === 0) {
      return {buffer, contentType: cleanType || "audio/webm", ext: cleanExt, transcoded: false};
    }
    return {buffer: outBuffer, contentType: "audio/mp4", ext: "m4a", transcoded: true};
  } catch (error) {
    console.warn("[story-audio] ffmpeg normalization skipped:", error?.message || error);
    return {buffer, contentType: cleanType || "audio/webm", ext: cleanExt, transcoded: false};
  } finally {
    await Promise.all([
      fs.rm(inPath, {force: true}).catch(() => {}),
      fs.rm(outPath, {force: true}).catch(() => {}),
    ]);
  }
}

/**
 * Best-effort automatic speech-to-text transcription using an OpenAI-compatible
 * endpoint when RODNYA_STT_API_URL + RODNYA_STT_API_KEY are configured.
 */
async function transcribeStoryAudio({
  buffer,
  contentType = "audio/mp4",
  filename = "story.m4a",
  config,
  fetchImpl = fetch,
} = {}) {
  if (!config?.sttEnabled || !config?.sttApiUrl || !config?.sttApiKey) {
    return null;
  }
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) {
    return null;
  }
  try {
    const form = new FormData();
    const blob = new Blob([buffer], {type: contentType || "audio/mp4"});
    form.append("file", blob, filename);
    form.append("model", config.sttModel || "whisper-1");
    form.append("language", "ru");

    const response = await fetchImpl(config.sttApiUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${config.sttApiKey}`,
      },
      body: form,
      signal: AbortSignal.timeout(25_000),
    });
    if (!response.ok) {
      console.warn(`[story-audio] STT HTTP ${response.status}`);
      return null;
    }
    const rawText = await response.text();
    let parsedText = "";
    try {
      const json = JSON.parse(rawText);
      parsedText = String(json?.text || "").trim();
    } catch (_) {
      parsedText = String(rawText || "").trim();
    }
    if (!parsedText) {
      return null;
    }
    return parsedText.slice(0, 20000);
  } catch (error) {
    console.warn("[story-audio] STT failed:", error?.message || error);
    return null;
  }
}

module.exports = {
  isFfmpegAvailable,
  normalizeStoryAudio,
  transcribeStoryAudio,
};
