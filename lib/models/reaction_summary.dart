import 'chat_message.dart';

/// Generic reaction-summary model — emoji + the userIds who picked it.
/// Type-aliased to [ChatMessageReactionSummary] which already carries
/// the right shape; the alias gives posts and comments a non-chat-
/// flavoured name to import without a structural duplicate.
typedef ReactionSummary = ChatMessageReactionSummary;
