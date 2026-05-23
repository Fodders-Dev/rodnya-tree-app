package com.ahjkuio.rodnya_family_app

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground service для активного звонка. Запуск гарантирует что
 * mic capture остаётся alive когда screen blank / app backgrounded
 * (Android 14+ revokes mic у app process без foreground service с
 * foregroundServiceType="microphone" — documented Android behavior
 * change, не device-specific quirk).
 *
 * Lifecycle:
 *  - Dart side `CallCoordinatorService._applyCall(state=active)` →
 *    MethodChannel `rodnya.calls/foreground` → `RodnyaCallForegroundBridge`
 *    → этот service started + startForeground с notification.
 *  - Update (mic toggle reflection, peer name changes) → same channel.
 *  - Terminal/disconnect → channel → stopSelf + stopForeground.
 *
 * Notification UX (Артёмов approved defaults 2026-05-22):
 *  - Title: «Идёт звонок с {peerName}» (либо «Идёт голосовой/видео-
 *    звонок» если peer unknown).
 *  - Channel: rodnya_active_call (HIGH importance, no sound, ongoing).
 *  - Actions: «Микрофон» (mute toggle) + «Завершить» (end call).
 *    Routes via MainActivity intent extras (singleTask launchMode
 *    surfaces existing MainActivity instance + onNewIntent routes
 *    к MethodChannel handler).
 *  - Tap notification body → opens MainActivity (CallScreen уже
 *    visible если в звонке).
 *
 * NB: PendingIntent.FLAG_IMMUTABLE требуется на API 31+. Если drop'нем
 * minSdk < 23, добавить FLAG_UPDATE_CURRENT.
 */
class RodnyaCallForegroundService : Service() {

    companion object {
        private const val ACTION_START = "rodnya.calls.foreground.START"
        private const val ACTION_STOP = "rodnya.calls.foreground.STOP"
        private const val ACTION_UPDATE = "rodnya.calls.foreground.UPDATE"

        private const val EXTRA_CALL_ID = "rodnya_fg_call_id"
        private const val EXTRA_PEER_NAME = "rodnya_fg_peer_name"
        private const val EXTRA_IS_VIDEO = "rodnya_fg_is_video"
        private const val EXTRA_MIC_ENABLED = "rodnya_fg_mic_enabled"

        // Forwarded intent extras для MainActivity routing. Reused
        // в RodnyaCallForegroundBridge.consumePendingNotificationAction()
        // — single source of truth для extras key naming.
        const val EXTRA_NOTIFICATION_ACTION = "rodnya_fg_notification_action"
        const val NOTIFICATION_ACTION_TOGGLE_MIC = "toggle_mic"
        const val NOTIFICATION_ACTION_END_CALL = "end_call"
        const val EXTRA_NOTIFICATION_CALL_ID = "rodnya_fg_notification_call_id"

        private const val NOTIFICATION_ID = 0x52464741 // "RFGA" — Rodnya FG Active

        /**
         * Build intent для start/update. Caller (RodnyaCallForegroundBridge)
         * заполняет extras + вызывает Context.startForegroundService.
         */
        fun startIntent(
            context: Context,
            callId: String,
            peerName: String?,
            isVideo: Boolean,
            micEnabled: Boolean,
            update: Boolean = false,
        ): Intent {
            return Intent(context, RodnyaCallForegroundService::class.java).apply {
                action = if (update) ACTION_UPDATE else ACTION_START
                putExtra(EXTRA_CALL_ID, callId)
                putExtra(EXTRA_PEER_NAME, peerName.orEmpty())
                putExtra(EXTRA_IS_VIDEO, isVideo)
                putExtra(EXTRA_MIC_ENABLED, micEnabled)
            }
        }

        fun stopIntent(context: Context): Intent {
            return Intent(context, RodnyaCallForegroundService::class.java).apply {
                action = ACTION_STOP
            }
        }
    }

    private var currentCallId: String? = null
    private var currentPeerName: String? = null
    private var currentIsVideo: Boolean = false
    private var currentMicEnabled: Boolean = true

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Make sure the channel exists перед startForeground (на cold
        // start service может стартовать ДО того как MainActivity
        // вызвал RodnyaNotificationChannels.ensureRegistered).
        RodnyaNotificationChannels.ensureRegistered(applicationContext)

        when (intent?.action) {
            ACTION_START, ACTION_UPDATE -> {
                currentCallId = intent.getStringExtra(EXTRA_CALL_ID)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?: currentCallId
                val peerName = intent.getStringExtra(EXTRA_PEER_NAME)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                if (peerName != null) {
                    currentPeerName = peerName
                }
                currentIsVideo = intent.getBooleanExtra(EXTRA_IS_VIDEO, currentIsVideo)
                currentMicEnabled =
                    intent.getBooleanExtra(EXTRA_MIC_ENABLED, currentMicEnabled)
                postForegroundNotification()
            }
            ACTION_STOP -> {
                stopAsForeground()
                return START_NOT_STICKY
            }
            else -> {
                // Service могли restart'нуть с null intent (sticky).
                // У нас START_NOT_STICKY поэтому такого не должно быть,
                // но defensive: если нет состояния — стоп.
                if (currentCallId.isNullOrEmpty()) {
                    stopAsForeground()
                    return START_NOT_STICKY
                }
                postForegroundNotification()
            }
        }

        // START_NOT_STICKY: если OS убьёт нас в low-memory, не
        // restart'имся автоматически — Dart-side reconnect (либо
        // следующий звонок) restart'нёт явно. Без этого может
        // surface'иться phantom "Идёт звонок" notification на
        // device reboot/OOM-kill.
        return START_NOT_STICKY
    }

    private fun postForegroundNotification() {
        val callId = currentCallId
        if (callId.isNullOrEmpty()) {
            stopAsForeground()
            return
        }
        val notification = buildNotification(
            callId = callId,
            peerName = currentPeerName,
            isVideo = currentIsVideo,
            micEnabled = currentMicEnabled,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun stopAsForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
        currentCallId = null
        currentPeerName = null
        currentIsVideo = false
        currentMicEnabled = true
    }

    private fun buildNotification(
        callId: String,
        peerName: String?,
        isVideo: Boolean,
        micEnabled: Boolean,
    ): Notification {
        val title = if (!peerName.isNullOrBlank()) {
            "Идёт звонок с $peerName"
        } else if (isVideo) {
            "Идёт видео-звонок"
        } else {
            "Идёт голосовой звонок"
        }

        val tapIntent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val tapPending = PendingIntent.getActivity(
            applicationContext,
            0,
            tapIntent,
            pendingIntentFlags(),
        )

        val toggleMicPending = buildActionPendingIntent(
            requestCode = 1001,
            action = NOTIFICATION_ACTION_TOGGLE_MIC,
            callId = callId,
        )
        val endCallPending = buildActionPendingIntent(
            requestCode = 1002,
            action = NOTIFICATION_ACTION_END_CALL,
            callId = callId,
        )

        val micLabel = if (micEnabled) "Заглушить" else "Включить микрофон"

        val builder = NotificationCompat.Builder(
            applicationContext,
            RodnyaNotificationChannels.ACTIVE_CALL_ID,
        )
            .setSmallIcon(android.R.drawable.stat_sys_phone_call)
            .setContentTitle(title)
            .setContentIntent(tapPending)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(
                NotificationCompat.Action.Builder(
                    android.R.drawable.ic_lock_silent_mode,
                    micLabel,
                    toggleMicPending,
                ).build(),
            )
            .addAction(
                NotificationCompat.Action.Builder(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "Завершить",
                    endCallPending,
                ).build(),
            )

        return builder.build()
    }

    private fun buildActionPendingIntent(
        requestCode: Int,
        action: String,
        callId: String,
    ): PendingIntent {
        val intent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_NOTIFICATION_ACTION, action)
            putExtra(EXTRA_NOTIFICATION_CALL_ID, callId)
        }
        return PendingIntent.getActivity(
            applicationContext,
            requestCode,
            intent,
            pendingIntentFlags(),
        )
    }

    private fun pendingIntentFlags(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
    }
}
