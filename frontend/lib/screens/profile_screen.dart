import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_provider.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/image_picker_field.dart';
import 'churches_screen.dart';
import 'my_bookings_screen.dart';
import 'settings_screen.dart';

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

  void _comingSoon(String what) => _toast('$what is not available yet');

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
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
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
            roleLabel: _roleLabel(user.role),
            onEditPhoto: () => _edit(user),
            onBell: () => _toast('No new notifications'),
          ),
          const SizedBox(height: 16),
          _Card(
            children: [
              _InfoRow(
                icon: Icons.mail_outline,
                label: 'Email',
                value: user.email,
              ),
              _InfoRow(
                icon: Icons.phone_outlined,
                label: 'Mobile',
                value: (user.phone ?? '').isEmpty ? '-' : user.phone!,
              ),
              _InfoRow(
                icon: Icons.church_outlined,
                label: 'Church',
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
                title: 'Edit Profile',
                onTap: () => _edit(user),
              ),
              _MenuRow(
                icon: Icons.settings_outlined,
                title: 'Settings',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
              if (!isSuperAdmin)
                _MenuRow(
                  icon: Icons.bookmark_border,
                  title: 'My Activities',
                  subtitle: 'Hall bookings',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const MyBookingsScreen()),
                  ),
                ),
              _MenuRow(
                icon: Icons.favorite_border,
                title: 'My Family',
                onTap: () => _comingSoon('My Family'),
              ),
              _MenuRow(
                icon: Icons.help_outline,
                title: 'Help & Support',
                onTap: () => _comingSoon('Help & Support'),
              ),
              _MenuRow(
                icon: Icons.info_outline,
                title: 'About',
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'Believers Palace',
                  applicationVersion: kAppVersion,
                  applicationLegalese:
                      'Bringing people and places of faith together.',
                ),
              ),
              _MenuRow(
                icon: Icons.logout,
                title: 'Logout',
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
    final phone = TextEditingController(text: user.phone ?? '');
    final unit = TextEditingController(text: user.unit ?? '');
    String? profilePic = user.profilePic;

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: phone,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              TextField(
                controller: unit,
                decoration: const InputDecoration(labelText: 'Unit'),
              ),
              ImagePickerField(
                label: 'Profile picture',
                initialUrl: user.profilePic,
                onChanged: (url) => profilePic = url,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await ref.read(authProvider.notifier).updateProfile({
                  'name': name.text,
                  'phone': phone.text.isEmpty ? null : phone.text,
                  'unit': unit.text.isEmpty ? null : unit.text,
                  'profilePic':
                      (profilePic == null || profilePic!.isEmpty)
                          ? null
                          : profilePic,
                });
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                if (mounted) _toast('Profile updated');
              } catch (e) {
                if (mounted) _toast(e.toString());
              }
            },
            child: const Text('Save'),
          ),
        ],
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
              const Expanded(
                child: Text(
                  'Profile',
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
                tooltip: 'Notifications',
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

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
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
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? color;
  final bool showChevron;

  const _MenuRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
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
                  if (subtitle != null)
                    Text(subtitle!,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
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
