import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/marketplace_models.dart';
import '../services/api_service.dart';
import '../widgets/multi_image_picker_field.dart';

class CommunityAdFormScreen extends ConsumerStatefulWidget {
  final CommunityAd? existing;

  const CommunityAdFormScreen({super.key, this.existing});

  @override
  ConsumerState<CommunityAdFormScreen> createState() => _CommunityAdFormScreenState();
}

class _CommunityAdFormScreenState extends ConsumerState<CommunityAdFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _location;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  List<String> _images = [];
  String? _categoryId;
  String _condition = 'used';
  List<MarketplaceCategory> _categories = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _price = TextEditingController(
        text: e != null ? (e.priceCents / 100).toStringAsFixed(2) : '');
    _location = TextEditingController(text: e?.location ?? '');
    _phone = TextEditingController(text: e?.contactPhone ?? '');
    _email = TextEditingController(text: e?.contactEmail ?? '');
    _images = List.from(e?.images ?? []);
    _categoryId = e?.categoryId;
    _condition = e?.condition ?? 'used';
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await ref.read(apiServiceProvider).listMarketplaceCategories('community');
      if (!mounted) return;
      setState(() => _categories = cats);
    } catch (_) {}
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _location.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  int? _parsePriceCents() {
    final v = double.tryParse(_price.text.trim());
    if (v == null || v <= 0) return null;
    return (v * 100).round();
  }

  Map<String, dynamic> _body() {
    final cents = _parsePriceCents();
    return {
      'categoryId': _categoryId,
      'title': _title.text.trim(),
      'description': _description.text.trim(),
      'images': _images,
      'priceCents': cents,
      'condition': _condition,
      'location': _location.text.trim(),
      if (_phone.text.trim().isNotEmpty) 'contactPhone': _phone.text.trim(),
      if (_email.text.trim().isNotEmpty) 'contactEmail': _email.text.trim(),
    };
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null) {
      setState(() => _error = 'Choose a category');
      return;
    }
    final cents = _parsePriceCents();
    if (cents == null) {
      setState(() => _error = 'Enter a valid price');
      return;
    }
    if (_phone.text.trim().isEmpty && _email.text.trim().isEmpty) {
      setState(() => _error = 'Provide a phone number or email');
      return;
    }
    setState(() => _saving = true);
    final api = ref.read(apiServiceProvider);
    try {
      if (widget.existing == null) {
        await api.createCommunityAd(_body());
      } else {
        await api.updateCommunityAd(widget.existing!.id, _body());
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New listing' : 'Edit listing'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Item name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 4,
            ),
            const SizedBox(height: 8),
            MultiImagePickerField(
              label: 'Photos',
              initialUrls: _images,
              onChanged: (urls) => setState(() => _images = urls),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _categoryId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: _categories
                  .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            TextFormField(
              controller: _price,
              decoration: const InputDecoration(labelText: 'Price (USD)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            DropdownButtonFormField<String>(
              value: _condition,
              decoration: const InputDecoration(labelText: 'Condition'),
              items: const [
                DropdownMenuItem(value: 'new', child: Text('New')),
                DropdownMenuItem(value: 'used', child: Text('Used')),
              ],
              onChanged: (v) => setState(() => _condition = v ?? 'used'),
            ),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(labelText: 'Location'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Contact phone'),
              keyboardType: TextInputType.phone,
            ),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Contact email'),
              keyboardType: TextInputType.emailAddress,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}