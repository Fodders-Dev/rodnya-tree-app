# ProGuard / R8 keep rules for Родня. Currently the release build does
# NOT enable shrinking (minifyEnabled is false in build.gradle), so
# these rules are a safety net for the day we flip the switch — without
# them livekit / RuStore / Flutter plugins lose reflective access to
# their pigeon channels and crash on startup.
#
# When you enable minification, set:
#   buildTypes.release.minifyEnabled = true
#   buildTypes.release.shrinkResources = true
#   buildTypes.release.proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'

# ── Flutter / pigeon channels ────────────────────────────────────────
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# ── flutter_rustore_push pigeon classes & our own subclass ──────────
-keep class ru.rustore.flutter_rustore_push.** { *; }
-keep class ru.rustore.flutter_rustore_push.pigeons.** { *; }
-keep class com.ahjkuio.rodnya_family_app.RodnyaPushService { *; }

# ── RuStore SDK (push, billing, update, review) ──────────────────────
# The SDK uses kotlin reflection + serialization on its model classes,
# so any obfuscation breaks message decoding and the RemoteMessage
# round-trip. Keep models + service base classes wholesale.
-keep class ru.rustore.sdk.** { *; }
-keep interface ru.rustore.sdk.** { *; }
-dontwarn ru.rustore.sdk.**

# ── LiveKit (WebRTC + signaling) ─────────────────────────────────────
# The WebRTC native bridge maps Java methods by name from JNI; any
# obfuscation drops the symbols and the Room/Track/Transceiver chain
# stops connecting. The livekit_client plugin already inherits the
# webrtc-jvm rules, but we belt-and-braces here.
-keep class io.livekit.** { *; }
-keep class livekit.** { *; }
-keep class org.webrtc.** { *; }
-dontwarn io.livekit.**
-dontwarn org.webrtc.**

# ── Hive ─────────────────────────────────────────────────────────────
# Hive uses generated TypeAdapters that reference class fields by name.
# Keep our Hive-annotated models + the generated adapters intact.
-keep class hive.** { *; }
-keep class * extends hive.HiveObject { *; }
-keep class * implements hive.HiveAdapter { *; }
-keepclassmembers class * {
    @hive.HiveField <fields>;
}

# ── Kotlin metadata / coroutines ─────────────────────────────────────
# Required for any reflection-based decoding (json_serializable,
# kotlinx.serialization, kotlin reflect). Also keeps coroutines
# Continuation symbols which suspend-fun bridges rely on.
-keep class kotlin.Metadata { *; }
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# ── permission_handler / app_links / shared_preferences plugins ──────
# Most are pure Java and survive R8, but their plugin entry points
# are loaded reflectively from the FlutterEngine.
-keep class com.baseflow.permissionhandler.** { *; }
-keep class com.llfbandit.app_links.** { *; }

# ── Our own app code that's referenced by name (intent extras) ───────
-keep class com.ahjkuio.rodnya_family_app.MainActivity { *; }
-keep class com.ahjkuio.rodnya_family_app.RodnyaConnectionService { *; }
-keep class com.ahjkuio.rodnya_family_app.RodnyaTelecomBridge { *; }
-keep class com.ahjkuio.rodnya_family_app.RodnyaNotificationChannels { *; }
