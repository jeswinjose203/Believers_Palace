import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_locale.dart';
import '../core/auth_provider.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/image_picker_field.dart';
import 'calendar_screen.dart';
import 'certificates_screen.dart';
import 'churches_screen.dart';
import 'my_bookings_screen.dart';
import 'settings_screen.dart';
import '../widgets/user_error.dart';

const kProfilePurple = Color(0xFF5B2A91);
const kProfilePurpleLight = Color(0xFF7B3FB5);
const kProfileIcon = Color(0xFF4A22A8);

/// Shared app version string shown in About / Settings.
const kAppVersion = '0.1.0';

/// Profile ("User") page: purple header with avatar, contact card and a menu.
/// "Settings" opens [SettingsScreen].
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String? _churchName;
  String? _loadedForChurchId;

  Future<void> _ensureChurchName(String? churchId) async {
    if (churchId == null || churchId == _loadedForChurchId) return;
    _loadedForChurchId = churchId;
    try {
      final church = await ref.read(apiServiceProvider).getChurch(churchId);
      if (mounted) setState(() => _churchName = church.name);
    } catch (_) {
      if (mounted) setState(() => _churchName = null);
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  void _comingSoon(String what) => _toast(context.tr('{0} is not available yet', [context.tr(what)]));

  void _changeChurch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            const ChurchesScreen(selectMode: true, popOnSelect: true),
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Log out?')),
        content: Text(context.tr('You will need to sign in again.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('Log out')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }
    _ensureChurchName(user.churchId);

    final isMember = user.role == 'user';
    final isSuperAdmin = user.role == 'super_admin';
    final hasPhone = user.phone?.isNotEmpty ?? false;
    final churchValue = user.churchId == null
        ? (isMember ? 'Select a church' : '-')
        : (_churchName ?? 'Loading...');

    return Scaffold(
      backgroundColor: const Color(0xFFF7F6FA),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Header(
            user: user,
            roleLabel: context.tr(_roleLabel(user.role)),
            onEditPhoto: () => _editProfilePicture(user),
            onBell: () => _toast(context.tr('No new notifications')),
          ),
          const SizedBox(height: 16),
          _Card(
            children: [
              _InfoRow(
                icon: Icons.mail_outline,
                label: context.tr('Email'),
                value: user.email,
              ),
              _InfoRow(
                icon: Icons.phone_outlined,
                label: !hasPhone || user.phoneVerified
                    ? context.tr('Mobile')
                    : context.tr('Mobile (unverified)'),
                value: hasPhone ? user.phone! : '-',
                trailing: hasPhone && user.phoneVerified
                    ? Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Tooltip(
                          message: context.tr('Mobile verified'),
                          child: const Icon(Icons.verified, color: Colors.green),
                        ),
                      )
                    : null,
              ),
              _InfoRow(
                icon: Icons.church_outlined,
                label: context.tr('Church'),
                value: churchValue,
                onTap: isMember ? _changeChurch : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Card(
            children: [
              _MenuRow(
                icon: Icons.person_outline,
                title: context.tr('Edit Profile'),
                onTap: () => _edit(user),
              ),
              _MenuRow(
                icon: Icons.settings_outlined,
                title: context.tr('Settings'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
              _MenuRow(
                icon: Icons.calendar_month,
                title: context.tr('Calendar'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CalendarScreen()),
                ),
              ),
              if (!isSuperAdmin)
                _MenuRow(
                  icon: Icons.bookmark_border,
                  title: context.tr('My Bookings'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MyBookingsScreen()),
                  ),
                ),
              _MenuRow(
                icon: Icons.school,
                title: context.tr('Certificates'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CertificatesScreen()),
                ),
              ),
              _MenuRow(
                icon: Icons.info_outline,
                title: context.tr('About'),
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'Believers Palace',
                  applicationVersion: kAppVersion,
                  applicationLegalese: context.tr(
                    'Bringing people and places of faith together.',
                  ),
                ),
              ),
              _MenuRow(
                icon: Icons.logout,
                title: context.tr('Logout'),
                color: Colors.red,
                showChevron: false,
                onTap: _logout,
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static String _roleLabel(String role) {
    switch (role) {
      case 'super_admin':
        return 'Super Admin';
      case 'church_admin':
        return 'Church Admin';
      case 'associate_priest':
        return 'Associate Priest';
      case 'priest':
        return 'Priest';
      default:
        return 'Member';
    }
  }

  Future<void> _edit(User user) async {
    final name = TextEditingController(text: user.name);
    final mobile = TextEditingController(text: user.phone ?? '');
    final email = TextEditingController(text: user.email);
    String? profilePic = user.profilePic;

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        title: Text(dialogContext.tr('Edit Profile')),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              TextField(
                controller: name,
                decoration: InputDecoration(labelText: dialogContext.tr('Name')),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: mobile,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: dialogContext.tr('Mobile'),
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  dialogContext.tr('Changing mobile requires verification.'),
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: dialogContext.tr('Email')),
              ),
              const SizedBox(height: 22),
              ImagePickerField(
                label: dialogContext.tr('Profile picture'),
                initialUrl: user.profilePic,
                onChanged: (url) => profilePic = url,
              ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(dialogContext.tr('Cancel')),
          ),
          TextButton(
            onPressed: () async {
              try {
                await ref.read(authProvider.notifier).updateProfile({
                  'name': name.text,
                  'phone': mobile.text.trim().isEmpty ? null : mobile.text.trim(),
                  'email': email.text.trim(),
                  'profilePic':
                      (profilePic == null || profilePic!.isEmpty)
                          ? null
                          : profilePic,
                });
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                if (mounted) _toast(context.tr('Profile updated'));
              } catch (e) {
                if (mounted) showUserError(context, e);
              }
            },
            child: Text(dialogContext.tr('Save')),
          ),
        ],
      ),
    );
  }

  Future<void> _editProfilePicture(User user) async {
    String? profilePic = user.profilePic;
    var changed = false;
    var uploading = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ImagePickerField(
                    label: '',
                    initialUrl: user.profilePic,
                    showLabel: false,
                    centerPreview: true,
                    outlineChangeButton: false,
                    previewSize: 128,
                    onChanged: (url) => setDialogState(() {
                      profilePic = url;
                      changed = true;
                    }),
                    onUploadingChanged: (value) =>
                        setDialogState(() => uploading = value),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: uploading
                            ? null
                            : () => Navigator.of(dialogContext).pop(),
                        child: Text(dialogContext.tr('Cancel')),
                      ),
                      TextButton(
                        onPressed: uploading || !changed
                            ? null
                            : () async {
                                try {
                                  await ref
                                      .read(authProvider.notifier)
                                      .updateProfile({
                                    // Empty string is accepted by existing API
                                    // versions and renders as the default avatar.
                                    'profilePic': profilePic ?? '',
                                  });
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                  if (mounted) {
                                    _toast(context.tr('Profile updated'));
                                  }
                                } catch (e) {
                                  if (mounted) showUserError(context, e);
                                }
                              },
                        child: Text(dialogContext.tr('Save')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Building blocks (also used by SettingsScreen).
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final User user;
  final String roleLabel;
  final VoidCallback onEditPhoto;
  final VoidCallback onBell;

  const _Header({
    required this.user,
    required this.roleLabel,
    required this.onEditPhoto,
    required this.onBell,
  });

  @override
  Widget build(BuildContext context) {
    final hasPic = (user.profilePic ?? '').isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kProfilePurpleLight, kProfilePurple],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.elliptical(400, 50)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 48),
              Expanded(
                child: Text(
                  context.tr('Profile'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.notifications_none, color: Colors.white),
                tooltip: context.tr('Notifications'),
                onPressed: onBell,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFFE6DAF2),
                  shape: BoxShape.circle,
                ),
                child: CircleAvatar(
                  radius: 52,
                  backgroundColor: const Color(0xFFD9C8EC),
                  backgroundImage: hasPic ? NetworkImage(user.profilePic!) : null,
                  child: hasPic
                      ? null
                      : const Icon(Icons.person, size: 64, color: kProfilePurple),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 4,
                child: Material(
                  color: const Color(0xFFE6DAF2),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onEditPhoto,
                    child: const Padding(
                      padding: EdgeInsets.all(7),
                      child: Icon(Icons.edit, size: 16, color: kProfileIcon),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            user.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            roleLabel,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

/// White rounded card holding rows separated by hairline dividers.
class _Card extends StatelessWidget {
  final List<Widget> children;

  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Divider(height: 1, indent: 56));
      rows.add(children[i]);
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: kProfileIcon),
            const SizedBox(width: 16),
            Text(label,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right, color: Colors.black54),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? color;
  final bool showChevron;

  const _MenuRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.color,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color ?? kProfileIcon),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            if (showChevron)
              const Icon(Icons.chevron_right, color: Colors.black54),
          ],
        ),
      ),
    );
  }
}

/// Re-exported row/card widgets for the settings page.
class SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const SettingsCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) => _Card(children: children);
}

class SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: kProfileIcon),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(value!,
                    style:
                        const TextStyle(fontSize: 14, color: Colors.black87)),
              ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              const Icon(Icons.chevron_right, color: Colors.black54),
          ],
        ),
      ),
    );
  }
}
