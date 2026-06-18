package com.ahjkuio.rodnya_family_app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * CA1 (P0): нативный аудиороутинг звонка (ушной / динамик / Bluetooth /
 * проводные). Причина бага: LiveKit/WebRTC на Android 12+ роутит через
 * депрекейтнутый `setSpeakerphoneOn`, поэтому `setSpeakerOn(false)`
 * (ушной) ненадёжен — на ушном тишина. Современный путь —
 * `AudioManager.setCommunicationDevice()` (API 31+), которым владеет ОДИН
 * хозяин тракта (этот бридж), а не WebRTC-AudioManager.
 *
 * Telecom у нас self-managed (RodnyaCallConnection: PROPERTY_SELF_MANAGED +
 * setAudioModeIsVoip), а self-managed Telecom НЕ маршрутизирует медиа-аудио
 * приложения — он лишь даёт состояние звонка. Поэтому единственным
 * владельцем тракта остаётся этот AudioManager-бридж (FR4 — без отдельной
 * Telecom-реконсиляции).
 *
 * MethodChannel `rodnya/call_audio` управляется из audio_route_service.dart.
 */
object RodnyaCallAudioBridge {
    private const val CHANNEL = "rodnya/call_audio"

    // Идентификаторы маршрутов — совпадают с id в audio_route_service.dart.
    private const val ROUTE_EARPIECE = "earpiece"
    private const val ROUTE_SPEAKER = "speaker"
    private const val ROUTE_BLUETOOTH = "bluetooth"
    private const val ROUTE_WIRED = "wired-headset"

    private val mainHandler = Handler(Looper.getMainLooper())

    private var appContext: Context? = null
    private var activityRef: WeakReference<MainActivity>? = null
    private var channel: MethodChannel? = null
    private var audioManager: AudioManager? = null
    private var focusRequest: AudioFocusRequest? = null
    private var active = false
    private var deviceCallback: AudioDeviceCallback? = null
    private var lastRequestedRoute: String? = null

    fun configure(activity: MainActivity, engine: FlutterEngine) {
        activityRef = WeakReference(activity)
        appContext = activity.applicationContext
        audioManager =
            appContext?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        val methodChannel =
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel = methodChannel
        methodChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        startCallAudio()
                        result.success(true)
                    }
                    "stop" -> {
                        stopCallAudio()
                        result.success(true)
                    }
                    "setRoute" -> {
                        val route = call.argument<String>("route") ?: ROUTE_EARPIECE
                        result.success(applyRoute(route))
                    }
                    "currentRoute" -> result.success(currentRoute())
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                result.error("call_audio_error", t.message, null)
            }
        }
    }

    /** FR1: режим связи + аудиофокус на старте звонка. Идемпотентно. */
    private fun startCallAudio() {
        val am = audioManager ?: return
        if (active) {
            // Идемпотентность (ревью C): повторный start() без stop() не
            // должен запрашивать новый аудиофокус (утечка прежнего, т.к.
            // focusRequest перезаписался бы без abandon). Достаточно
            // подтвердить режим связи.
            am.mode = AudioManager.MODE_IN_COMMUNICATION
            activityRef?.get()?.volumeControlStream = AudioManager.STREAM_VOICE_CALL
            return
        }
        am.mode = AudioManager.MODE_IN_COMMUNICATION
        activityRef?.get()?.volumeControlStream = AudioManager.STREAM_VOICE_CALL
        requestFocus(am)
        registerDeviceCallback(am)
        active = true
    }

    /** FR1/FR2: на завершении — отпустить фокус, очистить маршрут, mode. */
    private fun stopCallAudio() {
        val am = audioManager ?: return
        // Идемпотентность (ревью CA1/FR-B): нечего сворачивать, если звонок
        // не активен — иначе teardown по lifecycle затирал бы чужой mode.
        if (!active) {
            return
        }
        unregisterDeviceCallback(am)
        lastRequestedRoute = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                am.clearCommunicationDevice()
            } catch (_: Throwable) {
                // best-effort
            }
            @Suppress("DEPRECATION")
            am.isSpeakerphoneOn = false
            @Suppress("DEPRECATION")
            if (am.isBluetoothScoOn) {
                am.stopBluetoothSco()
            }
        } else {
            @Suppress("DEPRECATION")
            am.isSpeakerphoneOn = false
            @Suppress("DEPRECATION")
            if (am.isBluetoothScoOn) {
                // isBluetoothScoOn-сеттер framework игнорирует — реальный
                // разрыв делает только stopBluetoothSco() (ревью B).
                am.stopBluetoothSco()
            }
        }
        abandonFocus(am)
        // FR-D (ревью CA1): детерминированно возвращаем NORMAL, а не
        // «сохранённый» previousMode — при сосуществовании с WebRTC он мог
        // выставить IN_COMMUNICATION ДО нас, и восстановление такого
        // «грязного» режима оставило бы телефон в режиме связи после звонка
        // (ломая системный звук и следующий звонок). Корректное состояние
        // после завершения — MODE_NORMAL.
        am.mode = AudioManager.MODE_NORMAL
        activityRef?.get()?.volumeControlStream = AudioManager.USE_DEFAULT_STREAM_TYPE
        active = false
    }

    /**
     * FR-B (ревью CA1): гарантированный teardown на нативном lifecycle
     * (cleanUpFlutterEngine / onDestroy) — на случай, когда Dart НЕ прислал
     * stop (смерть Activity/движка, краш, любой не-happy-path). Без этого
     * телефон застревал бы в MODE_IN_COMMUNICATION с утечкой аудиофокуса и
     * AudioDeviceCallback → ломается системный звук и следующий звонок.
     * Идемпотентно с обычным stop (stopCallAudio() сам no-op при !active).
     */
    fun teardown() {
        try {
            stopCallAudio()
        } catch (_: Throwable) {
            // best-effort: teardown на пути lifecycle не должен бросать.
        }
        activityRef?.get()?.volumeControlStream = AudioManager.USE_DEFAULT_STREAM_TYPE
        activityRef = null
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun requestFocus(am: AudioManager) {
        // FR-A (ревью CA1): TRANSIENT (exclusive), а НЕ TRANSIENT_MAY_DUCK —
        // на время звонка фоновая музыка/видео должны ставиться на ПАУЗУ, а
        // не играть приглушённо (эталон — Telegram).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            val request = AudioFocusRequest.Builder(
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
            )
                .setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener { }
                .build()
            focusRequest = request
            am.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(
                null,
                AudioManager.STREAM_VOICE_CALL,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
            )
        }
    }

    private fun abandonFocus(am: AudioManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { am.abandonAudioFocusRequest(it) }
            focusRequest = null
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(null)
        }
    }

    /**
     * FR2: применить маршрут. API 31+ — setCommunicationDevice по типу;
     * ≤30 — легаси (speakerphone / bluetooth SCO). Возвращает true при
     * успехе.
     */
    private fun applyRoute(route: String): Boolean {
        val am = audioManager ?: return false
        // Маршрут имеет смысл только в режиме связи — гарантируем его.
        if (am.mode != AudioManager.MODE_IN_COMMUNICATION) {
            am.mode = AudioManager.MODE_IN_COMMUNICATION
        }
        val applied = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            applyRouteModern(am, route)
        } else {
            applyRouteLegacy(am, route)
        }
        if (applied) {
            lastRequestedRoute = route
            reinforceRoute(route)
        }
        return applied
    }

    /**
     * Some OEM WebRTC stacks briefly steal the audio route back after our
     * successful setCommunicationDevice()/speakerphone call. Re-apply the
     * user's latest choice a couple of times inside the first second so the
     * visible "Динамик" toggle matches the real Android route.
     */
    private fun reinforceRoute(route: String) {
        val delays = longArrayOf(180L, 520L)
        for (delay in delays) {
            mainHandler.postDelayed({
                val am = audioManager ?: return@postDelayed
                if (!active || lastRequestedRoute != route) {
                    return@postDelayed
                }
                if (am.mode != AudioManager.MODE_IN_COMMUNICATION) {
                    am.mode = AudioManager.MODE_IN_COMMUNICATION
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    applyRouteModern(am, route)
                } else {
                    applyRouteLegacy(am, route)
                }
            }, delay)
        }
    }

    private fun applyRouteModern(am: AudioManager, route: String): Boolean {
        val targetTypes = deviceTypesForRoute(route)
        val device = am.availableCommunicationDevices.firstOrNull { candidate ->
            targetTypes.contains(candidate.type)
        }
        if (device == null) {
            return applyRouteCompatibilityFallback(am, route)
        }
        try {
            am.clearCommunicationDevice()
        } catch (_: Throwable) {
            // best-effort
        }
        val applied = try {
            am.setCommunicationDevice(device)
        } catch (_: Throwable) {
            false
        }
        if (!applied) {
            return applyRouteCompatibilityFallback(am, route)
        }
        syncLegacySpeakerFlag(am, route)
        return true
    }

    /**
     * Некоторые Android 12+ прошивки не дают надёжно переключить встроенный
     * динамик через setCommunicationDevice(), но всё ещё слушают legacy
     * speakerphone flag. Перед fallback чистим communicationDevice, иначе
     * явный modern-route может перекрыть legacy флаг.
     */
    private fun applyRouteCompatibilityFallback(am: AudioManager, route: String): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                am.clearCommunicationDevice()
            } catch (_: Throwable) {
                // best-effort
            }
        }
        return applyRouteLegacy(am, route)
    }

    @Suppress("DEPRECATION")
    private fun applyRouteLegacy(am: AudioManager, route: String): Boolean {
        when (route) {
            ROUTE_SPEAKER -> {
                stopScoIfNeeded(am)
                am.isSpeakerphoneOn = true
            }
            ROUTE_BLUETOOTH -> {
                // SCO-линк поднимается асинхронно: startBluetoothSco() лишь
                // инициирует согласование, фактическое состояние придёт
                // позже (ACTION_SCO_AUDIO_STATE_UPDATED). Сам флаг
                // isBluetoothScoOn приложением не выставляется — framework
                // игнорирует сеттер. Поэтому НЕ врём об успехе сразу
                // (ревью B): если SCO недоступен — false; иначе инициируем
                // согласование, а фактический маршрут подтвердит
                // AudioDeviceCallback → currentRoute().
                if (!am.isBluetoothScoAvailableOffCall) {
                    return false
                }
                am.isSpeakerphoneOn = false
                am.startBluetoothSco()
            }
            ROUTE_EARPIECE, ROUTE_WIRED -> {
                stopScoIfNeeded(am)
                am.isSpeakerphoneOn = false
            }
            else -> return false
        }
        return true
    }

    @Suppress("DEPRECATION")
    private fun syncLegacySpeakerFlag(am: AudioManager, route: String) {
        when (route) {
            ROUTE_SPEAKER -> am.isSpeakerphoneOn = true
            ROUTE_EARPIECE, ROUTE_WIRED -> am.isSpeakerphoneOn = false
        }
    }

    @Suppress("DEPRECATION")
    private fun stopScoIfNeeded(am: AudioManager) {
        if (am.isBluetoothScoOn) {
            // см. ревью B: сеттер isBluetoothScoOn — no-op, рвём через
            // stopBluetoothSco().
            am.stopBluetoothSco()
        }
    }

    private fun deviceTypesForRoute(route: String): Set<Int> {
        return when (route) {
            ROUTE_SPEAKER -> setOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)
            ROUTE_EARPIECE -> setOf(AudioDeviceInfo.TYPE_BUILTIN_EARPIECE)
            ROUTE_BLUETOOTH -> setOf(
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_BLE_HEADSET,
            )
            ROUTE_WIRED -> setOf(
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_USB_HEADSET,
            )
            else -> emptySet()
        }
    }

    /** FR5: фактический активный маршрут — для отражения в UI. */
    private fun currentRoute(): String? {
        val am = audioManager ?: return null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val modernRoute = routeForDeviceType(am.communicationDevice?.type)
            if (modernRoute != null) {
                return modernRoute
            }
        }
        @Suppress("DEPRECATION")
        return when {
            am.isBluetoothScoOn -> ROUTE_BLUETOOTH
            am.isSpeakerphoneOn -> ROUTE_SPEAKER
            am.isWiredHeadsetOn -> ROUTE_WIRED
            else -> ROUTE_EARPIECE
        }
    }

    private fun routeForDeviceType(type: Int?): String? {
        return when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> ROUTE_EARPIECE
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> ROUTE_SPEAKER
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            -> ROUTE_BLUETOOTH
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            -> ROUTE_WIRED
            else -> null
        }
    }

    /**
     * FR5: подписка на смену аудиоустройств (подключили/отключили BT/
     * провод) → шлём актуальное состояние во Flutter, чтобы переключатель
     * отражал реальность, а не локальный bool.
     */
    private fun registerDeviceCallback(am: AudioManager) {
        if (deviceCallback != null) {
            return
        }
        val callback = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                notifyDevicesChanged()
            }

            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                notifyDevicesChanged()
            }
        }
        deviceCallback = callback
        am.registerAudioDeviceCallback(callback, mainHandler)
    }

    private fun unregisterDeviceCallback(am: AudioManager) {
        deviceCallback?.let { am.unregisterAudioDeviceCallback(it) }
        deviceCallback = null
    }

    private fun notifyDevicesChanged() {
        mainHandler.post {
            channel?.invokeMethod("onAudioDevicesChanged", null)
        }
    }
}
