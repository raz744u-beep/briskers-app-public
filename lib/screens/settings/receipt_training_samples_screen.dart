import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/briskers_i18n.dart';
import '../../services/briskers_api.dart';

class ReceiptTrainingSamplesScreen extends StatefulWidget {
  const ReceiptTrainingSamplesScreen({
    super.key,
    required this.businessId,
  });

  final String businessId;

  @override
  State<ReceiptTrainingSamplesScreen> createState() =>
      _ReceiptTrainingSamplesScreenState();
}

class _ReceiptTrainingSamplesScreenState
    extends State<ReceiptTrainingSamplesScreen> {
  static const _api = BriskersApi();
  final ImagePicker _picker = ImagePicker();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _counterparties = const [];
  List<Map<String, dynamic>> _samples = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        _api.transactionSettings(widget.businessId),
        _api.receiptTrainingSamples(widget.businessId),
      ]);

      final settings = Map<String, dynamic>.from(results[0] as Map);
      final counterparties = List<dynamic>.from(
        settings['counterparties'] ?? const <dynamic>[],
      ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();

      final samples = List<Map<String, dynamic>>.from(results[1] as List);

      if (!mounted) return;
      setState(() {
        _counterparties = counterparties
            .where((item) => item['active'] != false)
            .toList();
        _samples = samples;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  String _mimeType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<Map<String, dynamic>?> _choosePayee() async {
    if (_counterparties.isEmpty) return null;

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final normalized = query.trim().toLowerCase();
            final matches = _counterparties.where((item) {
              final name = item['name']?.toString() ?? '';
              return normalized.isEmpty ||
                  name.toLowerCase().contains(normalized);
            }).toList();

            return SafeArea(
              top: false,
              child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * 0.72,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: TextField(
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: tr('choosePayee'),
                          hintText: tr('searchByName'),
                          prefixIcon: const Icon(Icons.search),
                        ),
                        onChanged: (value) =>
                            setSheetState(() => query = value),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: matches.length,
                        itemBuilder: (context, index) {
                          final item = matches[index];
                          final surcharge =
                              item['default_surcharge_percent']?.toString() ??
                                  '';
                          return ListTile(
                            leading:
                                const Icon(Icons.storefront_outlined),
                            title: Text(
                              item['name']?.toString() ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: surcharge.isEmpty
                                ? null
                                : Text(
                                    '$surcharge% ${tr('defaultSurcharge')}',
                                  ),
                            onTap: () =>
                                Navigator.pop(sheetContext, item),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<ImageSource?> _chooseSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(tr('chooseSampleImages')),
              subtitle: Text(tr('chooseMultipleSamples')),
              onTap: () =>
                  Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(tr('takeSamplePhoto')),
              onTap: () =>
                  Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addSamples() async {
    if (_busy) return;

    final payee = await _choosePayee();
    if (payee == null || !mounted) return;

    final vendorId = payee['id']?.toString() ?? '';
    if (vendorId.isEmpty) return;

    final source = await _chooseSource();
    if (source == null || !mounted) return;

    List<XFile> files;
    if (source == ImageSource.gallery) {
      files = await _picker.pickMultiImage(
        imageQuality: 88,
        maxWidth: 2400,
      );
    } else {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 2400,
      );
      files = file == null ? const <XFile>[] : [file];
    }

    if (files.isEmpty || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      for (final file in files) {
        await _api.uploadReceiptTrainingSample(
          widget.businessId,
          vendorId: vendorId,
          filename: file.name,
          mimeType: _mimeType(file.name),
          bytes: await file.readAsBytes(),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            files.length == 1
                ? tr('trainingSampleAdded')
                : '${files.length} ${tr('trainingSamplesAdded')}',
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSample(Map<String, dynamic> sample) async {
    if (_busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('removeTrainingSample')),
        content: Text(tr('removeTrainingSampleQuestion')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('remove')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _api.deleteReceiptTrainingSample(
        widget.businessId,
        sample['id'].toString(),
        bucket: sample['bucket']?.toString() ?? '',
        key: sample['key']?.toString() ?? '',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, List<Map<String, dynamic>>> get _groupedSamples {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final sample in _samples) {
      final vendor = sample['vendor_name']?.toString() ?? tr('payee');
      result.putIfAbsent(vendor, () => <Map<String, dynamic>>[]).add(sample);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupedSamples;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('aiReceiptSamples')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _busy ? null : _addSamples,
        icon: _busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_a_photo_outlined),
        label: Text(tr('addSample')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.psychology_outlined),
                      title: Text(
                        tr('trainingReferenceOnly'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(tr('trainingReferenceExplanation')),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.security_outlined),
                      title: Text(tr('noAccountingEffect')),
                      subtitle: Text(tr('noAccountingEffectExplanation')),
                    ),
                  ),
                  if ((_error ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (groups.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(tr('noTrainingSamples')),
                      ),
                    )
                  else
                    for (final entry in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.storefront_outlined,
                              size: 20,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                entry.key,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                            Text(
                              '${entry.value.length} ${tr('samples')}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...entry.value.map(
                        (sample) => Card(
                          child: ListTile(
                            leading: const Icon(
                              Icons.receipt_long_outlined,
                            ),
                            title: Text(
                              sample['filename']?.toString() ??
                                  tr('receiptSample'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(tr('usedAsLayoutReference')),
                            trailing: IconButton(
                              tooltip: tr('remove'),
                              onPressed:
                                  _busy ? null : () => _deleteSample(sample),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                        ),
                      ),
                    ],
                ],
              ),
            ),
    );
  }
}
