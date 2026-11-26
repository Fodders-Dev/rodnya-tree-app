const crypto = require("node:crypto");
const {
  enforceSafeMediaOrLinkUrl,
  enforceSafeUrl,
} = require("../../input-guards");
const {
  ARTICLE_BLOCK_TYPES,
} = require("../constants");
const {
  normalizeNullableString,
  normalizeOptionalIsoTimestamp,
  nowIso,
} = require("./utils");

// Normalize one inline span inside a paragraph block. Drops malformed
// spans rather than throwing — a stray span shouldn't reject a whole
// save. Recognized: plain text, родственник-mention (personId ref +
// fallbackText for offline render), external link.
function normalizeArticleSpan(rawSpan) {
  if (typeof rawSpan === "string") {
    return rawSpan ? {text: rawSpan} : null;
  }
  if (!rawSpan || typeof rawSpan !== "object") return null;
  const type = normalizeNullableString(rawSpan.type);
  if (type === "mention") {
    const personId = normalizeNullableString(rawSpan.personId);
    if (!personId) return null;
    return {
      type: "mention",
      personId,
      fallbackText: String(rawSpan.fallbackText || rawSpan.text || "").trim(),
    };
  }
  if (type === "link") {
    const href = normalizeNullableString(rawSpan.href);
    if (!href) return null;
    const hrefGuard = enforceSafeUrl(href, {
      fieldName: "href",
      allowEmpty: false,
      allowedSchemes: ["http", "https"],
    });
    if (!hrefGuard.ok) {
      throw new Error("INVALID_BLOCK_CONTENT");
    }
    return {
      type: "link",
      href: hrefGuard.value,
      text: String(rawSpan.text || hrefGuard.value).trim().slice(0, 1000),
    };
  }
  // Plain text span (default).
  const text = typeof rawSpan.text === "string" ? rawSpan.text.slice(0, 20000) : "";
  return {text};
}

function normalizeArticleSpans(rawSpans) {
  if (!Array.isArray(rawSpans)) return [];
  return rawSpans.map(normalizeArticleSpan).filter(Boolean);
}

function normalizeArticleMediaItem(rawItem) {
  if (typeof rawItem === "string") {
    rawItem = {url: rawItem};
  }
  if (!rawItem || typeof rawItem !== "object") return null;
  const url = normalizeNullableString(rawItem.url);
  if (!url) return null;
  const urlGuard = enforceSafeMediaOrLinkUrl(url, {
    fieldName: "url",
    allowEmpty: false,
  });
  if (!urlGuard.ok) {
    throw new Error("INVALID_BLOCK_CONTENT");
  }
  let thumbnailUrl = normalizeNullableString(rawItem.thumbnailUrl);
  if (thumbnailUrl) {
    const thumbGuard = enforceSafeMediaOrLinkUrl(thumbnailUrl, {
      fieldName: "thumbnailUrl",
      allowEmpty: true,
    });
    if (!thumbGuard.ok) {
      throw new Error("INVALID_BLOCK_CONTENT");
    }
    thumbnailUrl = thumbGuard.value;
  }
  const caption = normalizeNullableString(rawItem.caption);
  if (caption && caption.length > 1000) {
    throw new Error("INVALID_BLOCK_CONTENT");
  }
  const accuracy = normalizeNullableString(rawItem.dateTakenAccuracy);
  return {
    url: urlGuard.value,
    thumbnailUrl,
    caption,
    dateTaken: normalizeOptionalIsoTimestamp(rawItem.dateTaken) || null,
    dateTakenAccuracy:
      accuracy === "exact" || accuracy === "year" || accuracy === "decade"
        ? accuracy
        : null,
  };
}

// Validate + normalize content for a block type. Throws
// INVALID_BLOCK_TYPE / INVALID_BLOCK_CONTENT (mapped to 400 in routes).
function normalizeArticleBlockContent(type, rawContent) {
  const normalizedType = normalizeNullableString(type);
  if (!normalizedType || !ARTICLE_BLOCK_TYPES.includes(normalizedType)) {
    throw new Error("INVALID_BLOCK_TYPE");
  }
  const content =
    rawContent && typeof rawContent === "object" ? rawContent : {};

  switch (normalizedType) {
    case "paragraph": {
      const rawSpans = Array.isArray(content.spans) ? content.spans : [];
      if (rawSpans.length > 200) throw new Error("INVALID_BLOCK_CONTENT");
      return {spans: normalizeArticleSpans(rawSpans)};
    }
    case "header": {
      const text = String(content.text || "").trim();
      if (text.length > 500) throw new Error("INVALID_BLOCK_CONTENT");
      const level = Number(content.level);
      return {
        text,
        level: level === 1 ? 1 : 2,
      };
    }
    case "photo": {
      const item = normalizeArticleMediaItem(content);
      if (!item) throw new Error("INVALID_BLOCK_CONTENT");
      return item;
    }
    case "gallery": {
      if (Array.isArray(content.items) && content.items.length > 50) {
        throw new Error("INVALID_BLOCK_CONTENT");
      }
      const items = Array.isArray(content.items)
        ? content.items.map(normalizeArticleMediaItem).filter(Boolean)
        : [];
      if (items.length === 0) throw new Error("INVALID_BLOCK_CONTENT");
      return {items};
    }
    case "audio": {
      const url = normalizeNullableString(content.url);
      if (!url) throw new Error("INVALID_BLOCK_CONTENT");
      const urlGuard = enforceSafeMediaOrLinkUrl(url, {
        fieldName: "url",
        allowEmpty: false,
      });
      if (!urlGuard.ok) throw new Error("INVALID_BLOCK_CONTENT");
      const durationSec = Number(content.durationSec);
      if (Number.isFinite(durationSec) && (durationSec < 0 || durationSec > 86400)) {
        throw new Error("INVALID_BLOCK_CONTENT");
      }
      const transcript = normalizeNullableString(content.transcript);
      if (transcript && transcript.length > 20000) {
        throw new Error("INVALID_BLOCK_CONTENT");
      }
      return {
        url: urlGuard.value,
        durationSec:
          Number.isFinite(durationSec) && durationSec > 0
            ? Math.round(durationSec)
            : null,
        transcript,
      };
    }
    case "quote": {
      const text = String(content.text || "").trim();
      const attribution = normalizeNullableString(content.attribution);
      if (text.length > 10000 || (attribution && attribution.length > 500)) {
        throw new Error("INVALID_BLOCK_CONTENT");
      }
      return {text, attribution};
    }
    case "divider":
    default:
      return {};
  }
}

function createArticleBlockRecord({type, content, actorUserId}) {
  const createdAt = nowIso();
  const author = normalizeNullableString(actorUserId);
  return {
    id: crypto.randomUUID(),
    type: normalizeNullableString(type),
    content: normalizeArticleBlockContent(type, content),
    createdByUserId: author,
    authorUserId: author,
    createdAt,
    updatedAt: createdAt,
  };
}

module.exports = {
  normalizeArticleSpan,
  normalizeArticleSpans,
  normalizeArticleMediaItem,
  normalizeArticleBlockContent,
  createArticleBlockRecord,
};
