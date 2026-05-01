const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildSafePreviewText,
  describeMessagePreview,
  normalizeAttachmentWaveform,
  normalizeMessageAttachments,
  normalizeReplyReference,
} = require("../src/chat-utils");

test("buildSafePreviewText trims and caps oversized text", () => {
  const preview = buildSafePreviewText(`  ${"a".repeat(400)}  `, 20);

  assert.equal(preview.length, 20);
  assert.equal(preview.endsWith("…"), true);
});

test("describeMessagePreview prefers text and falls back to media labels", () => {
  assert.equal(describeMessagePreview({text: " Привет "}), "Привет");
  assert.equal(
    describeMessagePreview({
      attachments: [
        {url: "https://cdn.example.com/voice.m4a", presentation: "voice_note"},
      ],
    }),
    "Голосовое",
  );
  assert.equal(
    describeMessagePreview({
      mediaUrls: [
        "https://cdn.example.com/one.jpg",
        "https://cdn.example.com/two.jpg",
      ],
    }),
    "Фото (2)",
  );
});

test("normalizeMessageAttachments preserves explicit metadata", () => {
  const attachments = normalizeMessageAttachments({
    attachments: [
      {
        url: " https://cdn.example.com/video.mp4 ",
        mimeType: "video/mp4",
        presentation: "video_note",
        durationMs: "1200",
        waveform: [0, "0.5", 2, -1],
        width: "640",
        height: "480",
      },
      {url: ""},
    ],
  });

  assert.equal(attachments.length, 1);
  assert.equal(attachments[0].type, "video");
  assert.equal(attachments[0].presentation, "video_note");
  assert.equal(attachments[0].durationMs, 1200);
  assert.deepEqual(attachments[0].waveform, [0, 0.5, 1, 0]);
  assert.equal(attachments[0].width, 640);
  assert.equal(attachments[0].height, 480);
});

test("normalizeAttachmentWaveform caps oversized samples", () => {
  const waveform = normalizeAttachmentWaveform(
    Array.from({length: 150}, (_, index) => (index % 3) / 2),
    30,
  );

  assert.equal(waveform.length, 30);
  assert.equal(waveform.every((value) => value >= 0 && value <= 1), true);
});

test("normalizeReplyReference rejects empty refs and normalizes sender name", () => {
  assert.equal(normalizeReplyReference({}), null);
  assert.deepEqual(
    normalizeReplyReference({
      id: " message-1 ",
      senderName: " ",
      text: " Ответ ",
    }),
    {
      messageId: "message-1",
      senderId: "",
      senderName: "Участник",
      text: "Ответ",
    },
  );
});
