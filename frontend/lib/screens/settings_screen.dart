import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
 
import '../l10n/app_locale.dart';
import '../core/auth_provider.dart';
import '../models/calendar_models.dart';
import '../services/api_service.dart';
import '../services/android_update_service.dart';
import 'profile_screen.dart';
import '../widgets/user_error.dart';
 
/// Settings page, opened from Profile > Settings.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
 
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}
 
class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
 
  void _comingSoon(String what) => _toast(context.tr('{0} is not available yet', [context.tr(what)]));
 
  Future<void> _calendarPreferences() async {
    CalendarPreferences? prefs;
    try {
      prefs = await ref.read(apiServiceProvider).getCalendarPreferences();
    } catch (e) {
      if (mounted) showUserError(context, e);
      return;
    }
    if (!mounted) return;
    var week = prefs.weekStartsOn;
    var df = prefs.dateFormat;
    var country = prefs.holidayCountry;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(ctx.tr('Calendar preferences')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: week,
                decoration: InputDecoration(labelText: ctx.tr('Week starts on')),
                items: [
                  DropdownMenuItem(value: 'monday', child: Text(ctx.tr('Monday'))),
                  DropdownMenuItem(value: 'sunday', child: Text(ctx.tr('Sunday'))),
                ],
                onChanged: (v) => setSt(() => week = v ?? week),
              ),
              DropdownButtonFormField<String>(
                value: df,
                decoration: InputDecoration(labelText: ctx.tr('Date format')),
                items: const [
                  DropdownMenuItem(value: 'dmy', child: Text('DD/MM/YYYY')),
                  DropdownMenuItem(value: 'mdy', child: Text('MM/DD/YYYY')),
                  DropdownMenuItem(value: 'ymd', child: Text('YYYY-MM-DD')),
                ],
                onChanged: (v) => setSt(() => df = v ?? df),
              ),
              TextField(
                decoration: InputDecoration(labelText: ctx.tr('Holiday country (ISO)')),
                controller: TextEditingController(text: country),
                onChanged: (v) => country = v.toUpperCase(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiServiceProvider).patchCalendarPreferences({
        'weekStartsOn': week,
        'dateFormat': df,
        'holidayCountry': country,
      });
      if (mounted) _toast(context.tr('Calendar preferences saved'));
    } catch (e) {
      if (mounted) showUserError(context, e);
    }
  }
 
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
        title: Text(context.tr('Change password')),
        content: Text(context.tr('We will email a password reset link to {0}.', [email])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('Send link')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiServiceProvider).forgotPassword(email);
      if (mounted) _toast(context.tr('Password reset email sent to {0}', [email]));
    } catch (e) {
      if (mounted) showUserError(context, e);
    }
  }
 
  Future<void> _logoutEverywhere() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Log out everywhere?')),
        content: Text(
          context.tr('This signs you out of all devices by revoking every active session. You will need to log in again.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('Log out everywhere')),
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
      if (mounted) showUserError(context, e);
    }
  }
 
  // ---- Other --------------------------------------------------------------
 
  void _clearCache() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
    setState(() {});
    _toast(context.tr('Cache cleared'));
  }
 
  void _legal(String title) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(
          context.tr('This document has not been published yet. Please contact your church office for details.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('Close')),
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
                  Expanded(
                    child: Text(
                      context.tr('Settings'),
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
                  _section(context.tr('Account')),
                  SettingsCard(children: [
                    SettingsRow(
                      icon: Icons.vpn_key_outlined,
                      title: context.tr('Change Password'),
                      onTap: _changePassword,
                    ),
                    SettingsRow(
                      icon: Icons.verified_user_outlined,
                      title: context.tr('Two-Factor Authentication'),
                      subtitle: context.tr('Add an extra layer of security'),
                      trailing: Switch(
                        value: false,
                        // Not supported by the backend yet: keep it off.
                        onChanged: (_) =>
                            _comingSoon('Two-factor authentication'),
                      ),
                    ),
                    SettingsRow(
                      icon: Icons.devices_outlined,
                      title: context.tr('Log out of all devices'),
                      onTap: _logoutEverywhere,
                    ),
                  ]),
                  _section(context.tr('Preferences')),
                  SettingsCard(children: [
                    SettingsRow(
                      icon: Icons.language,
                      title: context.tr('Language'),
                      value: languageName(Localizations.localeOf(context)),
                      onTap: () => showLanguagePicker(context, ref),
                    ),
                    SettingsRow(
                      icon: Icons.notifications_none,
                      title: context.tr('Notifications'),
                      onTap: () => _comingSoon('Notification settings'),
                    ),
                    SettingsRow(
                      icon: Icons.dark_mode_outlined,
                      title: context.tr('Theme'),
                      value: context.tr('Light'),
                      onTap: () => _toast(context.tr('Only the light theme is available')),
                    ),
                    SettingsRow(
                      icon: Icons.calendar_month_outlined,
                      title: context.tr('Calendar'),
                      subtitle: context.tr('Week start, date format, holidays'),
                      onTap: _calendarPreferences,
                    ),
                  ]),
                  _section(context.tr('Privacy & Security')),
                  SettingsCard(children: [
                    SettingsRow(
                      icon: Icons.lock_outline,
                      title: context.tr('Privacy'),
                      onTap: () => _comingSoon('Privacy settings'),
                    ),
                    SettingsRow(
                      icon: Icons.shield_outlined,
                      title: context.tr('App Permissions'),
                      onTap: () => _comingSoon('App permissions'),
                    ),
                  ]),
                  _section(context.tr('Other')),
                  SettingsCard(children: [
                    SettingsRow(
                      icon: Icons.download_outlined,
                      title: context.tr('App Update'),
                      subtitle: context.tr('Check for updates'),
                      onTap: () => ref
                          .read(androidUpdateProvider)
                          .checkManually(context),
                    ),
                    SettingsRow(
                      icon: Icons.delete_outline,
                      title: context.tr('Clear Cache'),
                      value: '${_cacheMb.toStringAsFixed(1)} MB',
                      onTap: _clearCache,
                    ),
                    SettingsRow(
                      icon: Icons.info_outline,
                      title: context.tr('Terms & Conditions'),
                      onTap: () => _legal(context.tr('Terms & Conditions')),
                    ),
                    SettingsRow(
                      icon: Icons.verified_user_outlined,
                      title: context.tr('Privacy Policy'),
                      onTap: () => _legal(context.tr('Privacy Policy')),
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
