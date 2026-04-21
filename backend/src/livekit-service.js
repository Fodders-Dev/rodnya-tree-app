const {
  AccessToken,
  RoomServiceClient,
  WebhookReceiver,
} = require("livekit-server-sdk");

function normalizeBaseUrl(value) {
  return String(value || "").trim().replace(/\/+$/, "");
}

function toWebSocketUrl(value) {
  const normalized = normalizeBaseUrl(value);
  if (!normalized) {
    return "";
  }
  if (/^wss?:\/\//i.test(normalized)) {
    return normalized;
  }
  if (/^https?:\/\//i.test(normalized)) {
    return normalized.replace(/^http/i, "ws");
  }
  return `wss://${normalized}`;
}

class LiveKitService {
  constructor(config = {}) {
    this.baseUrl = normalizeBaseUrl(config.liveKitUrl);
    this.wsUrl = toWebSocketUrl(config.liveKitUrl);
    this.apiKey = String(config.liveKitApiKey || "").trim();
    this.apiSecret = String(config.liveKitApiSecret || "").trim();
    this.webhookKey = String(config.liveKitWebhookKey || "").trim();
    this.isConfigured = Boolean(this.baseUrl && this.apiKey && this.apiSecret);
    this.roomServiceClient = this.isConfigured
      ? new RoomServiceClient(this.baseUrl, this.apiKey, this.apiSecret)
      : null;
    this.webhookReceiver = this.isConfigured
      ? new WebhookReceiver(this.apiKey, this.apiSecret)
      : null;
  }

  ensureConfigured() {
    if (!this.isConfigured) {
      throw new Error("LIVEKIT_NOT_CONFIGURED");
    }
  }

  async ensureRoom(roomName) {
    this.ensureConfigured();
    try {
      await this.roomServiceClient.createRoom({
        name: roomName,
        emptyTimeout: 60,
        departureTimeout: 15,
        maxParticipants: 2,
      });
    } catch (error) {
      const message = String(error?.message || "").toLowerCase();
      if (!message.includes("already")) {
        throw error;
      }
    }
  }

  async createSession({
    roomName,
    participantIdentity,
    participantName,
    metadata = null,
  }) {
    this.ensureConfigured();
    const token = new AccessToken(this.apiKey, this.apiSecret, {
      identity: participantIdentity,
      name: String(participantName || "").trim(),
      metadata: metadata == null ? undefined : JSON.stringify(metadata),
      ttl: "2h",
    });
    token.addGrant({
      roomJoin: true,
      room: roomName,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
    });

    return {
      roomName,
      url: this.wsUrl,
      token: await token.toJwt(),
      participantIdentity,
      participantName: String(participantName || "").trim() || null,
      createdAt: new Date().toISOString(),
    };
  }

  async receiveWebhook(body, authHeader = "") {
    if (this.webhookReceiver) {
      return this.webhookReceiver.receive(body, authHeader || undefined);
    }
    if (this.webhookKey && authHeader === this.webhookKey) {
      return JSON.parse(body);
    }
    throw new Error("LIVEKIT_WEBHOOK_NOT_CONFIGURED");
  }
}

function createLiveKitService(config) {
  return new LiveKitService(config);
}

module.exports = {
  LiveKitService,
  createLiveKitService,
};
