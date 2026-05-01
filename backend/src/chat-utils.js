function buildSafePreviewText(value, maxLength = 280) {
  if (value === null || value === undefined) {
    return "";
  }
  const rawText =
    typeof value === "string"
      ? value
      : typeof value === "number" || typeof value === "boolean"
        ? String(value)
        : "";
  if (!rawText) {
    return "";
  }
  const sampledText =
    rawText.length > maxLength * 4
      ? rawText.slice(0, maxLength * 4)
      : rawText;
  const normalizedText = sampledText.trim();
  if (!normalizedText) {
    return "";
  }
  if (normalizedText.length <= maxLength) {
    return normalizedText;
  }
  return `${normalizedText.slice(0, Math.max(0, maxLength - 1)).trimEnd()}…`;
}

function normalizeAttachmentPresentation(rawPresentation, rawType) {
  const normalizedPresentation = String(rawPresentation || "").trim().toLowerCase();
  if (
    normalizedPresentation === "default" ||
    normalizedPresentation === "voice_note" ||
    normalizedPresentation === "video_note"
  ) {
    return normalizedPresentation;
  }

  const normalizedType = String(rawType || "").trim().toLowerCase();
  if (normalizedType === "audio") {
    return "default";
  }
  if (normalizedType === "video") {
    return "default";
  }
  return "default";
}

function normalizeAttachmentType(rawType, url, mimeType) {
  const normalizedType = String(rawType || "").trim().toLowerCase();
  if (
    normalizedType === "image" ||
    normalizedType === "video" ||
    normalizedType === "audio" ||
    normalizedType === "file"
  ) {
    return normalizedType;
  }

  const normalizedMimeType = String(mimeType || "").trim().toLowerCase();
  if (normalizedMimeType.startsWith("image/")) {
    return "image";
  }
  if (normalizedMimeType.startsWith("video/")) {
    return "video";
  }
  if (normalizedMimeType.startsWith("audio/")) {
    return "audio";
  }

  const normalizedUrl = String(url || "").trim().toLowerCase();
  if (/\.(png|jpe?g|gif|webp)$/.test(normalizedUrl)) {
    return "image";
  }
  if (/\.(mp4|mov|webm)$/.test(normalizedUrl)) {
    return "video";
  }
  if (/\.(m4a|aac|mp3|wav|ogg)$/.test(normalizedUrl)) {
    return "audio";
  }

  return "file";
}

function normalizeAttachmentWaveform(rawWaveform, maxSamples = 100) {
  const samples = Array.isArray(rawWaveform)
    ? rawWaveform
        .map((value) => Number(value))
        .filter((value) => Number.isFinite(value))
        .map((value) => Math.max(0, Math.min(1, value)))
    : [];
  if (samples.length <= maxSamples) {
    return samples;
  }

  const bucketSize = samples.length / maxSamples;
  const normalized = [];
  for (let bucket = 0; bucket < maxSamples; bucket += 1) {
    const start = Math.floor(bucket * bucketSize);
    const end = Math.min(samples.length, Math.ceil((bucket + 1) * bucketSize));
    if (start >= end) {
      continue;
    }
    let sum = 0;
    for (let index = start; index < end; index += 1) {
      sum += samples[index];
    }
    normalized.push(Math.max(0, Math.min(1, sum / (end - start))));
  }
  return normalized;
}

function normalizeMessageAttachments(message) {
  const explicitAttachments = Array.isArray(message?.attachments)
    ? message.attachments
        .map((attachment) => {
          const url = String(attachment?.url || "").trim();
          if (!url) {
            return null;
          }

          return {
            type: normalizeAttachmentType(
              attachment?.type,
              url,
              attachment?.mimeType,
            ),
            url,
            presentation: normalizeAttachmentPresentation(
              attachment?.presentation,
              attachment?.type,
            ),
            mimeType: attachment?.mimeType
              ? String(attachment.mimeType).trim()
              : null,
            fileName: attachment?.fileName
              ? String(attachment.fileName).trim()
              : null,
            sizeBytes: Number.isFinite(Number(attachment?.sizeBytes))
              ? Number(attachment.sizeBytes)
              : null,
            durationMs: Number.isFinite(Number(attachment?.durationMs))
              ? Number(attachment.durationMs)
              : null,
            waveform: normalizeAttachmentWaveform(attachment?.waveform),
            width: Number.isFinite(Number(attachment?.width))
              ? Number(attachment.width)
              : null,
            height: Number.isFinite(Number(attachment?.height))
              ? Number(attachment.height)
              : null,
            thumbnailUrl: attachment?.thumbnailUrl
              ? String(attachment.thumbnailUrl).trim()
              : null,
          };
        })
        .filter(Boolean)
    : [];
  if (explicitAttachments.length > 0) {
    return explicitAttachments;
  }

  const legacyUrls = new Set();
  if (Array.isArray(message?.mediaUrls)) {
    for (const entry of message.mediaUrls) {
      const value = String(entry || "").trim();
      if (value) {
        legacyUrls.add(value);
      }
    }
  }
  const imageUrl = String(message?.imageUrl || "").trim();
  if (imageUrl) {
    legacyUrls.add(imageUrl);
  }

  return Array.from(legacyUrls).map((url) => ({
    type: normalizeAttachmentType("image", url, "image/jpeg"),
    url,
    presentation: "default",
    mimeType: "image/jpeg",
    fileName: null,
    sizeBytes: null,
    durationMs: null,
    waveform: [],
    width: null,
    height: null,
    thumbnailUrl: null,
  }));
}

function normalizeReplyReference(replyTo) {
  if (!replyTo || typeof replyTo !== "object") {
    return null;
  }

  const messageId = String(replyTo.messageId || replyTo.id || "").trim();
  if (!messageId) {
    return null;
  }

  return {
    messageId,
    senderId: String(replyTo.senderId || "").trim(),
    senderName: String(replyTo.senderName || "Участник").trim() || "Участник",
    text: String(replyTo.text || "").trim(),
  };
}

function describeMessagePreview(message) {
  const text = buildSafePreviewText(message?.text, 280);
  if (text) {
    return text;
  }

  const attachments = normalizeMessageAttachments(message);
  if (
    attachments.some((attachment) => attachment.presentation === "video_note")
  ) {
    return "Видеосообщение";
  }
  if (
    attachments.some((attachment) => attachment.presentation === "voice_note")
  ) {
    return "Голосовое";
  }
  const imageCount = attachments.filter((attachment) => attachment.type === "image")
    .length;
  if (imageCount > 1) {
    return `Фото (${imageCount})`;
  }
  if (attachments.some((attachment) => attachment.type === "video")) {
    return "Видео";
  }
  if (attachments.some((attachment) => attachment.type === "audio")) {
    return "Голосовое";
  }
  if (imageCount === 1) {
    return "Фото";
  }
  if (attachments.some((attachment) => attachment.type === "file")) {
    return "Файл";
  }

  return "";
}

module.exports = {
  buildSafePreviewText,
  describeMessagePreview,
  normalizeAttachmentPresentation,
  normalizeAttachmentType,
  normalizeAttachmentWaveform,
  normalizeMessageAttachments,
  normalizeReplyReference,
};
