import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/auth_provider.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class CertificatesScreen extends ConsumerStatefulWidget {
  const CertificatesScreen({super.key});

  @override
  ConsumerState<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends ConsumerState<CertificatesScreen> {
  Future<PaginatedResponse<Certificate>>? _future;

  Future<PaginatedResponse<Certificate>> _load() {
    final user = ref.read(authProvider).user!;
    return ref.read(apiServiceProvider).listCertificates(user.id, limit: 50);
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  void _show(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade800 : null,
      ),
    );
  }

  Future<void> _download(Certificate c) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/${c.fileName}';
      await ref.read(apiServiceProvider).downloadCertificate(c.id, path);
      _show('Saved to $path');
    } catch (e) {
      _show(e.toString(), isError: true);
    }
  }

  Future<void> _upload() async {
    final user = ref.read(authProvider).user!;
    await showDialog(
      context: context,
      builder: (context) => _UploadCertificateDialog(
        onUpload: (result) async {
          try {
            await ref.read(apiServiceProvider).uploadCertificate(
              user.id,
              file: result.file,
              type: result.type,
              certificateNumber: result.certificateNumber,
              fullName: result.fullName,
              issueDate: result.issueDate,
              notes: result.notes,
            );
            if (context.mounted) {
              Navigator.of(context).pop();
              _show('Certificate uploaded');
              _refresh();
            }
          } catch (e) {
            _show(e.toString(), isError: true);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    return Scaffold(
      appBar: AppBar(title: const Text('My Certificates')),
      floatingActionButton: FloatingActionButton(
        onPressed: _upload,
        child: const Icon(Icons.upload_file),
      ),
      body: FutureBuilder<PaginatedResponse<Certificate>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final certificates = snapshot.data?.data ?? [];
          if (certificates.isEmpty) {
            return const Center(child: Text('No certificates yet.'));
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              itemCount: certificates.length,
              itemBuilder: (context, i) {
                final c = certificates[i];
                return ListTile(
                  leading: const Icon(Icons.picture_as_pdf),
                  title: Text('${c.type} · ${c.certificateNumber}'),
                  subtitle: Text('${c.fullName} · ${c.fileName}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.download),
                    onPressed: () => _download(c),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _UploadResult {
  final File file;
  final String type;
  final String certificateNumber;
  final String fullName;
  final String? issueDate;
  final String? notes;

  _UploadResult({
    required this.file,
    required this.type,
    required this.certificateNumber,
    required this.fullName,
    this.issueDate,
    this.notes,
  });
}

class _UploadCertificateDialog extends StatefulWidget {
  final ValueChanged<_UploadResult> onUpload;

  const _UploadCertificateDialog({required this.onUpload});

  @override
  State<_UploadCertificateDialog> createState() => _UploadCertificateDialogState();
}

class _UploadCertificateDialogState extends State<_UploadCertificateDialog> {
  String _type = 'baptism';
  final _number = TextEditingController();
  final _fullName = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _issueDate;
  File? _file;
  String? _fileName;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _file = File(result.files.single.path!);
        _fileName = result.files.single.name;
      });
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _issueDate = d);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Upload certificate'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(_file == null ? 'Select PDF' : 'PDF: $_fileName'),
              trailing: const Icon(Icons.attach_file),
              onTap: _pickFile,
            ),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                'baptism',
                'confirmation',
                'marriage',
                'first_communion',
                'death',
                'other',
              ]
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v!),
            ),
            TextField(
              controller: _number,
              decoration: const InputDecoration(labelText: 'Certificate number'),
            ),
            TextField(
              controller: _fullName,
              decoration: const InputDecoration(labelText: 'Full name on certificate'),
            ),
            ListTile(
              title: const Text('Issue date (optional)'),
              subtitle: Text(_issueDate == null
                  ? 'Not set'
                  : _issueDate!.toIso8601String().split('T').first),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
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
          onPressed: _file == null ? null : () {
            widget.onUpload(_UploadResult(
              file: _file!,
              type: _type,
              certificateNumber: _number.text,
              fullName: _fullName.text,
              issueDate: _issueDate?.toIso8601String().split('T').first,
              notes: _notes.text.isEmpty ? null : _notes.text,
            ));
          },
          child: const Text('Upload'),
        ),
      ],
    );
  }
}
