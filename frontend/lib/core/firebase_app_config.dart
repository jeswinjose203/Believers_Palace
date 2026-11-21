import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseAppConfig {
  static FirebaseOptions? get options {
    if (kIsWeb) return null;
    final appId = switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        const String.fromEnvironment('FCM_ANDROID_APP_ID'),
      TargetPlatform.iOS => const String.fromEnvironment('FCM_IOS_APP_ID'),
      _ => '',
    };
    const apiKey = String.fromEnvironment('FCM_API_KEY');
    const project = String.fromEnvironment('FCM_PROJECT_ID');
    const sender = String.fromEnvironment('FCM_SENDER_ID');
    if ([appId, apiKey, project, sender].any((value) => value.isEmpty)) {
      return null;
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: sender,
      projectId: project,
    );
  }

  static Future<FirebaseApp>? _initializing;

  static Future<FirebaseApp> initialize(FirebaseOptions configuration) async {
    final initialization =
        _initializing ??= Firebase.initializeApp(options: configuration);
    try {
      return await initialization;
    } catch (_) {
      if (identical(_initializing, initialization)) _initializing = null;
      rethrow;
    }
  }
}
