import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../local/local_database_provider.dart';
import '../../services/lan_inventory_session.dart';
import '../../services/lan_record_inventory.dart';

class LanInventoryPreviewScreen extends StatefulWidget {
  const LanInventoryPreviewScreen({super.key, required this.businessId});

  final String businessId;

  @override
  State<LanInventoryPreviewScreen> createState() => _LanInventoryPreviewScreenState();
}

class _LanInventoryPreviewScreenState extends State<LanInventoryPreviewScreen> {
  final _code = TextEditingController();
  LanInventorySession? _offer;
  Timer? _expiry;
  LanInventoryDifference? _difference;
  bool _busy = false;
  String? _error;

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
    if (addresses.isEmpty) throw StateError('Connect this phone to the same private Wi-Fi as the other phone.');
    final address = addresses.length == 1 ? addresses.single :
        await showDialog<InternetAddress>(
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
    final inventory = await LanRecordInventory(localDatabase).read(widget.businessId);
    if (!mounted) return;
    final offer = await LanInventorySession.offer(
      address: address, business: widget.businessId, inventory: inventory,
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

  Future<void> _compare() => _run(() async {
    final code = _code.text;
    setState(() => _difference = null);
    final source = await LanInventorySession.fetch(code, widget.businessId);
    if (!mounted) return;
    final here = await LanRecordInventory(localDatabase).read(widget.businessId);
    if (mounted) setState(() => _difference = LanRecordInventory.compare(source, here));
  });

  Widget _result(String title, List<LanInventoryEntry> entries) {
    final totals = <String, int>{};
    for (final entry in entries) {
      totals.update(entry.kind, (n) => n + 1, ifAbsent: () => 1);
    }
    return Card(child: ListTile(
      title: Text('$title · ${entries.length}'),
      subtitle: Text(totals.entries.map((entry) => '${entry.key} ${entry.value}').join(' · ')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final offer = _offer;
    final difference = _difference;
    return Scaffold(
      appBar: AppBar(title: const Text('LAN record preview')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Use the same private Wi-Fi on both phones. Share from the source phone, then enter its code on the other phone. This preview leaves the saved records on both phones intact.'),
        const SizedBox(height: 12),
        if (offer == null)
          OutlinedButton(onPressed: _busy ? null : _start, child: const Text('Share my inventory'))
        else ...[
          const Text('Comparison code · expires after five minutes'),
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
        TextField(
          controller: _code, autocorrect: false, enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Code from the source phone', border: OutlineInputBorder(),
          ),
        ),
        FilledButton(onPressed: _busy ? null : _compare, child: const Text('Compare records')),
        if (_busy) const LinearProgressIndicator(),
        if (_error case final error?) Text(error),
        if (difference != null) ...[
          _result('Only on source phone', difference.onlyOnSource),
          _result('Only on this phone', difference.onlyOnDestination),
          _result('Different on both phones', difference.different),
          _result('Needs verification', difference.unverified),
          const Text('Results compare saved IDs and selected fields. Pending changes, local-only IDs, and documents without a saved detail go under Needs verification.'),
        ],
      ]),
    );
  }
}
