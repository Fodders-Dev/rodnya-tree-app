package com.ahjkuio.rodnya_family_app

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import ru.rustore.flutter_rustore_push.FlutterRustorePushService
import ru.rustore.sdk.pushclient.messaging.model.RemoteMessage

/**
 * Subclass of the flutter_rustore_push plugin service. Lives in the
 * same intent filter slot so the RuStore SDK delivers every push to
 * us — even when the Flutter engine is dead — and forwards via
 * `super.onMessageReceived` to the existing Dart-side callback when
 * the engine is alive.
 *
 * Adds two things on top of the default plugin behavior:
 *
 *  1. **Fullscreen incoming-call notification.** Default behavior on a
 *     killed app is at most a quiet system tray entry. Real ringers
 *     want `setFullScreenIntent` so the OS lifts our accept/reject
 *     UI over the lockscreen on Android 13+. We build that notification
 *     here whenever `data.type` is `call_invite` / `call`. Tap on the
 *     body or the green "Принять" pending-intent routes back to
 *     `MainActivity` with extras the existing `RodnyaTelecomBridge`
 *     already knows how to consume.
 *
 *  2. **Channel guarantee.** `RodnyaNotificationChannels.ensureRegistered`
 *     also runs from `MainActivity`, but a push can arrive BEFORE the
 *     activity has ever been opened post-install. Doing it once more
 *     here is cheap and safe (no-op when the channel exists).
 *
 * The plugin's default `FlutterRustorePushService` is removed from the
 * merged manifest via `tools:node="remove"` — we are the single
 * registered service. Without that we'd get duplicate Dart-side
 * deliveries.
 */
class RodnyaPushService : FlutterRustorePushService() {
    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)

        // Make sure channels exist before we try to post into one.
        RodnyaNotificationChannels.ensureRegistered(applicationContext)

        val data = message.data
        val type = (data["type"] ?: extractTypeFromPayload(data["payload"]))
            .orEmpty()
            .trim()
        if (type != "call_invite" && type != "call") {
            return
        }

        val callId = (data["callId"] ?: extractFromPayload(data["payload"], "callId"))
            ?.trim()
            .orEmpty()
        if (callId.isEmpty()) {
            return
        }

        val chatId = (data["chatId"] ?: extractFromPayload(data["payload"], "chatId"))
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        val callerName = (
            message.notification?.title
                ?: data["callerName"]
                ?: extractFromPayload(data["payload"], "callerName")
            )?.trim().orEmpty().ifEmpty { "Звонок" }
        val body = (
            message.notification?.body
                ?: data["body"]
                ?: "Входящий звонок"
            ).trim()
        val isVideo = (
            data["isVideo"] == "true" ||
            data["mediaMode"] == "video" ||
            extractFromPayload(data["payload"], "mediaMode") == "video"
        )

        showIncomingCallNotification(
            callId = callId,
            chatId = chatId,
            callerName = callerName,
            body = body,
            isVideo = isVideo,
        )
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
        val contentPendingIntent = buildActionPendingIntent(
            context = context,
            action = "open",
            callId = callId,
            chatId = chatId,
            isVideo = isVideo,
            requestCodeOffset = 3,
        )

        val ringtone =
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)

        val builder = NotificationCompat.Builder(
            context,
            RodnyaNotificationChannels.CALLS_ID,
        )
            .setSmallIcon(getNotificationIconResId(context))
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
            // Tap on the body — same flow as accept.
            .setContentIntent(contentPendingIntent)
            // Lockscreen "ringer" UI — needs USE_FULL_SCREEN_INTENT,
            // already declared in our manifest. setFullScreenIntent
            // also needs `true` to actually request lockscreen take-over.
            .setFullScreenIntent(contentPendingIntent, true)
            .addAction(
                getNotificationIconResId(context),
                "Отклонить",
                rejectPendingIntent,
            )
            .addAction(
                getNotificationIconResId(context),
                if (isVideo) "Принять видео" else "Принять",
                acceptPendingIntent,
            )

        // Stable id derived from the callId so a duplicate push for the
        // same call updates the existing notification instead of
        // stacking another.
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

        // Per-callId+action requestCode so accept and reject pending
        // intents don't collide.
        val requestCode = (callId.hashCode() and 0x7fffffff) + requestCodeOffset
        return PendingIntent.getActivity(context, requestCode, intent, flags)
    }

    private fun getNotificationIconResId(context: Context): Int {
        // We registered `rodnya.notification.icon` as a meta-data
        // resource in the manifest pointing at @drawable/ic_stat_notification.
        // Fall back to the launcher icon if for some reason the
        // metadata resolution fails (shouldn't happen in practice).
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
            JSONObject(rawPayload).optString("type", "").takeIf { it.isNotEmpty() }
        } catch (_: Throwable) {
            null
        }
    }

    private fun extractFromPayload(rawPayload: String?, field: String): String? {
        if (rawPayload.isNullOrBlank()) return null
        return try {
            val root = JSONObject(rawPayload)
            // Backend's _buildClientPayload wraps the originating data
            // under a `data` sub-object. Try the shallow field first
            // for forward compat, then dig into `data`.
            val direct = root.optString(field, "")
            if (direct.isNotEmpty()) return direct
            val nested = root.optJSONObject("data") ?: return null
            nested.optString(field, "").takeIf { it.isNotEmpty() }
        } catch (_: Throwable) {
            null
        }
    }
}
