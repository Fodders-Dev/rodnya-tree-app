package com.ahjkuio.rodnya_family_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build

/**
 * Registers notification channels Родня sends background pushes to.
 *
 * Android 8.0+ refuses to display a notification (including pushes
 * routed by RuStore VKPNS) unless the channel referenced by
 * `channel_id` exists. We create them once at process start so the
 * incoming-call ringer + chat notification both have somewhere to
 * land when the app is fully killed.
 *
 * Two channels:
 *   * "calls" — IMPORTANCE_HIGH, system ringtone, vibration on, used
 *     for `call_invite` / `call` push types. We deliberately use the
 *     OS ringtone URI rather than a bundled .mp3 to ensure the user
 *     hears the call even when their device is on silent/vibrate
 *     and to keep the APK lean.
 *   * "general" — IMPORTANCE_DEFAULT, default sound, used for chats,
 *     post replies, comments, etc.
 */
object RodnyaNotificationChannels {
    const val CALLS_ID = "calls"
    const val GENERAL_ID = "general"

    fun ensureRegistered(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as? NotificationManager ?: return

        if (manager.getNotificationChannel(CALLS_ID) == null) {
            val callsAttrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val ringtone =
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            val callsChannel = NotificationChannel(
                CALLS_ID,
                "Звонки",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Входящие аудио и видеозвонки"
                enableLights(true)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 600, 400, 600)
                setBypassDnd(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                setSound(ringtone, callsAttrs)
            }
            manager.createNotificationChannel(callsChannel)
        }

        if (manager.getNotificationChannel(GENERAL_ID) == null) {
            val generalChannel = NotificationChannel(
                GENERAL_ID,
                "Уведомления",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description =
                    "Сообщения, ответы и обновления родственного дерева"
                enableLights(true)
                enableVibration(true)
            }
            manager.createNotificationChannel(generalChannel)
        }
    }
}
