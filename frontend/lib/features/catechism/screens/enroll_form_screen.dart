import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../models/catechism_models.dart';
import '../services/catechism_api.dart';

class EnrollFormScreen extends ConsumerStatefulWidget {
  final CatechismClass catechismClass;

  const EnrollFormScreen({super.key, required this.catechismClass});

  @override
  ConsumerState<EnrollFormScreen> createState() => _EnrollFormScreenState();
}

class _EnrollFormScreenState extends ConsumerState<EnrollFormScreen> {
  final _name = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _dob;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  int _ageOn(DateTime dob) {
    final today = DateTime.now();
    var years = today.year - dob.year;
    final birthday = DateTime(today.year, dob.month, dob.day);
    if (today.isBefore(birthday)) years--;
    return years;
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      _msg('Student name is required');
      return;
    }
    if (_dob == null) {
      _msg('Date of birth is required');
      return;
    }
    if (_dob!.isAfter(DateTime.now())) {
      _msg('Date of birth cannot be in the future');
      return;
    }
    final age = _ageOn(_dob!);
    final cls = widget.catechismClass;
    if (cls.minAge != null && age < cls.minAge!) {
      _msg('Student must be at least ${cls.minAge} years old');
      return;
    }
    if (cls.maxAge != null && age > cls.maxAge!) {
      _msg('Student must be at most ${cls.maxAge} years old');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(catechismApiProvider).createEnrollment(cls.id, {
        'studentName': _name.text.trim(),
        'dateOfBirth': _dob!.toIso8601String().split('T').first,
        if (_notes.text.isNotEmpty) 'notes': _notes.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        _msg('Class is full or this student is already enrolled.');
      } else if (e.statusCode == 403) {
        _msg('You do not have permission to enroll.');
      } else {
        _msg(e.message);
      }
    } catch (e) {
      _msg(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _msg(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(2015, 1, 1),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enroll student')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Class: ${widget.catechismClass.name}'),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Student full name *'),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_dob == null ? 'Date of birth *' : 'DOB: ${_dob!.toLocal().toString().split(' ').first}'),
            trailing: const Icon(Icons.calendar_today),
            onTap: _pickDob,
          ),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes'),
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit enrollment'),
          ),
        ],
      ),
    );
  }
}