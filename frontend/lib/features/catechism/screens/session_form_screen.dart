import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/catechism_models.dart';
import '../services/catechism_api.dart';

class SessionFormScreen extends ConsumerStatefulWidget {
  final String classId;
  final CatechismSession? existing;

  const SessionFormScreen({super.key, required this.classId, this.existing});

  @override
  ConsumerState<SessionFormScreen> createState() => _SessionFormScreenState();
}

class _SessionFormScreenState extends ConsumerState<SessionFormScreen> {
  final _title = TextEditingController();
  final _topic = TextEditingController();
  final _notes = TextEditingController();
  final _start = TextEditingController(text: '09:00:00');
  final _end = TextEditingController(text: '10:00:00');
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _title.text = e.title;
      _topic.text = e.topic ?? '';
      _notes.text = e.notes ?? '';
      _start.text = e.startTime;
      _end.text = e.endTime;
      _date = e.sessionDate;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _topic.dispose();
    _notes.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      _msg('Title is required');
      return;
    }
    setState(() => _saving = true);
    final body = {
      'title': _title.text.trim(),
      'topic': _topic.text.trim().isEmpty ? null : _topic.text.trim(),
      'sessionDate': _date.toIso8601String().split('T').first,
      'startTime': _start.text.trim(),
      'endTime': _end.text.trim(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    };
    try {
      final api = ref.read(catechismApiProvider);
      if (widget.existing == null) {
        await api.createSession(widget.classId, body);
      } else {
        await api.updateSession(widget.existing!.id, body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _msg(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _msg(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'New lesson' : 'Edit lesson')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title *')),
          TextField(controller: _topic, decoration: const InputDecoration(labelText: 'Topic')),
          ListTile(
            title: Text('Date: ${_date.toLocal().toString().split(' ').first}'),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          TextField(
            controller: _start,
            decoration: const InputDecoration(labelText: 'Start time (HH:MM:SS)'),
          ),
          TextField(
            controller: _end,
            decoration: const InputDecoration(labelText: 'End time (HH:MM:SS)'),
          ),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes'),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}