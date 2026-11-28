import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_locale.dart';
import '../services/api_service.dart';
import 'user_error.dart';

/// A reusable form field that lets the user pick an image from their device and
/// uploads it to the backend. The resulting public URL (or null) is surfaced
/// via [onChanged]. Upload uses the file bytes so it works on every platform,
/// including web where a filesystem path is not available.
class ImagePickerField extends ConsumerStatefulWidget {
  final String label;
  final String? initialUrl;
  final ValueChanged<String?> onChanged;
  final ValueChanged<bool>? onUploadingChanged;
  final bool showLabel;
  final bool centerPreview;
  final bool outlineChangeButton;
  final double previewSize;

  const ImagePickerField({
    super.key,
    required this.label,
    this.initialUrl,
    required this.onChanged,
    this.onUploadingChanged,
    this.showLabel = true,
    this.centerPreview = false,
    this.outlineChangeButton = true,
    this.previewSize = 56,
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

  @override
  void didUpdateWidget(covariant ImagePickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the parent supplies a different initial URL (e.g. after loading the
    // full record for editing) and the user hasn't picked a new image in this
    // field, reflect the updated value in the preview.
    if (oldWidget.initialUrl != widget.initialUrl &&
        _url == oldWidget.initialUrl) {
      _url = widget.initialUrl;
    }
  }

  Future<void> _pickAndUpload() async {
    setState(() => _error = null);

    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true, // load bytes so upload works on all platforms
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = userErrorMessage(error,
          fallback: 'Could not open your files. Please try again.'));
      return;
    }
    if (!mounted || result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) {
      setState(() => _error = 'Could not read the selected image.');
      return;
    }

    setState(() => _uploading = true);
    widget.onUploadingChanged?.call(true);
    try {
      final url = await ref
          .read(apiServiceProvider)
          .uploadImageBytes(bytes, picked.name);
      if (!mounted) return;
      setState(() {
        _url = url;
        _uploading = false;
      });
      widget.onUploadingChanged?.call(false);
      widget.onChanged(url);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = userErrorMessage(e);
      });
      widget.onUploadingChanged?.call(false);
    }
  }

  void _clear() {
    setState(() => _url = null);
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final actions = Wrap(
      alignment: widget.centerPreview ? WrapAlignment.center : WrapAlignment.start,
      spacing: 8,
      children: [
        if (widget.outlineChangeButton)
          OutlinedButton.icon(
            onPressed: _uploading ? null : _pickAndUpload,
            icon: _changeIcon,
            label: _changeLabel(context),
          )
        else
          TextButton.icon(
            onPressed: _uploading ? null : _pickAndUpload,
            icon: _changeIcon,
            label: _changeLabel(context),
          ),
        if (_url != null && _url!.isNotEmpty)
          TextButton.icon(
            onPressed: _uploading ? null : _clear,
            icon: const Icon(Icons.clear, size: 18),
            label: Text(context.tr('Remove')),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: widget.centerPreview
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        if (widget.showLabel)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              widget.label,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        if (widget.centerPreview) ...[
          _Preview(url: _url, size: widget.previewSize),
          const SizedBox(height: 8),
          actions,
        ] else
          Row(
            children: [
              _Preview(url: _url, size: widget.previewSize),
              const SizedBox(width: 12),
              Expanded(child: actions),
            ],
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              context.tr(_error!),
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget get _changeIcon => _uploading
      ? const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : const Icon(Icons.photo_library, size: 18);

  Widget _changeLabel(BuildContext context) => Text(_uploading
      ? context.tr('Uploading...')
      : (_url == null
          ? context.tr('Choose image')
          : context.tr('Change image')));
}

class _Preview extends StatelessWidget {
  final String? url;
  final double size;

  const _Preview({required this.url, this.size = 56});

  @override
  Widget build(BuildContext context) {
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
