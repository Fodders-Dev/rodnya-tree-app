const {
  EMPTY_DB,
} = require("../constants");
const {
  normalizeStoredCall,
} = require("./chat-calls");

function normalizeDbState(parsed) {
  return {
    users: Array.isArray(parsed?.users) ? parsed.users : [],
    sessions: Array.isArray(parsed?.sessions) ? parsed.sessions : [],
    authHandoffs: Array.isArray(parsed?.authHandoffs) ? parsed.authHandoffs : [],
    passwordResetTokens: Array.isArray(parsed?.passwordResetTokens)
      ? parsed.passwordResetTokens
      : [],
    dismissedIdentitySuggestions: Array.isArray(
      parsed?.dismissedIdentitySuggestions,
    )
      ? parsed.dismissedIdentitySuggestions
      : [],
    identityFieldConflicts: Array.isArray(parsed?.identityFieldConflicts)
      ? parsed.identityFieldConflicts
      : [],
    graphPersons: Array.isArray(parsed?.graphPersons) ? parsed.graphPersons : [],
    graphRelations: Array.isArray(parsed?.graphRelations)
      ? parsed.graphRelations
      : [],
    branches: Array.isArray(parsed?.branches) ? parsed.branches : [],
    branchPersonViews: Array.isArray(parsed?.branchPersonViews)
      ? parsed.branchPersonViews
      : [],
    graphPersonEditGrants: Array.isArray(parsed?.graphPersonEditGrants)
      ? parsed.graphPersonEditGrants
      : [],
    migrationStatus:
      parsed?.migrationStatus && typeof parsed.migrationStatus === "object"
        ? parsed.migrationStatus
        : {},
    trees: Array.isArray(parsed?.trees) ? parsed.trees : [],
    // Phase B федеративные семьи. Backend identifiers ASCII
    // transliterated (semyi / semyaMembers) — JSON tooling +
    // codepaths comfortable c Latin keys. UI text + docs continue
    // c Cyrillic «семья». См. ENTITY-DESIGN.md §1.
    semyi: Array.isArray(parsed?.semyi) ? parsed.semyi : [],
    semyaMembers: Array.isArray(parsed?.semyaMembers)
      ? parsed.semyaMembers
      : [],
    semyaMemberHiddenPersons: Array.isArray(parsed?.semyaMemberHiddenPersons)
      ? parsed.semyaMemberHiddenPersons
      : [],
    semyaInvitations: Array.isArray(parsed?.semyaInvitations)
      ? parsed.semyaInvitations
      : [],
    semyaBrowseTokens: Array.isArray(parsed?.semyaBrowseTokens)
      ? parsed.semyaBrowseTokens
      : [],
    persons: Array.isArray(parsed?.persons) ? parsed.persons : [],
    // Ship Q4a (2026-05-28): backwards-compat — older data files
    // without deletedPersons field treated as empty.
    deletedPersons: Array.isArray(parsed?.deletedPersons)
      ? parsed.deletedPersons
      : [],
    // Ship Q4a (2026-05-28, Ship 30b): same для deletedPosts.
    deletedPosts: Array.isArray(parsed?.deletedPosts)
      ? parsed.deletedPosts
      : [],
    profileArticles: Array.isArray(parsed?.profileArticles)
      ? parsed.profileArticles
      : [],
    personIdentities: Array.isArray(parsed?.personIdentities)
      ? parsed.personIdentities
      : [],
    personAttributes: Array.isArray(parsed?.personAttributes)
      ? parsed.personAttributes
      : [],
    circles: Array.isArray(parsed?.circles) ? parsed.circles : [],
    circleMembers: Array.isArray(parsed?.circleMembers)
      ? parsed.circleMembers
      : [],
    mergeProposals: Array.isArray(parsed?.mergeProposals)
      ? parsed.mergeProposals
      : [],
    identityClaims: Array.isArray(parsed?.identityClaims)
      ? parsed.identityClaims
      : [],
    relations: Array.isArray(parsed?.relations) ? parsed.relations : [],
    chats: Array.isArray(parsed?.chats) ? parsed.chats : [],
    chatDrafts: Array.isArray(parsed?.chatDrafts) ? parsed.chatDrafts : [],
    chatPins: Array.isArray(parsed?.chatPins) ? parsed.chatPins : [],
    calls: Array.isArray(parsed?.calls)
      ? parsed.calls.map((entry) => normalizeStoredCall(entry)).filter(Boolean)
      : [],
    messages: Array.isArray(parsed?.messages) ? parsed.messages : [],
    messageReactions: Array.isArray(parsed?.messageReactions)
      ? parsed.messageReactions
      : [],
    relationRequests: Array.isArray(parsed?.relationRequests)
      ? parsed.relationRequests
      : [],
    kinshipChecks: Array.isArray(parsed?.kinshipChecks)
      ? parsed.kinshipChecks
      : [],
    storyRequests: Array.isArray(parsed?.storyRequests)
      ? parsed.storyRequests
      : [],
    onboardingStates: Array.isArray(parsed?.onboardingStates)
      ? parsed.onboardingStates
      : [],
    treeInvitations: Array.isArray(parsed?.treeInvitations)
      ? parsed.treeInvitations
      : [],
    treeChangeRecords: Array.isArray(parsed?.treeChangeRecords)
      ? parsed.treeChangeRecords
      : [],
    notifications: Array.isArray(parsed?.notifications)
      ? parsed.notifications
      : [],
    posts: Array.isArray(parsed?.posts) ? parsed.posts : [],
    // Phase E1: backwards-compat — older data files without the
    // gatherings field load as empty.
    gatherings: Array.isArray(parsed?.gatherings) ? parsed.gatherings : [],
    // Phase E4: same backwards-compat for polls.
    polls: Array.isArray(parsed?.polls) ? parsed.polls : [],
    stories: Array.isArray(parsed?.stories) ? parsed.stories : [],
    comments: Array.isArray(parsed?.comments) ? parsed.comments : [],
    postReactions: Array.isArray(parsed?.postReactions)
      ? parsed.postReactions
      : [],
    postCommentReactions: Array.isArray(parsed?.postCommentReactions)
      ? parsed.postCommentReactions
      : [],
    storyReactions: Array.isArray(parsed?.storyReactions)
      ? parsed.storyReactions
      : [],
    reports: Array.isArray(parsed?.reports) ? parsed.reports : [],
    blocks: Array.isArray(parsed?.blocks) ? parsed.blocks : [],
    profileContributions: Array.isArray(parsed?.profileContributions)
      ? parsed.profileContributions
      : [],
    pushDevices: Array.isArray(parsed?.pushDevices) ? parsed.pushDevices : [],
    pushDeliveries: Array.isArray(parsed?.pushDeliveries)
      ? parsed.pushDeliveries
      : [],
    clientDiagnostics: Array.isArray(parsed?.clientDiagnostics)
      ? parsed.clientDiagnostics
      : [],
    // Phase 3.6 hard-delete job artifacts. Default empty / null
    // preserves backward compat — old snapshots без этих полей
    // подхватятся прозрачно (см. EMPTY_DB).
    hardDeleteAudit: Array.isArray(parsed?.hardDeleteAudit)
      ? parsed.hardDeleteAudit
      : [],
    hardDeleteLastRunAt:
      typeof parsed?.hardDeleteLastRunAt === "string"
        ? parsed.hardDeleteLastRunAt
        : null,
  };
}

module.exports = {
  normalizeDbState,
};
