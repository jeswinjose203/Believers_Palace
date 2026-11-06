import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';

/// Lets the user pick several images, uploads each one, and reports the
/// ordered list of resulting URLs via [onChanged].
class MultiImagePickerField extends ConsumerStatefulWidget {
  final String label;
  final List<String> initialUrls;
  final ValueChanged<List<String>> onChanged;

  const MultiImagePickerField({
    super.key,
    required this.label,
    this.initialUrls = const [],
    required this.onChanged,
  });

  @override
  ConsumerState<MultiImagePickerField> createState() =>
      _MultiImagePickerFieldState();
}

class _MultiImagePickerFieldState extends ConsumerState<MultiImagePickerField> {
  late List<String> _urls;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _urls = List<String>.from(widget.initialUrls);
  }

  Future<void> _pickAndUpload() async {
    setState(() => _error = null);
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
    } catch (e) {
      setState(() => _error = 'Could not open picker: $e');
      return;
    }
    if (result == null || result.files.isEmpty) return;

    setState(() => _uploading = true);
    final api = ref.read(apiServiceProvider);
    final failed = <String>[];
    for (final f in result.files) {
      final bytes = f.bytes;
      if (bytes == null) {
        failed.add(f.name);
        continue;
      }
      try {
        final url = await api.uploadImageBytes(bytes, f.name);
        _urls.add(url);
      } catch (_) {
        failed.add(f.name);
      }
    }
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (failed.isNotEmpty) _error = 'Failed to upload: ${failed.join(', ')}';
    });
    widget.onChanged(List<String>.unmodifiable(_urls));
  }

  void _remove(int index) {
    setState(() => _urls.removeAt(index));
    widget.onChanged(List<String>.unmodifiable(_urls));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(widget.label,
              style: Theme.of(context).textTheme.labelLarge),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _urls.length; i++)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      _urls[i],
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 72,
                        height: 72,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image_outlined,
                            color: Colors.grey),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: InkWell(
                      onTap: _uploading ? null : () => _remove(i),
                      child: const CircleAvatar(
                        radius: 10,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 12, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _uploading ? null : _pickAndUpload,
          icon: _uploading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add_photo_alternate, size: 18),
          label: Text(_uploading ? 'Uploading...' : 'Add images'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
      ],
    );
  }
}
