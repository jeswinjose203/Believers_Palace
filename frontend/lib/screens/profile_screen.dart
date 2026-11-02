import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_provider.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/image_picker_field.dart';

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

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    _ensureChurchName(user.churchId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _edit(context, ref, user),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Center(
              child: CircleAvatar(
                radius: 48,
                backgroundImage:
                    (user.profilePic != null && user.profilePic!.isNotEmpty)
                        ? NetworkImage(user.profilePic!)
                        : null,
                child: (user.profilePic == null || user.profilePic!.isEmpty)
                    ? const Icon(Icons.person, size: 48)
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Chip(
                label: Text(_roleLabel(user.role)),
                backgroundColor: Colors.indigo.shade50,
              ),
            ),
            const SizedBox(height: 16),
            _tile('Name', user.name),
            _tile('Email', user.email),
            _tile('Phone', user.phone ?? '-'),
            _tile('Unit', user.unit ?? '-'),
            _tile('Role', _roleLabel(user.role)),
            if (user.churchId != null)
              _tile('Church', _churchName ?? 'Loading...'),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              icon: const Icon(Icons.devices),
              label: const Text('Log out everywhere'),
              onPressed: () => _logoutEverywhere(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logoutEverywhere(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out everywhere?'),
        content: const Text(
          'This signs you out of all devices by revoking every active session. '
          'You will need to log in again.',
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
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Widget _tile(String label, String value) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(label),
        subtitle: Text(value),
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

  Future<void> _edit(BuildContext context, WidgetRef ref, User user) async {
    final name = TextEditingController(text: user.name);
    final phone = TextEditingController(text: user.phone ?? '');
    final unit = TextEditingController(text: user.unit ?? '');
    String? profilePic = user.profilePic;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.of(context).pop(),
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
                      (profilePic == null || profilePic!.isEmpty) ? null : profilePic,
                });
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile updated')),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString())),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
