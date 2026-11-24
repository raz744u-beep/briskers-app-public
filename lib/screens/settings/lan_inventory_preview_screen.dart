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

  Widget _result(
    String title, List<LanInventoryEntry> entries, {
    bool showRecords = false,
    Map<String, LanInventoryEntry> destination = const {},
  }) {
    final totals = <String, int>{};
    for (final entry in entries) {
      totals.update(entry.kind, (n) => n + 1, ifAbsent: () => 1);
    }
    final heading = Text('$title · ${entries.length}');
    final summary = Text(totals.entries.map((entry) => '${entry.key} ${entry.value}').join(' · '));
    if (!showRecords || entries.isEmpty) {
      return Card(child: ListTile(title: heading, subtitle: summary));
    }
    return Card(child: ListTile(
      title: heading,
      subtitle: summary,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push<void>(context, MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final local = destination[entry.identity];
              final sourceFields = entry.review;
              final label = sourceFields['Number'] ?? sourceFields['Name'] ??
                  [sourceFields['Year'], sourceFields['Make'], sourceFields['Model']]
                      .whereType<String>().where((value) => value.isNotEmpty).join(' ');
              final changed = {
                ...sourceFields.keys,
                ...?local?.review.keys,
              }.where((key) => sourceFields[key] != local?.review[key]).toList();
              return ExpansionTile(
                title: Text(label.isEmpty ? entry.kind : '${entry.kind} · $label'),
                subtitle: local == null ? null : const Text('Source phone and this phone'),
                children: [
                  if (sourceFields.isEmpty)
                    const ListTile(title: Text('Record details unavailable. Update the source phone.'))
                  else if (local == null)
                    for (final field in sourceFields.entries)
                      ListTile(title: Text(field.key), subtitle: Text(field.value))
                  else if (changed.isEmpty)
                    const ListTile(title: Text('A saved field differs outside the displayed fields.'))
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
      )),
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
          _result('Only on source phone', difference.onlyOnSource, showRecords: true),
          _result('Only on this phone', difference.onlyOnDestination),
          _result('Different on both phones', difference.different,
            showRecords: true, destination: difference.destinationVersions),
          _result('Needs verification', difference.unverified),
          const Text('Results compare saved IDs and selected fields. Pending changes, local-only IDs, and documents without a saved detail go under Needs verification.'),
        ],
      ]),
    );
  }
}
