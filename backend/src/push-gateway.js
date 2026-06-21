const webPush = require("web-push");

class PushGateway {
  constructor({
    store,
    logger = console,
    config = {},
    webPushClient = webPush,
    httpClient = globalThis.fetch?.bind(globalThis),
  }) {
    this.store = store;
    this.logger = logger;
    this.config = {
      publicAppUrl: String(config.publicAppUrl || "https://rodnya-tree.ru"),
      webPushPublicKey: String(config.webPushPublicKey || "").trim(),
      webPushPrivateKey: String(config.webPushPrivateKey || "").trim(),
      webPushSubject: String(
        config.webPushSubject || "https://rodnya-tree.ru",
      ).trim(),
      webPushEnabled: Boolean(
        config.webPushEnabled ||
            (config.webPushPublicKey && config.webPushPrivateKey),
      ),
      rustorePushProjectId: String(config.rustorePushProjectId || "").trim(),
      rustorePushServiceToken: String(
        config.rustorePushServiceToken || "",
      ).trim(),
      rustorePushApiBaseUrl: String(
        config.rustorePushApiBaseUrl || "https://vkpns.rustore.ru",
      ).replace(/\/+$/, ""),
      rustorePushEnabled: Boolean(
        config.rustorePushEnabled ||
          (config.rustorePushProjectId && config.rustorePushServiceToken),
      ),
    };
    this.webPushClient = webPushClient;
    this.httpClient = httpClient;

    if (this.config.webPushEnabled) {
      this.webPushClient.setVapidDetails(
        this.config.webPushSubject,
        this.config.webPushPublicKey,
        this.config.webPushPrivateKey,
      );
    }
  }

  async dispatchNotification(notification, {targetSessionPublicId = null} = {}) {
    const allDevices = await this.store.listPushDevices(notification.userId);
    const normalizedTargetSessionPublicId = targetSessionPublicId
      ? String(targetSessionPublicId).trim()
      : "";
    const devices = normalizedTargetSessionPublicId
      ? allDevices.filter(
          (entry) =>
            (entry.sessionPublicId || "") === normalizedTargetSessionPublicId,
        )
      : allDevices;
    const deliveries = [];

    for (const device of devices) {
      const delivery = await this.store.createPushDelivery({
        notificationId: notification.id,
        userId: notification.userId,
        deviceId: device.id,
        provider: device.provider,
        status: "queued",
      });

      deliveries.push(delivery);
      this.logger.info?.(
        `[rodnya-backend] queued push delivery ${delivery.id} for ${device.provider}:${device.platform}`,
      );

      await this._deliverNotification(notification, device, delivery);
    }

    return deliveries;
  }

  async _deliverNotification(notification, device, delivery) {
    if (device.provider === "webpush") {
      await this._deliverWebPush(notification, device, delivery);
      return;
    }

    if (device.provider === "rustore") {
      await this._deliverRustorePush(notification, device, delivery);
      return;
    }

    await this.store.updatePushDelivery(delivery.id, {
      status: "failed",
      lastError: `unsupported_push_provider:${String(device.provider || "unknown").trim() || "unknown"}`,
    });
  }

  async _deliverWebPush(notification, device, delivery) {
    if (!this.config.webPushEnabled) {
      await this.store.updatePushDelivery(delivery.id, {
        status: "queued",
        lastError: "webpush_not_configured",
      });
      return;
    }

    let subscription;
    try {
      subscription = JSON.parse(device.token);
    } catch (error) {
      await this.store.updatePushDelivery(delivery.id, {
        status: "failed",
        lastError: `invalid_webpush_subscription:${error.message}`,
      });
      return;
    }

    const payload = JSON.stringify(this._buildWebPushPayload(notification));
    const options = this._buildWebPushOptions(notification);

    try {
      const response = await this.webPushClient.sendNotification(
        subscription,
        payload,
        options,
      );
      await this.store.updatePushDelivery(delivery.id, {
        status: "sent",
        deliveredAt: new Date().toISOString(),
        responseCode: Number(response?.statusCode || 201),
        lastError: null,
      });
    } catch (error) {
      await this.store.updatePushDelivery(delivery.id, {
        status: "failed",
        lastError: error?.message || String(error),
        responseCode: Number(error?.statusCode || 0) || null,
      });
    }
  }

  _notificationUrl(notification) {
    const baseUrl = String(this.config.publicAppUrl || "https://rodnya-tree.ru")
      .replace(/\/$/, "");
    const payload = encodeURIComponent(
      JSON.stringify({
        id: notification.id,
        type: notification.type,
        data: notification.data || {},
      }),
    );
    return `${baseUrl}/?notificationPayload=${payload}#/notifications`;
  }

  _buildWebPushPayload(notification) {
    const isIncomingCall = this._isCallSignalNotification(notification);
    const payload = {
      title: notification.title || "Родня",
      body: notification.body || "",
      tag: this._notificationTag(notification),
      payload: JSON.stringify(this._buildClientPayload(notification)),
      url: this._notificationUrl(notification),
    };

    if (isIncomingCall) {
      payload.event = this._callEventName(notification);
      payload.urgency = "high";
      payload.ttlSeconds = this._notificationTtlSeconds(notification);
      payload.timeSensitive = true;
      payload.renotify = true;
      payload.requireInteraction = true;
    }

    // Phase 6.5+: silent flag for data-only refresh signals
    // (e.g. tree_mutated). Service worker reads this и skips
    // `self.registration.showNotification` call — payload still
    // routes к client event handlers for refresh coordinator.
    // web/sw.js update — Phase 6.6 follow-up (без него на
    // background web banner может show; foreground filtering
    // в client handles foreground case).
    if (notification.silent === true) {
      payload.silent = true;
    }

    return payload;
  }

  _buildWebPushOptions(notification) {
    return {
      TTL: this._notificationTtlSeconds(notification),
      urgency: this._notificationUrgency(notification),
    };
  }

  async _deliverRustorePush(notification, device, delivery) {
    if (!this.config.rustorePushEnabled) {
      await this.store.updatePushDelivery(delivery.id, {
        status: "queued",
        lastError: "rustore_not_configured",
      });
      return;
    }

    if (typeof this.httpClient !== "function") {
      await this.store.updatePushDelivery(delivery.id, {
        status: "failed",
        lastError: "rustore_http_client_unavailable",
      });
      return;
    }

    // Build the VKPNS message envelope.
    //
    // VKPNS follows Firebase's split: a message with `notification`
    // (top-level) is auto-displayed by the OS *and* skips our
    // `RodnyaPushService.onMessageReceived` when the app is killed.
    // A `data`-only message *always* wakes our service.
    //
    // For incoming calls we MUST go data-only — the native subclass
    // builds a full-screen `setFullScreenIntent` notification with
    // accept/reject actions that the OS auto-display can't reproduce.
    // Skipping our service when the app is killed is exactly the
    // «звоню себе на телефон, а приложение закрыто — и я просто не
    // вижу звонок» bug the user reported.
    //
    // For everything else (chats, post replies, etc.) we keep the
    // notification field so the OS displays a clean heads-up even
    // when our process is dead.
    const isIncomingCall = this._isCallSignalNotification(notification);
    const androidConfig = {
      priority: isIncomingCall ? "HIGH" : "NORMAL",
      ttl: `${this._notificationTtlSeconds(notification)}s`,
      // Only set the system-display notification block for non-call
      // pushes. Calls render their own UI from native code.
      ...(isIncomingCall
        ? {}
        : {
            notification: {
              title: notification.title || "Родня",
              body: notification.body || "",
              channel_id: this._androidChannelId(notification),
              sound: "default",
              tag: this._notificationTag(notification),
            },
          }),
    };
    const requestBody = {
      message: {
        token: String(device.token || "").trim(),
        // Same logic at the message root: data-only for calls, mixed
        // payload for everything else.
        ...(isIncomingCall
          ? {}
          : {
              notification: {
                title: notification.title || "Родня",
                body: notification.body || "",
              },
            }),
        data: this._buildRustoreDataPayload(notification),
        android: androidConfig,
      },
    };
    const requestUrl = `${this.config.rustorePushApiBaseUrl}/v1/projects/${encodeURIComponent(this.config.rustorePushProjectId)}/messages:send`;

    try {
      const response = await this.httpClient(requestUrl, {
        method: "POST",
        headers: {
          authorization: `Bearer ${this.config.rustorePushServiceToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(requestBody),
        // FIX A3 (defense): без таймаута зависший VKPNS-fetch (мёртвый
        // токен / убитая Huawei) держал доставку бесконечно. AbortSignal
        // обрывает на 8с → catch ниже помечает delivery 'failed' быстро.
        signal: AbortSignal.timeout(8000),
      });

      if (response.ok) {
        await this.store.updatePushDelivery(delivery.id, {
          status: "sent",
          deliveredAt: new Date().toISOString(),
          responseCode: Number(response.status || 200),
          lastError: null,
        });
        return;
      }

      const responseText = await this._safeReadResponse(response);
      await this.store.updatePushDelivery(delivery.id, {
        status: "failed",
        lastError: responseText || `rustore_http_${response.status || 0}`,
        responseCode: Number(response.status || 0) || null,
      });
    } catch (error) {
      await this.store.updatePushDelivery(delivery.id, {
        status: "failed",
        lastError: error?.message || String(error),
      });
    }
  }

  _buildRustoreDataPayload(notification) {
    const isIncomingCall = this._isCallSignalNotification(notification);
    const payload = {
      notificationId: notification.id,
      type: notification.type || "generic",
      payload: JSON.stringify(this._buildClientPayload(notification)),
    };

    for (const [key, value] of Object.entries(notification.data || {})) {
      if (value == null) {
        continue;
      }
      payload[String(key)] =
        typeof value === "string" ? value : JSON.stringify(value);
    }

    if (isIncomingCall) {
      payload.priority = "high";
      payload.urgency = "high";
      payload.ttlSeconds = String(this._notificationTtlSeconds(notification));
      payload.timeSensitive = "true";
      payload.event = this._callEventName(notification);
      payload.collapseKey = this._notificationTag(notification);
      // Calls go data-only (see _deliverRustorePush) — when we drop
      // `message.notification` the native side loses access to
      // `message.notification.title`, which used to carry the caller
      // name. Mirror it explicitly so RodnyaPushService.kt can show
      // «Артем А.» instead of falling back to the generic «Звонок»
      // label when the app is killed/backgrounded.
      if (notification.title) {
        payload.callerName = String(notification.title);
      }
      if (notification.body) {
        payload.callerBody = String(notification.body);
      }
    }

    return payload;
  }

  _buildClientPayload(notification) {
    const payload = {
      id: notification.id,
      type: notification.type,
      data: notification.data || {},
    };

    if (this._isCallSignalNotification(notification)) {
      payload.priority = "high";
      payload.urgency = "high";
      payload.ttlSeconds = this._notificationTtlSeconds(notification);
      payload.timeSensitive = true;
      payload.event = this._callEventName(notification);
    }

    return payload;
  }

  // Call-control pushes go data-only + high-priority so they wake the
  // native RodnyaPushService even when the app is killed: incoming call
  // (full-screen ring) AND terminal signals (call_cancelled/call_ended)
  // that dismiss the ringing notification / post a missed-call entry.
  _isCallSignalNotification(notification) {
    return this._callEventName(notification) != null;
  }

  // Maps a call notification type to the client-facing push `event`.
  // BUG 2: terminal call states reuse the data-only call transport but
  // carry their own event so the client can dismiss / show «missed».
  _callEventName(notification) {
    const type = String(notification?.type || "").trim();
    if (type === "call_invite" || type === "call") {
      return "incoming_call";
    }
    if (type === "call_cancelled") {
      return "call_cancelled";
    }
    if (type === "call_ended") {
      return "call_ended";
    }
    return null;
  }

  /**
   * Map a notification type to the matching native Android channel.
   *
   * The channels are declared in `RodnyaNotificationChannels.kt` and
   * the IDs MUST match — Android silently drops a push whose channel
   * doesn't exist on the device. The split mirrors the user's mental
   * model: high-urgency «кто-то прямо сейчас обращается ко мне» (chat,
   * call ringer fallback) on its own channel, social/feed updates on
   * a softer channel, system/admin chatter on a quiet channel.
   *
   * Calls aren't routed through here — they go data-only and build
   * their own NotificationCompat entry on the calls channel from
   * RodnyaPushService.kt.
   */
  _androidChannelId(notification) {
    const type = String(notification?.type || "").trim();
    if (this._isCallSignalNotification(notification)) {
      return "calls";
    }
    if (type === "chat_message" || type === "chat") {
      return "chats";
    }
    if (
      type === "post_like" ||
      type === "post_comment" ||
      type === "comment_reply" ||
      type === "story_view" ||
      type === "story_reaction" ||
      type === "relative_added" ||
      type === "tree_invitation" ||
      type === "birthday"
    ) {
      return "social";
    }
    return "system";
  }

  _notificationUrgency(notification) {
    return this._isCallSignalNotification(notification) ? "high" : "normal";
  }

  _notificationTtlSeconds(notification) {
    // Incoming calls need a longer push window than the previous 30s.
    // OEM push queues (Huawei/Honor especially) can wake the app late; 90s
    // still avoids stale all-day call alerts but gives the backend/OS enough
    // room to deliver while the call timeout/reconciliation path can cancel
    // terminal calls.
    return this._isCallSignalNotification(notification) ? 90 : 3600;
  }

  _notificationTag(notification) {
    if (this._isCallSignalNotification(notification)) {
      const callId = notification?.data?.callId;
      if (callId != null && String(callId).trim()) {
        return `call:${String(callId).trim()}`;
      }
    }
    return notification.id;
  }

  async _safeReadResponse(response) {
    if (!response || typeof response.text !== "function") {
      return "";
    }

    try {
      return String(await response.text()).trim();
    } catch (_) {
      return "";
    }
  }
}

module.exports = {
  PushGateway,
};
