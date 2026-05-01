package com.ahjkuio.rodnya_family_app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
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
                    result.success(dismissCall(callId))
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

    private fun dismissCall(callId: String): Boolean {
        val normalizedCallId = callId.trim()
        if (normalizedCallId.isEmpty()) {
            return false
        }
        return RodnyaCallRegistry.dismiss(normalizedCallId)
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
    init {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            connectionProperties = PROPERTY_SELF_MANAGED
        }
        connectionCapabilities = CAPABILITY_MUTE
        setAudioModeIsVoip(true)
        setCallerDisplayName(callerName, TelecomManager.PRESENTATION_ALLOWED)
        setAddress(
            Uri.fromParts("tel", callerName, null),
            TelecomManager.PRESENTATION_ALLOWED
        )
        setVideoState(
            if (isVideo) {
                VideoProfile.STATE_BIDIRECTIONAL
            } else {
                VideoProfile.STATE_AUDIO_ONLY
            }
        )
        setRinging()
    }

    override fun onAnswer(videoState: Int) {
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

    private fun finish(cause: Int) {
        setDisconnected(DisconnectCause(cause))
        destroy()
        RodnyaCallRegistry.remove(callId)
    }
}
