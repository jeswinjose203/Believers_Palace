import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/api_service.dart';

const _roles = [
  'user',
  'priest',
  'associate_priest',
  'church_admin',
  'super_admin',
];

String roleLabel(String role) {
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

/// Super-admin screen to list users and change their roles.
class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  Future<PaginatedResponse<User>>? _future;
  String? _roleFilter;

  Future<PaginatedResponse<User>> _load() =>
      ref.read(apiServiceProvider).listUsers(role: _roleFilter, limit: 100);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  void _show(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _changeRole(User user) async {
    String selected = user.role;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Role for ${user.name}'),
          content: DropdownButtonFormField<String>(
            value: selected,
            decoration: const InputDecoration(labelText: 'Role'),
            items: _roles
                .map((r) => DropdownMenuItem(value: r, child: Text(roleLabel(r))))
                .toList(),
            onChanged: (v) => setState(() => selected = v!),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(selected),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == null || result == user.role) return;
    try {
      await ref.read(apiServiceProvider).updateRole(user.id, result);
      _show('Role updated to ${roleLabel(result)}');
      _refresh();
    } catch (e) {
      _show(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Users'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: DropdownButtonFormField<String?>(
              value: _roleFilter,
              decoration: const InputDecoration(
                labelText: 'Filter by role',
                isDense: true,
                filled: true,
                fillColor: Colors.white,
              ),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('All roles')),
                ..._roles.map(
                  (r) => DropdownMenuItem<String?>(
                      value: r, child: Text(roleLabel(r))),
                ),
              ],
              onChanged: (v) {
                setState(() => _roleFilter = v);
                _refresh();
              },
            ),
          ),
        ),
      ),
      body: FutureBuilder<PaginatedResponse<User>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final users = snapshot.data?.data ?? [];
          if (users.isEmpty) {
            return const Center(child: Text('No users found.'));
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              itemCount: users.length,
              itemBuilder: (context, i) {
                final u = users[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage:
                        (u.profilePic != null && u.profilePic!.isNotEmpty)
                            ? NetworkImage(u.profilePic!)
                            : null,
                    child: (u.profilePic == null || u.profilePic!.isEmpty)
                        ? Text(u.name.isNotEmpty ? u.name[0].toUpperCase() : '?')
                        : null,
                  ),
                  title: Text(u.name),
                  subtitle: Text(u.email),
                  trailing: Chip(label: Text(roleLabel(u.role))),
                  onTap: () => _changeRole(u),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
