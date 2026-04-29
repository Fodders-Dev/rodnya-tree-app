function handleMediaReadError(error, res) {
  if (
    error?.message === "INVALID_MEDIA_PATH" ||
    error?.message === "UNSUPPORTED_MEDIA_URL"
  ) {
    res.status(400).json({message: "Недопустимый media path"});
    return;
  }
  if (error?.message === "MEDIA_FILE_NOT_FOUND") {
    res.status(404).json({message: "Media файл не найден"});
    return;
  }
  if (!res.headersSent) {
    res.status(502).json({message: "Не удалось открыть media файл"});
  }
}

function registerPublicMediaRoutes(app, {mediaStorage}) {
  app.get(/^\/media\/(.+)$/, async (req, res) => {
    try {
      // Proxy public objects through the API when public base URL points back to
      // /media. This avoids circular redirects and keeps legacy media URLs valid.
      const handler = mediaStorage.handlePublicGetRequest
        ? mediaStorage.handlePublicGetRequest.bind(mediaStorage)
        : mediaStorage.handleGetRequest.bind(mediaStorage);
      await handler(req, res);
    } catch (error) {
      handleMediaReadError(error, res);
    }
  });

  app.get(/^\/storage\/(.+)$/, async (req, res) => {
    try {
      await mediaStorage.handlePublicGetRequest(req, res);
    } catch (error) {
      handleMediaReadError(error, res);
    }
  });
}

function registerAuthenticatedMediaRoutes(app, {mediaStorage, requireAuth}) {
  app.post("/v1/media/upload", requireAuth, async (req, res) => {
    const {bucket, path: mediaPath, fileBase64, contentType} = req.body || {};

    if (!bucket || !mediaPath || !fileBase64) {
      res.status(400).json({
        message: "Нужны bucket, path и fileBase64",
      });
      return;
    }

    try {
      const fileBuffer = Buffer.from(String(fileBase64), "base64");
      if (fileBuffer.length === 0) {
        res.status(400).json({message: "Пустой fileBase64 payload"});
        return;
      }

      const uploadResult = await mediaStorage.saveObject({
        req,
        bucket,
        relativePath: mediaPath,
        contentType,
        fileBuffer,
      });

      res.status(201).json(uploadResult);
    } catch (error) {
      if (error.message === "INVALID_MEDIA_PATH") {
        res.status(400).json({message: "Недопустимый media path"});
        return;
      }
      res.status(500).json({message: "Не удалось сохранить файл"});
    }
  });

  app.delete("/v1/media", requireAuth, async (req, res) => {
    const urlValue = String(req.body?.url || "").trim();
    if (!urlValue) {
      res.status(400).json({message: "Нужен url"});
      return;
    }

    try {
      await mediaStorage.deleteObjectByUrl(urlValue);
      res.status(204).send();
    } catch (error) {
      if (
        error.message === "INVALID_MEDIA_PATH" ||
        error.message === "UNSUPPORTED_MEDIA_URL" ||
        error instanceof TypeError
      ) {
        res.status(400).json({message: "Недопустимый media URL"});
        return;
      }
      res.status(500).json({message: "Не удалось удалить файл"});
    }
  });
}

module.exports = {
  registerAuthenticatedMediaRoutes,
  registerPublicMediaRoutes,
};
