package com.ahjkuio.rodnya_family_app

import android.app.PictureInPictureParams
import android.content.Intent
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// U6: маркер «источник установки определить не удалось». Должен
// СОВПАДАТЬ с kInstallerSourceUnavailable в app_update_service.dart —
// тогда Flutter одинаково fail-close'ит и при сломанном канале, и при
// внутренней ошибке нативного резолвера.
private const val INSTALLER_SOURCE_UNAVAILABLE = "__installer_source_unavailable__"

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Notification channels must exist before any push can be
        // displayed in the system tray on Android 8+. Register them
        // before wiring up the Flutter side so even a push that lands
        // during cold-start has somewhere to go.
        RodnyaNotificationChannels.ensureRegistered(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "rodnya/call_pip"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPictureInPicture" -> {
                    val width = call.argument<Int>("width") ?: 16
                    val height = call.argument<Int>("height") ?: 9
                    result.success(enterRodnyaPictureInPicture(width, height))
                }
                else -> result.notImplemented()
            }
        }
        // U3: гейт источника установки для OTA-самообновления (U2).
        // Возвращает packageName инсталлера или null при sideload —
        // апдейтер работает только при sideload (не магазин).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "rodnya/apk_updater"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstallerPackageName" ->
                    result.success(resolveInstallerPackageName())
                else -> result.notImplemented()
            }
        }
        RodnyaTelecomBridge.configure(this, flutterEngine)
        RodnyaCallForegroundBridge.configure(this, flutterEngine)
        // CA1: нативный аудиороутинг звонка (ушной/динамик/BT) —
        // setCommunicationDevice вместо депрекейтнутого setSpeakerphoneOn.
        RodnyaCallAudioBridge.configure(this, flutterEngine)
    }

    // CA1 FR-B (ревью): гарантированный teardown аудиотракта при отвязке
    // движка (смерть Activity/движка), даже если Dart не успел прислать stop.
    // Без этого телефон застревал бы в MODE_IN_COMMUNICATION с утечкой
    // фокуса/коллбэка. Не вызывается на смене конфигурации (движок живёт),
    // поэтому не рвёт аудио активного звонка при повороте экрана.
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        RodnyaCallAudioBridge.teardown()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        RodnyaTelecomBridge.handleIntent(this, intent)
        RodnyaCallForegroundBridge.handleIntent(this, intent)
    }

    /**
     * U3: packageName магазина-инсталлера, либо null при sideload.
     * API 30+ — InstallSourceInfo.installingPackageName (старый
     * getInstallerPackageName с API 30 deprecated). Любая ошибка →
     * null (трактуется на стороне Flutter как sideload).
     */
    private fun resolveInstallerPackageName(): String? {
        return try {
            val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                packageManager.getInstallSourceInfo(packageName)
                    .installingPackageName
            } else {
                @Suppress("DEPRECATION")
                packageManager.getInstallerPackageName(packageName)
            }
            when {
                // Честное отсутствие инсталлера — реальный sideload.
                installer.isNullOrEmpty() -> null
                // Само-инсталлер (== наш package) — деградировавший кейс,
                // fail-closed (не sideload-дефолт).
                installer == packageName -> INSTALLER_SOURCE_UNAVAILABLE
                else -> installer
            }
        } catch (_: Throwable) {
            // U6: внутренняя ошибка резолвера → fail-closed тем же
            // маркером (Flutter трактует как «источник неизвестен»),
            // а не null — иначе апдейтер мог бы активироваться в
            // магазинной сборке при сбое натива.
            INSTALLER_SOURCE_UNAVAILABLE
        }
    }

    private fun enterRodnyaPictureInPicture(width: Int, height: Int): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }

        val safeWidth = width.takeIf { it > 0 } ?: 16
        val safeHeight = height.takeIf { it > 0 } ?: 9
        return try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(safeWidth, safeHeight))
                .build()
            enterPictureInPictureMode(params)
        } catch (_: Throwable) {
            false
        }
    }
}
