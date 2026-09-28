import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';

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
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await _api.expenseDetail(
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

  Future<void> _openAttachment(Map<String, dynamic> attachment) async {
    try {
      final url = await _api.signedAttachmentUrl(
        attachment['bucket']?.toString() ?? 'briskers-private',
        attachment['key']?.toString() ?? '',
      );
      if (!mounted) return;
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
                  errorBuilder: (_, __, ___) => const SizedBox(
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
            ],
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Expense')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final detail = _detail;
    if (detail == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Expense')),
        body: Center(child: Text(_error ?? 'Expense not found.')),
      );
    }

    final attachments = List<dynamic>.from(detail['attachments'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    final vendor = detail['vendor']?.toString() ?? 'Expense';
    final category = detail['category']?.toString() ?? '';
    final account = detail['account']?.toString() ?? '';
    final date = detail['transaction_date']?.toString() ?? '';
    final remarks = detail['remarks']?.toString().trim() ?? '';
    final jobNumber = detail['job_number']?.toString().trim() ?? '';
    final documentNumber = detail['document_number']?.toString().trim() ?? '';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BriskersColors.expenses.withValues(alpha: 0.10),
        title: const Text('Expense'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              BriskersColors.expenses.withValues(alpha: 0.12),
                          child: const Icon(
                            Icons.payments_outlined,
                            color: BriskersColors.expenses,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                vendor,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (category.isNotEmpty) Text(category),
                            ],
                          ),
                        ),
                        Text(
                          _money(detail['amount']),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    if (date.isNotEmpty) Text('Date: $date'),
                    if (account.isNotEmpty) Text('Paid from: $account'),
                    if (jobNumber.isNotEmpty) Text('Job: $jobNumber'),
                    if (documentNumber.isNotEmpty)
                      Text('Invoice: #$documentNumber'),
                    if (remarks.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        remarks,
                        style: const TextStyle(height: 1.35),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Receipt photos',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _uploading ? null : _addReceipt,
                  icon: _uploading
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (attachments.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F8F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('No receipt photo attached yet.'),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: attachments.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemBuilder: (context, index) {
                  final attachment = attachments[index];
                  return FutureBuilder<String>(
                    future: _api.signedAttachmentUrl(
                      attachment['bucket']?.toString() ?? 'briskers-private',
                      attachment['key']?.toString() ?? '',
                    ),
                    builder: (context, snapshot) {
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: snapshot.hasData
                            ? () => _openAttachment(attachment)
                            : null,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: snapshot.hasData
                              ? Image.network(
                                  snapshot.data!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const ColoredBox(
                                    color: Color(0xFFF1F3F4),
                                    child: Center(
                                      child: Icon(Icons.broken_image_outlined),
                                    ),
                                  ),
                                )
                              : const ColoredBox(
                                  color: Color(0xFFF1F3F4),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                        ),
                      );
                    },
                  );
                },
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
      ),
    );
  }
}
