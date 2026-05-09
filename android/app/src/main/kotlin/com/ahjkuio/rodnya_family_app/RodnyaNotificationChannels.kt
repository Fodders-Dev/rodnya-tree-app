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
 * `channel_id` exists. We create them once at process start so any
 * incoming push has somewhere to land even on a fresh install before
 * the user has opened MainActivity.
 *
 * Channels (in order of urgency):
 *
 *   * "calls" — IMPORTANCE_HIGH, system ringtone, vibration on,
 *     bypasses DND. Used for `call_invite` push types built natively
 *     in RodnyaPushService with a full-screen intent.
 *   * "chats" — IMPORTANCE_HIGH, default sound, vibration on. New
 *     direct messages — the user expects an audible alert.
 *   * "social" — IMPORTANCE_DEFAULT, default sound. Replies, likes,
 *     story reactions, "X added you", upcoming birthdays — user wants
 *     to know but it's not time-critical.
 *   * "system" — IMPORTANCE_LOW, no sound, no vibration. Admin
 *     announcements, security warnings, anything else. The user can
 *     turn the channel off entirely without nuking the rest.
 *   * "general" (legacy) — kept around so old channel ids in flight
 *     pre-upgrade still land somewhere; not used by new payloads.
 *
 * Why split channels at all: per Telegram's notification design (and
 * Android's own UX guidelines), users get to silence a category they
 * don't care about without losing alerts they DO care about. Folding
 * everything onto one «general» channel was the entire reason the
 * user reported «их заёбывает уведомлениями по хуйне» — they couldn't
 * mute social activity without also muting messages.
 */
object RodnyaNotificationChannels {
    const val CALLS_ID = "calls"
    const val CHATS_ID = "chats"
    const val SOCIAL_ID = "social"
    const val SYSTEM_ID = "system"
    const val GENERAL_ID = "general" // legacy

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

        if (manager.getNotificationChannel(CHATS_ID) == null) {
            val chatsAttrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_INSTANT)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val chatsChannel = NotificationChannel(
                CHATS_ID,
                "Сообщения",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Новые сообщения от родных и друзей"
                enableLights(true)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 220, 80, 220)
                setShowBadge(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                    chatsAttrs,
                )
            }
            manager.createNotificationChannel(chatsChannel)
        }

        if (manager.getNotificationChannel(SOCIAL_ID) == null) {
            val socialChannel = NotificationChannel(
                SOCIAL_ID,
                "Активность",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description =
                    "Реакции, ответы, дни рождения и обновления дерева"
                enableLights(true)
                enableVibration(false)
                setShowBadge(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
            }
            manager.createNotificationChannel(socialChannel)
        }

        if (manager.getNotificationChannel(SYSTEM_ID) == null) {
            val systemChannel = NotificationChannel(
                SYSTEM_ID,
                "Системные",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Объявления и тихие напоминания"
                enableLights(false)
                enableVibration(false)
                setShowBadge(false)
                lockscreenVisibility = android.app.Notification.VISIBILITY_SECRET
                setSound(null, null)
            }
            manager.createNotificationChannel(systemChannel)
        }

        // Legacy «general» channel — keep around so installs that
        // already had it don't see a phantom empty entry in Settings,
        // and so any push still in flight with channel_id=general
        // continues to land somewhere.
        if (manager.getNotificationChannel(GENERAL_ID) == null) {
            val generalChannel = NotificationChannel(
                GENERAL_ID,
                "Прочие уведомления",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Старые уведомления (используйте новые категории)"
                enableLights(true)
                enableVibration(true)
            }
            manager.createNotificationChannel(generalChannel)
        }
    }
}
