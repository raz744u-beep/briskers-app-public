import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide showDialog, showModalBottomSheet;

import '../../core/module_modal_theme.dart';

import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:saf/saf.dart';

import '../../core/briskers_colors.dart';
import '../../core/connection_mode.dart';
import '../../core/navigation_content_timing.dart';
import '../../services/briskers_api.dart';
import '../../services/warranty_receipt_reporting.dart';
import '../../services/local_attachment_cache.dart';
import '../../services/local_financial_cache.dart';
import '../../services/expenseiq_local_photo_sync.dart';
import 'expense_entry_screen.dart';
import 'transaction_recurring_dialog.dart';

class ExpenseDetailScreen extends StatefulWidget {
  const ExpenseDetailScreen({
    super.key,
    required this.businessId,
    required this.transactionId,
    this.allowRecurring = true,
    this.canDeleteTransaction = false,
    this.cachedDetail,
    this.api = const BriskersApi(),
    this.financialCache,
    this.localPhotoSync,
    this.receiptReporting,
    this.onChanged,
  });

  final VoidCallback? onChanged;
  final String businessId;
  final String transactionId;
  final bool allowRecurring;
  final bool canDeleteTransaction;
  final Map<String, dynamic>? cachedDetail;
  final BriskersApi api;
  final LocalFinancialCache? financialCache;
  final ExpenseIqLocalPhotoSync? localPhotoSync;
  final WarrantyReceiptReporting? receiptReporting;

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen>
    with ModuleModalState<ExpenseDetailScreen> {
  @override
  Color get modalAccent => BriskersColors.expenses;
  BriskersApi get _api => widget.api;
  final _picker = ImagePicker();
  late LocalAttachmentCache _attachmentCache;
  late LocalFinancialCache _localFinancial;
  late ExpenseIqLocalPhotoSync _localExpenseIq;
  Map<String, dynamic>? _localExpenseIqPhoto;

  Map<String, dynamic>? _detail;
  bool _loading = true;
  bool _canDeleteRecords = false;
  bool _uploading = false;
  String? _deletingAttachmentId;
  bool _busy = false;
  String? _error;
  final Map<String, Future<String>> _attachmentUrls = {};
  final Map<String, Future<File?>> _attachmentFiles = {};
  final Map<String, Future<Uint8List>> _localPhotoBytes = {};
  int _loadGeneration = 0;
  int _recordGeneration = 0;
  bool _hasAuthoritativeDetail = false;
  String _detailSource = 'preview';

  @override
  void initState() {
    super.initState();
    _initializeRecord();
  }

  @override
  void didUpdateWidget(covariant ExpenseDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.transactionId != widget.transactionId ||
        oldWidget.api != widget.api ||
        oldWidget.financialCache != widget.financialCache ||
        oldWidget.localPhotoSync != widget.localPhotoSync ||
        oldWidget.receiptReporting != widget.receiptReporting) {
      _initializeRecord();
    }
  }

  void _initializeRecord() {
    // Also invalidates every old response when Flutter reuses this State for
    // another transaction or business, including an A -> B -> A navigation.
    _loadGeneration++;
    _recordGeneration++;
    _attachmentCache = LocalAttachmentCache(api: _api);
    _localFinancial = widget.financialCache ?? LocalFinancialCache();
    _localExpenseIq = widget.localPhotoSync ?? ExpenseIqLocalPhotoSync();
    _detail = null;
    _localExpenseIqPhoto = null;
    _attachmentUrls.clear();
    _attachmentFiles.clear();
    _localPhotoBytes.clear();
    _loading = true;
    _hasAuthoritativeDetail = false;
    _canDeleteRecords = false;
    _uploading = false;
    _deletingAttachmentId = null;
    _busy = false;
    _error = null;
    final cached = widget.cachedDetail;
    final offline = BriskersConnectionModeController.instance.forceOffline;
    if (cached != null) {
      _loadCached(cached, offline: offline);
    } else if (offline) {
      unawaited(_loadOffline());
    } else {
      unawaited(_load());
    }
  }

  bool _isCurrent(int generation) => mounted && generation == _loadGeneration;

  Map<String, dynamic> _normalizedDetail(Map<String, dynamic> raw) => {
    ...raw,
    'date': raw['date'] ?? raw['transaction_date'],
    'attachments': raw['attachments'] ?? const <dynamic>[],
  };

  Future<Map<String, dynamic>> _withReceiptReporting(
    Map<String, dynamic> raw, {
    required String businessId,
    required String transactionId,
  }) async {
    try {
      final reporting =
          widget.receiptReporting ?? WarrantyReceiptReporting(api: _api);
      return (await reporting.enrich(businessId, [
        {...raw, 'id': transactionId},
      ], refresh: false)).single;
    } catch (_) {
      return WarrantyReceiptReporting.unverified(raw);
    }
  }

  Future<void> _loadOffline() async {
    final generation = ++_loadGeneration;
    final businessId = widget.businessId;
    final transactionId = widget.transactionId;
    final summary = widget.cachedDetail;
    _canDeleteRecords = false;
    unawaited(_loadLocalExpenseIqPhoto(generation));
    try {
      final saved = await _localFinancial.loadTransactionDetail(
        businessId,
        transactionId,
      );
      if (!mounted || !_isCurrent(generation)) return;
      final rawDetail = saved ?? summary;
      if (rawDetail == null) {
        setState(() {
          _loading = false;
          _error =
              'This expense has not been cached on this device. '
              'Open it while online first to make it available offline.';
        });
        return;
      }
      final detail = _normalizedDetail(rawDetail)
        ..['editable'] = saved != null
        ..['deletable'] = false;
      setState(() {
        _detail = detail;
        _detailSource = saved == null ? 'preview' : 'local';
        _loading = false;
        _error = null;
      });
      unawaited(_enrichVisibleExpense(detail, generation));
    } catch (error) {
      if (!mounted || !_isCurrent(generation)) return;
      setState(() {
        _loading = false;
        _error = 'Offline expense details unavailable: $error';
      });
    }
  }

  // Paint the tapped list row without waiting for disk or network. A list
  // summary or online disk fallback never grants mutation permissions.
  void _loadCached(Map<String, dynamic> summary, {bool offline = false}) {
    _detailSource = 'preview';
    _detail = _normalizedDetail(summary)
      ..['editable'] = false
      ..['deletable'] = false;
    _loading = false;
    _error = null;
    _canDeleteRecords = false;
    if (offline) {
      unawaited(_loadOffline());
    } else {
      unawaited(_load(hydrateLocal: true));
    }
  }

  Future<void> _loadLocalPreview(int generation) async {
    try {
      final saved = await _localFinancial.loadTransactionDetail(
        widget.businessId,
        widget.transactionId,
      );
      if (!_isCurrent(generation) || _hasAuthoritativeDetail || saved == null) {
        return;
      }
      final detail = _normalizedDetail(saved)
        ..['editable'] = false
        ..['deletable'] = false;
      setState(() {
        _detail = detail;
        _detailSource = 'local';
      });
      unawaited(_enrichVisibleExpense(detail, generation));
    } catch (_) {
      // Keep the already visible list summary if local storage is unavailable.
    }
  }

  Future<void> _enrichVisibleExpense(
    Map<String, dynamic> raw,
    int generation,
  ) async {
    final enriched = await _withReceiptReporting(
      raw,
      businessId: widget.businessId,
      transactionId: widget.transactionId,
    );
    if (!_isCurrent(generation) || !identical(_detail, raw)) return;
    setState(() {
      // Reporting only owns this projection. It must never restore old
      // attachments, values, or permissions after a newer detail/action.
      _detail = {...raw}
        ..remove('reporting_amount')
        ..remove('reporting_processor_fee')
        ..remove('reporting_status');
      for (final key in const [
        'reporting_amount',
        'reporting_processor_fee',
        'reporting_status',
      ]) {
        if (enriched.containsKey(key)) _detail![key] = enriched[key];
      }
    });
  }

  Future<void> _load({bool hydrateLocal = false}) async {
    if (BriskersConnectionModeController.instance.forceOffline) {
      await _loadOffline();
      return;
    }
    final generation = ++_loadGeneration;
    final businessId = widget.businessId;
    final transactionId = widget.transactionId;
    final api = _api;
    setState(() => _canDeleteRecords = false);
    unawaited(_loadLocalExpenseIqPhoto(generation));
    if (hydrateLocal) unawaited(_loadLocalPreview(generation));
    try {
      final rawDetail = Map<String, dynamic>.from(
        await api.transactionDetail(businessId, transactionId),
      );
      if (!_isCurrent(generation) ||
          BriskersConnectionModeController.instance.forceOffline) {
        return;
      }
      final detail = _normalizedDetail(rawDetail);
      setState(() {
        _detail = detail;
        _detailSource = 'server';
        // Keep in-flight and completed local-image lookups when metadata
        // refreshes. The per-attachment key already changes for new files.
        _attachmentUrls.clear();
        _hasAuthoritativeDetail = true;
        _loading = false;
        _error = null;
      });
      unawaited(_enrichVisibleExpense(detail, generation));
      unawaited(_loadDeletePermission(generation, api, businessId));
      unawaited(
        _cacheExpenseDetail(rawDetail, generation, businessId, transactionId),
      );
    } catch (error) {
      if (!mounted || !_isCurrent(generation)) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadDeletePermission(
    int generation,
    BriskersApi api,
    String businessId,
  ) async {
    try {
      final permissions = await api.myPermissions(businessId);
      if (!_isCurrent(generation) ||
          BriskersConnectionModeController.instance.forceOffline) {
        return;
      }
      setState(
        () => _canDeleteRecords = permissions.contains('records.delete'),
      );
    } catch (_) {
      // Permission-dependent actions remain disabled.
    }
  }

  Future<void> _cacheExpenseDetail(
    Map<String, dynamic> rawDetail,
    int generation,
    String businessId,
    String transactionId,
  ) async {
    try {
      if (!mounted || !_isCurrent(generation)) return;
      await _localFinancial.saveTransactionDetail(
        businessId,
        transactionId,
        rawDetail,
      );
      if (!_isCurrent(generation) ||
          BriskersConnectionModeController.instance.forceOffline) {
        return;
      }
      await _prefetchLocalAttachments(
        List<dynamic>.from(rawDetail['attachments'] ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(),
        generation,
      );
      if (_isCurrent(generation) && _attachmentFiles.isNotEmpty) {
        setState(_attachmentFiles.clear);
      }
    } catch (_) {
      // Receipt/cache warming must not block the visible transaction.
    }
  }

  Future<void> _loadLocalExpenseIqPhoto(int generation) async {
    try {
      final photo = await _localExpenseIq.localForExpense(
        widget.businessId,
        widget.transactionId,
      );
      if (_isCurrent(generation)) {
        setState(() => _localExpenseIqPhoto = photo);
      }
    } catch (_) {
      // Online receipt view remains available.
    }
  }

  Future<void> _openLocalExpenseIqPhoto(String uri) async {
    final generation = _loadGeneration;
    try {
      final bytes = await _readLocalPhoto(uri);
      if (!mounted || !_isCurrent(generation)) return;
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5,
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        ),
      );
    } catch (error) {
      if (mounted && _isCurrent(generation)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Original photo unavailable: $error')),
        );
      }
    }
  }

  Future<Uint8List> _readLocalPhoto(String uri) =>
      _localPhotoBytes.putIfAbsent(uri, () => Saf().readFileBytes(uri));

  Widget _localExpenseIqReceiptCard() {
    final photo = _localExpenseIqPhoto!;
    final uri = photo['source_uri']?.toString() ?? '';
    final state = photo['state']?.toString() ?? 'pending';
    return Card(
      child: ListTile(
        leading: uri.isEmpty
            ? const Icon(Icons.image_not_supported_outlined)
            : FutureBuilder<Uint8List>(
                future: _readLocalPhoto(uri),
                builder: (context, snapshot) => snapshot.hasData
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(
                          snapshot.data!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Icon(Icons.image_outlined),
              ),
        title: Text(photo['filename']?.toString() ?? 'ExpenseIQ photo'),
        subtitle: Text(
          state == 'uploaded'
              ? 'Synced to cloud'
              : state == 'missing'
              ? 'Original file not found'
              : state == 'failed'
              ? 'Upload pending retry'
              : 'Available locally · awaiting sync',
        ),
        trailing: const Icon(Icons.zoom_in_outlined),
        onTap: uri.isEmpty ? null : () => _openLocalExpenseIqPhoto(uri),
      ),
    );
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
    int generation,
  ) async {
    final attachmentCache = _attachmentCache;
    final pending = <Future<File?>>[];
    for (final attachment in attachments) {
      if (!_isCurrent(generation) ||
          BriskersConnectionModeController.instance.forceOffline) {
        return;
      }
      final bucket = attachment['bucket']?.toString() ?? 'briskers-private';
      final key = attachment['key']?.toString() ?? '';
      if (key.isEmpty) continue;
      pending.add(attachmentCache.getOrDownload(bucket, key));
      if (pending.length >= 4) {
        await Future.wait(pending);
        pending.clear();
      }
    }
    if (pending.isNotEmpty) await Future.wait(pending);
  }

  Future<File?> _localAttachment(Map<String, dynamic> attachment) {
    final cacheKey =
        '${_attachmentCacheKey(attachment)}|'
        '${attachment['local_file_path'] ?? ''}';
    return _attachmentFiles.putIfAbsent(
      cacheKey,
      () => _findLocalAttachment(attachment),
    );
  }

  Future<File?> _findLocalAttachment(Map<String, dynamic> attachment) async {
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
    if (_detail?['editable'] != true || _uploading) return;
    final generation = _loadGeneration;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.camera_alt_outlined,
                color: Color(0xFF167F43),
              ),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: Color(0xFF2468BB),
              ),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !_isCurrent(generation)) return;

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
    if (files.isEmpty || !_isCurrent(generation)) return;

    final actionGeneration = ++_loadGeneration;
    final recordGeneration = _recordGeneration;
    final businessId = widget.businessId;
    final transactionId = widget.transactionId;
    final api = _api;
    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      for (final file in files) {
        if (!_isCurrent(actionGeneration)) return;
        await api.uploadExpensePhoto(
          businessId,
          transactionId,
          filename: file.name,
          mimeType: _mimeType(file.name),
          bytes: await file.readAsBytes(),
        );
      }
      widget.onChanged?.call();
      if (_isCurrent(actionGeneration)) await _load();
    } catch (error) {
      if (_isCurrent(actionGeneration)) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && recordGeneration == _recordGeneration) {
        setState(() => _uploading = false);
      }
    }
  }

  Future<void> _replaceReceipt(Map<String, dynamic> attachment) async {
    final editable = _detail?['editable'] == true;
    final generation = _loadGeneration;
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
    if (source == null || !_isCurrent(generation)) return;

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
    if (file == null || !_isCurrent(generation)) return;

    final actionGeneration = ++_loadGeneration;
    final recordGeneration = _recordGeneration;
    final businessId = widget.businessId;
    final transactionId = widget.transactionId;
    final api = _api;
    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      await api.uploadExpensePhoto(
        businessId,
        transactionId,
        filename: file.name,
        mimeType: _mimeType(file.name),
        bytes: await file.readAsBytes(),
      );

      if (!_isCurrent(actionGeneration)) return;
      final attachmentId = attachment['attachment_id']?.toString() ?? '';
      if (attachmentId.isNotEmpty) {
        await api.archiveExpensePhotoForReplace(
          businessId,
          transactionId,
          attachmentId,
          bucket: attachment['bucket']?.toString() ?? 'briskers-private',
          key: attachment['key']?.toString() ?? '',
        );
      }

      widget.onChanged?.call();
      if (_isCurrent(actionGeneration)) await _load();
    } catch (error) {
      if (_isCurrent(actionGeneration)) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && recordGeneration == _recordGeneration) {
        setState(() => _uploading = false);
      }
    }
  }

  Future<void> _openAttachment(Map<String, dynamic> attachment) async {
    final generation = _loadGeneration;
    try {
      final local = await _localAttachment(attachment);
      String? url;
      if (!mounted || !_isCurrent(generation)) return;
      if (local == null) {
        if (BriskersConnectionModeController.instance.forceOffline) {
          throw StateError(
            'This receipt photo has not been cached on this device.',
          );
        }
        url = await _attachmentUrl(attachment);
      }
      if (!mounted || !_isCurrent(generation)) return;
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
              if (editable && _canDeleteRecords)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      if (_isCurrent(generation)) {
                        await _deleteAttachment(attachment);
                      }
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
      if (_isCurrent(generation)) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _deleteAttachment(Map<String, dynamic> attachment) async {
    final attachmentId = attachment['attachment_id']?.toString() ?? '';
    if (attachmentId.isEmpty ||
        _deletingAttachmentId != null ||
        _detail?['editable'] != true ||
        !_canDeleteRecords) {
      return;
    }
    final generation = _loadGeneration;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete receipt photo?'),
        content: const Text('The photo will be removed from this transaction.'),
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
    if (confirmed != true ||
        !_isCurrent(generation) ||
        _detail?['editable'] != true ||
        !_canDeleteRecords) {
      return;
    }

    final actionGeneration = ++_loadGeneration;
    final recordGeneration = _recordGeneration;
    final businessId = widget.businessId;
    final transactionId = widget.transactionId;

    setState(() {
      _deletingAttachmentId = attachmentId;
      _error = null;
    });

    try {
      await _api.deleteExpensePhoto(
        businessId,
        transactionId,
        attachmentId,
        bucket: attachment['bucket']?.toString() ?? 'briskers-private',
        key: attachment['key']?.toString() ?? '',
      );
      widget.onChanged?.call();
      if (_isCurrent(actionGeneration)) await _load();
    } catch (error) {
      if (_isCurrent(actionGeneration)) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && recordGeneration == _recordGeneration) {
        setState(() => _deletingAttachmentId = null);
      }
    }
  }

  Future<void> _edit() async {
    final detail = _detail;
    if (detail == null || detail['editable'] != true || _busy) return;
    var generation = _loadGeneration;

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
      if (changed == true && _isCurrent(generation)) {
        widget.onChanged?.call();
        generation = ++_loadGeneration;
        final saved = await _localFinancial.loadTransactionDetail(
          widget.businessId,
          widget.transactionId,
        );
        if (saved != null && _isCurrent(generation)) {
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
    if (!mounted || !_isCurrent(generation)) return;

    final accounts = List<dynamic>.from(
      options['accounts'] ?? const [],
    ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
    final categories = List<dynamic>.from(
      options['categories'] ?? const [],
    ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
    final counterparties = List<dynamic>.from(
      options['counterparties'] ?? const [],
    ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();

    final amount = TextEditingController(
      text: detail['amount']?.toString() ?? '',
    );
    final remarks = TextEditingController(
      text: detail['remarks']?.toString() ?? '',
    );

    var direction = detail['direction']?.toString() == 'income'
        ? 'income'
        : 'expense';
    String? accountId = detail['account_id']?.toString();
    String? categoryId = detail['category_id']?.toString();
    String? counterpartyId = detail['counterparty_id']?.toString();
    var date =
        DateTime.tryParse(detail['date']?.toString() ?? '') ?? DateTime.now();

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
                            onSelectionChanged: (value) =>
                                setSheetState(() => direction = value.first),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: amount,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            scrollPadding: const EdgeInsets.only(bottom: 160),
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
                              labelText: direction == 'income'
                                  ? 'Payer'
                                  : 'Payee',
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
                            leading: const Icon(Icons.calendar_today_outlined),
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
                            scrollPadding: const EdgeInsets.only(bottom: 160),
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
                      style: FilledButton.styleFrom(
                        backgroundColor: BriskersColors.expenses,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        if (!_isCurrent(generation) || _busy) return;
                        final parsed = num.tryParse(
                          amount.text.trim().replaceAll(',', ''),
                        );
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

                        generation = ++_loadGeneration;
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
                          counterpartyName: selectedCounterparty?['name']
                              ?.toString(),
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
    if (saved == true && _isCurrent(generation)) {
      widget.onChanged?.call();
      await _load();
    }
  }

  Future<void> _copy() async {
    if (_detail?['editable'] != true || _busy) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseEntryScreen(
          businessId: widget.businessId,
          copyTransactionId: widget.transactionId,
          allowRecurring: widget.allowRecurring,
        ),
      ),
    );
    if (changed == true) {
      widget.onChanged?.call();
    }
  }

  Future<void> _delete() async {
    final detail = _detail;
    if (detail == null ||
        _busy ||
        !widget.canDeleteTransaction ||
        detail['deletable'] != true ||
        !_canDeleteRecords) {
      return;
    }
    final generation = _loadGeneration;

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
    if (confirmed != true ||
        !_isCurrent(generation) ||
        !_canDeleteRecords ||
        !widget.canDeleteTransaction) {
      return;
    }
    final actionGeneration = ++_loadGeneration;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.voidManualTransaction(widget.businessId, widget.transactionId);
      widget.onChanged?.call();
      if (mounted && _isCurrent(actionGeneration)) Navigator.pop(context);
    } catch (error) {
      if (_isCurrent(actionGeneration)) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  String _repeatLabel(Map<String, dynamic>? rule) {
    if (rule == null || rule['is_repeating'] != true) {
      return 'Not recurring';
    }
    final frequency = rule['frequency']?.toString() ?? '';
    final interval =
        int.tryParse(rule['interval_count']?.toString() ?? '') ?? 1;
    final label = switch (frequency) {
      'daily' => 'Daily',
      'weekly' when interval == 2 => 'Every 2 weeks',
      'weekly' => 'Weekly',
      'yearly' => 'Yearly',
      _ => 'Monthly',
    };
    final next = rule['next_date']?.toString() ?? '';
    return next.isEmpty ? label : '$label · next $next';
  }

  Future<void> _manageRecurring() async {
    final detail = _detail;
    if (detail == null ||
        detail['editable'] != true ||
        _busy ||
        !widget.allowRecurring) {
      return;
    }
    if (BriskersConnectionModeController.instance.forceOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Connect to change the recurring schedule. '
            'The original transaction remains available offline.',
          ),
        ),
      );
      return;
    }
    final generation = _loadGeneration;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => TransactionRecurringDialog(
        businessId: widget.businessId,
        transactionId: widget.transactionId,
        transaction: detail,
      ),
    );
    if (changed == true && _isCurrent(generation)) {
      widget.onChanged?.call();
      await _load();
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
    final bucket = attachment['bucket']?.toString() ?? 'briskers-private';
    final key = attachment['key']?.toString() ?? '';

    if (key.isEmpty && localPath.isEmpty) {
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
      key: ValueKey(
        '${widget.businessId}|${widget.transactionId}|$bucket|$key|$localPath',
      ),
      future: _localAttachment(attachment),
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

        // In Auto, wait for the local-file check to finish before considering
        // a signed cloud URL. Starting both at once made cached thumbnails
        // flicker for about a second on every record refresh.
        if (localSnapshot.connectionState != ConnectionState.done) {
          return Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: BriskersColors.expenses.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.image_outlined),
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

    NavigationContentTiming.contentVisible(
      'expense_detail',
        context: context,
      source: _detailSource,
    );
    final recordGeneration = _recordGeneration;
    final income = detail['direction']?.toString() == 'income';
    final editable = detail['editable'] == true;
    final deletable =
        widget.canDeleteTransaction &&
        _canDeleteRecords &&
        detail['deletable'] == true;
    final attachments = List<dynamic>.from(
      detail['attachments'] ?? const [],
    ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
    final counterparty =
        detail['counterparty']?.toString() ?? (income ? 'Income' : 'Expense');
    final category = detail['category']?.toString() ?? '';
    final account = detail['account']?.toString() ?? '';
    final date = detail['date']?.toString() ?? '';
    final remarks = detail['remarks']?.toString() ?? '';
    final jobNumber = detail['job_number']?.toString().trim() ?? '';
    final jobTitle = detail['job_title']?.toString().trim() ?? '';
    final customerName = detail['job_customer_name']?.toString().trim() ?? '';
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
    final recurringRule = recurring is Map
        ? Map<String, dynamic>.from(recurring)
        : null;
    final mayManageRecurring =
        widget.allowRecurring &&
        editable &&
        (detail['job_id']?.toString() ?? '').isEmpty &&
        (detail['document_id']?.toString() ?? '').isEmpty;
    final color = income ? const Color(0xFF169B62) : BriskersColors.expenses;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: color.withValues(alpha: 0.10),
        title: Text(income ? 'Income' : 'Expense'),
        actions: [
          if (editable)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (mounted && recordGeneration == _recordGeneration) {
                  unawaited(_handleMenu(value));
                }
              },
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
                    '${income ? '+' : '-'}${_money(WarrantyReceiptReporting.amount(detail))}',
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
          if (income &&
              detail['reporting_status'] == 'verified' &&
              detail['reporting_amount'] != null) ...[
            _DetailRow(
              label: 'Gross received / invoice credit',
              value: _money(detail['amount']),
            ),
            _DetailRow(
              label: 'Processor fee (not shop income)',
              value: _money(detail['reporting_processor_fee']),
            ),
            _DetailRow(
              label: 'Retained receipts',
              value: _money(detail['reporting_amount']),
            ),
          ],
          if (income && detail['reporting_status'] != 'verified')
            const Text(
              'Gross receipt shown. Processor fee could not be verified; sync invoice details and refresh before relying on net receipts.',
            ),
          _DetailRow(label: 'Category', value: category),
          _DetailRow(label: 'Account', value: account),
          _DetailRow(label: 'Date', value: date),
          if (jobNumber.isNotEmpty) _DetailRow(label: 'Job', value: jobNumber),
          if (documentNumber.isNotEmpty)
            _DetailRow(label: 'Invoice', value: documentNumber),
          if (mayManageRecurring)
            Card(
              margin: const EdgeInsets.only(top: 12),
              child: ListTile(
                leading: const Icon(Icons.event_repeat_outlined),
                title: const Text('Recurring transaction'),
                subtitle: Text(_repeatLabel(recurringRule)),
                trailing: TextButton(
                  onPressed: _manageRecurring,
                  child: Text(
                    recurringRule?['is_repeating'] == true
                        ? 'Change'
                        : 'Make recurring',
                  ),
                ),
                onTap: _manageRecurring,
              ),
            )
          else if (widget.allowRecurring && recurringRule != null)
            _DetailRow(label: 'Repeating', value: _repeatLabel(recurringRule)),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Receipts',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
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
          if (_localExpenseIqPhoto != null &&
              (attachments.isEmpty ||
                  _localExpenseIqPhoto!['state'] != 'uploaded'))
            _localExpenseIqReceiptCard(),
          if (attachments.isEmpty && _localExpenseIqPhoto == null)
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
                      if (editable && _canDeleteRecords)
                        IconButton(
                          tooltip: 'Delete receipt photo',
                          onPressed:
                              _deletingAttachmentId ==
                                  attachment['attachment_id']?.toString()
                              ? null
                              : () => _deleteAttachment(attachment),
                          icon:
                              _deletingAttachmentId ==
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
  const _DetailRow({required this.label, required this.value});

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
