import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_provider.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/image_picker_field.dart';
import 'church_detail_screen.dart';

class ChurchesScreen extends ConsumerStatefulWidget {
  const ChurchesScreen({super.key});

  @override
  ConsumerState<ChurchesScreen> createState() => _ChurchesScreenState();
}

class _ChurchesScreenState extends ConsumerState<ChurchesScreen> {
  final _search = TextEditingController();
  Future<PaginatedResponse<Church>>? _future;

  Future<PaginatedResponse<Church>> _load() => ref
      .read(apiServiceProvider)
      .listChurches(search: _search.text, limit: 50);

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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _createOrEdit({Church? existing}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ChurchFormDialog(existing: existing),
    );
    if (result == true) _refresh();
  }

  Future<void> _delete(Church church) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${church.name}?'),
        content: const Text(
            'This permanently removes the church and is not reversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(apiServiceProvider).deleteChurch(church.id);
      _show('Church deleted');
      _refresh();
    } catch (e) {
      _show(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isSuperAdmin = user?.role == 'super_admin';

    bool canEdit(Church c) =>
        isSuperAdmin ||
        (user?.role == 'church_admin' && user?.churchId == c.id);

    return Scaffold(
      appBar: AppBar(title: const Text('Churches')),
      floatingActionButton: isSuperAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _createOrEdit(),
              icon: const Icon(Icons.add),
              label: const Text('Add Church'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search churches',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _refresh,
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _refresh(),
            ),
          ),
          Expanded(
            child: FutureBuilder<PaginatedResponse<Church>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text('Error: ${snapshot.error}'),
                    ),
                  );
                }
                final churches = snapshot.data?.data ?? [];
                if (churches.isEmpty) {
                  return const Center(child: Text('No churches found.'));
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    itemCount: churches.length,
                    itemBuilder: (context, i) {
                      final c = churches[i];
                      return ListTile(
                        leading: c.logo != null
                            ? CircleAvatar(backgroundImage: NetworkImage(c.logo!))
                            : const CircleAvatar(child: Icon(Icons.church)),
                        title: Text(c.name),
                        subtitle: Text(c.address ?? ''),
                        trailing: canEdit(c)
                            ? PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'edit') _createOrEdit(existing: c);
                                  if (v == 'delete') _delete(c);
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit'),
                                  ),
                                  if (isSuperAdmin)
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete'),
                                    ),
                                ],
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChurchDetailScreen(church: c),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A dialog for creating or editing a church, including a logo image upload.
class ChurchFormDialog extends ConsumerStatefulWidget {
  final Church? existing;

  const ChurchFormDialog({super.key, this.existing});

  @override
  ConsumerState<ChurchFormDialog> createState() => _ChurchFormDialogState();
}

class _ChurchFormDialogState extends ConsumerState<ChurchFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  String? _logo;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name = TextEditingController(text: c?.name ?? '');
    _address = TextEditingController(text: c?.address ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _logo = c?.logo;
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'name': _name.text.trim(),
      'address': _address.text.isEmpty ? null : _address.text,
      'phone': _phone.text.isEmpty ? null : _phone.text,
      'email': _email.text.isEmpty ? null : _email.text,
      'logo': (_logo == null || _logo!.isEmpty) ? null : _logo,
    };
    try {
      final api = ref.read(apiServiceProvider);
      if (widget.existing == null) {
        await api.createChurch(body);
      } else {
        await api.updateChurch(widget.existing!.id, body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Church' : 'Edit Church'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            TextField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            TextField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            ImagePickerField(
              label: 'Logo',
              initialUrl: _logo,
              onChanged: (url) => _logo = url,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
