import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_locale.dart';

const _repository = 'jeswinjose203/Believers_Palace';
const _assetName = 'believers-palace.apk';
const _installedBuild = int.fromEnvironment('APP_RELEASE_BUILD');

final androidUpdateProvider = Provider<AndroidUpdatePrompter>((ref) {
  final updates = AndroidUpdatePrompter(GlobalKey<NavigatorState>());
  ref.onDispose(updates.dispose);
  return updates;
});

class AndroidRelease {
  const AndroidRelease(this.version, this.build, this.apk, this.size);
  final String version;
  final int build;
  final Uri apk;
  final int size;

  static AndroidRelease? fromJson(Object? data) {
    if (data is! Map<String, dynamic>) return null;
    final tag = data['tag_name'];
    final assets = data['assets'];
    if (tag is! String || assets is! List) return null;
    final match = RegExp(r'^v(\d+\.\d+\.\d+)\+([1-9]\d{0,9})$').firstMatch(tag);
    if (match == null || match.end != tag.length) return null;
    final apkAssets = assets.where((asset) =>
        asset is Map<String, dynamic> &&
        asset['name'] == _assetName &&
        asset['state'] == 'uploaded' &&
        asset['size'] is int &&
        (asset['size'] as int) > 0);
    if (apkAssets.isEmpty) return null;
    final build = int.parse(match[2]!);
    if (build > 2100000000) return null;
    return AndroidRelease(
      match[1]!,
      build,
      Uri.https(
          'github.com', '/$_repository/releases/download/$tag/$_assetName'),
      apkAssets.first['size'] as int,
    );
  }
}

class AndroidUpdatePrompter with WidgetsBindingObserver {
  AndroidUpdatePrompter(this.navigator);
  final GlobalKey<NavigatorState> navigator;
  static const _installer = MethodChannel('believers_palace/android_update');
  static bool get _supported =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      _installedBuild > 0;
  DateTime? _nextCheck;
  bool _running = false;
  bool _disposed = false;

  void start() {
    if (!_supported) return;
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

  Future<void> checkManually(BuildContext context) async {
    if (!_supported) {
      _notify(
          context, 'In-app updates are available on signed Android releases.');
      return;
    }
    await _check(manualContext: context);
  }

  void _notify(BuildContext? context, String message) {
    if (context == null || !context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.tr(message))),
    );
  }

  Future<void> _check({BuildContext? manualContext}) async {
    final now = DateTime.now();
    if (_disposed ||
        (manualContext == null && _nextCheck?.isAfter(now) == true)) return;
    if (_running) {
      _notify(
          manualContext, 'An update check or download is already in progress.');
      return;
    }
    _running = true;
    _nextCheck = now.add(const Duration(minutes: 15));
    final progress = manualContext == null
        ? null
        : ScaffoldMessenger.maybeOf(manualContext)?.showSnackBar(SnackBar(
            content: Text(manualContext.tr('Checking for updates…')),
            duration: const Duration(seconds: 10),
          ));
    try {
      final response = await http.get(
          Uri.https('api.github.com', '/repos/$_repository/releases/latest'),
          headers: {
            'Accept': 'application/vnd.github+json'
          }).timeout(const Duration(seconds: 8));
      progress?.close();
      if (_disposed) return;
      if (response.statusCode != 200) throw StateError('Release unavailable');
      final release = AndroidRelease.fromJson(jsonDecode(response.body));
      if (release == null) throw StateError('Invalid release');
      _nextCheck = now.add(const Duration(hours: 6));
      if (release.build <= _installedBuild) {
        _notify(manualContext, 'Your app is up to date.');
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final reminderKey = 'android_update_reminder_${release.build}';
      final remindAt = prefs.getInt(reminderKey) ?? 0;
      if (_disposed ||
          (manualContext == null && remindAt > now.millisecondsSinceEpoch)) {
        return;
      }
      final context = manualContext ?? navigator.currentState?.overlay?.context;
      if (context == null ||
          !context.mounted ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        _nextCheck = null;
        return;
      }
      final download = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('App update available')),
          content: Text(
            context.tr(
              'Version {0} is ready. Download it here, then confirm the update in Android.',
              [release.version],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('Later')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('Download update')),
            ),
          ],
        ),
      );
      if (download == true &&
          (!context.mounted || !await _install(context, release))) {
        _nextCheck = now.add(const Duration(minutes: 15));
        return;
      }
      await prefs.setInt(reminderKey,
          DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch);
    } catch (_) {
      progress?.close();
      _notify(manualContext, 'Could not check for updates. Try again later.');
    } finally {
      _running = false;
    }
  }

  Future<bool> _install(BuildContext context, AndroidRelease release) async {
    final progress = ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(context.tr('Downloading update…')),
      duration: const Duration(minutes: 5),
    ));
    try {
      final status = await _installer.invokeMethod<String>('install', {
        'url': release.apk.toString(),
        'build': release.build,
        'size': release.size,
      });
      progress?.close();
      if (status == 'permissionRequired') {
        _notify(context,
            'Allow installs from Believers Palace in Android settings, then check again.');
        return false;
      }
      if (status != 'installerOpened')
        throw StateError('Installer unavailable');
      return true;
    } catch (_) {
      progress?.close();
      _notify(context, 'Could not download or open the update. Try again.');
      return false;
    }
  }
}
