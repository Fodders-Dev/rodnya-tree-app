package com.ahjkuio.rodnya_family_app

import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingReceiver

class RodnyaFcmMessagingReceiver : FlutterFirebaseMessagingReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            intent.extras?.let { extras ->
                val message = RemoteMessage(extras)
                RodnyaCallNotifier.handlePushData(
                    context = context.applicationContext,
                    data = message.data,
                    notificationTitle = message.notification?.title,
                    notificationBody = message.notification?.body,
                )
            }
        } catch (error: Throwable) {
            Log.w("RodnyaFcmReceiver", "Failed to render native FCM call", error)
        }

        super.onReceive(context, intent)
    }
}
