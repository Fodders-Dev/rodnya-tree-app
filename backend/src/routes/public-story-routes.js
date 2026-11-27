const crypto = require("node:crypto");
const {normalizePublicUrl, composeDisplayName} = require("../profile-utils");
const {
  normalizeStoryAudio,
  transcribeStoryAudio,
} = require("../services/story-audio-service");

const MAX_GUEST_STORY_MEDIA_BYTES = 20 * 1024 * 1024;
const MAX_DRAIN_BYTES = 32 * 1024 * 1024;

const ALLOWED_AUDIO_MIME_TO_EXT = new Map([
  ["audio/mp4", "m4a"],
  ["audio/m4a", "m4a"],
  ["audio/x-m4a", "m4a"],
  ["audio/aac", "aac"],
  ["audio/mpeg", "mp3"],
  ["audio/mp3", "mp3"],
  ["audio/webm", "webm"],
  ["video/webm", "webm"],
  ["audio/ogg", "ogg"],
  ["audio/opus", "opus"],
  ["audio/wav", "wav"],
  ["audio/x-wav", "wav"],
  ["audio/wave", "wav"],
]);

const ALLOWED_PHOTO_MIME_TO_EXT = new Map([
  ["image/jpeg", "jpg"],
  ["image/jpg", "jpg"],
  ["image/png", "png"],
  ["image/webp", "webp"],
  ["image/heic", "heic"],
  ["image/heif", "heif"],
  ["image/gif", "gif"],
]);

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function buildPublicStoryUrl(req, config, shareToken) {
  const token = String(shareToken || "").trim();
  if (!token) return null;
  const configured = String(
    config?.publicStoryBaseUrl || config?.publicApiUrl || "",
  )
    .trim()
    .replace(/\/+$/, "");
  if (configured) {
    return `${configured}/story/${encodeURIComponent(token)}`;
  }
  const proto = String(req?.protocol || "https").trim() || "https";
  const host =
    typeof req?.get === "function"
      ? String(req.get("host") || "").trim()
      : "";
  const origin = host ? `${proto}://${host}` : "https://rodnya-tree.ru";
  return `${origin.replace(/\/+$/, "")}/story/${encodeURIComponent(token)}`;
}

function extractOrigin(urlValue) {
  const raw = String(urlValue || "").trim();
  if (!raw) return "";
  try {
    return new URL(raw).origin;
  } catch (_) {
    return "";
  }
}

function actorNameForDisplay(user) {
  return (
    user?.profile?.displayName ||
    composeDisplayName(user?.profile || {}) ||
    user?.email ||
    "Кто-то из родных"
  );
}

function truncateText(text, max) {
  const clean = String(text || "").trim();
  return clean.length > max ? `${clean.slice(0, max - 1)}…` : clean;
}

function applyPublicStoryHtmlHeaders(res, {nonce, config}) {
  const mediaOrigin = extractOrigin(config?.mediaPublicBaseUrl);
  const apiOrigin = extractOrigin(config?.publicApiUrl);
  const extraOrigins = [...new Set([mediaOrigin, apiOrigin].filter(Boolean))].join(
    " ",
  );
  const imgSrc = ["'self'", "data:", "blob:", extraOrigins]
    .filter(Boolean)
    .join(" ");
  const mediaSrc = ["'self'", "blob:", extraOrigins].filter(Boolean).join(" ");

  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate");
  res.setHeader("Referrer-Policy", "no-referrer");
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader(
    "Permissions-Policy",
    "microphone=(self), camera=(), geolocation=()",
  );
  res.setHeader(
    "Content-Security-Policy",
    [
      "default-src 'none'",
      `script-src 'nonce-${nonce}'`,
      `style-src 'nonce-${nonce}'`,
      `img-src ${imgSrc}`,
      `media-src ${mediaSrc}`,
      "connect-src 'self'",
      "frame-ancestors 'none'",
      "base-uri 'none'",
      "form-action 'self'",
    ].join("; "),
  );
}

function renderStatusHtmlPage({title, heading, message, ogTitle, ogDescription, ogImage, nonce}) {
  return `<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
  <meta name="robots" content="noindex, nofollow, noarchive" />
  <title>${escapeHtml(title)}</title>
  <meta property="og:type" content="website" />
  <meta property="og:site_name" content="Родня" />
  <meta property="og:title" content="${escapeHtml(ogTitle)}" />
  <meta property="og:description" content="${escapeHtml(ogDescription)}" />
  ${ogImage ? `<meta property="og:image" content="${escapeHtml(ogImage)}" />` : ""}
  <style nonce="${nonce}">
    :root {
      color-scheme: light dark;
      --bg: #f7f1e6;
      --surface: #ffffff;
      --ink: #1f2a1c;
      --ink-2: #4c5746;
      --accent: #2f6f4a;
      --accent-ink: #ffffff;
      --line: rgba(31, 42, 28, 0.14);
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #14180f;
        --surface: #1d2319;
        --ink: #f7f1e6;
        --ink-2: #cfc5b5;
        --accent: #6cc28d;
        --accent-ink: #102117;
        --line: rgba(247, 241, 230, 0.14);
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, system-ui, sans-serif;
      background: var(--bg);
      color: var(--ink);
      display: grid;
      place-items: center;
      padding: 20px;
    }
    main {
      width: 100%;
      max-width: 480px;
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 24px;
      padding: 28px 24px;
      text-align: center;
      box-shadow: 0 18px 36px -22px rgba(0, 0, 0, 0.22);
    }
    .brand { font-size: 13px; font-weight: 700; color: var(--accent); letter-spacing: 0.04em; text-transform: uppercase; margin-bottom: 12px; }
    h1 { font-size: 24px; line-height: 1.25; margin: 0 0 12px; }
    p { font-size: 17px; line-height: 1.5; color: var(--ink-2); margin: 0; }
  </style>
</head>
<body>
  <main>
    <div class="brand">Родня · Семейная книга</div>
    <h1>${escapeHtml(heading)}</h1>
    <p>${escapeHtml(message)}</p>
  </main>
</body>
</html>`;
}

function renderPendingStoryPage({
  token,
  requesterName,
  personName,
  personPhotoUrl,
  questionText,
  targetName,
  ogImage,
  pageUrl,
  nonce,
}) {
  const ogTitle = `${requesterName} спрашивает о ${personName} — Родня`;
  const ogDescription = truncateText(questionText, 180);
  const encodedToken = encodeURIComponent(token);

  return `<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
  <meta name="robots" content="noindex, nofollow, noarchive" />
  <title>${escapeHtml(ogTitle)}</title>
  <meta property="og:type" content="website" />
  <meta property="og:site_name" content="Родня" />
  <meta property="og:url" content="${escapeHtml(pageUrl)}" />
  <meta property="og:title" content="${escapeHtml(ogTitle)}" />
  <meta property="og:description" content="${escapeHtml(ogDescription)}" />
  ${ogImage ? `<meta property="og:image" content="${escapeHtml(ogImage)}" />` : ""}
  <style nonce="${nonce}">
    :root {
      color-scheme: light dark;
      --bg: #f7f1e6;
      --surface: #ffffff;
      --surface-soft: #f2ebe0;
      --ink: #1f2a1c;
      --ink-2: #4a5644;
      --accent: #2f6f4a;
      --accent-ink: #ffffff;
      --danger: #b83a3a;
      --line: rgba(31, 42, 28, 0.14);
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #14180f;
        --surface: #1d2319;
        --surface-soft: #262e21;
        --ink: #f7f1e6;
        --ink-2: #cfc5b5;
        --accent: #6cc28d;
        --accent-ink: #102117;
        --danger: #e06c6c;
        --line: rgba(247, 241, 230, 0.14);
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, system-ui, sans-serif;
      background: var(--bg);
      color: var(--ink);
      padding: 16px 14px 40px;
      line-height: 1.5;
    }
    main {
      width: 100%;
      max-width: 560px;
      margin: 0 auto;
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 24px;
      padding: 24px 20px;
      box-shadow: 0 18px 38px -24px rgba(0, 0, 0, 0.24);
    }
    .brand { font-size: 13px; font-weight: 800; color: var(--accent); letter-spacing: 0.04em; text-transform: uppercase; margin-bottom: 14px; }
    .hero { display: flex; align-items: center; gap: 14px; margin-bottom: 16px; }
    .avatar {
      width: 56px; height: 56px; border-radius: 999px; flex: 0 0 auto;
      background: var(--surface-soft); display: grid; place-items: center;
      font-size: 22px; font-weight: 800; color: var(--accent); overflow: hidden;
      border: 1px solid var(--line);
    }
    .avatar img { width: 100%; height: 100%; object-fit: cover; }
    .asker { font-size: 15px; color: var(--ink-2); }
    .hero-name { font-size: 21px; font-weight: 800; line-height: 1.25; }
    .question-box {
      background: var(--surface-soft);
      border-left: 4px solid var(--accent);
      border-radius: 14px;
      padding: 16px 18px;
      font-size: 20px;
      font-weight: 700;
      line-height: 1.4;
      margin: 12px 0 20px;
    }
    .section { margin-top: 20px; }
    .label { display: block; font-size: 15px; font-weight: 700; margin-bottom: 8px; }
    input[type="text"], textarea {
      width: 100%;
      font: inherit;
      font-size: 17px;
      color: var(--ink);
      background: var(--bg);
      border: 1px solid var(--line);
      border-radius: 14px;
      padding: 12px 14px;
    }
    textarea { min-height: 112px; resize: vertical; }
    .btn {
      width: 100%;
      min-height: 56px;
      border: 0;
      border-radius: 999px;
      font: inherit;
      font-size: 18px;
      font-weight: 700;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 10px;
      padding: 12px 20px;
      transition: opacity 0.15s ease;
    }
    .btn:disabled { opacity: 0.55; cursor: not-allowed; }
    .btn-primary { background: var(--accent); color: var(--accent-ink); }
    .btn-danger { background: var(--danger); color: #ffffff; }
    .btn-secondary { background: var(--surface-soft); color: var(--ink); border: 1px solid var(--line); }
    .row { display: flex; gap: 10px; flex-wrap: wrap; }
    .row > .btn { flex: 1 1 180px; }
    .rec-status { font-size: 18px; font-weight: 700; color: var(--danger); text-align: center; margin-bottom: 10px; }
    audio { width: 100%; margin: 10px 0; }
    .hint { font-size: 14px; color: var(--ink-2); margin-top: 6px; }
    .error-banner {
      margin-top: 14px; padding: 12px 14px; border-radius: 12px;
      background: rgba(184, 58, 58, 0.12); color: var(--danger); font-size: 15px; font-weight: 600;
    }
    .photo-preview { width: 100%; max-height: 260px; object-fit: cover; border-radius: 14px; margin-top: 10px; border: 1px solid var(--line); }
    .hidden { display: none !important; }
    .mt-10 { margin-top: 10px; }
    .done-card { text-align: center; padding: 16px 4px; }
    .done-card h2 { font-size: 25px; margin: 0 0 10px; }
    .done-card p { font-size: 17px; color: var(--ink-2); }
  </style>
</head>
<body>
  <main id="app-card">
    <div class="brand">Родня · История для семьи</div>
    <div id="form-view">
      <div class="hero">
        <div class="avatar">
          ${personPhotoUrl ? `<img src="${escapeHtml(personPhotoUrl)}" alt="${escapeHtml(personName)}" />` : escapeHtml((personName || "Р").slice(0, 1).toUpperCase())}
        </div>
        <div>
          <div class="asker">${escapeHtml(requesterName)} просит рассказать о родном человеке:</div>
          <div class="hero-name">${escapeHtml(personName)}</div>
        </div>
      </div>

      <div class="question-box">«${escapeHtml(questionText)}»</div>

      <div class="section">
        <label class="label" for="respondentName">Как вас подписать в семейной книге?</label>
        <input type="text" id="respondentName" maxlength="120" value="${escapeHtml(targetName || "")}" placeholder="Например: Бабушка Лида или дядя Саша" />
      </div>

      <div class="section" id="voice-section">
        <span class="label">1. Расскажите голосом (самое простое)</span>
        <button type="button" class="btn btn-primary" id="recStartBtn">Начать запись голоса</button>

        <div id="recActiveBox" class="hidden">
          <div class="rec-status">Идёт запись · <span id="recTimer">0:00</span></div>
          <button type="button" class="btn btn-danger" id="recStopBtn">Остановить запись</button>
        </div>

        <div id="recPreviewBox" class="hidden">
          <audio id="audioPreview" controls></audio>
          <button type="button" class="btn btn-secondary" id="recResetBtn">Записать заново</button>
        </div>

        <div id="micFallbackBox" class="hidden">
          <p class="hint" id="micFallbackHint">Микрофон недоступен в этом встроенном окне. Можно открыть ссылку в браузере (Safari / Chrome), выбрать аудиофайл с телефона или написать ответ текстом ниже.</p>
          <label class="btn btn-secondary" for="audioFileInput">Выбрать аудиофайл</label>
          <input type="file" id="audioFileInput" accept="audio/*" class="hidden" />
        </div>
      </div>

      <div class="section">
        <label class="label" for="textAnswer">2. Или напишите текстом (можно вместе с голосом)</label>
        <textarea id="textAnswer" maxlength="10000" placeholder="Поделитесь воспоминанием…"></textarea>
      </div>

      <div class="section">
        <span class="label">3. Можно прикрепить старое фото (необязательно)</span>
        <div class="row">
          <label class="btn btn-secondary" for="photoInput">Выбрать фотографию</label>
          <button type="button" class="btn btn-secondary hidden" id="photoClearBtn">Убрать фото</button>
        </div>
        <input type="file" id="photoInput" accept="image/*" class="hidden" />
        <img id="photoPreview" class="photo-preview hidden" alt="Выбранное фото" />
        <div id="photoCaptionWrap" class="hidden mt-10">
          <input type="text" id="photoCaption" maxlength="300" placeholder="Подпись к фото (например: 1978 год, на даче)" />
        </div>
      </div>

      <div id="errorBanner" class="error-banner hidden"></div>

      <div class="section">
        <button type="button" class="btn btn-primary" id="submitBtn">Отправить историю</button>
        <p class="hint">Регистрация не нужна — ваш рассказ сразу попадёт на страницу ${escapeHtml(personName)}.</p>
      </div>
    </div>

    <div id="done-view" class="done-card hidden">
      <h2>Спасибо! История сохранена</h2>
      <p>${escapeHtml(requesterName)} получит уведомление, а ваш рассказ уже появился в семейной книге.</p>
    </div>
  </main>

  <script nonce="${nonce}">
    (function () {
      var token = "${encodedToken}";
      var mediaUrlBase = "/story/" + token + "/media";
      var answerUrl = "/story/" + token + "/answer";

      var recStartBtn = document.getElementById("recStartBtn");
      var recActiveBox = document.getElementById("recActiveBox");
      var recStopBtn = document.getElementById("recStopBtn");
      var recTimerEl = document.getElementById("recTimer");
      var recPreviewBox = document.getElementById("recPreviewBox");
      var audioPreview = document.getElementById("audioPreview");
      var recResetBtn = document.getElementById("recResetBtn");
      var micFallbackBox = document.getElementById("micFallbackBox");
      var audioFileInput = document.getElementById("audioFileInput");
      var photoInput = document.getElementById("photoInput");
      var photoPreview = document.getElementById("photoPreview");
      var photoClearBtn = document.getElementById("photoClearBtn");
      var photoCaptionWrap = document.getElementById("photoCaptionWrap");
      var photoCaption = document.getElementById("photoCaption");
      var textAnswer = document.getElementById("textAnswer");
      var respondentName = document.getElementById("respondentName");
      var submitBtn = document.getElementById("submitBtn");
      var errorBanner = document.getElementById("errorBanner");
      var formView = document.getElementById("form-view");
      var doneView = document.getElementById("done-view");

      var mediaRecorder = null;
      var activeStream = null;
      var chunks = [];
      var timerId = null;
      var startedAtMs = 0;
      var recordedBlob = null;
      var recordedDurationSec = null;
      var audioObjectUrl = null;
      var selectedPhotoFile = null;
      var photoObjectUrl = null;

      function showError(msg) {
        if (!msg) {
          errorBanner.classList.add("hidden");
          errorBanner.textContent = "";
          return;
        }
        errorBanner.textContent = msg;
        errorBanner.classList.remove("hidden");
      }

      function formatSec(sec) {
        var total = Math.max(0, Math.floor(sec));
        var m = Math.floor(total / 60);
        var s = total % 60;
        return m + ":" + (s < 10 ? "0" + s : s);
      }

      function pickSupportedAudioMime() {
        if (typeof MediaRecorder === "undefined") return "";
        var candidates = [
          "audio/mp4;codecs=mp4a.40.2",
          "audio/mp4",
          "audio/webm;codecs=opus",
          "audio/webm",
          "audio/ogg;codecs=opus",
        ];
        if (typeof MediaRecorder.isTypeSupported !== "function") return "";
        for (var i = 0; i < candidates.length; i++) {
          if (MediaRecorder.isTypeSupported(candidates[i])) return candidates[i];
        }
        return "";
      }

      function clearAudioState() {
        recordedBlob = null;
        recordedDurationSec = null;
        if (audioObjectUrl) {
          URL.revokeObjectURL(audioObjectUrl);
          audioObjectUrl = null;
        }
        audioPreview.removeAttribute("src");
        recPreviewBox.classList.add("hidden");
        recActiveBox.classList.add("hidden");
        recStartBtn.classList.remove("hidden");
      }

      function stopActiveTracks() {
        if (activeStream) {
          activeStream.getTracks().forEach(function (t) { t.stop(); });
          activeStream = null;
        }
        if (timerId) {
          clearInterval(timerId);
          timerId = null;
        }
      }

      if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia || typeof MediaRecorder === "undefined") {
        micFallbackBox.classList.remove("hidden");
      }

      recStartBtn.addEventListener("click", function () {
        showError("");
        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia || typeof MediaRecorder === "undefined") {
          micFallbackBox.classList.remove("hidden");
          return;
        }
        navigator.mediaDevices.getUserMedia({ audio: true }).then(function (stream) {
          activeStream = stream;
          chunks = [];
          var mime = pickSupportedAudioMime();
          mediaRecorder = mime ? new MediaRecorder(stream, { mimeType: mime }) : new MediaRecorder(stream);
          mediaRecorder.ondataavailable = function (ev) {
            if (ev.data && ev.data.size > 0) chunks.push(ev.data);
          };
          mediaRecorder.onstop = function () {
            var elapsed = Math.max(1, Math.round((Date.now() - startedAtMs) / 1000));
            stopActiveTracks();
            var finalMime = (mediaRecorder && mediaRecorder.mimeType) || mime || "audio/webm";
            recordedBlob = new Blob(chunks, { type: finalMime });
            recordedDurationSec = elapsed;
            if (audioObjectUrl) URL.revokeObjectURL(audioObjectUrl);
            audioObjectUrl = URL.createObjectURL(recordedBlob);
            audioPreview.src = audioObjectUrl;
            recActiveBox.classList.add("hidden");
            recPreviewBox.classList.remove("hidden");
          };
          startedAtMs = Date.now();
          recTimerEl.textContent = "0:00";
          recStartBtn.classList.add("hidden");
          recActiveBox.classList.remove("hidden");
          mediaRecorder.start(250);
          timerId = setInterval(function () {
            var sec = Math.floor((Date.now() - startedAtMs) / 1000);
            recTimerEl.textContent = formatSec(sec);
            if (sec >= 600 && mediaRecorder && mediaRecorder.state === "recording") {
              mediaRecorder.stop();
            }
          }, 300);
        }).catch(function () {
          micFallbackBox.classList.remove("hidden");
          showError("Не удалось включить микрофон. Разрешите доступ или используйте аудиофайл / текст ниже.");
        });
      });

      recStopBtn.addEventListener("click", function () {
        if (mediaRecorder && mediaRecorder.state === "recording") {
          mediaRecorder.stop();
        }
      });

      recResetBtn.addEventListener("click", function () {
        clearAudioState();
      });

      audioFileInput.addEventListener("change", function () {
        var file = audioFileInput.files && audioFileInput.files[0];
        if (!file) return;
        recordedBlob = file;
        recordedDurationSec = null;
        if (audioObjectUrl) URL.revokeObjectURL(audioObjectUrl);
        audioObjectUrl = URL.createObjectURL(file);
        audioPreview.src = audioObjectUrl;
        recStartBtn.classList.add("hidden");
        recPreviewBox.classList.remove("hidden");
      });

      photoInput.addEventListener("change", function () {
        var file = photoInput.files && photoInput.files[0];
        if (!file) return;
        selectedPhotoFile = file;
        if (photoObjectUrl) URL.revokeObjectURL(photoObjectUrl);
        photoObjectUrl = URL.createObjectURL(file);
        photoPreview.src = photoObjectUrl;
        photoPreview.classList.remove("hidden");
        photoClearBtn.classList.remove("hidden");
        photoCaptionWrap.classList.remove("hidden");
      });

      photoClearBtn.addEventListener("click", function () {
        selectedPhotoFile = null;
        photoInput.value = "";
        if (photoObjectUrl) URL.revokeObjectURL(photoObjectUrl);
        photoObjectUrl = null;
        photoPreview.classList.add("hidden");
        photoClearBtn.classList.add("hidden");
        photoCaptionWrap.classList.add("hidden");
        photoCaption.value = "";
      });

      function uploadMedia(kind, blob) {
        var contentType = (blob && blob.type) || (kind === "photo" ? "image/jpeg" : "audio/mp4");
        return fetch(mediaUrlBase + "?kind=" + encodeURIComponent(kind), {
          method: "PUT",
          headers: { "Content-Type": contentType },
          body: blob,
        }).then(function (resp) {
          return resp.json().catch(function () { return {}; }).then(function (data) {
            if (!resp.ok) throw new Error(data.message || "Не удалось загрузить файл");
            return data;
          });
        });
      }

      submitBtn.addEventListener("click", function () {
        showError("");
        var textVal = (textAnswer.value || "").trim();
        if (!recordedBlob && !textVal && !selectedPhotoFile) {
          showError("Запишите голос, напишите текст или прикрепите фотографию.");
          return;
        }
        if (recordedBlob && recordedBlob.size > 20 * 1024 * 1024) {
          showError("Аудиозапись больше 20 МБ. Попробуйте записать чуть короче.");
          return;
        }
        if (selectedPhotoFile && selectedPhotoFile.size > 20 * 1024 * 1024) {
          showError("Фотография больше 20 МБ.");
          return;
        }

        submitBtn.disabled = true;
        submitBtn.textContent = "Сохраняем историю…";

        var chain = Promise.resolve({});
        var payload = {
          respondentName: (respondentName.value || "").trim() || null,
          text: textVal || null,
          audio: null,
          photo: null,
        };

        if (recordedBlob) {
          chain = chain.then(function () {
            return uploadMedia("audio", recordedBlob).then(function (res) {
              payload.audio = {
                mediaUrl: res.url,
                durationSec: recordedDurationSec,
                transcript: res.transcript || null,
              };
            });
          });
        }
        if (selectedPhotoFile) {
          chain = chain.then(function () {
            return uploadMedia("photo", selectedPhotoFile).then(function (res) {
              payload.photo = {
                mediaUrl: res.url,
                caption: (photoCaption.value || "").trim() || null,
              };
            });
          });
        }

        chain.then(function () {
          return fetch(answerUrl, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(payload),
          }).then(function (resp) {
            return resp.json().catch(function () { return {}; }).then(function (data) {
              if (!resp.ok) throw new Error(data.message || "Не удалось сохранить историю");
              return data;
            });
          });
        }).then(function () {
          formView.classList.add("hidden");
          doneView.classList.remove("hidden");
        }).catch(function (err) {
          showError((err && err.message) || "Ошибка отправки. Попробуйте ещё раз.");
          submitBtn.disabled = false;
          submitBtn.textContent = "Отправить историю";
        });
      });
    })();
  </script>
</body>
</html>`;
}

async function readBinaryStreamWithLimit(req, res, maxBytes) {
  const declared = Number(req.headers["content-length"]);
  if (Number.isFinite(declared) && declared > maxBytes) {
    if (declared <= MAX_DRAIN_BYTES) {
      req.resume();
    } else {
      res.on("finish", () => req.destroy());
    }
    return {tooLarge: true};
  }

  const chunks = [];
  let total = 0;
  for await (const chunk of req) {
    total += chunk.length;
    if (total > maxBytes) {
      res.on("finish", () => req.destroy());
      return {tooLarge: true};
    }
    chunks.push(chunk);
  }
  return {buffer: Buffer.concat(chunks)};
}

function registerPublicStoryRoutes(
  app,
  {store, config, mediaStorage, createAndDispatchNotification},
) {
  function defaultOgImage() {
    const appBase = String(config?.publicAppUrl || "https://rodnya-tree.ru")
      .trim()
      .replace(/\/+$/, "");
    return appBase ? `${appBase}/icons/Icon-512.png` : null;
  }

  async function notifyExpired(newlyExpired) {
    for (const request of newlyExpired || []) {
      try {
        await createAndDispatchNotification({
          userId: request.requesterUserId,
          type: "story_request_expired",
          title: "Вопрос остался без ответа",
          body: request.question?.text || "",
          data: {
            requestId: request.id,
            treeId: request.treeId,
            personId: request.personId,
          },
        });
      } catch (error) {
        console.warn("[public-story] expired notification failed", error);
      }
    }
  }

  // GET /story/:token — fast elder-friendly SSR HTML + OpenGraph card.
  app.get("/story/:token", async (req, res) => {
    const token = String(req.params.token || "").trim();
    const outcome = await store.findStoryRequestByShareToken(token);
    await notifyExpired(outcome.newlyExpired);

    const nonce = crypto.randomBytes(16).toString("base64");
    applyPublicStoryHtmlHeaders(res, {nonce, config});
    const fallbackImage = defaultOgImage();

    if (!outcome.request) {
      res.status(404).send(
        renderStatusHtmlPage({
          title: "Ссылка не найдена — Родня",
          heading: "Ссылка не найдена",
          message: "Возможно, она устарела или была скопирована не полностью.",
          ogTitle: "Родня — семейная история",
          ogDescription: "Откройте семейную книгу в Родне.",
          ogImage: fallbackImage,
          nonce,
        }),
      );
      return;
    }

    const request = outcome.request;
    if (request.status === "answered") {
      res.status(200).send(
        renderStatusHtmlPage({
          title: "История уже сохранена — Родня",
          heading: "Спасибо! История уже в семейной книге",
          message: "Ответ по этой ссылке уже записан и сохранён.",
          ogTitle: "Родня — семейная история",
          ogDescription: "Ответ уже сохранён в семейной книге.",
          ogImage: fallbackImage,
          nonce,
        }),
      );
      return;
    }

    if (request.status !== "pending") {
      res.status(410).send(
        renderStatusHtmlPage({
          title: "Ссылка больше не действует — Родня",
          heading: "Эта ссылка больше не действует",
          message: "Попросите близких прислать новую ссылку, если хотите поделиться историей.",
          ogTitle: "Родня — семейная история",
          ogDescription: "Срок действия этой ссылки закончился.",
          ogImage: fallbackImage,
          nonce,
        }),
      );
      return;
    }

    const requesterName = actorNameForDisplay(outcome.requester);
    const personName = outcome.person?.name || "родном человеке";
    const personPhotoUrl = normalizePublicUrl(outcome.person?.photoUrl || null);
    const ogImage = personPhotoUrl || fallbackImage;
    const pageUrl = buildPublicStoryUrl(req, config, token);

    res.status(200).send(
      renderPendingStoryPage({
        token,
        requesterName,
        personName,
        personPhotoUrl,
        questionText: request.question?.text || "",
        targetName: request.targetName || "",
        ogImage,
        pageUrl,
        nonce,
      }),
    );
  });

  // PUT /story/:token/media?kind=audio|photo — capability-token-gated media upload.
  app.put("/story/:token/media", async (req, res) => {
    const token = String(req.params.token || "").trim();
    const kind = String(req.query?.kind || "").trim().toLowerCase();
    if (kind !== "audio" && kind !== "photo") {
      res.status(400).json({message: "kind должен быть 'audio' или 'photo'"});
      return;
    }

    const lookup = await store.findStoryRequestByShareToken(token);
    await notifyExpired(lookup.newlyExpired);
    if (!lookup.request) {
      res.status(404).json({message: "Ссылка не найдена"});
      return;
    }
    if (lookup.request.status !== "pending") {
      res.status(410).json({message: "Эта ссылка больше не принимает ответы"});
      return;
    }

    const rawContentType = String(req.headers["content-type"] || "")
      .split(";")[0]
      .trim()
      .toLowerCase();
    const allowMap =
      kind === "audio" ? ALLOWED_AUDIO_MIME_TO_EXT : ALLOWED_PHOTO_MIME_TO_EXT;
    const ext = allowMap.get(rawContentType);
    if (!ext) {
      res.status(400).json({message: "Неподдерживаемый формат файла"});
      return;
    }

    const readResult = await readBinaryStreamWithLimit(
      req,
      res,
      MAX_GUEST_STORY_MEDIA_BYTES,
    );
    if (readResult.tooLarge) {
      res.status(413).json({message: "Файл не должен превышать 20 МБ"});
      return;
    }
    const rawBuffer = readResult.buffer;
    if (!rawBuffer || rawBuffer.length === 0) {
      res.status(400).json({message: "Файл пустой"});
      return;
    }

    let finalBuffer = rawBuffer;
    let finalContentType = rawContentType;
    let finalExt = ext;
    if (kind === "audio") {
      const normalized = await normalizeStoryAudio({
        buffer: rawBuffer,
        contentType: rawContentType,
        originalExt: ext,
      });
      finalBuffer = normalized.buffer;
      finalContentType = normalized.contentType;
      finalExt = normalized.ext;
    }

    const relativePath = `${lookup.request.id}/${crypto.randomUUID()}.${finalExt}`;
    const saved = await mediaStorage.saveObject({
      req,
      bucket: "story-answers",
      relativePath,
      contentType: finalContentType,
      fileBuffer: finalBuffer,
      uploaderUserId: null,
    });

    const recorded = await store.recordGuestStoryUpload({
      token,
      url: saved.url,
      bucket: saved.bucket,
      relativePath: saved.path,
      kind,
      contentType: finalContentType,
      size: saved.size,
    });
    await notifyExpired(recorded.newlyExpired);

    if (recorded.error) {
      await mediaStorage.deleteObjectByUrl(saved.url).catch(() => {});
      if (recorded.error === "GUEST_UPLOAD_LIMIT") {
        res.status(429).json({message: "Превышен лимит загрузок по этой ссылке"});
        return;
      }
      if (recorded.error === "NOT_PENDING") {
        res.status(410).json({message: "Эта ссылка больше не принимает ответы"});
        return;
      }
      res.status(404).json({message: "Ссылка не найдена"});
      return;
    }

    let transcript = null;
    if (kind === "audio" && config?.sttEnabled) {
      transcript = await transcribeStoryAudio({
        buffer: finalBuffer,
        contentType: finalContentType,
        filename: `story.${finalExt}`,
        config,
      });
    }

    res.status(201).json({
      url: saved.url,
      contentType: finalContentType,
      size: saved.size,
      kind,
      transcript,
    });
  });

  // POST /story/:token/answer — submit combined guest answer (audio/text/photo).
  app.post("/story/:token/answer", async (req, res) => {
    const token = String(req.params.token || "").trim();
    const outcome = await store.answerPublicStoryRequest({
      token,
      respondentName: req.body?.respondentName,
      audio: req.body?.audio,
      text: req.body?.text,
      photo: req.body?.photo,
    });
    await notifyExpired(outcome.newlyExpired);

    if (outcome.error === "NOT_FOUND") {
      res.status(404).json({message: "Ссылка не найдена"});
      return;
    }
    if (outcome.error === "NOT_PENDING") {
      res.status(410).json({message: "На этот вопрос уже ответили или срок ссылки истёк"});
      return;
    }
    if (outcome.error === "INVALID_ANSWER" || outcome.error === "INVALID_INPUT") {
      res.status(400).json({message: "Проверьте введённый ответ"});
      return;
    }
    if (outcome.error) {
      res.status(500).json({message: "Не удалось сохранить историю"});
      return;
    }

    for (const orphanUrl of outcome.unusedUploads || []) {
      await mediaStorage.deleteObjectByUrl(orphanUrl).catch(() => {});
    }

    const respondentLabel =
      outcome.request.answer?.respondentName || "Родственник по ссылке";
    await createAndDispatchNotification({
      userId: outcome.request.requesterUserId,
      type: "story_request_answered",
      title: `${respondentLabel} делится историей`,
      body: truncateText(outcome.request.question?.text || "", 80),
      data: {
        requestId: outcome.request.id,
        treeId: outcome.request.treeId,
        personId: outcome.request.personId,
        articleBlockId: outcome.blocks[0]?.id || null,
        respondentName: outcome.request.answer?.respondentName || null,
        deliveryMode: "public_link",
      },
    });

    res.json({
      ok: true,
      requestId: outcome.request.id,
      blockIds: outcome.blocks.map((b) => b.id),
    });
  });
}

module.exports = {
  registerPublicStoryRoutes,
  buildPublicStoryUrl,
  MAX_GUEST_STORY_MEDIA_BYTES,
  ALLOWED_AUDIO_MIME_TO_EXT,
  ALLOWED_PHOTO_MIME_TO_EXT,
  readBinaryStreamWithLimit,
};
