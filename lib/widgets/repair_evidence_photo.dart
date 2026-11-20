import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/local_attachment_cache.dart';
import '../services/local_repair_groups.dart';

/// Reads an immutable authorization copy first, then an existing local photo.
/// Customer review never downloads from a business storage service.
class RepairEvidencePhoto extends StatefulWidget {
  const RepairEvidencePhoto({super.key, required this.business,
    required this.photo, required this.store});
  final String business;
  final Map<String, dynamic> photo;
  final LocalRepairGroups store;
  @override State<RepairEvidencePhoto> createState() => _RepairEvidencePhotoState();
}
class _RepairEvidencePhotoState extends State<RepairEvidencePhoto> {
  late Future<Uint8List?> bytes = _read();
  Future<Uint8List?> _read() async {
    final reference = widget.photo['media_ref']?.toString() ?? '';
    if (reference.isNotEmpty) { return widget.store.media(widget.business, reference); }
    final path = widget.photo['local_file_path']?.toString() ?? '';
    if (path.isNotEmpty && await File(path).exists()) { return File(path).readAsBytes(); }
    final file = await LocalAttachmentCache().existing(
      widget.photo['bucket']?.toString() ?? '', widget.photo['key']?.toString() ?? '');
    return file?.readAsBytes();
  }
  @override void didUpdateWidget(covariant RepairEvidencePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.toString() != widget.photo.toString()) bytes = _read();
  }
  @override Widget build(BuildContext context) => FutureBuilder(future: bytes,
    builder: (context, snapshot) {
      final data = snapshot.data;
      if (data == null) { return const SizedBox(width: 86, height: 70,
        child: Center(child: Icon(Icons.image_not_supported_outlined))); }
      return InkWell(onTap: () => showDialog<void>(context: context, builder: (dialog) => Dialog(
        child: InteractiveViewer(child: Image.memory(data, fit: BoxFit.contain)))),
        child: Image.memory(data, width: 86, height: 70, fit: BoxFit.cover,
          errorBuilder: (context, error, trace) => const SizedBox(width: 86, height: 70,
            child: Icon(Icons.broken_image_outlined))));
    });
}
