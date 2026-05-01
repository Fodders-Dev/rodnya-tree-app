package com.example.rodnya_family_app

import android.app.PictureInPictureParams
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
