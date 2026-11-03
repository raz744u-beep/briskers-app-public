import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../local/local_database_provider.dart';
import '../../services/local_number_allocator.dart';
import '../../services/device_owner_authorization.dart';

import '../../core/briskers_colors.dart';


/// Owner-only device-local numbering controls.
class DocumentNumberingSettingsScreen extends StatefulWidget {
  const DocumentNumberingSettingsScreen({
    super.key,
    required this.businessId,
  });

  final String businessId;

  @override
  State<DocumentNumberingSettingsScreen> createState() =>
      _DocumentNumberingSettingsScreenState();
}

class _DocumentNumberingSettingsScreenState
    extends State<DocumentNumberingSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  final Map<String, Map<String, dynamic>> _counters = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final numbers=LocalNumberAllocator(localDatabase);
      final rows=<Map<String,dynamic>>[];
      for(final kind in const ['invoice','job']) {
        rows.add({'document_kind':kind,'next_number':await numbers.nextNumber(widget.businessId,kind),
          'prefix':kind=='job' ? 'J-' : ''});
      }
      if (!mounted) return;
      setState(() {
        _counters.clear();
        for (final raw in rows) {
          final record = Map<String, dynamic>.from(raw as Map);
          _counters[record['document_kind'].toString()] = record;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _change(String kind) async {
    if (_saving) return;
    final data = _counters[kind];
    if (data == null) return;
    final controller = TextEditingController(
      text: data['next_number']?.toString() ?? '',
    );
    final entered = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Next ${_title(kind)} Number'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Next number',
            helperText: 'Existing numbers will be skipped automatically.',
          ),
          onTap: () => controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          ),
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
    if (!mounted || entered == null) return;
    final number = int.tryParse(entered);
    if (number == null || number < 1 || number > 999999999) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter a positive number up to 999,999,999.'),
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      final grant=await DeviceOwnerAuthorization.instance.authority.authorizeLocal(widget.businessId);
      grant.assertValid(widget.businessId,grant.actorId);
      await LocalNumberAllocator(localDatabase).setNextNumber(widget.businessId,kind,number);
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Next ${_title(kind).toLowerCase()} number updated.'),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not update numbering: $error'),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _title(String kind) => switch (kind) {
    'invoice' => 'Invoice',
    'estimate' => 'Estimate',
    'job' => 'Job',
    _ => kind,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Document Numbering')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'These numbers are stored on this device. Only the Owner can change them. Existing invoices keep their numbers.',
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Text(_error!, style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                )),
              for (final kind in const ['invoice', 'job'])
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.tag,
                      color: BriskersColors.settings),
                    title: Text('Next ${_title(kind)} Number'),
                    subtitle: Text(
                      _counters.containsKey(kind)
                          ? 'Prefix: ${_counters[kind]!['prefix'] ?? ''}'
                          : 'Numbering not initialized',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _counters[kind]?['next_number']?.toString() ?? '—',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.edit_outlined),
                      ],
                    ),
                    onTap: _saving || !_counters.containsKey(kind)
                        ? null
                        : () => _change(kind),
                  ),
                ),
              if (_saving) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              const Text(
                'Numbers are assigned offline. Existing numbers are skipped. Delete the latest invoice to reuse its number automatically; assign older freed numbers from the invoice menu.',
              ),
              TextButton.icon(
                onPressed: _saving ? null : _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Numbers'),
              ),
            ],
          ),
  );
}
