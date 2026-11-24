import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Counts are a read-only preflight. A difference in totals is not a list of
/// missing records, and matching totals cannot establish identical data.
class DeviceInventoryComparison extends StatefulWidget {
  const DeviceInventoryComparison({
    super.key,
    required this.businessId,
    required this.counts,
  });

  final String businessId;
  final Map<String, int> counts;

  @override
  State<DeviceInventoryComparison> createState() =>
      _DeviceInventoryComparisonState();
}

class _DeviceInventoryComparisonState extends State<DeviceInventoryComparison> {
  static const _labels = {
    'customers': 'Customers',
    'vehicles': 'Vehicles',
    'jobs': 'Jobs',
    'estimates': 'Estimates',
    'invoices': 'Invoices',
  };

  Map<String, int>? _other;
  String? _message;

  String get _scope => base64UrlEncode(const DartSha256().hashSync(
    utf8.encode('briskers-device-inventory-v1:${widget.businessId}'),
  ).bytes);

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: jsonEncode({
      'version': 1,
      'shop': _scope,
      'counts': {for (final key in _labels.keys) key: widget.counts[key]},
    })));
    if (!mounted) return;
    setState(() => _message = 'Counts copied. Paste them into Compare device counts on the other phone.');
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (!mounted) return;
    try {
      if (text == null || text.length > 2048) throw const FormatException();
      final data = jsonDecode(text);
      if (data is! Map || data['version'] != 1 || data['counts'] is! Map) {
        throw const FormatException();
      }
      if (data['shop'] != _scope) {
        setState(() {
          _other = null;
          _message = 'These counts belong to a different shop.';
        });
        return;
      }
      final counts = <String, int>{};
      for (final key in _labels.keys) {
        final value = data['counts'][key];
        if (value is! int || value < 0) throw const FormatException();
        counts[key] = value;
      }
      setState(() {
        _other = counts;
        _message = null;
      });
    } on FormatException {
      setState(() {
        _other = null;
        _message = 'Copy the counts from the other phone first.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final other = _other;
    final ready = _labels.keys.every(widget.counts.containsKey);
    return ExpansionTile(
      leading: const Icon(Icons.devices_outlined),
      title: const Text('Compare device counts'),
      subtitle: const Text('Compare offline inventory before transferring records.'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Copy these counts on one phone and paste the copied text on the other. '
          'The summary contains counts and a shop check, without customer details.',
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          OutlinedButton(onPressed: ready ? _copy : null, child: const Text('Copy counts')),
          OutlinedButton(onPressed: ready ? _paste : null, child: const Text('Paste other phone’s counts')),
        ]),
        if (_message case final message?) Text(message),
        if (other != null) ...[
          for (final entry in _labels.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(entry.value),
              subtitle: Text('This phone ${widget.counts[entry.key]} · Other phone ${other[entry.key]}'),
            ),
          const Text('Matching counts can still contain different records.'),
        ],
      ],
    );
  }
}
