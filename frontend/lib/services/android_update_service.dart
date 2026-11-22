import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const _repository = 'jeswinjose203/Believers_Palace';
const _assetName = 'believers-palace.apk';
const _installedBuild = int.fromEnvironment('APP_RELEASE_BUILD');

class AndroidRelease {
  const AndroidRelease(this.version, this.build, this.apk);
  final String version;
  final int build;
  final Uri apk;

  static AndroidRelease? fromJson(Object? data) {
    if (data is! Map<String, dynamic>) return null;
    final tag = data['tag_name'];
    final assets = data['assets'];
    if (tag is! String || assets is! List) return null;
    final match = RegExp(r'^v(\d+\.\d+\.\d+)\+([1-9]\d{0,9})$').firstMatch(tag);
    if (match == null || match.end != tag.length) return null;
    final hasApk = assets.any((asset) =>
        asset is Map<String, dynamic> &&
        asset['name'] == _assetName &&
        asset['state'] == 'uploaded' &&
        asset['size'] is int &&
        (asset['size'] as int) > 0);
    if (!hasApk) return null;
    final build = int.parse(match[2]!);
    if (build > 2100000000) return null;
    return AndroidRelease(
      match[1]!,
      build,
      Uri.https(
          'github.com', '/$_repository/releases/download/$tag/$_assetName'),
    );
  }
}

class AndroidUpdatePrompter with WidgetsBindingObserver {
  AndroidUpdatePrompter(this.navigator);
  final GlobalKey<NavigatorState> navigator;
  DateTime? _nextCheck;
  bool _running = false;
  bool _disposed = false;

  void start() {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        _installedBuild <= 0) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
  }

  Future<void> _check() async {
    final now = DateTime.now();
    if (_disposed || _running || _nextCheck?.isAfter(now) == true) return;
    _running = true;
    _nextCheck = now.add(const Duration(minutes: 15));
    try {
      final response = await http.get(
          Uri.https('api.github.com', '/repos/$_repository/releases/latest'),
          headers: {
            'Accept': 'application/vnd.github+json'
          }).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;
      _nextCheck = now.add(const Duration(hours: 6));
      final release = AndroidRelease.fromJson(jsonDecode(response.body));
      if (release == null || release.build <= _installedBuild || _disposed) {
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final reminderKey = 'android_update_reminder_${release.build}';
      final remindAt = prefs.getInt(reminderKey) ?? 0;
      if (remindAt > now.millisecondsSinceEpoch || _disposed) return;
      final context = navigator.currentState?.overlay?.context;
      if (context == null ||
          !context.mounted ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        _nextCheck = null;
        return;
      }
      final download = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('App update available'),
          content: Text(
            'Version ${release.version} is ready. Download the APK, open it, '
            'and tap Update. Keep this app installed to preserve your data.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Download update'),
            ),
          ],
        ),
      );
      if (download == true) {
        bool opened;
        try {
          opened = await launchUrl(release.apk,
              mode: LaunchMode.externalApplication);
        } catch (_) {
          opened = false;
        }
        if (!opened) {
          if (context.mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(content: Text('Could not open the APK download.')),
            );
          }
          _nextCheck = now.add(const Duration(minutes: 15));
          return;
        }
      }
      await prefs.setInt(reminderKey,
          DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch);
    } catch (_) {
      // Offline or invalid release metadata should never block the app.
    } finally {
      _running = false;
    }
  }
}
