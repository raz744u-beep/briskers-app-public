import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';
import 'expense_entry_screen.dart';

class ExpenseDetailScreen extends StatefulWidget {
  const ExpenseDetailScreen({
    super.key,
    required this.businessId,
    required this.transactionId,
  });

  final String businessId;
  final String transactionId;

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  static const _api = BriskersApi();
  final _picker = ImagePicker();

  Map<String, dynamic>? _detail;
  bool _loading = true;
  bool _uploading = false;
  String? _deletingAttachmentId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await _api.transactionDetail(
        widget.businessId,
        widget.transactionId,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  String _money(Object? raw) {
    final value = num.tryParse(raw?.toString() ?? '') ?? 0;
    return NumberFormat.currency(symbol: '\$').format(value);
  }

  String _mimeType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _addReceipt() async {
    if (_uploading) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    List<XFile> files = const [];
    if (source == ImageSource.gallery) {
      files = await _picker.pickMultiImage(imageQuality: 92);
    } else {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );
      if (file != null) files = [file];
    }
    if (files.isEmpty) return;

    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      for (final file in files) {
        await _api.uploadExpensePhoto(
          widget.businessId,
          widget.transactionId,
          filename: file.name,
          mimeType: _mimeType(file.name),
          bytes: await file.readAsBytes(),
        );
      }
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _replaceReceipt(
    Map<String, dynamic> attachment,
  ) async {
    if (_uploading || _deletingAttachmentId != null) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose replacement from gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take replacement photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    XFile? file;
    if (source == ImageSource.gallery) {
      file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );
    } else {
      file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );
    }
    if (file == null || !mounted) return;

    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      await _api.uploadExpensePhoto(
        widget.businessId,
        widget.transactionId,
        filename: file.name,
        mimeType: _mimeType(file.name),
        bytes: await file.readAsBytes(),
      );

      final attachmentId = attachment['attachment_id']?.toString() ?? '';
      if (attachmentId.isNotEmpty) {
        await _api.deleteExpensePhoto(
          widget.businessId,
          widget.transactionId,
          attachmentId,
          bucket: attachment['bucket']?.toString() ?? 'briskers-private',
          key: attachment['key']?.toString() ?? '',
        );
      }

      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _openAttachment(Map<String, dynamic> attachment) async {
    try {
      final url = await _api.signedAttachmentUrl(
        attachment['bucket']?.toString() ?? 'briskers-private',
        attachment['key']?.toString() ?? '',
      );
      if (!mounted) return;
      final editable = _detail?['editable'] == true;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            children: [
              InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 300,
                    child: Center(child: Text('Could not load receipt.')),
                  ),
                ),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close),
                ),
              ),
              if (editable)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      await _deleteAttachment(attachment);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete photo'),
                  ),
                ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _deleteAttachment(
    Map<String, dynamic> attachment,
  ) async {
    final attachmentId = attachment['attachment_id']?.toString() ?? '';
    if (attachmentId.isEmpty || _deletingAttachmentId != null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete receipt photo?'),
        content: const Text(
          'The photo will be removed from this transaction.',
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
    if (confirmed != true || !mounted) return;

    setState(() {
      _deletingAttachmentId = attachmentId;
      _error = null;
    });

    try {
      await _api.deleteExpensePhoto(
        widget.businessId,
        widget.transactionId,
        attachmentId,
        bucket: attachment['bucket']?.toString() ?? 'briskers-private',
        key: attachment['key']?.toString() ?? '',
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _deletingAttachmentId = null);
    }
  }

  Future<void> _edit() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseEntryScreen(
          businessId: widget.businessId,
          editTransactionId: widget.transactionId,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _copy() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseEntryScreen(
          businessId: widget.businessId,
          copyTransactionId: widget.transactionId,
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final detail = _detail;
    if (detail == null || _busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text(
          'The transaction will disappear from normal views but remain in the audit history.',
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
      _busy = true;
      _error = null;
    });
    try {
      await _api.voidManualTransaction(
        widget.businessId,
        widget.transactionId,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _handleMenu(String value) async {
    if (value == 'edit') await _edit();
    if (value == 'copy') await _copy();
    if (value == 'delete') await _delete();
  }

  Widget _receiptThumbnail(Map<String, dynamic> attachment) {
    const size = 52.0;
    final bucket = attachment['bucket']?.toString() ?? '';
    final key = attachment['key']?.toString() ?? '';

    if (bucket.isEmpty || key.isEmpty) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BriskersColors.expenses.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.broken_image_outlined),
      );
    }

    return FutureBuilder<String>(
      future: _api.signedAttachmentUrl(bucket, key),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: BriskersColors.expenses.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: snapshot.hasError
                ? const Icon(Icons.broken_image_outlined)
                : const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            snapshot.data!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              color: BriskersColors.expenses.withValues(alpha: 0.08),
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaction')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final detail = _detail;
    if (detail == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaction')),
        body: Center(child: Text(_error ?? 'Transaction not found.')),
      );
    }

    final income = detail['direction']?.toString() == 'income';
    final editable = detail['editable'] == true;
    final deletable = detail['deletable'] == true;
    final attachments = List<dynamic>.from(detail['attachments'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    final counterparty = detail['counterparty']?.toString() ??
        (income ? 'Income' : 'Expense');
    final category = detail['category']?.toString() ?? '';
    final account = detail['account']?.toString() ?? '';
    final date = detail['date']?.toString() ?? '';
    final remarks = detail['remarks']?.toString() ?? '';
    final jobNumber = detail['job_number']?.toString().trim() ?? '';
    final jobTitle = detail['job_title']?.toString().trim() ?? '';
    final customerName =
        detail['job_customer_name']?.toString().trim() ?? '';
    final documentNumber = detail['document_number']?.toString().trim() ?? '';
    final contextLine = <String>[
      if (customerName.isNotEmpty) customerName,
      if (jobNumber.isNotEmpty || jobTitle.isNotEmpty)
        <String>[
          if (jobNumber.isNotEmpty) jobNumber,
          if (jobTitle.isNotEmpty) jobTitle,
        ].join(' — '),
      if (documentNumber.isNotEmpty) 'Invoice #$documentNumber',
    ].join(' • ');
    final recurring = detail['recurring_rule'];
    final color =
        income ? const Color(0xFF169B62) : BriskersColors.expenses;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: color.withValues(alpha: 0.10),
        title: Text(income ? 'Income' : 'Expense'),
        actions: [
          if (editable)
            PopupMenuButton<String>(
              onSelected: _handleMenu,
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit transaction'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'copy',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.copy_outlined),
                    title: Text('Copy transaction'),
                  ),
                ),
                if (deletable)
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete transaction'),
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Icon(
                      income ? Icons.south_west : Icons.north_east,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      counterparty,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${income ? '+' : '-'}${_money(detail['amount'])}',
                    style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (contextLine.isNotEmpty) ...[
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.link_outlined),
                title: const Text(
                  'Linked to',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(contextLine),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _DetailRow(label: 'Category', value: category),
          _DetailRow(label: 'Account', value: account),
          _DetailRow(label: 'Date', value: date),
          if (jobNumber.isNotEmpty)
            _DetailRow(label: 'Job', value: jobNumber),
          if (documentNumber.isNotEmpty)
            _DetailRow(label: 'Invoice', value: documentNumber),
          if (recurring is Map)
            _DetailRow(
              label: 'Repeating',
              value: <String>[
                recurring['frequency']?.toString() ?? '',
                if ((recurring['next_date']?.toString() ?? '').isNotEmpty)
                  'next ${recurring['next_date']}',
              ].where((x) => x.isNotEmpty).join(' • '),
            ),
          if (remarks.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Description / notes',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(remarks),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Receipts',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (editable)
                TextButton.icon(
                  onPressed: _uploading ? null : _addReceipt,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(_uploading ? 'Uploading...' : 'Add'),
                ),
            ],
          ),
          if (attachments.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('No receipt photos attached.'),
              ),
            )
          else
            ...attachments.map(
              (attachment) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  child: Row(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _openAttachment(attachment),
                        child: _receiptThumbnail(attachment),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'View receipt',
                        onPressed: () => _openAttachment(attachment),
                        icon: const Icon(Icons.zoom_in),
                      ),
                      if (editable)
                        IconButton(
                          tooltip: 'Replace receipt photo',
                          onPressed: _uploading
                              ? null
                              : () => _replaceReceipt(attachment),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      if (editable)
                        IconButton(
                          tooltip: 'Delete receipt photo',
                          onPressed:
                              _deletingAttachmentId ==
                                      attachment['attachment_id']?.toString()
                                  ? null
                                  : () => _deleteAttachment(attachment),
                          icon: _deletingAttachmentId ==
                                  attachment['attachment_id']?.toString()
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.delete_outline),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
