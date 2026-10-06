import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../core/connection_mode.dart';
import '../../services/briskers_api.dart';
import '../../services/local_attachment_cache.dart';
import '../../services/local_financial_cache.dart';
import 'expense_entry_screen.dart';

class ExpenseDetailScreen extends StatefulWidget {
  const ExpenseDetailScreen({
    super.key,
    required this.businessId,
    required this.transactionId,
    this.allowRecurring = true,
    this.canDeleteTransaction = false,
    this.cachedDetail,
  });

  final String businessId;
  final String transactionId;
  final bool allowRecurring;
  final bool canDeleteTransaction;
  final Map<String, dynamic>? cachedDetail;

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  static const _api = BriskersApi();
  final _picker = ImagePicker();
  final LocalAttachmentCache _attachmentCache = LocalAttachmentCache();
  final LocalFinancialCache _localFinancial = LocalFinancialCache();

  Map<String, dynamic>? _detail;
  bool _loading = true;
  bool _canDeleteRecords = false;
  bool _uploading = false;
  String? _deletingAttachmentId;
  bool _busy = false;
  String? _error;
  final Map<String, Future<String>> _attachmentUrls = {};

  @override
  void initState() {
    super.initState();
    final cached = widget.cachedDetail;
    if (cached != null) {
      _loadCached(cached);
    } else {
      _load();
    }
  }

  Future<void> _loadCached(Map<String, dynamic> summary) async {
    final saved = await _localFinancial.loadTransactionDetail(
      widget.businessId,
      widget.transactionId,
    );
    final detail = Map<String, dynamic>.from(saved ?? summary)
      ..['editable'] = true
      ..['deletable'] = false
      ..['date'] = (saved ?? summary)['date'] ??
          (saved ?? summary)['transaction_date']
      ..['attachments'] =
          (saved ?? summary)['attachments'] ?? const <dynamic>[];

    if (!mounted) return;
    setState(() {
      _detail = detail;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        _api.transactionDetail(
          widget.businessId,
          widget.transactionId,
        ),
        _api.myPermissions(widget.businessId),
      ]);
      final detail = Map<String, dynamic>.from(results[0] as Map);
      final permissions = List<String>.from(results[1] as List);
      await _localFinancial.saveTransactionDetail(
        widget.businessId,
        widget.transactionId,
        detail,
      );
      await _prefetchLocalAttachments(
        List<dynamic>.from(detail['attachments'] ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(),
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _canDeleteRecords = permissions.contains('records.delete');
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

  String _attachmentCacheKey(Map<String, dynamic> attachment) {
    final bucket = attachment['bucket']?.toString() ?? 'briskers-private';
    final key = attachment['key']?.toString() ?? '';
    return '$bucket|$key';
  }

  Future<String> _attachmentUrl(Map<String, dynamic> attachment) {
    final cacheKey = _attachmentCacheKey(attachment);
    return _attachmentUrls.putIfAbsent(
      cacheKey,
      () => _api.signedAttachmentUrl(
        attachment['bucket']?.toString() ?? 'briskers-private',
        attachment['key']?.toString() ?? '',
      ),
    );
  }

  Future<void> _prefetchLocalAttachments(
    List<Map<String, dynamic>> attachments,
  ) async {
    final pending = <Future<File?>>[];
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
    if (pending.isNotEmpty) await Future.wait(pending);
  }

  void _preloadAttachments(List<Map<String, dynamic>> attachments) {
    _prefetchLocalAttachments(attachments);
  }

  Future<File?> _localAttachment(
    Map<String, dynamic> attachment,
  ) async {
    final localPath = attachment['local_file_path']?.toString() ?? '';
    if (localPath.isNotEmpty) {
      final file = File(localPath);
      if (await file.exists()) return file;
    }
    return _attachmentCache.existing(
      attachment['bucket']?.toString() ?? 'briskers-private',
      attachment['key']?.toString() ?? '',
    );
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
    final editable = _detail?['editable'] == true;
    if (!editable || _uploading || _deletingAttachmentId != null) {
      return;
    }

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
        await _api.archiveExpensePhotoForReplace(
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
      final local = await _localAttachment(attachment);
      String? url;
      if (local == null) {
        url = await _attachmentUrl(attachment);
      }
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
                child: local != null
                    ? Image.file(local, fit: BoxFit.contain)
                    : Image.network(
                        url!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox(
                          height: 300,
                          child: Center(
                            child: Text('Could not load receipt.'),
                          ),
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
              if (editable && _canDeleteRecords)
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
    final detail = _detail;
    if (detail == null || _busy) return;

    if (BriskersConnectionModeController.instance.forceOffline) {
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ExpenseEntryScreen(
            businessId: widget.businessId,
            editTransactionId: widget.transactionId,
            allowRecurring: widget.allowRecurring,
          ),
        ),
      );
      if (changed == true && mounted) {
        final saved = await _localFinancial.loadTransactionDetail(
          widget.businessId,
          widget.transactionId,
        );
        if (saved != null) {
          setState(() {
            _detail = Map<String, dynamic>.from(saved)
              ..['editable'] = true
              ..['deletable'] = false;
            _error = null;
          });
        }
      }
      return;
    }

    final options = await _api.transactionOptions(widget.businessId);
    if (!mounted) return;

    final accounts = List<dynamic>.from(options['accounts'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    final categories = List<dynamic>.from(options['categories'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    final counterparties =
        List<dynamic>.from(options['counterparties'] ?? const [])
            .map((raw) => Map<String, dynamic>.from(raw as Map))
            .toList();

    final amount = TextEditingController(
      text: detail['amount']?.toString() ?? '',
    );
    final remarks = TextEditingController(
      text: detail['remarks']?.toString() ?? '',
    );

    var direction =
        detail['direction']?.toString() == 'income' ? 'income' : 'expense';
    String? accountId = detail['account_id']?.toString();
    String? categoryId = detail['category_id']?.toString();
    String? counterpartyId = detail['counterparty_id']?.toString();
    var date = DateTime.tryParse(detail['date']?.toString() ?? '') ??
        DateTime.now();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final keyboard = MediaQuery.viewInsetsOf(sheetContext).bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, keyboard + 16),
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.82,
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Edit expense',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext, false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        children: [
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'expense',
                                label: Text('Expense'),
                                icon: Icon(Icons.north_east),
                              ),
                              ButtonSegment(
                                value: 'income',
                                label: Text('Income'),
                                icon: Icon(Icons.south_west),
                              ),
                            ],
                            selected: {direction},
                            onSelectionChanged: (value) => setSheetState(
                              () => direction = value.first,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: amount,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            scrollPadding:
                                const EdgeInsets.only(bottom: 160),
                            decoration: const InputDecoration(
                              labelText: 'Amount',
                              prefixText: r'$',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String?>(
                            initialValue: counterpartyId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText:
                                  direction == 'income' ? 'Payer' : 'Payee',
                              border: const OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('None'),
                              ),
                              ...counterparties.map(
                                (item) => DropdownMenuItem<String?>(
                                  value: item['id']?.toString(),
                                  child: Text(
                                    item['name']?.toString() ?? '',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (value) =>
                                setSheetState(() => counterpartyId = value),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: categoryId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                              border: OutlineInputBorder(),
                            ),
                            items: categories
                                .map(
                                  (item) => DropdownMenuItem<String>(
                                    value: item['id']?.toString(),
                                    child: Text(
                                      item['name']?.toString() ?? '',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setSheetState(() => categoryId = value),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: accountId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: direction == 'income'
                                  ? 'Deposited to'
                                  : 'Paid from',
                              border: const OutlineInputBorder(),
                            ),
                            items: accounts
                                .map(
                                  (item) => DropdownMenuItem<String>(
                                    value: item['id']?.toString(),
                                    child: Text(
                                      item['name']?.toString() ?? '',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setSheetState(() => accountId = value),
                          ),
                          const SizedBox(height: 8),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading:
                                const Icon(Icons.calendar_today_outlined),
                            title: const Text('Transaction date'),
                            subtitle: Text(
                              '${date.month}/${date.day}/${date.year}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              final selected = await showDatePicker(
                                context: sheetContext,
                                initialDate: date,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (selected != null) {
                                setSheetState(() => date = selected);
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: remarks,
                            minLines: 2,
                            maxLines: 5,
                            scrollPadding:
                                const EdgeInsets.only(bottom: 160),
                            decoration: const InputDecoration(
                              labelText: 'Description / notes',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final parsed =
                            num.tryParse(amount.text.trim().replaceAll(',', ''));
                        if (parsed == null ||
                            parsed <= 0 ||
                            accountId == null ||
                            categoryId == null) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Amount, category and account are required.',
                              ),
                            ),
                          );
                          return;
                        }

                        Map<String, dynamic>? selectedCounterparty;
                        for (final item in counterparties) {
                          if (item['id']?.toString() == counterpartyId) {
                            selectedCounterparty = item;
                            break;
                          }
                        }

                        await _api.updateManualTransaction(
                          widget.businessId,
                          widget.transactionId,
                          direction: direction,
                          accountId: accountId!,
                          categoryId: categoryId!,
                          amount: parsed,
                          date: date,
                          jobId: detail['job_id']?.toString(),
                          documentId: detail['document_id']?.toString(),
                          counterpartyId: counterpartyId,
                          counterpartyName:
                              selectedCounterparty?['name']?.toString(),
                          remarks: remarks.text.trim(),
                        );

                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext, true);
                        }
                      },
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save changes'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    amount.dispose();
    remarks.dispose();
    if (saved == true) await _load();
  }

  Future<void> _copy() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseEntryScreen(
          businessId: widget.businessId,
          copyTransactionId: widget.transactionId,
          allowRecurring: widget.allowRecurring,
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
    if (value == 'delete' && widget.canDeleteTransaction) await _delete();
  }

  Widget _receiptThumbnail(Map<String, dynamic> attachment) {
    const size = 52.0;
    final localPath = attachment['local_file_path']?.toString() ?? '';
    if (localPath.isNotEmpty && File(localPath).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(localPath),
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }

    final bucket = attachment['bucket']?.toString() ?? 'briskers-private';
    final key = attachment['key']?.toString() ?? '';

    if (key.isEmpty) {
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

    return FutureBuilder<File?>(
      future: _attachmentCache.existing(bucket, key),
      builder: (context, localSnapshot) {
        final local = localSnapshot.data;
        if (local != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              local,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          );
        }

        if (BriskersConnectionModeController.instance.forceOffline) {
          return Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: BriskersColors.expenses.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.image_not_supported_outlined),
          );
        }

        return FutureBuilder<String>(
          future: _attachmentUrl(attachment),
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
    final deletable = widget.canDeleteTransaction && detail['deletable'] == true;
    final attachments = List<dynamic>.from(detail['attachments'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _preloadAttachments(attachments);
    });
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
          if (remarks.isNotEmpty) ...[
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
            const SizedBox(height: 12),
          ],
          _DetailRow(label: 'Category', value: category),
          _DetailRow(label: 'Account', value: account),
          _DetailRow(label: 'Date', value: date),
          if (jobNumber.isNotEmpty)
            _DetailRow(label: 'Job', value: jobNumber),
          if (documentNumber.isNotEmpty)
            _DetailRow(label: 'Invoice', value: documentNumber),
          if (widget.allowRecurring && recurring is Map)
            _DetailRow(
              label: 'Repeating',
              value: <String>[
                recurring['frequency']?.toString() ?? '',
                if ((recurring['next_date']?.toString() ?? '').isNotEmpty)
                  'next ${recurring['next_date']}',
              ].where((x) => x.isNotEmpty).join(' • '),
            ),
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
