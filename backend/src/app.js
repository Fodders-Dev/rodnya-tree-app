const express = require("express");

const {
  computeProfileStatus,
  composeDisplayName,
  normalizeProfileContributionPolicy,
  normalizePrimaryTrustedChannel,
  normalizePublicUrl,
  sanitizeProfile,
  sanitizeUserProfilePreview,
} = require("./profile-utils");
const {PushGateway} = require("./push-gateway");
const {createMediaStorage} = require("./media-storage");
const {createGoogleTokenVerifier} = require("./google-auth");
const {createVkAuthClient} = require("./vk-auth");
const {createMaxAuthClient} = require("./max-auth");
const {createLiveKitService} = require("./livekit-service");
const {createEmailSender} = require("./email-sender");
const {createOperationalStatus} = require("./operational-status");
const {InMemoryRateLimitBackend} = require("./rate-limit-backends");
const {deriveSessionPublicId} = require("./store");
const {createAppMappers} = require("./mappers");
const {
  registerCoreHttpMiddleware,
  registerJsonBodyParser,
  registerHealthRoutes,
  registerErrorHandlers,
} = require("./middleware/http-pipeline");
const {registerRateLimitMiddleware} = require("./middleware/rate-limit");
const {createAccessGuards} = require("./middleware/access-guards");
const {createCallCoordinator} = require("./calls/call-coordinator");
const {createAppOrchestrators} = require("./services/app-orchestrators");
const {
  registerLiveKitWebhookRoute,
  registerCallRoutes,
} = require("./routes/call-routes");
const {registerAdminRoutes} = require("./routes/admin-routes");
const {registerAppUpdateRoutes} = require("./routes/app-update-routes");
const {registerAuthSessionRoutes} = require("./routes/auth-session-routes");
const {
  registerAuthenticatedMediaRoutes,
  registerPublicMediaRoutes,
} = require("./routes/media-routes");
const {registerChatRoutes} = require("./routes/chat-routes");
const {registerCircleRoutes} = require("./routes/circle-routes");
const {registerDiagnosticsRoutes} = require("./routes/diagnostics-routes");
const {registerGoogleAuthRoutes} = require("./routes/google-auth-routes");
const {registerGraphRoutes} = require("./routes/graph-routes");
const {registerGraphPersonRoutes} = require("./routes/graph-person-routes");
const {registerOnboardingRoutes} = require("./routes/onboarding-routes");
const {registerKinshipChecksRoutes} = require("./routes/kinship-checks-routes");
const {registerStoryRequestRoutes} = require("./routes/story-request-routes");
const {registerPublicStoryRoutes} = require("./routes/public-story-routes");
const {registerSemyaRoutes} = require("./routes/semya-routes");
const {registerMembershipRoutes} = require("./routes/membership-routes");
const {registerSemyaInvitationRoutes} = require("./routes/semya-invitation-routes");
const {registerSemyaPullRoutes} = require("./routes/semya-pull-routes");
const {registerSemyaBrowseRoutes} = require("./routes/semya-browse-routes");
const {registerSemyaHideFilterRoutes} = require("./routes/semya-hide-filter-routes");
const {registerDeletedPersonsRoutes} = require("./routes/deleted-persons-routes");
const {registerDeletedPostsRoutes} = require("./routes/deleted-posts-routes");
const {registerProfileArticleRoutes} = require("./routes/profile-article-routes");
const {registerIdentityRoutes} = require("./routes/identity-routes");
const {registerMaxAuthRoutes} = require("./routes/max-auth-routes");
const {registerMergeRoutes} = require("./routes/merge-routes");
const {registerNotificationRoutes} = require("./routes/notification-routes");
const {registerPendingInvitationRoutes} = require("./routes/pending-invitation-routes");
const {registerPostRoutes} = require("./routes/post-routes");
const {registerGatheringRoutes} = require("./routes/gathering-routes");
const {registerPollRoutes} = require("./routes/poll-routes");
const {registerProfileRoutes} = require("./routes/profile-routes");
const {registerPushRoutes} = require("./routes/push-routes");
const {registerRelationRequestRoutes} = require("./routes/relation-request-routes");
const {registerSafetyRoutes} = require("./routes/safety-routes");
const {registerStoryRoutes} = require("./routes/story-routes");
const {registerTelegramAuthRoutes} = require("./routes/telegram-auth-routes");
const {registerTreeInvitationRoutes} = require("./routes/tree-invitation-routes");
const {registerTreeRoutes} = require("./routes/tree-routes");
const {registerUserRoutes} = require("./routes/user-routes");
const {registerVkAuthRoutes} = require("./routes/vk-auth-routes");

const EMERGENCY_CHAT_PREVIEW_RESPONSE_CAP = 200;

function createApp({
  store,
  config,
  realtimeHub = null,
  pushGateway = null,
  mediaStorage = null,
  googleTokenVerifier = null,
  vkAuthClient = null,
  maxAuthClient = null,
  liveKitService = null,
  runtimeInfo = null,
  emailSender = null,
  rateLimitBackend = null,
}) {
  const app = express();
  const useSemyaModel =
    String(process.env.RODNYA_FEDERATED_SEMYI_ENABLED || "")
      .trim()
      .toLowerCase() === "true";
  const resolvedPushGateway = pushGateway ?? new PushGateway({store, config});
  const resolvedMediaStorage = mediaStorage ?? createMediaStorage(config);
  const resolvedGoogleTokenVerifier =
    googleTokenVerifier ?? createGoogleTokenVerifier(config);
  const resolvedVkAuthClient = vkAuthClient ?? createVkAuthClient(config);
  const resolvedMaxAuthClient = maxAuthClient ?? createMaxAuthClient(config);
  const resolvedLiveKitService = liveKitService ?? createLiveKitService(config);
  const resolvedEmailSender =
    emailSender ?? createEmailSender({config, logger: console});
  const resolvedRateLimitBackend =
    rateLimitBackend ?? new InMemoryRateLimitBackend();
  const operationalStatus = createOperationalStatus({
    store,
    config,
    realtimeHub,
    mediaStorage: resolvedMediaStorage,
    liveKitService: resolvedLiveKitService,
    vkAuthClient: resolvedVkAuthClient,
    maxAuthClient: resolvedMaxAuthClient,
    runtimeInfo,
  });
  const {normalizedRuntimeInfo, buildStatusPayload, ensureReady} =
    operationalStatus;

  const {
    mapTree,
    mapPerson,
    mapProfileContribution,
    mapRelation,
    mapTreeGraphSnapshot,
    mapTreeChangeRecord,
    mapRelationRequest,
    mapTreeInvitation,
    mapNotification,
    mapBlock,
    mapReport,
    mapPushDevice,
    mapPushDelivery,
    mapPost,
    mapGathering,
    mapPoll,
    mapStory,
    mapComment,
    mapChatMessage,
    mapChatRecord,
    mapCallRecord,
    mapChatParticipant,
    mapChatBranchRoot,
    mapChatPreview,
    resolvePublicAppUrl,
    mapLinkedAuthIdentity,
    buildTrustedChannels,
    resolvePrimaryTrustedChannelProvider,
    buildTrustedChannelSummary,
    authResponse,
    resolveGoogleDisplayName,
    buildGoogleIdentityFromPayload,
  } = createAppMappers({config, realtimeHub});

  const {
    resolveSharedTreeIdsForUsers,
    buildProfileViewerContext,
    buildPersonDossierPayload,
    createAndDispatchNotification,
  } = createAppOrchestrators({
    store,
    realtimeHub,
    pushGateway: resolvedPushGateway,
  });

  let readDeviceContextRef = null;
  const callCoordinator = createCallCoordinator({
    store,
    config,
    realtimeHub,
    liveKitService: resolvedLiveKitService,
    createAndDispatchNotification,
    getReadDeviceContext: () => readDeviceContextRef,
  });
  const {resolvePublicApiUrl} = callCoordinator;

  const {
    requirePublicTree,
    readDeviceContext,
    requireAuth,
    requireOwnUser,
    requireTreeAccess,
    requireSemyaAccess,
    requireGraphPersonEdit,
    requireGraphPersonRead,
    requireChatAccess,
    requireCallAccess,
    requireCallJoinAccess,
    requireAdmin,
  } = createAccessGuards({
    store,
    config,
    useSemyaModel,
    findFreshCall: callCoordinator.findFreshCall,
  });
  readDeviceContextRef = readDeviceContext;

  registerCoreHttpMiddleware(app, {config, normalizedRuntimeInfo});
  registerLiveKitWebhookRoute(app, {
    store,
    liveKitService: resolvedLiveKitService,
    callCoordinator,
  });
  registerJsonBodyParser(app);
  registerPublicMediaRoutes(app, {mediaStorage: resolvedMediaStorage});
  registerAppUpdateRoutes(app, {config});
  registerRateLimitMiddleware(app, {
    config,
    rateLimitBackend: resolvedRateLimitBackend,
  });
  registerHealthRoutes(app, {buildStatusPayload, ensureReady});

  registerAuthSessionRoutes(app, {
    store,
    mediaStorage: resolvedMediaStorage,
    config,
    emailSender: resolvedEmailSender,
    requireAuth,
    authResponse,
    sanitizeProfile,
    computeProfileStatus,
    readDeviceContext,
    realtimeHub,
    deriveSessionPublicId,
  });

  registerProfileRoutes(app, {
    store,
    requireAuth,
    requireOwnUser,
    sanitizeProfile,
    computeProfileStatus,
    composeDisplayName,
    mapProfileContribution,
    mapLinkedAuthIdentity,
    buildTrustedChannels,
    resolvePrimaryTrustedChannelProvider,
    buildTrustedChannelSummary,
  });

  registerGoogleAuthRoutes(app, {
    store,
    requireAuth,
    googleTokenVerifier: resolvedGoogleTokenVerifier,
    buildGoogleIdentityFromPayload,
    authResponse,
    readDeviceContext,
  });

  registerVkAuthRoutes(app, {
    store,
    requireAuth,
    vkAuthClient: resolvedVkAuthClient,
    resolvePublicApiUrl,
    resolvePublicAppUrl,
    authResponse,
    readDeviceContext,
  });

  registerTelegramAuthRoutes(app, {
    store,
    config,
    requireAuth,
    resolvePublicApiUrl,
    resolvePublicAppUrl,
    authResponse,
    readDeviceContext,
  });

  registerMaxAuthRoutes(app, {
    store,
    requireAuth,
    maxAuthClient: resolvedMaxAuthClient,
    resolvePublicAppUrl,
    authResponse,
    readDeviceContext,
  });
  registerAuthenticatedMediaRoutes(app, {
    mediaStorage: resolvedMediaStorage,
    requireAuth,
  });

  registerStoryRoutes(app, {
    store,
    requireAuth,
    requireTreeAccess,
    composeDisplayName,
    mapStory,
    pushGateway: resolvedPushGateway,
  });

  registerPostRoutes(app, {
    store,
    requireAuth,
    requireTreeAccess,
    composeDisplayName,
    mapPost,
    mapComment,
    createAndDispatchNotification,
    pushGateway: resolvedPushGateway,
  });

  registerGatheringRoutes(app, {
    store,
    requireAuth,
    requireTreeAccess,
    composeDisplayName,
    mapGathering,
    createAndDispatchNotification,
    pushGateway: resolvedPushGateway,
  });

  registerPollRoutes(app, {
    store,
    requireAuth,
    requireTreeAccess,
    composeDisplayName,
    mapPoll,
    createAndDispatchNotification,
    pushGateway: resolvedPushGateway,
  });

  registerCircleRoutes(app, {
    store,
    requireAuth,
    requireTreeAccess,
  });

  registerMergeRoutes(app, {
    store,
    requireAuth,
    requireGraphPersonEdit,
  });

  registerIdentityRoutes(app, {
    store,
    requireAuth,
    requireTreeAccess,
    requireGraphPersonEdit,
  });

  registerGraphRoutes(app, {
    store,
    requireAuth,
  });

  registerGraphPersonRoutes(app, {
    store,
    requireAuth,
    requireGraphPersonRead,
    createAndDispatchNotification,
  });

  // Phase 6 chunk 1 (PHASE-6-PROPOSAL.md §3.2).
  registerOnboardingRoutes(app, {
    store,
    requireAuth,
  });

  registerKinshipChecksRoutes(app, {
    store,
    requireAuth,
    createAndDispatchNotification,
  });

  // «Спросить историю» MVP-1 (STORY-REQUEST-MVP1-BRIEF.md). requireGraphPersonEdit
  // threaded so the route can gate request-creation on the initiator's
  // person-edit rights before store.createStoryRequest ever runs.
  registerStoryRequestRoutes(app, {
    store,
    config,
    mediaStorage: resolvedMediaStorage,
    requireAuth,
    requireTreeAccess,
    requireGraphPersonEdit,
    createAndDispatchNotification,
  });

  // «Спросить историю» v2 — lightweight SSR HTML + token-gated guest answer/media.
  registerPublicStoryRoutes(app, {
    store,
    config,
    mediaStorage: resolvedMediaStorage,
    createAndDispatchNotification,
  });

  // Phase B Week 2 Ship 2: семья HTTP endpoints (5 routes).
  registerSemyaRoutes(app, {
    store,
    requireAuth,
    requireSemyaAccess,
  });

  // Phase B Week 2 Ship 3: семья membership HTTP endpoints (4 routes).
  registerMembershipRoutes(app, {
    store,
    requireAuth,
    requireSemyaAccess,
  });

  // Phase B Week 2 Ship 4: семья invitation flow (3 routes).
  // FE7 (email dispatch): config + emailSender threaded so a fresh
  // email-addressed invitation auto-sends a warm accept-link email.
  registerSemyaInvitationRoutes(app, {
    store,
    config,
    requireAuth,
    requireSemyaAccess,
    createAndDispatchNotification,
    emailSender: resolvedEmailSender,
  });

  // Phase B Week 3 Ship 6: cross-семья pull-selectively endpoint.
  registerSemyaPullRoutes(app, {
    store,
    requireAuth,
    requireSemyaAccess,
    createAndDispatchNotification,
  });

  // Phase B Week 3 Ship 7: browse mode (read-only capability tokens).
  registerSemyaBrowseRoutes(app, {
    store,
    requireAuth,
    requireSemyaAccess,
  });

  // Phase B Week 3 Ship 8: hide-filter endpoints (privacy-critical).
  registerSemyaHideFilterRoutes(app, {
    store,
    requireAuth,
    requireSemyaAccess,
  });

  // Ship Q4a (2026-05-28): «корзина» — soft-deleted persons recovery.
  registerDeletedPersonsRoutes(app, {
    store,
    requireAuth,
  });

  // Ship Q4a (2026-05-28, Ship 30b): same для posts.
  registerDeletedPostsRoutes(app, {
    store,
    requireAuth,
  });

  // Profile Phase 1 (2026-05-28): article-style biography CRUD.
  // Writes reuse requireGraphPersonEdit (same gate as person edits);
  // reads use requireTreeAccess.
  registerProfileArticleRoutes(app, {
    store,
    requireAuth,
    requireTreeAccess,
    requireGraphPersonEdit,
  });

  registerTreeRoutes(app, {
    store,
    requireAuth,
    requireTreeAccess,
    requireGraphPersonEdit,
    requirePublicTree,
    mapTree,
    mapPerson,
    mapRelation,
    mapProfileContribution,
    mapTreeChangeRecord,
    mapTreeGraphSnapshot,
    buildPersonDossierPayload,
    createAndDispatchNotification,
  });

  registerTreeInvitationRoutes(app, {
    store,
    requireAuth,
    requireTreeAccess,
    createAndDispatchNotification,
    mapTree,
    mapTreeInvitation,
  });

  registerRelationRequestRoutes(app, {
    store,
    requireAuth,
    requireTreeAccess,
    createAndDispatchNotification,
    mapPerson,
    mapRelation,
    mapRelationRequest,
  });

  registerChatRoutes(app, {
    store,
    requireAuth,
    requireTreeAccess,
    requireChatAccess,
    createAndDispatchNotification,
    mapChatPreview,
    mapChatRecord,
    mapChatMessage,
    mapChatParticipant,
    mapChatBranchRoot,
    realtimeHub,
    emergencyChatPreviewResponseCap: EMERGENCY_CHAT_PREVIEW_RESPONSE_CAP,
  });

  registerDiagnosticsRoutes(app, {
    store,
    requireAuth,
    logger: console,
  });

  registerSafetyRoutes(app, {
    store,
    requireAuth,
    mapBlock,
    mapReport,
  });

  registerAdminRoutes(app, {
    store,
    requireAuth,
    requireAdmin,
    buildStatusPayload,
    mapReport,
  });


  registerCallRoutes(app, {
    store,
    realtimeHub,
    liveKitService: resolvedLiveKitService,
    requireAuth,
    requireChatAccess,
    requireCallAccess,
    requireCallJoinAccess,
    createAndDispatchNotification,
    callCoordinator,
  });

  registerUserRoutes(app, {
    store,
    requireAuth,
    sanitizeUserProfilePreview,
    sanitizeProfile,
    computeProfileStatus,
    buildProfileViewerContext,
  });

  registerNotificationRoutes(app, {
    store,
    requireAuth,
    mapNotification,
    realtimeHub,
  });

  registerPushRoutes(app, {
    store,
    config,
    requireAuth,
    mapPushDevice,
    mapPushDelivery,
  });

  registerPendingInvitationRoutes(app, {
    store,
    requireAuth,
    requireTreeAccess,
    mapTree,
    mapPerson,
  });

  registerErrorHandlers(app, {runtimeInfo});

  return app;
}

module.exports = {
  createApp,
};
