import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_i18n.dart';

/// Unsaved receipt selections only. Removing one never deletes a device file,
/// a saved attachment, or anything already waiting in the offline sync queue.
class ExpenseReceiptAttachments extends StatefulWidget {
  const ExpenseReceiptAttachments({
    super.key,
    required this.receipts,
    required this.onChanged,
    this.enabled = true,
  });

  final List<XFile> receipts;
  final ValueChanged<List<XFile>> onChanged;
  final bool enabled;

  @override
  State<ExpenseReceiptAttachments> createState() =>
      _ExpenseReceiptAttachmentsState();
}

class _ExpenseReceiptAttachmentsState
    extends State<ExpenseReceiptAttachments> {
  bool _confirmingRemoval = false;

  Future<void> _remove(int selectedIndex) async {
    if (!widget.enabled || _confirmingRemoval) return;
    final selected = widget.receipts[selectedIndex];
    final label = _photoLabel(selectedIndex);
    setState(() => _confirmingRemoval = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(tr('removeSelectedReceiptTitle')),
        content: Text(
          tr('removeSelectedReceiptQuestion').replaceAll('{photo}', label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('cancel')),
          ),
          FilledButton.icon(
            key: const ValueKey('confirm-receipt-removal'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
              minimumSize: const Size(96, 48),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline),
            label: Text(tr('remove')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _confirmingRemoval = false);
    if (confirmed != true || !widget.enabled) return;

    // Resolve the selected object again in case the parent changed the list
    // while the confirmation was open. Never remove by filename or file path:
    // the same device photo can be selected more than once.
    final index = selectedIndex < widget.receipts.length &&
            identical(widget.receipts[selectedIndex], selected)
        ? selectedIndex
        : widget.receipts.indexWhere((item) => identical(item, selected));
    if (index < 0) return;
    final remaining = List<XFile>.from(widget.receipts)..removeAt(index);
    widget.onChanged(remaining);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(widget.receipts.length, (index) {
        return _ReceiptPhotoCard(
          key: ValueKey('expense-receipt-${index + 1}'),
          file: widget.receipts[index],
          label: _photoLabel(index),
          enabled: widget.enabled && !_confirmingRemoval,
          onRemove: widget.enabled && !_confirmingRemoval
              ? () => _remove(index)
              : null,
        );
      }),
    );
  }
}

String _photoLabel(int index) =>
    tr('receiptPhotoNumber').replaceAll('{number}', '${index + 1}');

class _ReceiptPhotoCard extends StatefulWidget {
  const _ReceiptPhotoCard({
    super.key,
    required this.file,
    required this.label,
    required this.enabled,
    required this.onRemove,
  });

  final XFile file;
  final String label;
  final bool enabled;
  final VoidCallback? onRemove;

  @override
  State<_ReceiptPhotoCard> createState() => _ReceiptPhotoCardState();
}

class _ReceiptPreview {
  const _ReceiptPreview({this.bytes, this.modified});

  final Uint8List? bytes;
  final DateTime? modified;
}

class _ReceiptPhotoCardState extends State<_ReceiptPhotoCard> {
  late Future<_ReceiptPreview> _preview;
  bool _previewOpen = false;

  @override
  void initState() {
    super.initState();
    _preview = _readPreview();
  }

  @override
  void didUpdateWidget(covariant _ReceiptPhotoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.file, widget.file)) _preview = _readPreview();
  }

  Future<_ReceiptPreview> _readPreview() async {
    // Capture the selected file before awaiting, so a reordered card cannot
    // combine one photo's image with another photo's metadata.
    final file = widget.file;
    Uint8List? bytes;
    DateTime? modified;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      // A missing local image must not hide its selection or Remove action.
    }
    try {
      modified = await file.lastModified();
    } catch (_) {
      // File metadata is optional; never invent a capture or transaction date.
    }
    return _ReceiptPreview(bytes: bytes, modified: modified);
  }

  String _fileSize(int bytes) {
    final mb = bytes >= 1024 * 1024;
    final value = bytes / (mb ? 1024 * 1024 : 1024);
    final formatted = NumberFormat(
      '0.#',
      BriskersLanguageController.instance.code,
    ).format(value);
    return '$formatted ${mb ? 'MB' : 'KB'}';
  }

  Future<void> _open(Uint8List bytes) async {
    if (!widget.enabled || _previewOpen) return;
    _previewOpen = true;
    final label = widget.label;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: tr('closeReceiptPhoto'),
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(tr('receiptPhotoPreviewUnavailable')),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } finally {
      _previewOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FutureBuilder<_ReceiptPreview>(
          future: _preview,
          builder: (context, snapshot) {
            // FutureBuilder retains old data while a reused card loads its
            // next file. Never display that previous photo under a new label.
            final preview = snapshot.connectionState == ConnectionState.done
                ? snapshot.data
                : null;
            final bytes = preview?.bytes;
            final modified = preview?.modified;
            final previewReady = bytes != null && bytes.isNotEmpty;
            final metadata = <String>[
              if (modified != null)
                tr('receiptPhotoFileDate').replaceAll(
                  '{date}',
                  DateFormat.yMd(
                    BriskersLanguageController.instance.code,
                  ).format(modified),
                ),
              if (previewReady) _fileSize(bytes.lengthInBytes),
            ].join(' • ');
            final information = Row(
              children: [
                Semantics(
                  button: previewReady && widget.enabled,
                  label: tr('viewReceiptPhoto').replaceAll(
                    '{photo}',
                    widget.label,
                  ),
                  child: Tooltip(
                    message: tr('viewReceiptPhoto').replaceAll(
                      '{photo}',
                      widget.label,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: previewReady && widget.enabled
                          ? () => _open(bytes)
                          : null,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox.square(
                          dimension: 64,
                          child: previewReady
                              ? Image.memory(
                                  bytes,
                                  fit: BoxFit.cover,
                                  cacheWidth: 160,
                                  excludeFromSemantics: true,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.broken_image_outlined,
                                  ),
                                )
                              : const Icon(Icons.photo_outlined),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                      if (previewReady) ...[
                        const SizedBox(height: 4),
                        Text(
                          metadata,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ] else if (snapshot.connectionState ==
                          ConnectionState.done) ...[
                        const SizedBox(height: 4),
                        Text(
                          tr('receiptPhotoPreviewUnavailable'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
            final remove = OutlinedButton.icon(
              onPressed: widget.onRemove,
              icon: const Icon(Icons.delete_outline),
              label: Text(tr('remove')),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.error,
                side: BorderSide(color: colors.error),
                minimumSize: const Size(104, 48),
              ),
            );
            return LayoutBuilder(
              builder: (context, constraints) {
                // Keep the labeled action fully readable on narrow screens
                // and at large accessibility text sizes, including Spanish.
                final stacked = constraints.maxWidth < 300 ||
                    MediaQuery.textScalerOf(context).scale(14) > 18;
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      information,
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: remove),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: information),
                    const SizedBox(width: 12),
                    remove,
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
