import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';

/// A reusable form field that lets the user pick an image from their device,
/// uploads it to the backend, and reports the resulting public URL.
///
/// It also accepts/falls back to a manually entered URL so existing data and
/// external links keep working. The current value (an image URL or null) is
/// surfaced via [onChanged].
class ImagePickerField extends ConsumerStatefulWidget {
  final String label;
  final String? initialUrl;
  final ValueChanged<String?> onChanged;

  const ImagePickerField({
    super.key,
    required this.label,
    this.initialUrl,
    required this.onChanged,
  });

  @override
  ConsumerState<ImagePickerField> createState() => _ImagePickerFieldState();
}

class _ImagePickerFieldState extends ConsumerState<ImagePickerField> {
  late final TextEditingController _urlController;
  String? _url;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url = widget.initialUrl;
    _urlController = TextEditingController(text: widget.initialUrl ?? '');
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;

    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final url = await ref.read(apiServiceProvider).uploadImage(File(path));
      setState(() {
        _url = url;
        _urlController.text = url;
        _uploading = false;
      });
      widget.onChanged(url);
    } catch (e) {
      setState(() {
        _uploading = false;
        _error = e.toString();
      });
    }
  }

  void _clear() {
    setState(() {
      _url = null;
      _urlController.clear();
    });
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            widget.label,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Row(
          children: [
            _Preview(url: _url),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _uploading ? null : _pickAndUpload,
                        icon: _uploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.photo_library, size: 18),
                        label: Text(_uploading ? 'Uploading...' : 'Choose image'),
                      ),
                      if (_url != null && _url!.isNotEmpty)
                        TextButton.icon(
                          onPressed: _uploading ? null : _clear,
                          icon: const Icon(Icons.clear, size: 18),
                          label: const Text('Remove'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        TextField(
          controller: _urlController,
          decoration: const InputDecoration(
            labelText: 'Or paste an image URL',
            isDense: true,
          ),
          onChanged: (v) {
            setState(() => _url = v.isEmpty ? null : v);
            widget.onChanged(v.isEmpty ? null : v);
          },
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  final String? url;

  const _Preview({required this.url});

  @override
  Widget build(BuildContext context) {
    const size = 56.0;
    if (url == null || url!.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.image_outlined, color: Colors.grey),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: Colors.grey.shade200,
          child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
        ),
      ),
    );
  }
}
