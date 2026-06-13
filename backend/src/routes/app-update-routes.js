// U1: OTA self-update для sideloaded APK-сборок (раздача через Telegram,
// магазин их не обновляет). Эндпоинт ПУБЛИЧНЫЙ — без requireAuth, потому
// что обновиться нужно и до входа.
//
// Источник истины — env (config.latestAndroidUpdate). Пока оператор не
// задал versionCode + apkUrl, фича выключена: отвечаем 204, и клиент
// молчит (никаких баннеров).
function registerAppUpdateRoutes(app, {config}) {
  app.get("/v1/app/latest", (req, res) => {
    const latest = (config && config.latestAndroidUpdate) || {};
    const versionCode = Number(latest.versionCode) || 0;
    const apkUrl = String(latest.apkUrl || "").trim();

    // Фича выключена — пустой ответ, клиент не показывает обновление.
    if (versionCode <= 0 || !apkUrl) {
      res.status(204).end();
      return;
    }

    res.json({
      versionCode,
      versionName: String(latest.versionName || "").trim() || null,
      apkUrl,
      minVersionCode: Number(latest.minVersionCode) || 0,
      notes: String(latest.notes || "").trim() || null,
    });
  });
}

module.exports = {registerAppUpdateRoutes};
