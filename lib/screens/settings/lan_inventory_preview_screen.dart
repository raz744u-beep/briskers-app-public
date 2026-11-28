import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart';

import '../../local/local_database_provider.dart';
import '../../services/lan_customer_vehicle_copy.dart';
import '../../services/lan_inventory_session.dart';
import '../../services/lan_record_inventory.dart';
import 'lan_pairing_scanner_screen.dart';

class LanInventoryPreviewScreen extends StatefulWidget {
  const LanInventoryPreviewScreen({super.key, required this.businessId});

  final String businessId;

  @override
  State<LanInventoryPreviewScreen> createState() =>
      _LanInventoryPreviewScreenState();
}

class _LanInventoryPreviewScreenState extends State<LanInventoryPreviewScreen> {
  final _code = TextEditingController();
  LanInventorySession? _offer;
  Timer? _expiry;
  LanInventoryDifference? _difference;
  List<LanInventoryEntry>? _sourceInventory;
  bool _busy = false;
  String? _error;
  bool _allowCopy = false;
  String? _comparedCode;
  String? _copyResult;

  @override
  void dispose() {
    _code.dispose();
    _expiry?.cancel();
    final offer = _offer;
    if (offer != null) unawaited(offer.close());
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() => _run(() async {
    final addresses = await LanInventorySession.addresses();
    if (!mounted) return;
    if (addresses.isEmpty) {
      throw StateError(
        'Connect this phone to the same private Wi-Fi as the other phone.',
      );
    }
    final address = addresses.length == 1
        ? addresses.single
        : await showDialog<InternetAddress>(
            context: context,
            builder: (dialog) => SimpleDialog(
              title: const Text('Choose this phone’s Wi-Fi address'),
              children: [
                for (final option in addresses)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(dialog, option),
                    child: Text(option.address),
                  ),
              ],
            ),
          );
    if (address == null || !mounted) return;
    final db = localDatabase;
    final (inventory, recordCopy) = await db.transaction(
      () async => (
        await LanRecordInventory(db).read(widget.businessId),
        _allowCopy
            ? await LanCustomerVehicleCopy(db).share(widget.businessId)
            : null,
      ),
    );
    if (!mounted) return;
    final offer = await LanInventorySession.offer(
      address: address,
      business: widget.businessId,
      inventory: inventory,
      recordCopy: recordCopy,
    );
    if (!mounted) {
      await offer.close();
      return;
    }
    setState(() => _offer = offer);
    _expiry = Timer(const Duration(minutes: 5), () {
      if (mounted) setState(() => _offer = null);
    });
  });

  Future<void> _stop() async {
    final offer = _offer;
    _expiry?.cancel();
    setState(() => _offer = null);
    await offer?.close();
  }

  Future<void> _scanCode() async {
    FocusScope.of(context).unfocus();
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const LanPairingScannerScreen()),
    );
    if (!mounted || code == null) return;
    _code.text = code;
    _clearComparison();
  }

  void _clearComparison() => setState(() {
    _difference = null;
    _sourceInventory = null;
    _comparedCode = null;
    _copyResult = null;
    _error = null;
  });

  Future<void> _compare() => _run(() async {
    final code = _code.text;
    _clearComparison();
    final source = await LanInventorySession.fetch(code, widget.businessId);
    if (!mounted) return;
    final here = await LanRecordInventory(
      localDatabase,
    ).read(widget.businessId);
    if (mounted) {
      setState(() {
        _difference = LanRecordInventory.compare(source, here);
        _sourceInventory = source;
        _comparedCode = code;
      });
    }
  });

  static const _copyKinds = {'customer', 'vehicle', 'job'};

  Future<void> _copyMissingRecords() => _run(() async {
    final code = _comparedCode;
    final difference = _difference;
    final source = _sourceInventory;
    if (code == null || difference == null || source == null) return;
    final eligible = {
      for (final item in difference.onlyOnSource)
        if (_copyKinds.contains(item.kind)) item.identity,
    };
    if (eligible.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Copy missing records?'),
        content: const Text(
          'This can add eligible customers, vehicles, and open unassigned jobs with no linked work. Records already saved here stay as they are. '
          'Review any records this step skips before copying them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Copy to this phone'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final bundle = await LanInventorySession.fetchRecordCopy(
      code,
      widget.businessId,
    );
    if (!mounted) return;
    final result = await LanCustomerVehicleCopy(localDatabase).copyMissing(
      business: widget.businessId,
      bundle: bundle,
      approvedIdentities: eligible,
    );
    if (!mounted) return;
    final remaining =
        eligible.length - result.customers - result.vehicles - result.jobs;
    setState(() {
      _copyResult =
          'Copied ${result.customers} customers, ${result.vehicles} vehicles, and ${result.jobs} jobs. '
          '$remaining copy candidates still need review.';
    });
    final here = await LanRecordInventory(
      localDatabase,
    ).read(widget.businessId);
    if (mounted) {
      setState(() => _difference = LanRecordInventory.compare(source, here));
    }
  });

  Widget _result(
    String title,
    List<LanInventoryEntry> entries, {
    bool showRecords = false,
    Map<String, LanInventoryEntry> destination = const {},
  }) {
    final totals = <String, int>{};
    for (final entry in entries) {
      totals.update(entry.kind, (n) => n + 1, ifAbsent: () => 1);
    }
    final heading = Text('$title · ${entries.length}');
    final summary = Text(
      totals.entries.map((entry) => '${entry.key} ${entry.value}').join(' · '),
    );
    if (!showRecords || entries.isEmpty) {
      return Card(
        child: ListTile(title: heading, subtitle: summary),
      );
    }
    return Card(
      child: ListTile(
        title: heading,
        subtitle: summary,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: Text(title)),
              body: ListView.builder(
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final local = destination[entry.identity];
                  final sourceFields = entry.review;
                  final label =
                      sourceFields['Number'] ??
                      sourceFields['Name'] ??
                      [
                            sourceFields['Year'],
                            sourceFields['Make'],
                            sourceFields['Model'],
                          ]
                          .whereType<String>()
                          .where((value) => value.isNotEmpty)
                          .join(' ');
                  final changed = {...sourceFields.keys, ...?local?.review.keys}
                      .where((key) => sourceFields[key] != local?.review[key])
                      .toList();
                  return ExpansionTile(
                    title: Text(
                      label.isEmpty ? entry.kind : '${entry.kind} · $label',
                    ),
                    subtitle: local == null
                        ? null
                        : const Text('Source phone and this phone'),
                    children: [
                      if (sourceFields.isEmpty)
                        const ListTile(
                          title: Text(
                            'Record details unavailable. Update the source phone.',
                          ),
                        )
                      else if (local == null)
                        for (final field in sourceFields.entries)
                          ListTile(
                            title: Text(field.key),
                            subtitle: Text(field.value),
                          )
                      else if (changed.isEmpty)
                        const ListTile(
                          title: Text(
                            'A saved field differs outside the displayed fields.',
                          ),
                        )
                      else
                        for (final field in changed)
                          ListTile(
                            title: Text(field),
                            subtitle: Text(
                              'Source phone  ${sourceFields[field] ?? 'Unavailable'}\n'
                              'This phone  ${local.review[field] ?? 'Unavailable'}',
                            ),
                          ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final offer = _offer;
    final difference = _difference;
    return Scaffold(
      appBar: AppBar(title: const Text('LAN compare and copy')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Use the same private Wi-Fi on both phones. Share from the source phone, then scan or enter its pairing code on the other phone. Comparing records leaves both phones untouched. Copying takes a separate confirmation on this phone.',
          ),
          const SizedBox(height: 12),
          if (offer == null) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow copying eligible records'),
              subtitle: const Text(
                'Use this only on the source phone. The code can read customer contact details on this Wi-Fi session.',
              ),
              value: _allowCopy,
              onChanged: _busy
                  ? null
                  : (enabled) => setState(() => _allowCopy = enabled),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _start,
              child: Text(
                _allowCopy
                    ? 'Share inventory and record copy'
                    : 'Share my inventory',
              ),
            ),
          ] else ...[
            const Text('Comparison code · expires after five minutes'),
            const SizedBox(height: 8),
            Center(
              child: Semantics(
                image: true,
                label: 'Briskers pairing QR code',
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 224),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: CustomPaint(painter: _PairingQrPainter(offer.code)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(offer.code),
            OutlinedButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: offer.code));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Comparison code copied.')),
                  );
                }
              },
              child: const Text('Copy code'),
            ),
            TextButton(onPressed: _stop, child: const Text('Stop sharing')),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _scanCode,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan pairing code'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _code,
            enabled: !_busy,
            onChanged: (_) => _clearComparison(),
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Code from the source phone',
              border: OutlineInputBorder(),
            ),
          ),
          FilledButton(
            onPressed: _busy ? null : _compare,
            child: const Text('Compare records'),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error case final error?) Text(error),
          if (_copyResult case final result?) Text(result),
          if (difference != null) ...[
            if (difference.onlyOnSource.any(
              (item) => _copyKinds.contains(item.kind),
            ))
              OutlinedButton(
                onPressed: _busy ? null : _copyMissingRecords,
                child: const Text('Copy eligible records'),
              ),
            _result(
              'Only on source phone',
              difference.onlyOnSource,
              showRecords: true,
            ),
            _result(
              'Only on this phone',
              difference.onlyOnDestination,
              showRecords: true,
            ),
            _result(
              'Different on both phones',
              difference.different,
              showRecords: true,
              destination: difference.destinationVersions,
            ),
            _result(
              'Needs verification',
              difference.unverified,
              showRecords: true,
              destination: difference.destinationVersions,
            ),
            const Text(
              'Results compare saved IDs and selected fields. Pending changes, local-only IDs, and documents without a saved detail go under Needs verification.',
            ),
          ],
        ],
      ),
    );
  }
}

class _PairingQrPainter extends CustomPainter {
  _PairingQrPainter(this.code)
    : _image = QrImage(
        QrCode.fromData(data: code, errorCorrectLevel: QrErrorCorrectLevel.M),
      );

  final String code;
  final QrImage _image;

  @override
  void paint(Canvas canvas, Size size) {
    const quietZone = 4;
    final side = size.shortestSide;
    final moduleSize = side / (_image.moduleCount + 2 * quietZone);
    final padding = quietZone * moduleSize;
    final paint = Paint()..isAntiAlias = false;
    canvas.drawRect(Offset.zero & size, paint..color = Colors.white);
    paint.color = Colors.black;
    for (var row = 0; row < _image.moduleCount; row++) {
      for (var column = 0; column < _image.moduleCount; column++) {
        if (_image.isDark(row, column)) {
          canvas.drawRect(
            Rect.fromLTRB(
              padding + column * moduleSize,
              padding + row * moduleSize,
              padding + (column + 1) * moduleSize,
              padding + (row + 1) * moduleSize,
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PairingQrPainter oldDelegate) => code != oldDelegate.code;
}
