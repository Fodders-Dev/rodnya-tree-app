package com.ahjkuio.rodnya_family_app

import android.util.Log
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

class RodnyaFcmMessagingService : FlutterFirebaseMessagingService() {
    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        try {
            RodnyaCallNotifier.handlePushData(
                context = applicationContext,
                data = remoteMessage.data,
                notificationTitle = remoteMessage.notification?.title,
                notificationBody = remoteMessage.notification?.body,
            )
        } catch (error: Throwable) {
            Log.w("RodnyaFcmService", "Failed to render native FCM call", error)
        }
        super.onMessageReceived(remoteMessage)
    }
}
