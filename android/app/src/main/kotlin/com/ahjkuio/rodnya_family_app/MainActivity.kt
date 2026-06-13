package com.ahjkuio.rodnya_family_app

import android.app.PictureInPictureParams
import android.content.Intent
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                packageManager.getInstallSourceInfo(packageName)
                    .installingPackageName
            } else {
                @Suppress("DEPRECATION")
                packageManager.getInstallerPackageName(packageName)
            }
        } catch (_: Throwable) {
            null
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
