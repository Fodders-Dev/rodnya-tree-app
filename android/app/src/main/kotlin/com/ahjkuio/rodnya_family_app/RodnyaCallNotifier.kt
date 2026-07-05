package com.ahjkuio.rodnya_family_app

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import org.json.JSONObject

object RodnyaCallNotifier {
    fun handlePushData(
        context: Context,
        data: Map<String, String>,
        notificationTitle: String? = null,
        notificationBody: String? = null,
    ): Boolean {
        val appContext = context.applicationContext
        RodnyaNotificationChannels.ensureRegistered(appContext)

        val type = (data["type"] ?: extractTypeFromPayload(data["payload"]))
            ?.trim().orEmpty()
        if (type == "call_cancelled" || type == "call_ended") {
            handleCallTerminal(
                context = appContext,
                data = data,
                notificationTitle = notificationTitle,
                type = type,
            )
            return true
        }
        if (type != "call_invite" && type != "call") {
            return false
        }

        val callId = (data["callId"] ?: extractFromPayload(data["payload"], "callId"))
            ?.trim().orEmpty()
        if (callId.isEmpty()) {
            return false
        }

        val chatId = (data["chatId"] ?: extractFromPayload(data["payload"], "chatId"))
            ?.trim()?.takeIf { it.isNotEmpty() }
        // Calls are data-only on the backend so killed-app Android can
        // build a full-screen notification. Legacy notification title/body
        // remain as fallbacks for older pushes.
        val callerName = (
            data["callerName"]
                ?: notificationTitle
                ?: extractFromPayload(data["payload"], "callerName")
                ?: extractFromPayload(data["payload"], "title")
            )?.trim().orEmpty().ifEmpty { "Звонок" }
        val body = (
            data["callerBody"]
                ?: data["body"]
                ?: notificationBody
                ?: extractFromPayload(data["payload"], "body")
                ?: "Входящий звонок"
            ).trim()
        val isVideo = data["isVideo"] == "true" ||
            data["mediaMode"] == "video" ||
            extractFromPayload(data["payload"], "mediaMode") == "video"

        showIncomingCallNotification(
            context = appContext,
            callId = callId,
            chatId = chatId,
            callerName = callerName,
            body = body,
            isVideo = isVideo,
        )
        return true
    }

    private fun showIncomingCallNotification(
        context: Context,
        callId: String,
        chatId: String?,
        callerName: String,
        body: String,
        isVideo: Boolean,
    ) {
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
            .setColor(context.getColor(R.color.colorAccent))
            .setContentTitle(callerName)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(false)
            // P0 teardown: ОС сама снимает ongoing-нотификацию с рингтоном по
            // истечении ring-окна, даже если её никто не отменил (процесс
            // убит, терминальный пуш не дошёл). Без этого рингтон/MODE_RINGTONE
            // залипал → кнопки громкости телефона переставали работать.
            .setTimeoutAfter(RodnyaTelecomBridge.RING_TIMEOUT_MS)
            .setSound(ringtone)
            .setVibrate(longArrayOf(0, 600, 400, 600))
            .setContentIntent(openPendingIntent)
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

        val notificationId = callId.hashCode() and 0x7fffffff
        manager.notify(notificationId, builder.build())
    }

    private fun handleCallTerminal(
        context: Context,
        data: Map<String, String>,
        notificationTitle: String?,
        type: String,
    ) {
        val callId = (data["callId"] ?: extractFromPayload(data["payload"], "callId"))
            ?.trim().orEmpty()
        if (callId.isEmpty()) {
            return
        }
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as? NotificationManager ?: return

        val notificationId = callId.hashCode() and 0x7fffffff
        manager.cancel(notificationId)
        // P0 teardown: рвём и self-managed Telecom-соединение, а не только
        // нотификацию. Иначе call_cancelled-пуш гасил рингтон, но фантомный
        // вызов оставался на спаренных часах и держал MODE_RINGTONE.
        RodnyaTelecomBridge.dismissConnection(context, callId)

        if (type == "call_ended") {
            return
        }

        val callState = (data["callState"]
            ?: extractFromPayload(data["payload"], "callState"))
            ?.trim().orEmpty()
        if (callState != "missed" && callState != "cancelled") {
            return
        }

        val callerName = (
            data["callerName"]
                ?: notificationTitle
                ?: extractFromPayload(data["payload"], "callerName")
            )?.trim().orEmpty().ifEmpty { "Звонок" }
        val isVideo = data["isVideo"] == "true" ||
            data["mediaMode"] == "video" ||
            extractFromPayload(data["payload"], "mediaMode") == "video"

        showMissedCallNotification(context, callId, callerName, isVideo)
    }

    private fun showMissedCallNotification(
        context: Context,
        callId: String,
        callerName: String,
        isVideo: Boolean,
    ) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as? NotificationManager ?: return

        val openPendingIntent = buildActionPendingIntent(
            context = context,
            action = "open",
            callId = callId,
            chatId = null,
            isVideo = isVideo,
            requestCodeOffset = 4,
        )
        val iconResId = getNotificationIconResId(context)
        val text = if (isVideo) "Пропущенный видеозвонок" else "Пропущенный звонок"

        val builder = NotificationCompat.Builder(
            context,
            RodnyaNotificationChannels.SOCIAL_ID,
        )
            .setSmallIcon(iconResId)
            .setColor(context.getColor(R.color.colorAccent))
            .setContentTitle(callerName)
            .setContentText(text)
            .setCategory(NotificationCompat.CATEGORY_MISSED_CALL)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(openPendingIntent)

        val missedId = (callId.hashCode() and 0x7fffffff) xor 0x4D495353
        manager.notify(missedId, builder.build())
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
            val direct = root.optString(field, "")
            if (direct.isNotEmpty()) return direct
            val nested = root.optJSONObject("data") ?: return null
            nested.optString(field, "").takeIf { it.isNotEmpty() }
        } catch (_: Throwable) {
            null
        }
    }
}
