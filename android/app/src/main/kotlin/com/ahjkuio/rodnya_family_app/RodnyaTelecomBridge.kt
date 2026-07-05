package com.ahjkuio.rodnya_family_app

import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telecom.VideoProfile
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap

private const val ACCOUNT_ID = "rodnya_self_managed_calls"
private const val CHANNEL_NAME = "rodnya/android_calls"
private const val EXTRA_CALL_ACTION = "rodnya_call_action"
private const val EXTRA_CALL_ID = "rodnya_call_id"
private const val EXTRA_CHAT_ID = "rodnya_chat_id"
private const val EXTRA_CALLER_NAME = "rodnya_caller_name"
private const val EXTRA_IS_VIDEO = "rodnya_is_video"
private const val PREFS_NAME = "rodnya_android_calls"
private const val PREF_ACTION = "pending_action"
private const val PREF_CALL_ID = "pending_call_id"
private const val PREF_CHAT_ID = "pending_chat_id"

object RodnyaTelecomBridge {
    /**
     * Ring-предохранитель self-managed соединения: если входящий не приняли
     * и НЕ снесли (процесс убит / звонок вытеснен / call_cancelled-пуш не
     * дошёл) — авто-disconnect по этому таймауту, чтобы фантомный вызов не
     * висел вечно на часах и не держал MODE_RINGTONE. Слегка больше
     * серверного ring-окна (~30s), чтобы не резать легитимный звонок раньше
     * сервера. Общий источник для соединения и для нотификации-таймаута.
     */
    const val RING_TIMEOUT_MS = 45_000L

    fun configure(activity: MainActivity, flutterEngine: FlutterEngine) {
        handleIntent(activity, activity.intent)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "registerPhoneAccount" -> {
                    result.success(registerPhoneAccount(activity))
                }
                "showIncomingCall" -> {
                    val callId = call.argument<String>("callId") ?: ""
                    val callerName = call.argument<String>("callerName") ?: ""
                    val isVideo = call.argument<Boolean>("isVideo") ?: false
                    val chatId = call.argument<String>("chatId")
                    result.success(
                        showIncomingCall(
                            activity,
                            callId = callId,
                            callerName = callerName,
                            isVideo = isVideo,
                            chatId = chatId
                        )
                    )
                }
                "dismissCall" -> {
                    val callId = call.argument<String>("callId") ?: ""
                    result.success(dismissCall(activity, callId))
                }
                "consumePendingAction" -> {
                    result.success(consumePendingAction(activity))
                }
                else -> result.notImplemented()
            }
        }
    }

    fun handleIntent(context: Context, intent: Intent?) {
        val action = intent?.getStringExtra(EXTRA_CALL_ACTION)?.trim().orEmpty()
        val callId = intent?.getStringExtra(EXTRA_CALL_ID)?.trim().orEmpty()
        val chatId = intent?.getStringExtra(EXTRA_CHAT_ID)?.trim()
        if (action.isEmpty() || callId.isEmpty()) {
            return
        }
        storePendingAction(context, action, callId, chatId)
    }

    fun storePendingAction(
        context: Context,
        action: String,
        callId: String,
        chatId: String?
    ) {
        val normalizedAction = action.trim()
        val normalizedCallId = callId.trim()
        if (normalizedAction.isEmpty() || normalizedCallId.isEmpty()) {
            return
        }
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(PREF_ACTION, normalizedAction)
            .putString(PREF_CALL_ID, normalizedCallId)
            .putString(PREF_CHAT_ID, chatId?.trim().orEmpty())
            .apply()
        cancelIncomingCallNotification(context, normalizedCallId)
    }

    fun startMainActivityForAction(
        context: Context,
        action: String,
        callId: String,
        chatId: String?
    ) {
        storePendingAction(context, action, callId, chatId)
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_CALL_ACTION, action)
            putExtra(EXTRA_CALL_ID, callId)
            putExtra(EXTRA_CHAT_ID, chatId)
        }
        context.startActivity(intent)
    }

    private fun consumePendingAction(context: Context): Map<String, Any?>? {
        val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val action = preferences.getString(PREF_ACTION, null)?.trim().orEmpty()
        val callId = preferences.getString(PREF_CALL_ID, null)?.trim().orEmpty()
        val chatId = preferences.getString(PREF_CHAT_ID, null)?.trim().orEmpty()
        preferences.edit()
            .remove(PREF_ACTION)
            .remove(PREF_CALL_ID)
            .remove(PREF_CHAT_ID)
            .apply()
        if (action.isEmpty() || callId.isEmpty()) {
            return null
        }
        return mapOf(
            "action" to action,
            "callId" to callId,
            "chatId" to chatId.takeIf { it.isNotEmpty() }
        )
    }

    private fun registerPhoneAccount(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }
        return try {
            val telecomManager =
                context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            val handle = phoneAccountHandle(context)
            val account = PhoneAccount.builder(handle, "Родня")
                .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
                .build()
            telecomManager.registerPhoneAccount(account)
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun showIncomingCall(
        context: Context,
        callId: String,
        callerName: String,
        isVideo: Boolean,
        chatId: String?
    ): Boolean {
        val normalizedCallId = callId.trim()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || normalizedCallId.isEmpty()) {
            return false
        }
        return try {
            val telecomManager =
                context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            val handle = phoneAccountHandle(context)
            if (!registerPhoneAccount(context)) {
                return false
            }
            val incomingExtras = Bundle().apply {
                putString(EXTRA_CALL_ID, normalizedCallId)
                putString(EXTRA_CHAT_ID, chatId?.trim())
                putString(EXTRA_CALLER_NAME, callerName.trim())
                putBoolean(EXTRA_IS_VIDEO, isVideo)
            }
            val extras = Bundle().apply {
                putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle)
                putBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS, incomingExtras)
            }
            telecomManager.addNewIncomingCall(handle, extras)
            true
        } catch (_: Throwable) {
            false
        }
    }

    fun cancelIncomingCallNotification(context: Context, callId: String) {
        val normalizedCallId = callId.trim()
        if (normalizedCallId.isEmpty()) {
            return
        }
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                ?: return
        notificationManager.cancel(normalizedCallId.hashCode() and 0x7fffffff)
    }

    private fun dismissCall(context: Context, callId: String): Boolean {
        val normalizedCallId = callId.trim()
        if (normalizedCallId.isEmpty()) {
            return false
        }
        cancelIncomingCallNotification(context, normalizedCallId)
        return RodnyaCallRegistry.dismiss(normalizedCallId)
    }

    /**
     * Публичный снос Telecom-соединения по callId — для терминального пуша
     * (call_cancelled/call_ended) из RodnyaCallNotifier, который раньше гасил
     * только нотификацию и оставлял self-managed соединение (фантом на часах +
     * MODE_RINGTONE) живым. Идемпотентно: no-op, если соединения уже нет.
     */
    fun dismissConnection(context: Context, callId: String): Boolean {
        return dismissCall(context, callId)
    }

    private fun phoneAccountHandle(context: Context): PhoneAccountHandle {
        return PhoneAccountHandle(
            ComponentName(context, RodnyaConnectionService::class.java),
            ACCOUNT_ID
        )
    }
}

class RodnyaConnectionService : ConnectionService() {
    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        val extras = request?.extras ?: Bundle.EMPTY
        val incomingExtras =
            extras.getBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS) ?: extras
        val callId = incomingExtras.getString(EXTRA_CALL_ID)?.trim().orEmpty()
        val chatId = incomingExtras.getString(EXTRA_CHAT_ID)?.trim()
        val callerName = incomingExtras.getString(EXTRA_CALLER_NAME)?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: "Родня"
        val isVideo = incomingExtras.getBoolean(EXTRA_IS_VIDEO, false)
        val connection = RodnyaCallConnection(
            context = applicationContext,
            callId = callId,
            chatId = chatId,
            callerName = callerName,
            isVideo = isVideo
        )
        RodnyaCallRegistry.put(callId, connection)
        return connection
    }

    override fun onCreateIncomingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ) {
        val extras = request?.extras ?: Bundle.EMPTY
        val incomingExtras =
            extras.getBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS) ?: extras
        val callId = incomingExtras.getString(EXTRA_CALL_ID)?.trim().orEmpty()
        if (callId.isNotEmpty()) {
            RodnyaCallRegistry.remove(callId)
            RodnyaTelecomBridge.cancelIncomingCallNotification(
                applicationContext,
                callId
            )
        }
        super.onCreateIncomingConnectionFailed(connectionManagerPhoneAccount, request)
    }
}

private object RodnyaCallRegistry {
    private val connections = ConcurrentHashMap<String, RodnyaCallConnection>()

    fun put(callId: String, connection: RodnyaCallConnection) {
        val normalizedCallId = callId.trim()
        if (normalizedCallId.isNotEmpty()) {
            connections[normalizedCallId] = connection
        }
    }

    fun remove(callId: String) {
        val normalizedCallId = callId.trim()
        if (normalizedCallId.isNotEmpty()) {
            connections.remove(normalizedCallId)
        }
    }

    fun dismiss(callId: String): Boolean {
        val connection = connections.remove(callId.trim()) ?: return false
        connection.disconnectFromFlutter()
        return true
    }
}

private class RodnyaCallConnection(
    private val context: Context,
    private val callId: String,
    private val chatId: String?,
    callerName: String,
    isVideo: Boolean
) : Connection() {
    // Гигиена teardown (P0): self-managed RINGING-соединение зеркалится на
    // спаренные часы и держит аудио-режим. Если Flutter НЕ снёс его (процесс
    // убит, звонок вытеснен другим, call_cancelled-пуш не дошёл) — раньше оно
    // звонило ВЕЧНО: фантомный вызов на часах + залипший MODE_RINGTONE, из-за
    // которого кнопки громкости телефона переставали работать. Предохранитель:
    // авто-disconnect по ring-таймауту, если на звонок так и не ответили.
    // @Volatile: onAnswer читает/пишет answered на Telecom-потоке, а
    // ring-таймаут — на main; терминальный пуш дёргает finish() с фонового
    // потока мессенджера. Плюс сам finish() маршалится на main (см. ниже),
    // так что мутации Connection и флагов происходят на одном потоке.
    @Volatile
    private var answered = false
    @Volatile
    private var finished = false
    private val timeoutHandler = Handler(Looper.getMainLooper())
    private val ringTimeoutRunnable = Runnable {
        if (!answered && !finished) {
            finish(DisconnectCause.MISSED)
        }
    }

    init {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            connectionProperties = PROPERTY_SELF_MANAGED
        }
        connectionCapabilities = CAPABILITY_MUTE
        setAudioModeIsVoip(true)
        setCallerDisplayName(callerName, TelecomManager.PRESENTATION_ALLOWED)
        // Адрес ставим tel:-URI ТОЛЬКО для реального телефонного номера. Для
        // отображаемого имени («Родня» / имя из пуша) tel:-хендл рендерится на
        // спаренных часах как фейковый «номер» — они выкидывают не-цифры из
        // handle, поэтому UUID инициатора превращался в «21433289429097». Без
        // адреса часы показывают callerDisplayName, что и нужно.
        if (looksLikePhoneNumber(callerName)) {
            setAddress(
                Uri.fromParts("tel", callerName, null),
                TelecomManager.PRESENTATION_ALLOWED
            )
        }
        setVideoState(
            if (isVideo) {
                VideoProfile.STATE_BIDIRECTIONAL
            } else {
                VideoProfile.STATE_AUDIO_ONLY
            }
        )
        setRinging()
        timeoutHandler.postDelayed(
            ringTimeoutRunnable,
            RodnyaTelecomBridge.RING_TIMEOUT_MS,
        )
    }

    override fun onAnswer(videoState: Int) {
        answered = true
        timeoutHandler.removeCallbacks(ringTimeoutRunnable)
        RodnyaTelecomBridge.startMainActivityForAction(
            context,
            action = "accept",
            callId = callId,
            chatId = chatId
        )
        setActive()
    }

    override fun onReject() {
        RodnyaTelecomBridge.storePendingAction(
            context,
            action = "reject",
            callId = callId,
            chatId = chatId
        )
        finish(DisconnectCause.REJECTED)
    }

    override fun onDisconnect() {
        RodnyaTelecomBridge.storePendingAction(
            context,
            action = "disconnect",
            callId = callId,
            chatId = chatId
        )
        finish(DisconnectCause.LOCAL)
    }

    override fun onAbort() {
        finish(DisconnectCause.CANCELED)
    }

    fun disconnectFromFlutter() {
        finish(DisconnectCause.LOCAL)
    }

    private fun looksLikePhoneNumber(value: String): Boolean {
        val trimmed = value.trim()
        return trimmed.isNotEmpty() &&
            trimmed.any { it.isDigit() } &&
            trimmed.all {
                it.isDigit() || it == '+' || it == '-' || it == ' ' ||
                    it == '(' || it == ')'
            }
    }

    private fun finish(cause: Int) {
        // Маршалим на main-looper: терминальный пуш (call_cancelled/
        // call_ended) приходит на ФОНОВОМ потоке мессенджера и по цепочке
        // dismissConnection → registry.dismiss → disconnectFromFlutter
        // доходит сюда. Telecom-мутаторы Connection (setDisconnected/destroy)
        // ждут main-поток, а гонка фонового finish с main-таймаутом/onAnswer
        // могла дважды дёрнуть teardown. Единая точка сериализации: все пути
        // finish() исполняются на одном (main) потоке.
        if (Looper.myLooper() != Looper.getMainLooper()) {
            timeoutHandler.post { finish(cause) }
            return
        }
        // Идемпотентность: повторный finish (таймаут + reject-гонка, двойной
        // dismiss) не должен второй раз дёргать setDisconnected/destroy.
        if (finished) {
            return
        }
        finished = true
        timeoutHandler.removeCallbacks(ringTimeoutRunnable)
        setDisconnected(DisconnectCause(cause))
        destroy()
        RodnyaCallRegistry.remove(callId)
        RodnyaTelecomBridge.cancelIncomingCallNotification(context, callId)
    }
}
