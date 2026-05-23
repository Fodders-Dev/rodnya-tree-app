package com.ahjkuio.rodnya_family_app

import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val CHANNEL_NAME = "rodnya.calls/foreground"
private const val PREFS_NAME = "rodnya_call_foreground"
private const val PREF_PENDING_ACTION = "pending_notification_action"
private const val PREF_PENDING_CALL_ID = "pending_notification_call_id"

/**
 * Bridge между Dart `CallCoordinatorService` и Kotlin
 * `RodnyaCallForegroundService`. Зеркалит pattern
 * `RodnyaTelecomBridge` — MethodChannel handler + intent-extra
 * routing + SharedPreferences pending-action queue для notification
 * action buttons.
 *
 * Methods от Dart → Android:
 *  - `startCallService({callId, peerName, isVideo, micEnabled})` —
 *    запускает foreground service с persistent notification.
 *  - `updateCallService({callId, peerName, micEnabled})` —
 *    переопубликовывает notification с обновлённым состоянием.
 *  - `stopCallService()` — останавливает service + dismisses
 *    notification.
 *  - `consumePendingNotificationAction()` — возвращает (и стирает)
 *    pending action из notification button tap. Dart polls
 *    при `_handlePendingAndroidCallAction` flow либо при resume.
 *
 * Notification action button tap routing:
 *  1. PendingIntent в RodnyaCallForegroundService открывает
 *     MainActivity (singleTask launchMode surfaces existing instance).
 *  2. MainActivity.onNewIntent → `handleIntent` ниже → читаем
 *     extras → сохраняем в SharedPreferences.
 *  3. Dart side polls через `consumePendingNotificationAction()` —
 *     либо явно при app resume, либо через
 *     `CallCoordinatorService.didChangeAppLifecycleState`.
 */
object RodnyaCallForegroundBridge {

    fun configure(activity: MainActivity, flutterEngine: FlutterEngine) {
        // Capture intent extras если MainActivity был cold-started
        // через notification action tap.
        handleIntent(activity, activity.intent)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCallService" -> {
                    val callId = call.argument<String>("callId") ?: ""
                    val peerName = call.argument<String>("peerName")
                    val isVideo = call.argument<Boolean>("isVideo") ?: false
                    val micEnabled = call.argument<Boolean>("micEnabled") ?: true
                    result.success(
                        startCallService(
                            activity.applicationContext,
                            callId = callId,
                            peerName = peerName,
                            isVideo = isVideo,
                            micEnabled = micEnabled,
                        ),
                    )
                }
                "updateCallService" -> {
                    val callId = call.argument<String>("callId") ?: ""
                    val peerName = call.argument<String>("peerName")
                    val micEnabled = call.argument<Boolean>("micEnabled") ?: true
                    val isVideo = call.argument<Boolean>("isVideo") ?: false
                    result.success(
                        updateCallService(
                            activity.applicationContext,
                            callId = callId,
                            peerName = peerName,
                            isVideo = isVideo,
                            micEnabled = micEnabled,
                        ),
                    )
                }
                "stopCallService" -> {
                    result.success(stopCallService(activity.applicationContext))
                }
                "consumePendingNotificationAction" -> {
                    result.success(consumePendingAction(activity.applicationContext))
                }
                else -> result.notImplemented()
            }
        }
    }

    fun handleIntent(context: Context, intent: Intent?) {
        val action = intent
            ?.getStringExtra(RodnyaCallForegroundService.EXTRA_NOTIFICATION_ACTION)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: return
        val callId = intent
            .getStringExtra(RodnyaCallForegroundService.EXTRA_NOTIFICATION_CALL_ID)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: return
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(PREF_PENDING_ACTION, action)
            .putString(PREF_PENDING_CALL_ID, callId)
            .apply()
        // Очищаем extras чтобы повторные onNewIntent не re-fire'или
        // ту же action. SharedPreferences теперь — единственный source
        // правды для pending action.
        intent.removeExtra(RodnyaCallForegroundService.EXTRA_NOTIFICATION_ACTION)
        intent.removeExtra(RodnyaCallForegroundService.EXTRA_NOTIFICATION_CALL_ID)
    }

    private fun startCallService(
        context: Context,
        callId: String,
        peerName: String?,
        isVideo: Boolean,
        micEnabled: Boolean,
    ): Boolean {
        val normalizedCallId = callId.trim()
        if (normalizedCallId.isEmpty()) {
            return false
        }
        val intent = RodnyaCallForegroundService.startIntent(
            context,
            callId = normalizedCallId,
            peerName = peerName,
            isVideo = isVideo,
            micEnabled = micEnabled,
            update = false,
        )
        return startServiceCompat(context, intent)
    }

    private fun updateCallService(
        context: Context,
        callId: String,
        peerName: String?,
        isVideo: Boolean,
        micEnabled: Boolean,
    ): Boolean {
        val normalizedCallId = callId.trim()
        if (normalizedCallId.isEmpty()) {
            return false
        }
        val intent = RodnyaCallForegroundService.startIntent(
            context,
            callId = normalizedCallId,
            peerName = peerName,
            isVideo = isVideo,
            micEnabled = micEnabled,
            update = true,
        )
        // Update path использует тот же startForegroundService —
        // OS routes к onStartCommand existing service'а, который
        // re-posts notification с обновлёнными extras.
        return startServiceCompat(context, intent)
    }

    private fun stopCallService(context: Context): Boolean {
        return try {
            // startForegroundService с ACTION_STOP — ловит даже если
            // service был убит OS-ью и rebound'нулся, чтобы
            // stopForeground + stopSelf вызвалось без exception.
            startServiceCompat(context, RodnyaCallForegroundService.stopIntent(context))
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun startServiceCompat(context: Context, intent: Intent): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            true
        } catch (_: Throwable) {
            // Service может fail'нуться если app не в foreground +
            // нет ALLOW_BACKGROUND_ACTIVITY_STARTS exemption. Логируем
            // через swallow, Dart side увидит missing audio symptom +
            // surfaceит через `microphonePublishFailed` flag (Q1 fix).
            false
        }
    }

    private fun consumePendingAction(context: Context): Map<String, Any?>? {
        val preferences =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val action = preferences.getString(PREF_PENDING_ACTION, null)?.trim().orEmpty()
        val callId = preferences.getString(PREF_PENDING_CALL_ID, null)?.trim().orEmpty()
        preferences.edit()
            .remove(PREF_PENDING_ACTION)
            .remove(PREF_PENDING_CALL_ID)
            .apply()
        if (action.isEmpty() || callId.isEmpty()) {
            return null
        }
        return mapOf(
            "action" to action,
            "callId" to callId,
        )
    }
}
