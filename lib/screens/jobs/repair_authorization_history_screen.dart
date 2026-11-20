import 'package:flutter/material.dart';
import '../../core/briskers_colors.dart';
import '../../services/local_repair_groups.dart';
import '../../services/offline_document_draft_service.dart';
import '../../widgets/repair_evidence_photo.dart';
import '../../widgets/briskers_dialog.dart';
import 'job_document_screen.dart';

class RepairAuthorizationHistoryScreen extends StatefulWidget {
  const RepairAuthorizationHistoryScreen({super.key, required this.business,
    this.estimate, this.vehicle, required this.owner, this.store});
  final String business;
  final String? estimate, vehicle;
  final bool owner;
  final LocalRepairGroups? store;
  @override State<RepairAuthorizationHistoryScreen> createState() => _RepairAuthorizationHistoryScreenState();
}
class _RepairAuthorizationHistoryScreenState extends State<RepairAuthorizationHistoryScreen> {
  late final store = widget.store ?? LocalRepairGroups();
  late final history = widget.estimate != null ? store.history(widget.business, widget.estimate!)
    : store.vehicleHistory(widget.business, widget.vehicle ?? '');
  bool busy = false;
  String? error;
  Future<void> _copy(Map<String, dynamic> event, Map<String, dynamic> group) async {
    if (busy || !widget.owner) { return; }
    final confirmed = await showDialog<bool>(context: context, builder: (dialog) => BriskersDialog(
      title: 'Copy declined repair?', content: const Text('Create a new estimate using this quote. Review current prices and obtain new authorization.'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
        FilledButton(style: BriskersDialog.confirmStyle(), onPressed: () => Navigator.pop(dialog, true), child: const Text('Create estimate'))]));
    if (confirmed != true || !mounted) { return; }
    setState(() { busy = true; error = null; });
    try {
      final drafts = OfflineDocumentDraftService(database: store.db, cache: store.cache);
      final id = await store.db.transaction(() async {
        final id = await drafts.createStandaloneEstimate(widget.business,
          customerId: event['customer_id'] as String, customerName: event['customer_name']?.toString() ?? '',
          vehicleId: event['vehicle_id']?.toString(), vehicleLabel: event['vehicle']?.toString(),
          initialLines: (group['lines'] as List).whereType<Map>().map((line) => Map<String, dynamic>.from(line)).toList());
        final groupId = await store.add(widget.business, id, group['name'] as String);
        final detail = (await store.cache.load(widget.business, id))!;
        for (final line in (detail['lines'] as List).whereType<Map>()) {
          await store.move(widget.business, id, line['id'] as String, groupId);
        }
        await store.edit(widget.business, id, groupId, name: group['name'] as String,
          description: group['description']?.toString() ?? '',
          evidence: (group['evidence'] as List? ?? const []).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList());
        return id;
      });
      if (!mounted) { return; }
      await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => JobDocumentScreen(
        businessId: widget.business, documentId: id, isOwner: true, roleCode: 'owner')));
    } catch (failure) { if (mounted) setState(() => error = '$failure'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Repair authorization history'), foregroundColor: Colors.white,
      flexibleSpace: Container(decoration: const BoxDecoration(gradient: BriskersColors.blueHeader))),
    body: FutureBuilder(future: history, builder: (context, snapshot) {
      final events = snapshot.data;
      if (snapshot.hasError) { return Center(child: Text('History unavailable: ${snapshot.error}')); }
      if (events == null) { return const Center(child: CircularProgressIndicator()); }
      return ListView(padding: const EdgeInsets.all(12), children: [
        if (error != null) Text(error!, style: const TextStyle(color: BriskersColors.destructive)),
        if (events.isEmpty) const Text('No recorded repair authorizations.'),
        for (final event in events) Card(color: Colors.white, child: ExpansionTile(
          title: Text('${event['timestamp']}'),
          subtitle: Text('${event['method']} · ${event['actor']}'),
          childrenPadding: const EdgeInsets.all(12),
          children: [
            if ('${event['notes'] ?? ''}'.isNotEmpty) Text('${event['notes']}'),
            if (event['signature_ref'] != null) FutureBuilder(
              future: store.signature(widget.business, event['signature_ref'] as String),
              builder: (context, signature) => signature.data == null ? const SizedBox.shrink()
                : Image.memory(signature.data!, height: 110, fit: BoxFit.contain)),
            for (final raw in event['groups'] as List) Builder(builder: (context) {
              final group = Map<String, dynamic>.from(raw as Map);
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${group['name']} · ${group['decision']} · quoted \$${((group['quoted_cents'] as num) / 100).toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
                if (group['description'] != null) Text('${group['description']}'),
                for (final line in (group['lines'] as List).whereType<Map>()) Text('${line['name']} · Qty ${line['quantity']}'),
                for (final finding in (group['evidence'] as List? ?? const []).whereType<Map>()) ...[
                  Text('${finding['body'] ?? ''}'),
                  Wrap(spacing: 8, children: [for (final photo in (finding['photos'] as List? ?? const []).whereType<Map>())
                    RepairEvidencePhoto(business: widget.business, photo: Map<String, dynamic>.from(photo), store: store)]),
                ],
                if (widget.owner && group['decision'] == 'declined') TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: BriskersColors.confirm),
                  onPressed: busy ? null : () => _copy(event, group), icon: const Icon(Icons.copy_outlined), label: const Text('Copy to new estimate')),
                const Divider(),
              ]);
            }),
          ])),
      ]);
    }),
  );
}
