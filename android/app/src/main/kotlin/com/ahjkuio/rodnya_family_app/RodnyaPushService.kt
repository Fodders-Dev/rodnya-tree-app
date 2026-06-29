package com.ahjkuio.rodnya_family_app

import android.os.Handler
import android.os.Looper
import ru.rustore.flutter_rustore_push.FlutterRustorePushService
import ru.rustore.flutter_rustore_push.pigeons.Message as PigeonMessage
import ru.rustore.flutter_rustore_push.pigeons.Notification as PigeonNotification
import ru.rustore.sdk.pushclient.messaging.exception.RuStorePushClientException
import ru.rustore.sdk.pushclient.messaging.model.RemoteMessage
import ru.rustore.sdk.pushclient.messaging.service.RuStoreMessagingService

/**
 * Replacement for `flutter_rustore_push`'s `FlutterRustorePushService`.
 *
 * The plugin's class is `final` so we can't subclass it from app code,
 * and the underlying `RuStoreMessagingService` only allows a SINGLE
 * registered service for the `MESSAGING_EVENT` intent filter. So we
 * remove the plugin's service from the merged manifest with
 * `tools:node="remove"` and stand up our own subclass of
 * `RuStoreMessagingService` here.
 *
 * Two responsibilities:
 *
 *  1. **Forward to Flutter**, the same way the plugin would. We hand
 *     the message off to `FlutterRustorePushService.client` — a
 *     companion-object `RuStorePushCallbacks` that the plugin pumps
 *     into the Dart side via pigeon. When the app is in memory the
 *     existing `attachCallbacks(onMessageReceived: ...)` listener
 *     in `RustoreService.initializePushListeners` keeps firing
 *     unchanged.
 *
 *  2. **Build a full-screen incoming-call notification** when the
 *     payload is a `call_invite` and the Flutter engine is dead.
 *     The OS auto-display from `notification.title` / `body` plus
 *     `android.notification.channel_id` is fine for a heads-up, but
 *     to lift our accept/reject UI over the lockscreen we need
 *     `setFullScreenIntent` in a `Notification.Builder` — that's
 *     only buildable from native code.
 */
class RodnyaPushService : RuStoreMessagingService() {

    private val uiThreadHandler: Handler = Handler(Looper.getMainLooper())

    override fun onNewToken(token: String) {
        // Mirror the plugin behavior: hop to the main thread and pump
        // the new token to whichever Dart-side callback is attached.
        uiThreadHandler.post {
            FlutterRustorePushService.client?.newToken(token) { }
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        // 1) Forward to Flutter (only fires when the engine is alive).
        forwardToFlutter(message)

        // 2) Custom call-invite full-screen notification. Shared with
        //    the FCM receiver/service so both push providers render the
        //    exact same native incoming-call UI.
        RodnyaCallNotifier.handlePushData(
            context = applicationContext,
            data = message.data,
            notificationTitle = message.notification?.title,
            notificationBody = message.notification?.body,
        )
    }

    override fun onDeletedMessages() {
        uiThreadHandler.post {
            FlutterRustorePushService.client?.deletedMessages { }
        }
    }

    override fun onError(errors: List<RuStorePushClientException>) {
        uiThreadHandler.post {
            FlutterRustorePushService.client?.error(errors.toString()) { }
        }
    }

    private fun forwardToFlutter(message: RemoteMessage) {
        // Mirror FlutterRustorePushService.onMessageReceived's pigeon
        // payload shape so the Dart side gets identical data
        // regardless of whether the plugin's default service or ours
        // delivered the message.
        val pigeonNotification = message.notification?.let { source ->
            PigeonNotification(
                title = source.title.orEmpty(),
                body = source.body.orEmpty(),
                channelId = source.channelId.orEmpty(),
                clickAction = source.clickAction.orEmpty(),
                icon = source.icon.orEmpty(),
                color = source.color.orEmpty(),
                imageUrl = source.imageUrl?.toString().orEmpty(),
            )
        }
        @Suppress("UNCHECKED_CAST")
        val pigeonMessage = PigeonMessage(
            messageId = message.messageId,
            data = message.data as Map<String?, String?>,
            priority = message.priority.toLong(),
            ttl = message.ttl.toLong(),
            collapseKey = message.collapseKey,
            notification = pigeonNotification,
        )
        uiThreadHandler.post {
            FlutterRustorePushService.client?.messageReceived(pigeonMessage) { }
        }
    }

}
