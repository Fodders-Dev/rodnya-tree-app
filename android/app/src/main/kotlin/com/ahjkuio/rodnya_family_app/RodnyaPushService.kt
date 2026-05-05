package com.ahjkuio.rodnya_family_app

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import org.json.JSONObject
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

        // 2) Make sure channels exist before we try to post into one —
        //    a push can arrive on a fresh install before the user
        //    ever opened MainActivity, so we re-register here too.
        RodnyaNotificationChannels.ensureRegistered(applicationContext)

        // 3) Custom call-invite full-screen notification.
        val type = (message.data["type"] ?: extractTypeFromPayload(message.data["payload"]))
            ?.trim().orEmpty()
        if (type != "call_invite" && type != "call") {
            return
        }

        val callId = (message.data["callId"]
            ?: extractFromPayload(message.data["payload"], "callId"))
            ?.trim().orEmpty()
        if (callId.isEmpty()) {
            return
        }

        val chatId = (message.data["chatId"]
            ?: extractFromPayload(message.data["payload"], "chatId"))
            ?.trim()?.takeIf { it.isNotEmpty() }
        val callerName = (
            message.notification?.title
                ?: message.data["callerName"]
                ?: extractFromPayload(message.data["payload"], "callerName")
            )?.trim().orEmpty().ifEmpty { "Звонок" }
        val body = (
            message.notification?.body
                ?: message.data["body"]
                ?: "Входящий звонок"
            ).trim()
        val isVideo = message.data["isVideo"] == "true" ||
            message.data["mediaMode"] == "video" ||
            extractFromPayload(message.data["payload"], "mediaMode") == "video"

        showIncomingCallNotification(
            callId = callId,
            chatId = chatId,
            callerName = callerName,
            body = body,
            isVideo = isVideo,
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

    private fun showIncomingCallNotification(
        callId: String,
        chatId: String?,
        callerName: String,
        body: String,
        isVideo: Boolean,
    ) {
        val context = applicationContext
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as? NotificationManager ?: return

        val acceptPendingIntent = buildActionPendingIntent(
            context = context,
            action = "accept",
            callId = callId,
            chatId = chatId,
            isVideo = isVideo,
            requestCodeOffset = 1,
        )
        val rejectPendingIntent = buildActionPendingIntent(
            context = context,
            action = "reject",
            callId = callId,
            chatId = chatId,
            isVideo = isVideo,
            requestCodeOffset = 2,
        )
        val openPendingIntent = buildActionPendingIntent(
            context = context,
            action = "open",
            callId = callId,
            chatId = chatId,
            isVideo = isVideo,
            requestCodeOffset = 3,
        )

        val ringtone =
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        val iconResId = getNotificationIconResId(context)

        val builder = NotificationCompat.Builder(
            context,
            RodnyaNotificationChannels.CALLS_ID,
        )
            .setSmallIcon(iconResId)
            .setContentTitle(callerName)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(false)
            .setSound(ringtone)
            .setVibrate(longArrayOf(0, 600, 400, 600))
            // Tap on the body — same flow as accept (open the app and
            // let Flutter route via the pending action store).
            .setContentIntent(openPendingIntent)
            // Lockscreen "ringer" UI — needs USE_FULL_SCREEN_INTENT,
            // already declared in our manifest. Passing `true` as the
            // second arg actually requests lockscreen take-over.
            .setFullScreenIntent(openPendingIntent, true)
            .addAction(
                iconResId,
                "Отклонить",
                rejectPendingIntent,
            )
            .addAction(
                iconResId,
                if (isVideo) "Принять видео" else "Принять",
                acceptPendingIntent,
            )

        // Stable id so duplicate pushes for the same call update
        // the existing notification instead of stacking.
        val notificationId = callId.hashCode() and 0x7fffffff
        manager.notify(notificationId, builder.build())
    }

    private fun buildActionPendingIntent(
        context: Context,
        action: String,
        callId: String,
        chatId: String?,
        isVideo: Boolean,
        requestCodeOffset: Int,
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("rodnya_call_action", action)
            putExtra("rodnya_call_id", callId)
            putExtra("rodnya_chat_id", chatId)
            putExtra("rodnya_is_video", isVideo)
        }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val requestCode =
            (callId.hashCode() and 0x7fffffff) + requestCodeOffset
        return PendingIntent.getActivity(context, requestCode, intent, flags)
    }

    private fun getNotificationIconResId(context: Context): Int {
        return try {
            val info = context.packageManager.getApplicationInfo(
                context.packageName,
                android.content.pm.PackageManager.GET_META_DATA,
            )
            info.metaData?.getInt("rodnya.notification.icon")
                ?.takeIf { it != 0 }
                ?: context.applicationInfo.icon
        } catch (_: Throwable) {
            context.applicationInfo.icon
        }
    }

    private fun extractTypeFromPayload(rawPayload: String?): String? {
        if (rawPayload.isNullOrBlank()) return null
        return try {
            JSONObject(rawPayload).optString("type", "")
                .takeIf { it.isNotEmpty() }
        } catch (_: Throwable) {
            null
        }
    }

    private fun extractFromPayload(rawPayload: String?, field: String): String? {
        if (rawPayload.isNullOrBlank()) return null
        return try {
            val root = JSONObject(rawPayload)
            // The backend's _buildClientPayload nests the originating
            // data under `data` — try the shallow field first for
            // forward-compat, then dig into `data`.
            val direct = root.optString(field, "")
            if (direct.isNotEmpty()) return direct
            val nested = root.optJSONObject("data") ?: return null
            nested.optString(field, "").takeIf { it.isNotEmpty() }
        } catch (_: Throwable) {
            null
        }
    }
}
