// Firebase options are intentionally loaded from dart-defines.
// Secrets must not be committed into the repository.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    final options = currentPlatformOrNull;
    if (options != null) {
      return options;
    }
    throw UnsupportedError(
      'Firebase options are not configured for the current platform. '
      'Provide LINEAGE_FIREBASE_* dart-defines or a native Firebase config file.',
    );
  }

  static FirebaseOptions? get currentPlatformOrNull {
    if (kIsWeb) {
      return _webOrNull;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _androidOrNull;
      case TargetPlatform.iOS:
        return _iosOrNull;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static FirebaseOptions? get _webOrNull => _optionsFromEnvironment(
        apiKey: const String.fromEnvironment('LINEAGE_FIREBASE_WEB_API_KEY'),
        appId: const String.fromEnvironment('LINEAGE_FIREBASE_WEB_APP_ID'),
        messagingSenderId: const String.fromEnvironment(
          'LINEAGE_FIREBASE_MESSAGING_SENDER_ID',
        ),
        projectId: const String.fromEnvironment('LINEAGE_FIREBASE_PROJECT_ID'),
        authDomain: const String.fromEnvironment(
          'LINEAGE_FIREBASE_WEB_AUTH_DOMAIN',
        ),
        storageBucket: const String.fromEnvironment(
          'LINEAGE_FIREBASE_STORAGE_BUCKET',
        ),
        measurementId: const String.fromEnvironment(
          'LINEAGE_FIREBASE_WEB_MEASUREMENT_ID',
        ),
      );

  static FirebaseOptions? get _androidOrNull => _optionsFromEnvironment(
        apiKey:
            const String.fromEnvironment('LINEAGE_FIREBASE_ANDROID_API_KEY'),
        appId: const String.fromEnvironment('LINEAGE_FIREBASE_ANDROID_APP_ID'),
        messagingSenderId: const String.fromEnvironment(
          'LINEAGE_FIREBASE_MESSAGING_SENDER_ID',
        ),
        projectId: const String.fromEnvironment('LINEAGE_FIREBASE_PROJECT_ID'),
        storageBucket: const String.fromEnvironment(
          'LINEAGE_FIREBASE_STORAGE_BUCKET',
        ),
      );

  static FirebaseOptions? get _iosOrNull => _optionsFromEnvironment(
        apiKey: const String.fromEnvironment('LINEAGE_FIREBASE_IOS_API_KEY'),
        appId: const String.fromEnvironment('LINEAGE_FIREBASE_IOS_APP_ID'),
        messagingSenderId: const String.fromEnvironment(
          'LINEAGE_FIREBASE_MESSAGING_SENDER_ID',
        ),
        projectId: const String.fromEnvironment('LINEAGE_FIREBASE_PROJECT_ID'),
        storageBucket: const String.fromEnvironment(
          'LINEAGE_FIREBASE_STORAGE_BUCKET',
        ),
        iosBundleId: const String.fromEnvironment(
          'LINEAGE_FIREBASE_IOS_BUNDLE_ID',
        ),
      );

  static FirebaseOptions? _optionsFromEnvironment({
    required String apiKey,
    required String appId,
    required String messagingSenderId,
    required String projectId,
    String? authDomain,
    String? storageBucket,
    String? measurementId,
    String? iosBundleId,
  }) {
    if (apiKey.isEmpty ||
        appId.isEmpty ||
        messagingSenderId.isEmpty ||
        projectId.isEmpty) {
      return null;
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: authDomain?.isEmpty ?? true ? null : authDomain,
      storageBucket: storageBucket?.isEmpty ?? true ? null : storageBucket,
      measurementId: measurementId?.isEmpty ?? true ? null : measurementId,
      iosBundleId: iosBundleId?.isEmpty ?? true ? null : iosBundleId,
    );
  }
}
