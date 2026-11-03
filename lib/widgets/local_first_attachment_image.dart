import 'dart:io';

import 'package:flutter/material.dart';

import '../core/connection_mode.dart';
import '../services/local_attachment_cache.dart';

/// Photo metadata belongs to an already authorized record. Resolve its
/// locally saved original before attempting any signed server download.
class LocalFirstAttachmentImage extends StatefulWidget {
  const LocalFirstAttachmentImage({
    super.key,
    required this.attachment,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.onOpen,
  });

  final Map<String, dynamic> attachment;
  final double width, height;
  final BoxFit fit;
  final ValueChanged<File>? onOpen;

  @override
  State<LocalFirstAttachmentImage> createState() =>
      _LocalFirstAttachmentImageState();
}

class _LocalFirstAttachmentImageState
    extends State<LocalFirstAttachmentImage> {
  final LocalAttachmentCache _cache = LocalAttachmentCache();
  late Future<File?> _imageFile;

  String _identity(Map<String, dynamic> a) =>
      '${a['bucket']}::${a['key']}::${a['local_file_path']}';

  @override
  void initState() {
    super.initState();
    _imageFile = _resolve();
  }

  @override
  void didUpdateWidget(covariant LocalFirstAttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_identity(oldWidget.attachment) != _identity(widget.attachment)) {
      _imageFile = _resolve();
    }
  }

  Future<File?> _resolve() async {
    final attachment = widget.attachment;
    final path = attachment['local_file_path']?.toString() ?? '';
    if (path.isNotEmpty) {
      final file = File(path);
      if (await file.exists() && await file.length() > 0) return file;
    }
    final bucket = attachment['bucket']?.toString() ?? 'briskers-private';
    final key = attachment['key']?.toString() ?? '';
    if (bucket.isEmpty || key.isEmpty) return null;
    final cached = await _cache.existing(bucket, key);
    if (cached != null) return cached;
    if (BriskersConnectionModeController.instance.forceOffline) return null;
    // Only this image waits; text, notes and other record fields remain usable.
    return _cache.getOrDownload(bucket, key);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _imageFile,
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) {
          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: Center(
              child: snapshot.connectionState == ConnectionState.done
                  ? const Icon(Icons.broken_image_outlined)
                  : const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }
        final image = Image.file(
          file,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          cacheWidth: (widget.width * 2.5).round(),
          errorBuilder: (_, _, _) => SizedBox(
            width: widget.width, height: widget.height,
            child: const Icon(Icons.broken_image_outlined),
          ),
        );
        if (widget.onOpen == null) return image;
        return InkWell(
          onTap: () => widget.onOpen!(file),
          child: image,
        );
      },
    );
  }
}
