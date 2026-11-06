import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_provider.dart';
import '../services/api_service.dart';
import 'profile_screen.dart';

/// Settings page, opened from Profile > Settings.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  void _comingSoon(String what) => _toast('$what is not available yet');

  double get _cacheMb =>
      PaintingBinding.instance.imageCache.currentSizeBytes / (1024 * 1024);

  // ---- Account ------------------------------------------------------------

  /// The backend has no "change password while signed in" endpoint, so this
  /// uses the existing reset flow: a reset link is emailed to the user.
  Future<void> _changePassword() async {
    final email = ref.read(authProvider).user?.email;
    if (email == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change password'),
        content: Text('We will email a password reset link to $email.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send link'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiServiceProvider).forgotPassword(email);
      _toast('Password reset email sent to $email');
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _logoutEverywhere() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out everywhere?'),
        content: const Text(
          'This signs you out of all devices by revoking every active '
          'session. You will need to log in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out everywhere'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(authProvider.notifier).logoutEverywhere();
      // main.dart swaps to the login screen; drop this pushed route.
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      _toast(e.toString());
    }
  }

  // ---- Preferences --------------------------------------------------------

  Future<void> _language() async {
    await showDialog<void>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Language'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(),
            child: const Row(
              children: [
                Expanded(child: Text('English')),
                Icon(Icons.check, color: kProfileIcon),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 12),
            child: Text('More languages are coming soon.',
                style: TextStyle(color: Colors.black54, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ---- Other --------------------------------------------------------------

  void _clearCache() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
    setState(() {});
    _toast('Cache cleared');
  }

  void _legal(String title) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text(
          'This document has not been published yet. Please contact your '
          'church office for details.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kProfilePurple,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(bottom: 20),
            color: kProfilePurple,
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Expanded(
                    child: Text(
                      'Settings',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF1F0F5),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  _section('Account'),
                  SettingsCard(children: [
                    SettingsRow(
                      icon: Icons.vpn_key_outlined,
                      title: 'Change Password',
                      onTap: _changePassword,
                    ),
                    SettingsRow(
                      icon: Icons.verified_user_outlined,
                      title: 'Two-Factor Authentication',
                      subtitle: 'Add an extra layer of security',
                      trailing: Switch(
                        value: false,
                        // Not supported by the backend yet: keep it off.
                        onChanged: (_) =>
                            _comingSoon('Two-factor authentication'),
                      ),
                    ),
                    SettingsRow(
                      icon: Icons.devices_outlined,
                      title: 'Log out of all devices',
                      onTap: _logoutEverywhere,
                    ),
                  ]),
                  _section('Preferences'),
                  SettingsCard(children: [
                    SettingsRow(
                      icon: Icons.language,
                      title: 'Language',
                      value: 'English',
                      onTap: _language,
                    ),
                    SettingsRow(
                      icon: Icons.notifications_none,
                      title: 'Notifications',
                      onTap: () => _comingSoon('Notification settings'),
                    ),
                    SettingsRow(
                      icon: Icons.dark_mode_outlined,
                      title: 'Theme',
                      value: 'Light',
                      onTap: () => _toast('Only the light theme is available'),
                    ),
                  ]),
                  _section('Privacy & Security'),
                  SettingsCard(children: [
                    SettingsRow(
                      icon: Icons.lock_outline,
                      title: 'Privacy',
                      onTap: () => _comingSoon('Privacy settings'),
                    ),
                    SettingsRow(
                      icon: Icons.shield_outlined,
                      title: 'App Permissions',
                      onTap: () => _comingSoon('App permissions'),
                    ),
                  ]),
                  _section('Other'),
                  SettingsCard(children: [
                    SettingsRow(
                      icon: Icons.download_outlined,
                      title: 'App Update',
                      value: 'v$kAppVersion',
                      onTap: () => _toast('You are on version $kAppVersion'),
                    ),
                    SettingsRow(
                      icon: Icons.delete_outline,
                      title: 'Clear Cache',
                      value: '${_cacheMb.toStringAsFixed(1)} MB',
                      onTap: _clearCache,
                    ),
                    SettingsRow(
                      icon: Icons.info_outline,
                      title: 'Terms & Conditions',
                      onTap: () => _legal('Terms & Conditions'),
                    ),
                    SettingsRow(
                      icon: Icons.verified_user_outlined,
                      title: 'Privacy Policy',
                      onTap: () => _legal('Privacy Policy'),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
