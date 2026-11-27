import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/firebase_app_config.dart';
import 'api_service.dart';

final chatPushProvider = Provider<ChatPushService>((ref) {
  final push = ChatPushService(ref.watch(apiServiceProvider));
  ref.onDispose(push.dispose);
  return push;
});

class ChatPushService {
  ChatPushService(this._api);

  final ApiService _api;
  static const _tokenKey = 'chat_push.device_token';
  StreamSubscription<String>? _refresh;
  String? _userId;
  bool _starting = false;
  bool _registered = false;

  bool get registered => _registered;

  Future<void> start(String userId) async {
    if (!FirebaseAppConfig.canInitialize ||
        _starting ||
        (_registered && _userId == userId)) {
      return;
    }
    _starting = true;
    _userId = userId;
    try {
      await FirebaseAppConfig.initialize();
      if (_userId != userId) return;
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission();
      if (_userId != userId ||
          permission.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        var token = await messaging.getAPNSToken();
        for (var attempt = 0; token == null && attempt < 5; attempt++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          if (_userId != userId) return;
          token = await messaging.getAPNSToken();
        }
        if (token == null) return;
      }
      final android = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        'chat_messages',
        'Chat messages',
        importance: Importance.high,
      ));
      await _refresh?.cancel();
      _refresh = messaging.onRegistered.listen((token) {
        unawaited(_register(userId, token));
      });
      await messaging.register();
    } catch (error) {
      debugPrint('Chat push registration is unavailable: ${error.runtimeType}');
    } finally {
      _starting = false;
    }
  }

  Future<void> _register(String userId, String token) async {
    if (_userId != userId) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final oldToken = prefs.getString(_tokenKey);
      if (_userId != userId) return;
      await _api.registerChatPushDevice(token);
      if (_userId != userId) return;
      await prefs.setString(_tokenKey, token);
      _registered = true;
      if (oldToken != null && oldToken != token) {
        await _api.removeChatPushDevice(oldToken);
      }
    } catch (error) {
      debugPrint('Could not register chat push device: ${error.runtimeType}');
    }
  }

  Future<void> signOut() async {
    dispose();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    try {
      if (token != null) await _api.removeChatPushDevice(token);
    } catch (_) {
      // Invalidating the Firebase token also stops alerts if the API is offline.
    }
    try {
      if (FirebaseAppConfig.canInitialize && Firebase.apps.isNotEmpty) {
        await FirebaseMessaging.instance.unregister();
      }
    } catch (_) {}
    await prefs.remove(_tokenKey);
  }

  void dispose() {
    _userId = null;
    _registered = false;
    unawaited(_refresh?.cancel());
    _refresh = null;
  }
}
