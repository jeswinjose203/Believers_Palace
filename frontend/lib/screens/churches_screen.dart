import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_provider.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/image_picker_field.dart';
import '../widgets/multi_image_picker_field.dart';
import 'church_detail_screen.dart';

class ChurchesScreen extends ConsumerStatefulWidget {
  /// When true, shows a prompt and a "Select" action so the user can choose
  /// their church (used as the home page until a church is selected).
  final bool selectMode;

  /// Pop this route after a church is selected (when pushed on the navigator).
  final bool popOnSelect;

  const ChurchesScreen({
    super.key,
    this.selectMode = false,
    this.popOnSelect = false,
  });

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

  Future<void> _select(Church church) async {
    try {
      await ref
          .read(authProvider.notifier)
          .updateProfile({'churchId': church.id});
      if (!mounted) return;
      _show('${church.name} selected');
      if (widget.popOnSelect && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      _show(e.toString());
    }
  }

  Future<void> _createOrEdit({Church? existing}) async {
    // The list only returns a condensed church; load the full record so the
    // form is prefilled (and saving does not blank phone/email/priests).
    Church? full = existing;
    if (existing != null) {
      try {
        full = await ref.read(apiServiceProvider).getChurch(existing.id);
      } catch (e) {
        _show('Could not load church details: $e');
        return;
      }
    }
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ChurchFormDialog(existing: full),
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
      appBar: AppBar(
        title: Text(widget.selectMode ? 'Select your church' : 'Churches'),
      ),
      floatingActionButton: isSuperAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _createOrEdit(),
              icon: const Icon(Icons.add),
              label: const Text('Add Church'),
            )
          : null,
      body: Column(
        children: [
          if (widget.selectMode)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.primaryContainer,
              padding: const EdgeInsets.all(12),
              child: const Text(
                'Select your church to see its details, announcements and '
                'events on your home page.',
              ),
            ),
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
                        isThreeLine: (c.description ?? '').isNotEmpty,
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((c.address ?? '').isNotEmpty) Text(c.address!),
                            if ((c.description ?? '').isNotEmpty)
                              Text(
                                c.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
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
                            : widget.selectMode
                                ? (c.id == user?.churchId
                                    ? const Chip(label: Text('Current'))
                                    : FilledButton.tonal(
                                        onPressed: () => _select(c),
                                        child: const Text('Select'),
                                      ))
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
  late final TextEditingController _description;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  String? _logo;
  List<String> _images = [];
  late final TextEditingController _priestName;
  late final TextEditingController _priestPhone;
  late final TextEditingController _priestEmail;
  late final TextEditingController _assocName;
  late final TextEditingController _assocPhone;
  late final TextEditingController _assocEmail;
  String? _priestPic;
  String? _assocPic;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name = TextEditingController(text: c?.name ?? '');
    _description = TextEditingController(text: c?.description ?? '');
    _address = TextEditingController(text: c?.address ?? '');
    _images = List<String>.from(c?.images ?? const []);
    _priestName = TextEditingController(text: c?.priest?.name ?? '');
    _priestPhone = TextEditingController(text: c?.priest?.phone ?? '');
    _priestEmail = TextEditingController(text: c?.priest?.email ?? '');
    _assocName = TextEditingController(text: c?.associatePriest?.name ?? '');
    _assocPhone = TextEditingController(text: c?.associatePriest?.phone ?? '');
    _assocEmail = TextEditingController(text: c?.associatePriest?.email ?? '');
    _priestPic = c?.priest?.profilePic;
    _assocPic = c?.associatePriest?.profilePic;
    _phone = TextEditingController(text: c?.phone ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _logo = c?.logo;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _priestName.dispose();
    _priestPhone.dispose();
    _priestEmail.dispose();
    _assocName.dispose();
    _assocPhone.dispose();
    _assocEmail.dispose();
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
    Map<String, dynamic>? priest(
            TextEditingController n,
            TextEditingController p,
            TextEditingController e,
            String? pic) =>
        n.text.trim().isEmpty
            ? null
            : {
                'name': n.text.trim(),
                'phone': p.text.trim(),
                'email': e.text.trim(),
                'profilePic': pic,
              };
    final body = {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'images': _images,
      'priest': priest(_priestName, _priestPhone, _priestEmail, _priestPic),
      'associatePriest':
          priest(_assocName, _assocPhone, _assocEmail, _assocPic),
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
    final isEdit = widget.existing != null;
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: const Color(0xFFF4F2FA),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FormHeader(
            title: isEdit ? 'Edit Church' : 'Add Church',
            subtitle: 'Register a new church or prayer venue',
            onBack: _saving ? null : () => Navigator.of(context).pop(false),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FormSection(
                    icon: Icons.church_outlined,
                    title: 'Basic Details',
                    children: [
                      _FieldLabel('Name', required: true),
                      _OutlinedField(
                        controller: _name,
                        hint: 'Enter church name',
                        icon: Icons.church_outlined,
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel('Description'),
                      _OutlinedField(
                        controller: _description,
                        hint: 'Brief description about the church',
                        minLines: 3,
                        maxLines: 5,
                        maxLength: 250,
                        showCounter: true,
                      ),
                    ],
                  ),
                  _FormSection(
                    icon: Icons.location_on_outlined,
                    title: 'Contact & Location',
                    children: [
                      _FieldLabel('Address'),
                      _OutlinedField(
                        controller: _address,
                        hint: 'Enter full address',
                        icon: Icons.location_on_outlined,
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel('Phone'),
                      _OutlinedField(
                        controller: _phone,
                        hint: 'Enter mobile number',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel('Email'),
                      _OutlinedField(
                        controller: _email,
                        hint: 'Enter email address',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ],
                  ),
                  _FormSection(
                    icon: Icons.person_outline,
                    title: 'Priest / Administrator',
                    children: [
                      _FieldLabel('Name'),
                      _OutlinedField(
                        controller: _priestName,
                        hint: 'Enter name',
                        icon: Icons.person_outline,
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel('Phone'),
                      _OutlinedField(
                        controller: _priestPhone,
                        hint: 'Enter mobile number',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel('Email'),
                      _OutlinedField(
                        controller: _priestEmail,
                        hint: 'Enter email address',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel('Profile Photo'),
                      ImagePickerField(
                        label: '',
                        initialUrl: _priestPic,
                        onChanged: (url) => _priestPic = url,
                      ),
                    ],
                  ),
                  _CollapsibleSection(
                    icon: Icons.groups_outlined,
                    title: 'Associate Priest',
                    trailingLabel: '(Optional)',
                    children: [
                      _FieldLabel('Name'),
                      _OutlinedField(
                        controller: _assocName,
                        hint: 'Enter name',
                        icon: Icons.person_outline,
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel('Phone'),
                      _OutlinedField(
                        controller: _assocPhone,
                        hint: 'Enter mobile number',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel('Email'),
                      _OutlinedField(
                        controller: _assocEmail,
                        hint: 'Enter email address',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel('Associate priest photo'),
                      ImagePickerField(
                        label: '',
                        initialUrl: _assocPic,
                        onChanged: (url) => _assocPic = url,
                      ),
                    ],
                  ),
                  _FormSection(
                    icon: Icons.photo_library_outlined,
                    title: 'Gallery & Additional Information',
                    children: [
                      _FieldLabel('Logo'),
                      ImagePickerField(
                        label: '',
                        initialUrl: _logo,
                        onChanged: (url) => _logo = url,
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel('Gallery Images'),
                      MultiImagePickerField(
                        label: '',
                        initialUrls: _images,
                        onChanged: (urls) =>
                            _images = List<String>.from(urls),
                      ),
                    ],
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
          _FormActionBar(
            saving: _saving,
            onCancel:
                _saving ? null : () => Navigator.of(context).pop(false),
            onSave: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}

const Color _kFormPurple = Color(0xFF7B2FBE);

/// Purple gradient header for the church form, matching the app design.
class _FormHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onBack;

  const _FormHeader({
    required this.title,
    required this.subtitle,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8E2DE2), Color(0xFF6A1FB5)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Column(
              children: [
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 4),
            child: Icon(Icons.church, color: Colors.white54, size: 32),
          ),
        ],
      ),
    );
  }
}

/// A white rounded card grouping related form fields under an icon + title.
class _FormSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _FormSection({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeaderRow(icon: icon, title: title),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

/// A collapsible white card section (used for the optional associate priest).
class _CollapsibleSection extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? trailingLabel;
  final List<Widget> children;

  const _CollapsibleSection({
    required this.icon,
    required this.title,
    this.trailingLabel,
    required this.children,
  });

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Expanded(
                  child: _SectionHeaderRow(
                    icon: widget.icon,
                    title: widget.title,
                    trailingLabel: widget.trailingLabel,
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: _kFormPurple,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 12),
            ...widget.children,
          ],
        ],
      ),
    );
  }
}

/// The circular-icon + title row shared by section headers.
class _SectionHeaderRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailingLabel;

  const _SectionHeaderRow({
    required this.icon,
    required this.title,
    this.trailingLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _kFormPurple.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: _kFormPurple),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _kFormPurple,
          ),
        ),
        if (trailingLabel != null) ...[
          const SizedBox(width: 6),
          Text(
            trailingLabel!,
            style: const TextStyle(color: Colors.black45, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

/// A small field label with an optional required asterisk.
class _FieldLabel extends StatelessWidget {
  final String text;
  final bool required;

  const _FieldLabel(this.text, {this.required = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          children: [
            if (required)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: Colors.red),
              ),
          ],
        ),
      ),
    );
  }
}

/// An outlined text field with an optional leading icon and character counter,
/// styled to match the target design.
class _OutlinedField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final bool showCounter;
  final TextInputType? keyboardType;

  const _OutlinedField({
    required this.controller,
    required this.hint,
    this.icon,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
    this.showCounter = false,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c),
        );
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: showCounter ? maxLength : null,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
        isDense: true,
        counterText: showCounter ? null : '',
        prefixIcon: icon == null
            ? null
            : Icon(icon, size: 18, color: _kFormPurple),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: const Color(0xFFFAF9FC),
        enabledBorder: border(Colors.black12),
        focusedBorder: border(_kFormPurple),
        border: border(Colors.black12),
      ),
    );
  }
}

/// The sticky bottom action bar with Cancel and Save buttons.
class _FormActionBar extends StatelessWidget {
  final bool saving;
  final VoidCallback? onCancel;
  final VoidCallback? onSave;

  const _FormActionBar({
    required this.saving,
    this.onCancel,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.black12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: _kFormPurple,
                side: const BorderSide(color: _kFormPurple),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Cancel',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kFormPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save',
                      style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
