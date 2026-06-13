const {enforceSafeUrl} = require("../input-guards");

function finiteInt(value) {
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

// U1: OTA self-update для sideloaded APK-сборок (раздача через Telegram,
// магазин их не обновляет). Эндпоинт ПУБЛИЧНЫЙ — без requireAuth, потому
// что обновиться нужно и до входа.
//
// Источник истины — env (config.latestAndroidUpdate). Пока оператор не
// задал versionCode + валидный https apkUrl, фича выключена: отвечаем
// 204, и клиент молчит (никаких баннеров).
function registerAppUpdateRoutes(app, {config}) {
  app.get("/v1/app/latest", (req, res) => {
    const latest = (config && config.latestAndroidUpdate) || {};
    const versionCode = finiteInt(latest.versionCode);

    // APK скачивается и ставится на устройство — только https (cleartext
    // можно подменить по дороге). Невалидную/не-https ссылку трактуем
    // как «фича выключена».
    const apkGuard = enforceSafeUrl(latest.apkUrl, {
      fieldName: "apkUrl",
      allowEmpty: false,
      allowedSchemes: ["https"],
    });

    // U6: enforceSafeUrl проверяет схему, но не структуру URL —
    // дополнительно требуем корректный URL с непустым host (иначе
    // "https:///x" прошёл бы). Невалидный → фича выключена.
    let apkHasHost = false;
    if (apkGuard.ok) {
      try {
        apkHasHost = Boolean(new URL(apkGuard.value).hostname);
      } catch (_) {
        apkHasHost = false;
      }
    }

    if (versionCode <= 0 || !apkGuard.ok || !apkHasHost) {
      res.status(204).end();
      return;
    }

    res.json({
      versionCode,
      versionName: String(latest.versionName || "").trim() || null,
      apkUrl: apkGuard.value,
      minVersionCode: finiteInt(latest.minVersionCode),
      notes: String(latest.notes || "").trim() || null,
      // U6: hex SHA-256 (или null) — клиент сверяет перед установкой.
      sha256: String(latest.sha256 || "").trim() || null,
    });
  });
}

module.exports = {registerAppUpdateRoutes};
