import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../core/connection_mode.dart';
import '../../services/briskers_api.dart';
import '../../services/customer_detail_cache.dart';
import '../../services/local_attachment_cache.dart';
import '../../services/offline_customer_detail_write_service.dart';

class CustomerNotesSection extends StatefulWidget {
  const CustomerNotesSection({
    super.key,
    required this.businessId,
    required this.customerId,
  });

  final String businessId;
  final String customerId;

  @override
  State<CustomerNotesSection> createState() => _CustomerNotesSectionState();
}

class _CustomerNotesSectionState extends State<CustomerNotesSection> {
  static const _api = BriskersApi();
  static const _cache = CustomerDetailCache();
  final LocalAttachmentCache _attachmentCache = LocalAttachmentCache();
  final OfflineCustomerDetailWriteService _offlineWrites =
      OfflineCustomerDetailWriteService();
  final _picker = ImagePicker();
  final _note = TextEditingController();

  List<Map<String, dynamic>> _notes = const [];
  final List<XFile> _photos = [];
  bool _loading = true;
  bool _canDeleteRecords = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final offline = BriskersConnectionModeController.instance.forceOffline;
    if (offline) {
      final cached = await _cache.load(
        widget.businessId,
        widget.customerId,
        'notes',
      );
      final notes = cached is List
          ? cached
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _canDeleteRecords = false;
        _loading = false;
        _error = null;
      });
      return;
    }

    try {
      final results = await Future.wait<dynamic>([
        _api.customerNotes(
          widget.businessId,
          widget.customerId,
        ),
        _api.myPermissions(widget.businessId),
      ]);
      final notes = List<Map<String, dynamic>>.from(results[0] as List);
      final permissions = List<String>.from(results[1] as List);
      await _cache.save(
        widget.businessId,
        widget.customerId,
        'notes',
        notes,
      );
      await _prefetchNotePhotos(notes);
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _canDeleteRecords = permissions.contains('records.delete');
        _loading = false;
        _error = null;
      });
    } catch (error) {
      final cached = await _cache.load(
        widget.businessId,
        widget.customerId,
        'notes',
      );
      final notes = cached is List
          ? cached
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _canDeleteRecords = false;
        _loading = false;
        _error = notes.isEmpty ? error.toString() : null;
      });
    }
  }

  Future<void> _prefetchNotePhotos(
    List<Map<String, dynamic>> notes,
  ) async {
    final pending = <Future<dynamic>>[];
    for (final note in notes) {
      final attachments = List<dynamic>.from(
        note['attachments'] ?? const [],
      ).whereType<Map>().map((raw) {
        return Map<String, dynamic>.from(raw);
      });
      for (final attachment in attachments) {
        final bucket =
            attachment['bucket']?.toString() ?? 'briskers-private';
        final key = attachment['key']?.toString() ?? '';
        if (key.isEmpty) continue;
        pending.add(_attachmentCache.getOrDownload(bucket, key));
        if (pending.length >= 4) {
          await Future.wait(pending);
          pending.clear();
        }
      }
    }
    if (pending.isNotEmpty) await Future.wait(pending);
  }

  String _mimeType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<List<XFile>> _pickPictures(ImageSource source) async {
    if (source == ImageSource.gallery) {
      return _picker.pickMultiImage(
        imageQuality: 88,
        maxWidth: 1920,
        maxHeight: 1920,
      );
    }

    final photo = await _picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    return photo == null ? const [] : [photo];
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final photos = await _pickPictures(source);
      if (photos.isNotEmpty && mounted) {
        setState(() {
          _photos.addAll(photos);
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _uploadPhotos(String noteId, Iterable<XFile> photos) async {
    for (final photo in photos) {
      final bytes = await photo.readAsBytes();
      await _api.uploadCustomerNotePhoto(
        widget.businessId,
        noteId,
        filename: photo.name,
        mimeType: _mimeType(photo.name),
        bytes: bytes,
      );
    }
  }

  Future<void> _addNote() async {
    final body = _note.text.trim();
    if (body.isEmpty && _photos.isEmpty) {
      setState(() => _error = 'Type a note or add a picture first.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final stagedPhotos = <Map<String, dynamic>>[];
      for (final photo in _photos) {
        stagedPhotos.add({
          'filename': photo.name,
          'mime_type': _mimeType(photo.name),
          'bytes': await photo.readAsBytes(),
        });
      }

      await _offlineWrites.createCustomerNote(
        widget.businessId,
        widget.customerId,
        body: body,
        photos: stagedPhotos,
      );

      _note.clear();
      _photos.clear();

      final cached = await _cache.load(
        widget.businessId,
        widget.customerId,
        'notes',
      );
      final notes = cached is List
          ? cached
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];

      if (mounted) {
        setState(() {
          _notes = notes;
          _saving = false;
          _error = null;
        });
      }

      if (!BriskersConnectionModeController.instance.forceOffline) {
        unawaited(
          _offlineWrites.flush(widget.businessId).then((_) => _load()),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _editNote(Map<String, dynamic> note) async {
    final offline =
        BriskersConnectionModeController.instance.forceOffline;

    if (offline) {
      final controller = TextEditingController(
        text: note['body']?.toString() ?? '',
      );
      final updated = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Edit note'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Note'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (updated == null) return;

      try {
        await _offlineWrites.updateCustomerNote(
          widget.businessId,
          widget.customerId,
          note['id'].toString(),
          body: updated,
        );
        final cached = await _cache.load(
          widget.businessId,
          widget.customerId,
          'notes',
        );
        final notes = cached is List
            ? cached
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
            : <Map<String, dynamic>>[];
        if (mounted) setState(() => _notes = notes);
      } catch (error) {
        if (mounted) setState(() => _error = error.toString());
      }
      return;
    }

    final result = await showDialog<_NoteEditResult>(
      context: context,
      builder: (_) => _EditCustomerNoteDialog(
        initialText: note['body']?.toString() ?? '',
        canDeleteExisting: _canDeleteRecords,
        attachments: List<Map<String, dynamic>>.from(
          List<dynamic>.from(note['attachments'] ?? const [])
              .map((raw) => Map<String, dynamic>.from(raw as Map)),
        ),
      ),
    );

    if (result == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final noteId = note['id'].toString();

    try {
      await _api.updateCustomerNote(
        widget.businessId,
        noteId,
        body: result.body,
      );

      await _uploadPhotos(noteId, result.newPhotos);

      for (final attachment in result.removedAttachments) {
        await _api.deleteCustomerNoteAttachment(
          widget.businessId,
          noteId,
          attachment['attachment_id'].toString(),
        );
      }

      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  Future<void> _deleteNote(Map<String, dynamic> note) async {
    if (!_canDeleteRecords) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text(
          'This deletes the note and every picture attached to it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.deleteCustomerNote(
        widget.businessId,
        note['id'].toString(),
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _composer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        children: [
          TextField(
            controller: _note,
            minLines: 3,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Add a note',
              hintText: 'Type your note here...',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          if (_photos.isNotEmpty)
            Column(
              children: List.generate(_photos.length, (index) {
                final photo = _photos[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.image_outlined),
                  title: Text(
                    photo.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: const Text('Picture ready to attach'),
                  trailing: IconButton(
                    tooltip: 'Remove picture',
                    onPressed: _saving
                        ? null
                        : () => setState(() => _photos.removeAt(index)),
                    icon: const Icon(Icons.close),
                  ),
                );
              }),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _addNote,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_comment_outlined),
              label: Text(_saving ? 'Saving...' : 'Add note'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _notes.length;

    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        maintainState: false,
        leading: const Icon(
          Icons.note_alt_outlined,
          color: BriskersColors.notes,
        ),
        title: const Text(
          'Notes',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: _loading
            ? const Text('Loading notes...')
            : Text(count == 1 ? '1 note' : '$count notes'),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          _composer(),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_notes.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('No customer notes yet.'),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: _notes
                    .asMap()
                    .entries
                    .map(
                      (entry) => _NoteCard(
                        note: entry.value,
                        index: entry.key,
                        onEdit: () => _editNote(entry.value),
                        canDelete: !BriskersConnectionModeController.instance.forceOffline && _canDeleteRecords,
                        onDelete: () => _deleteNote(entry.value),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoteEditResult {
  const _NoteEditResult({
    required this.body,
    required this.newPhotos,
    required this.removedAttachments,
  });

  final String body;
  final List<XFile> newPhotos;
  final List<Map<String, dynamic>> removedAttachments;
}

class _EditCustomerNoteDialog extends StatefulWidget {
  const _EditCustomerNoteDialog({
    required this.initialText,
    required this.attachments,
    required this.canDeleteExisting,
  });

  final String initialText;
  final List<Map<String, dynamic>> attachments;
  final bool canDeleteExisting;

  @override
  State<_EditCustomerNoteDialog> createState() =>
      _EditCustomerNoteDialogState();
}

class _EditCustomerNoteDialogState
    extends State<_EditCustomerNoteDialog> {
  static const _api = BriskersApi();

  late final TextEditingController _controller;
  final _picker = ImagePicker();
  late final List<Map<String, dynamic>> _attachments;
  final List<Map<String, dynamic>> _removedAttachments = [];
  final List<XFile> _newPhotos = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _attachments = List<Map<String, dynamic>>.from(widget.attachments);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addPictures(ImageSource source) async {
    try {
      late final List<XFile> photos;
      if (source == ImageSource.gallery) {
        photos = await _picker.pickMultiImage(
          imageQuality: 88,
          maxWidth: 1920,
          maxHeight: 1920,
        );
      } else {
        final photo = await _picker.pickImage(
          source: source,
          imageQuality: 88,
          maxWidth: 1920,
          maxHeight: 1920,
        );
        photos = photo == null ? <XFile>[] : <XFile>[photo];
      }

      if (photos.isNotEmpty && mounted) {
        setState(() {
          _newPhotos.addAll(photos);
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _removeExisting(Map<String, dynamic> attachment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove picture?'),
        content: const Text(
          'The picture will be removed from this note when you tap Save.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _attachments.remove(attachment);
      _removedAttachments.add(attachment);
      _error = null;
    });
  }

  void _save() {
    final body = _controller.text.trim();
    if (body.isEmpty && _attachments.isEmpty && _newPhotos.isEmpty) {
      setState(
        () => _error = 'A note must contain text or at least one picture.',
      );
      return;
    }

    Navigator.of(context).pop(
      _NoteEditResult(
        body: body,
        newPhotos: List<XFile>.from(_newPhotos),
        removedAttachments:
            List<Map<String, dynamic>>.from(_removedAttachments),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('Edit note'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Pictures',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              if (_attachments.isEmpty && _newPhotos.isEmpty)
                const Text('No pictures attached.')
              else ...[
                if (_attachments.isNotEmpty)
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _attachments
                        .map(
                          (attachment) => _EditableAttachmentThumbnail(
                            api: _api,
                            attachment: attachment,
                            onRemove: widget.canDeleteExisting
                                ? () => _removeExisting(attachment)
                                : null,
                          ),
                        )
                        .toList(),
                  ),
                if (_newPhotos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...List.generate(_newPhotos.length, (index) {
                    final photo = _newPhotos[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.add_photo_alternate_outlined),
                      title: Text(
                        photo.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: const Text('New picture'),
                      trailing: IconButton(
                        tooltip: 'Remove picture',
                        onPressed: () => setState(
                          () => _newPhotos.removeAt(index),
                        ),
                        icon: const Icon(Icons.close),
                      ),
                    );
                  }),
                ],
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _addPictures(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Camera'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _addPictures(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Gallery'),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _EditableAttachmentThumbnail extends StatefulWidget {
  const _EditableAttachmentThumbnail({
    required this.api,
    required this.attachment,
    required this.onRemove,
  });

  final BriskersApi api;
  final Map<String, dynamic> attachment;
  final VoidCallback? onRemove;

  @override
  State<_EditableAttachmentThumbnail> createState() =>
      _EditableAttachmentThumbnailState();
}

class _EditableAttachmentThumbnailState
    extends State<_EditableAttachmentThumbnail> {
  late final Future<String> _url;

  @override
  void initState() {
    super.initState();
    _url = widget.api.signedAttachmentUrl(
      widget.attachment['bucket'].toString(),
      widget.attachment['key'].toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: FutureBuilder<String>(
                  future: _url,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox(
                        width: 96,
                        height: 96,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return Image.network(
                      snapshot.data!,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      cacheWidth: 240,
                      errorBuilder: (_, _, _) => const SizedBox(
                        width: 96,
                        height: 96,
                        child: Center(
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (widget.onRemove != null)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Material(
                    color: Theme.of(context).colorScheme.error,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: widget.onRemove,
                      child: const Padding(
                        padding: EdgeInsets.all(5),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            widget.attachment['filename']?.toString() ?? 'Picture',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatefulWidget {
  const _NoteCard({
    required this.note,
    required this.index,
    required this.onEdit,
    required this.canDelete,
    required this.onDelete,
  });

  final Map<String, dynamic> note;
  final int index;
  final VoidCallback onEdit;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final attachments = List<dynamic>.from(note['attachments'] ?? const []);
    final createdAt = DateTime.tryParse(note['created_at']?.toString() ?? '');
    final seen = note['seen'] == true;
    final body = (note['body']?.toString() ?? '').trim();

    final statusColor = seen
        ? const Color(0xFF2E7D32)
        : const Color(0xFFC62828);
    final statusBackground = seen
        ? const Color(0xFFE8F5E9)
        : const Color(0xFFFFEBEE);
    final rowColor = widget.index.isEven
        ? const Color(0xFFEEF6FF)
        : const Color(0xFFEFFBF4);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: rowColor,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 10, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          body.isEmpty ? 'Picture note' : body,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            height: 1.15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(
                          Icons.keyboard_arrow_down,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Align(
                    alignment: Alignment.centerRight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: statusBackground,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              seen
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 12,
                              color: statusColor,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              seen ? 'Seen' : 'Not seen',
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 9.5,
                                height: 1.15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            child: _expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    createdAt == null
                                        ? 'Customer note'
                                        : DateFormat('MMM d, yyyy h:mm a')
                                            .format(createdAt.toLocal()),
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  tooltip: 'Note options',
                                  onSelected: (value) {
                                    if (value == 'edit') widget.onEdit();
                                    if (value == 'delete') widget.onDelete();
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(Icons.edit_outlined),
                                        title: Text('Edit note'),
                                      ),
                                    ),
                                    if (widget.canDelete)
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(Icons.delete_outline),
                                          title: Text('Delete note'),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            if (body.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(body),
                            ],
                            if (attachments.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: attachments.map((raw) {
                                  final attachment =
                                      Map<String, dynamic>.from(raw as Map);
                                  return _NoteImage(attachment: attachment);
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _NoteImage extends StatefulWidget {
  const _NoteImage({required this.attachment});

  final Map<String, dynamic> attachment;

  @override
  State<_NoteImage> createState() => _NoteImageState();
}

class _NoteImageState extends State<_NoteImage> {
  static const _api = BriskersApi();
  late final Future<String> _url;

  @override
  void initState() {
    super.initState();
    _url = _api.signedAttachmentUrl(
      widget.attachment['bucket'].toString(),
      widget.attachment['key'].toString(),
    );
  }

  Future<void> _openViewer(String url) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _CustomerNoteImageViewer(
          imageUrl: url,
          title: widget.attachment['filename']?.toString() ?? 'Picture',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            width: 92,
            height: 92,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(
            width: 92,
            height: 92,
            child: Center(child: Icon(Icons.broken_image_outlined)),
          );
        }

        final url = snapshot.data!;
        return Tooltip(
          message: 'Tap to view picture',
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _openViewer(url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    width: 92,
                    height: 92,
                    cacheWidth: 240,
                    errorBuilder: (_, _, _) => const SizedBox(
                      width: 92,
                      height: 92,
                      child: Center(
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                  const Positioned(
                    right: 5,
                    bottom: 5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0x99000000),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.zoom_in,
                          size: 17,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CustomerNoteImageViewer extends StatelessWidget {
  const _CustomerNoteImageViewer({
    required this.imageUrl,
    required this.title,
  });

  final String imageUrl;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 5,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Colors.white,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
