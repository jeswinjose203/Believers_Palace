import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_locale.dart';
import '../../../widgets/image_picker_field.dart';
import '../models/catechism_models.dart';
import '../services/catechism_api.dart';

class ManageClassFormScreen extends ConsumerStatefulWidget {
  final String churchId;
  final CatechismClass? existing;

  const ManageClassFormScreen(
      {super.key, required this.churchId, this.existing});

  @override
  ConsumerState<ManageClassFormScreen> createState() =>
      _ManageClassFormScreenState();
}

class _ManageClassFormScreenState extends ConsumerState<ManageClassFormScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _teacher = TextEditingController();
  final _location = TextEditingController();
  final _capacity = TextEditingController(text: '20');
  String _level = 'first_communion';
  String _status = 'draft';
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(days: 180));
  String? _image;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _description.text = e.description ?? '';
      _teacher.text = e.teacherName ?? '';
      _location.text = e.location ?? '';
      _capacity.text = e.capacity.toString();
      _level = e.level;
      _status = e.status;
      _start = e.startDate;
      _end = e.endDate;
      _image = e.image;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _teacher.dispose();
    _location.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Map<String, dynamic> _body() {
    final cap = int.tryParse(_capacity.text.trim()) ?? 0;
    return {
      'name': _name.text.trim(),
      'description':
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      'level': _level,
      'teacherName': _teacher.text.trim().isEmpty ? null : _teacher.text.trim(),
      'teacherUserId': widget.existing?.teacherUserId,
      'location': _location.text.trim().isEmpty ? null : _location.text.trim(),
      'schedule': <Map<String, String>>[],
      'startDate': _jsonDate(_start),
      'endDate': _jsonDate(_end),
      'capacity': cap,
      'status': _status,
      'image': (_image == null || _image!.isEmpty) ? null : _image,
    };
  }

  String _jsonDate(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day).toIso8601String();

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      _show(context.tr('Name is required'));
      return;
    }
    if (_end.isBefore(_start)) {
      _show(context.tr('End date must be after start date'));
      return;
    }
    setState(() => _saving = true);
    try {
      final api = ref.read(catechismApiProvider);
      if (widget.existing == null) {
        await api.createClass(widget.churchId, _body());
      } else {
        await api.updateClass(widget.existing!.id, _body());
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _show(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _show(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.existing == null
              ? context.tr('New class')
              : context.tr('Edit class'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
              controller: _name,
              decoration: InputDecoration(labelText: context.tr('Name *'))),
          TextField(
            controller: _description,
            decoration: InputDecoration(labelText: context.tr('Description')),
            maxLines: 3,
          ),
          DropdownButtonFormField<String>(
            initialValue: _level,
            decoration: InputDecoration(labelText: context.tr('Level')),
            items: [
              DropdownMenuItem(
                  value: 'first_communion',
                  child: Text(context.tr('First Communion'))),
              DropdownMenuItem(
                  value: 'confirmation',
                  child: Text(context.tr('Confirmation'))),
              DropdownMenuItem(
                  value: 'baptism_prep',
                  child: Text(context.tr('Baptism prep'))),
              DropdownMenuItem(
                  value: 'sunday_school',
                  child: Text(context.tr('Sunday school'))),
              DropdownMenuItem(
                  value: 'adult', child: Text(context.tr('Adult'))),
              DropdownMenuItem(
                  value: 'other', child: Text(context.tr('Other'))),
            ],
            onChanged: (v) => setState(() => _level = v ?? _level),
          ),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: InputDecoration(labelText: context.tr('Status')),
            items: [
              DropdownMenuItem(
                  value: 'draft', child: Text(context.tr('Draft'))),
              DropdownMenuItem(value: 'open', child: Text(context.tr('Open'))),
              DropdownMenuItem(
                  value: 'closed', child: Text(context.tr('Closed'))),
              DropdownMenuItem(
                  value: 'completed', child: Text(context.tr('Completed'))),
            ],
            onChanged: (v) => setState(() => _status = v ?? _status),
          ),
          TextField(
              controller: _teacher,
              decoration:
                  InputDecoration(labelText: context.tr('Teacher name'))),
          TextField(
              controller: _location,
              decoration: InputDecoration(labelText: context.tr('Location'))),
          TextField(
            controller: _capacity,
            decoration: InputDecoration(labelText: context.tr('Capacity *')),
            keyboardType: TextInputType.number,
          ),
          ListTile(
            title: Text(context.tr(
                'Start: {0}', [_start.toLocal().toString().split(' ').first])),
            onTap: () => _pickDate(true),
          ),
          ListTile(
            title: Text(context
                .tr('End: {0}', [_end.toLocal().toString().split(' ').first])),
            onTap: () => _pickDate(false),
          ),
          ImagePickerField(
            label: context.tr('Image'),
            initialUrl: _image,
            onChanged: (url) => _image = url,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? context.tr('Saving…') : context.tr('Save')),
          ),
        ],
      ),
    );
  }
}
