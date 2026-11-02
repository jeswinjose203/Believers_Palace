import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';

/// A reusable form field that lets the user pick an image from their device and
/// uploads it to the backend. The resulting public URL (or null) is surfaced
/// via [onChanged]. Upload uses the file bytes so it works on every platform,
/// including web where a filesystem path is not available.
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
  String? _url;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url = widget.initialUrl;
  }

  Future<void> _pickAndUpload() async {
    setState(() => _error = null);

    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true, // load bytes so upload works on all platforms
      );
    } catch (e) {
      setState(() => _error = 'Could not open picker: $e');
      return;
    }
    if (result == null || result.files.isEmpty) return; // cancelled

    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) {
      setState(() => _error = 'Could not read the selected image.');
      return;
    }

    setState(() => _uploading = true);
    try {
      final url = await ref
          .read(apiServiceProvider)
          .uploadImageBytes(bytes, picked.name);
      if (!mounted) return;
      setState(() {
        _url = url;
        _uploading = false;
      });
      widget.onChanged(url);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = e.toString();
      });
    }
  }

  void _clear() {
    setState(() => _url = null);
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
              child: Wrap(
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
                    label: Text(_uploading
                        ? 'Uploading...'
                        : (_url == null ? 'Choose image' : 'Change image')),
                  ),
                  if (_url != null && _url!.isNotEmpty)
                    TextButton.icon(
                      onPressed: _uploading ? null : _clear,
                      icon: const Icon(Icons.clear, size: 18),
                      label: const Text('Remove'),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
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
