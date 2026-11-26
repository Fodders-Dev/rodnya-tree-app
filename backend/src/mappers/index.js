const treeMappers = require("./tree-mappers");
const notificationSafetyMappers = require("./notification-safety-mappers");
const contentMappers = require("./content-mappers");
const chatCallMappers = require("./chat-call-mappers");
const {createAuthPresenters} = require("./auth-presenters");

function createAppMappers({config, realtimeHub = null}) {
  const {mapChatParticipant} = chatCallMappers.createChatCallMappers({
    realtimeHub,
  });
  const authPresenters = createAuthPresenters({config});

  return {
    ...treeMappers,
    ...notificationSafetyMappers,
    ...contentMappers,
    ...chatCallMappers,
    mapChatParticipant,
    ...authPresenters,
  };
}

module.exports = {
  createAppMappers,
  ...treeMappers,
  ...notificationSafetyMappers,
  ...contentMappers,
  ...chatCallMappers,
};
